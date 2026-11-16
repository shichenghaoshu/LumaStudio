"""Bounded v1 package validation, shared recipe-schema vocabulary, no executable code."""
import base64, hashlib, json, math, re, sys
from pathlib import Path

ROOT=Path(sys._MEIPASS) if getattr(sys,"frozen",False) else Path(__file__).resolve().parents[2]
MAX_BYTES=12*1024*1024
KINDS={'lut':{'asset.lut','edit.recipe'},'recipe':{'edit.recipe'},'localAdjustment':{'edit.localMask'},'aiTool':{'agent.plan','edit.recipe'}}
GROUPS={'tone','whiteBalance','color','curves','grading','style','beauty','detail','effects'}
ID=re.compile(r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+){1,7}$')
VERSION=re.compile(r'^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$')
USER=re.compile(r'^[a-z][a-z0-9_-]{2,39}$')
RECIPE_SCHEMA=json.loads((ROOT/'Packages/PhotoDomain/Sources/Resources/edit-recipe.schema.json').read_text())
class APIError(Exception):
    def __init__(self,status,code,message): self.status,self.code,self.message=status,code,message

def require(ok,message,code='invalid_package',status=422):
    if not ok: raise APIError(status,code,message)
def keys(value,allowed,required=None):
    require(isinstance(value,dict),'内容必须为对象')
    require(set(value)<=set(allowed),'包含未知字段：'+', '.join(sorted(set(value)-set(allowed))))
    if required: require(set(required)<=set(value),'缺少必需字段')
def text(value,limit):
    return isinstance(value,str) and 0<len(value.strip())<=limit and all(ord(c)>=32 or c=='\n' for c in value)
def integer(v): return isinstance(v,int) and not isinstance(v,bool)
def schema_check(value,schema,depth=0):
    require(depth<=14,'编辑参数嵌套过深')
    if 'enum' in schema: require(any(type(value)==type(v) and value==v for v in schema['enum']),'参数不在允许值中')
    if 'anyOf' in schema:
        for sub in schema['anyOf']:
            try: schema_check(value,sub,depth+1);return
            except APIError: pass
        raise APIError(422,'invalid_package','参数类型不匹配')
    t=schema.get('type')
    if t=='object':
        require(isinstance(value,dict),'参数需为对象')
        require(set(schema.get('required',[]))<=set(value),'编辑参数缺少必需字段')
        props=schema.get('properties',{})
        for k,v in value.items():
            require(k in props or schema.get('additionalProperties') is not False,'未知编辑参数：'+k)
            if k in props: schema_check(v,props[k],depth+1)
    elif t=='array':
        require(isinstance(value,list),'参数需为数组')
        require(schema.get('minItems',0)<=len(value)<=schema.get('maxItems',100000),'参数数组长度超限')
        for item in value: schema_check(item,schema['items'],depth+1)
    elif t in ('number','integer'):
        require(isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value),'参数需为有限数值')
        require(t!='integer' or int(value)==value,'参数需为整数')
        require(schema.get('minimum',-math.inf)<=value<=schema.get('maximum',math.inf),'编辑参数超出范围')
    elif t=='string':
        require(isinstance(value,str),'参数需为文本');require(len(value)<=schema.get('maxLength',100000),'参数文本过长')
        if 'pattern' in schema: require(re.search(schema['pattern'],value) is not None,'参数文本格式错误')
    elif t=='boolean': require(isinstance(value,bool),'参数需为布尔值')
    elif t=='null': require(value is None,'参数需为空值')
    else: raise RuntimeError('Unsupported recipe schema keyword')

def recipe_semantics(r):
    """Cross-field checks beyond numeric JSON Schema, matching host admission."""
    c=r.get('color',{});bands=[h['band'] for h in c.get('hsl',[])]
    require(len(set(bands))==len(bands),'HSL 分组重复')
    for points in c.get('curve',{}).values():
        require(not points or (2<=len(points)<=16 and points[0]['x']==0 and points[-1]['x']==1 and all(a['x']<b['x'] for a,b in zip(points,points[1:]))),'曲线端点或顺序无效')
    masks=r.get('masks',[]);ids=[m['id'] for m in masks]
    require(len(set(ids))==len(ids),'局部区域 ID 重复')
    for m in masks:
        require(m['kind'] in ['face','skin','subject','background','brush'],'尚未支持该区域分割模型')
        require(sum(len(stroke['points']) for stroke in m.get('strokes',[]))<=16384,'画笔点数总量超限')
    locks=r.get('lockedParameters',[]);require(len(set(locks))==len(locks),'锁定参数重复')
    operations=[{'tool':'global.adjust'}]+([{'tool':'beauty.skin'}] if r.get('beauty',{}).get('enabled',False) else [])+[{'tool':'color.adjust'}]+[{'tool':'local.adjust','maskID':mid} for mid in ids]
    require(not r.get('operations') or r['operations']==operations,'工具调用与编辑声明不一致')
    name=r.get('export',{}).get('nameTemplate','{name}_{id}')
    require(bool(name) and '..' not in name and not any(ch in name for ch in ['/','\\']) and all(ord(ch)>=32 for ch in name),'输出命名规则无效')
    for token in ['{name}','{id}','{index}','{date}']:name=name.replace(token,'')
    require('{' not in name and '}' not in name,'输出命名占位符无效')

def validate_cube(data):
    require(len(data)<=8*1024*1024,'LUT 超过 8 MB')
    try: lines=data.decode('utf-8').splitlines()
    except UnicodeDecodeError: raise APIError(422,'invalid_lut','CUBE 需使用 UTF-8 文本')
    size=None;rows=0
    for line in lines:
        line=line.split('#',1)[0].strip()
        if not line: continue
        parts=line.split();key=parts[0]
        if key=='TITLE': continue
        if key=='LUT_3D_SIZE':
            require(size is None and len(parts)==2 and parts[1].isdigit(),'LUT 尺寸声明无效')
            size=int(parts[1]);require(2<=size<=65,'LUT 尺寸需为 2–65')
        elif key in ('DOMAIN_MIN','DOMAIN_MAX'):
            try: v=list(map(float,parts[1:]))
            except ValueError: raise APIError(422,'invalid_lut','LUT 定义域无效')
            require(v==([0.,0.,0.] if key=='DOMAIN_MIN' else [1.,1.,1.]),'LUT 需使用 0–1 定义域')
        else:
            try: v=list(map(float,parts))
            except ValueError: raise APIError(422,'invalid_lut','不支持的 LUT 指令')
            require(len(v)==3 and all(math.isfinite(n) and 0<=n<=1 for n in v),'LUT 节点需为三个 0–1 有限数值')
            rows+=1
    require(size is not None and rows==size**3,'LUT 节点数量与尺寸不一致')

def decode_package(raw):
    require(len(raw)<=MAX_BYTES,'插件包超过 12 MB')
    try: p=json.loads(raw,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite')))
    except (ValueError,UnicodeDecodeError,RecursionError): raise APIError(422,'invalid_json','插件 JSON 无效')
    keys(p,{'schemaVersion','manifest','payload','assets'},{'schemaVersion','manifest','payload','assets'})
    require(type(p['schemaVersion']) is int and p['schemaVersion']==1,'插件协议版本不支持')
    m=p['manifest'];keys(m,{'id','version','name','summary','author','kind','license','tags','capabilities','supports'},{'id','version','name','summary','author','kind','license','tags','capabilities','supports'})
    require(isinstance(m['id'],str) and len(m['id'])<=100 and ID.fullmatch(m['id']),'插件 ID 无效')
    require(isinstance(m['version'],str) and VERSION.fullmatch(m['version']),'版本需为 major.minor.patch')
    require(text(m['name'],80) and text(m['summary'],600),'插件名称或简介无效')
    a=m['author'];keys(a,{'id','name','roles'},{'id','name','roles'})
    require(isinstance(a['id'],str) and USER.fullmatch(a['id']) and text(a['name'],80),'作者无效')
    require(isinstance(a['roles'],list) and 1<=len(a['roles'])<=3 and all(v in ['photographer','colorist','developer'] for v in a['roles']),'作者角色无效')
    require(isinstance(m['tags'],list) and len(m['tags'])<=8 and all(text(v,24) for v in m['tags']),'标签无效')
    require(isinstance(m['kind'],str) and m['kind'] in KINDS,'插件类型无效')
    require(isinstance(m['capabilities'],list) and all(isinstance(v,str) for v in m['capabilities']) and len(set(m['capabilities']))==len(m['capabilities']) and set(m['capabilities'])==KINDS[m['kind']],'能力声明与内容不一致')
    require(isinstance(m['supports'],list) and 1<=len(m['supports'])<=3 and all(v in ['editor','batch','agent'] for v in m['supports']) and len(set(m['supports']))==len(m['supports']),'调用场景无效')
    l=m['license'];keys(l,{'type','terms','spdx','sourceURL','priceCents','currency'},{'type','terms'})
    require(l['type'] in ['openSource','free','commercial'] and text(l['terms'],4000),'许可条款无效')
    if l['type']=='openSource': require(l.get('spdx') in ['MIT','Apache-2.0','BSD-3-Clause','CC0-1.0','CC-BY-4.0'] and isinstance(l.get('sourceURL'),str) and l['sourceURL'].startswith('https://'),'开源作品需提供许可及 HTTPS 源码地址')
    if l['type']=='commercial': require(integer(l.get('priceCents')) and 1<=l['priceCents']<=100000000 and l.get('currency') in ['CNY','USD'],'商业价格或币种无效')
    else: require(l.get('priceCents') in (None,0),'免费作品不能声明收费价格')
    body=p['payload'];keys(body,{'groups','recipe','mask','instruction','lutAsset','intensity'})
    assets=p['assets'];require(isinstance(assets,list) and len(assets)<=1,'首版每包支持一个 LUT 资源')
    for asset in assets:
        keys(asset,{'path','sha256','data'},{'path','sha256','data'})
        require(isinstance(asset['path'],str) and re.fullmatch(r'[A-Za-z0-9_-]{1,64}\.cube',asset['path']),'资源名称不能包含路径')
        try: data=base64.b64decode(asset['data'],validate=True)
        except (ValueError,TypeError): raise APIError(422,'invalid_package','资源 Base64 无效')
        require(hashlib.sha256(data).hexdigest()==asset['sha256'],'资源校验失败');validate_cube(data)
    kind=m['kind']
    expected={'lut':{'lutAsset','intensity'},'recipe':{'groups','recipe'},'localAdjustment':{'mask'},'aiTool':{'instruction'}}[kind]
    require(set(body)==expected,'插件内容与类型不一致')
    require(kind=='lut' or not assets,'仅 LUT 插件可以包含资源')
    if kind=='lut': require(len(assets)==1 and body['lutAsset']==assets[0]['path'] and isinstance(body['intensity'],(int,float)) and not isinstance(body['intensity'],bool) and math.isfinite(body['intensity']) and 0<=body['intensity']<=1,'LUT 资源或强度无效')
    if kind=='recipe':
        require(isinstance(body['groups'],list) and 1<=len(body['groups'])<=len(GROUPS) and all(v in GROUPS for v in body['groups']) and len(set(body['groups']))==len(body['groups']),'参数分组无效')
        schema_check(body['recipe'],RECIPE_SCHEMA);recipe_semantics(body['recipe'])
        recipe=body['recipe'];require(recipe.get('version')==2,'仅支持 v2 编辑配方')
        require(recipe.get('color',{}).get('referenceProfileID') is None,'不能引用作者本机的档案')
        lut=recipe.get('color',{}).get('lut')
        require(lut is None or not lut.startswith('user_'),'请把自定义 LUT 发布为 LUT 插件')
    if kind=='localAdjustment':
        schema_check({'version':2,'masks':[body['mask']]},RECIPE_SCHEMA);recipe_semantics({'masks':[body['mask']]})
        require(body['mask'].get('kind') in ['face','skin','subject','background','brush'],'尚未支持该区域分割模型')
    if kind=='aiTool': require(text(body['instruction'],2000),'AI 指令需为 1–2000 字')
    return p
