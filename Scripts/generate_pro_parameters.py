#!/usr/bin/env python3
"""Generate v2 settings, scalar metadata and strict schema from one checked definition.

Generation is a development step; neither Python nor generation runs inside the app.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
# name, default, min, max, Chinese label, display scale, offset, unit, step
GLOBAL = [
    ('exposure',0,-5,5,'曝光',1,0,' EV',.01),('contrast',1,0,2,'对比度',100,-100,'',.01),
    ('brightness',0,-.3,.3,'亮度',100,0,'',.005),
    ('highlights',0,-1,1,'高光',100,0,'',.01),('shadows',0,-1,1,'阴影',100,0,'',.01),
    ('whites',0,-1,1,'白色色阶',100,0,'',.01),('blacks',0,-1,1,'黑色色阶',100,0,'',.01),
    ('temperature',6500,2000,12000,'色温',1,0,' K',1),('tint',0,-150,150,'色调',1,0,'',1),
    ('saturation',1,0,2,'饱和度',100,-100,'',.01),('vibrance',0,-1,1,'自然饱和度',100,0,'',.01),
    ('clarity',0,-1,1,'清晰度',100,0,'',.01),('texture',0,-1,1,'纹理',100,0,'',.01),
    ('dehaze',0,-1,1,'去朦胧',100,0,'',.01),
]
BEAUTY = [
    ('strength',.35,0,1,'磨皮强度',100,0,'%',.01),('radius',8,2,32,'磨皮半径',1,0,' px',.1),
    ('smoothing',1,0,1,'平滑程度',100,0,'%',.01),('texturePreservation',.94,.6,1,'纹理保留',100,0,'%',.01),
    ('detailRecovery',.04,0,.3,'细节恢复',100,0,'%',.005),('sharpness',0,0,1,'皮肤锐度',100,0,'%',.01),
    ('blemishRemoval',.2,0,1,'细小瑕疵弱化',100,0,'%',.01),('blemishThreshold',.025,.005,.1,'瑕疵检测阈值',1000,0,'',.001),
    ('skinTone',.25,0,1,'肤色优化',100,0,'%',.01),('toneUniformity',.16,0,1,'肤色均匀度',100,0,'%',.01),
    ('skinTemperature',6500,2000,12000,'皮肤色温',1,0,' K',1),('skinTint',0,-150,150,'皮肤色调',1,0,'',1),
    ('skinBrightness',0,-1,1,'皮肤亮度',100,0,'',.01),('skinSaturation',1,0,2,'皮肤饱和度',100,-100,'',.01),
    ('shadowRepair',0,0,1,'皮肤暗部修复',100,0,'%',.01),
]
DETAIL = [
    ('sharpening',0,0,2,'锐化强度',100,0,'',.01),('radius',1,.2,3,'锐化半径',1,0,' px',.1),
    ('detail',.5,0,1,'锐化细节',100,0,'%',.01),('masking',0,0,1,'锐化蒙版',100,0,'%',.01),
    ('luminanceNoise',0,0,1,'亮度降噪',100,0,'%',.01),('luminanceDetail',.5,0,1,'亮度细节',100,0,'%',.01),
    ('colorNoise',0,0,1,'色彩降噪',100,0,'%',.01),('colorDetail',.5,0,1,'色彩细节',100,0,'%',.01),
]
EFFECTS = [
    ('vignette',0,-1,1,'暗角强度',100,0,'',.01),('vignetteMidpoint',.5,.1,1,'暗角中点',100,0,'%',.01),
    ('vignetteRoundness',1,.2,1,'暗角圆度',100,0,'%',.01),('vignetteFeather',.6,.05,1,'暗角羽化',100,0,'%',.01),
    ('grain',0,0,1,'胶片颗粒',100,0,'%',.01),('grainSize',1,.5,4,'颗粒尺寸',1,0,' px',.1),
    ('grainRoughness',.5,0,1,'颗粒粗糙度',100,0,'%',.01),('fade',0,0,1,'褪色',100,0,'%',.01),
    ('bloom',0,0,1,'高光泛光',100,0,'%',.01),('bloomRadius',10,1,50,'泛光半径',1,0,' px',.5),
    ('filmHue',35,0,360,'胶片色调',1,0,'°',1),('filmSaturation',0,0,.3,'胶片染色',100,0,'%',.005),
]
GEOMETRY = [
    ('rotation',0,-45,45,'旋转角度',1,0,'°',.1),('horizontal',0,-.4,.4,'水平透视',100,0,'',.005),
    ('vertical',0,-.4,.4,'垂直透视',100,0,'',.005),('distortion',0,-.4,.4,'手动畸变',100,0,'',.005),
    ('chromaticAberration',0,-1,1,'手动色差校正',100,0,'',.01),('lensVignette',0,0,1,'手动镜头暗角补偿',100,0,'%',.01),
    ('scale',1,1,4,'构图缩放',100,0,'%',.01),('centerX',.5,0,1,'构图水平位置',100,0,'%',.01),
    ('centerY',.5,0,1,'构图垂直位置',100,0,'%',.01),
]
GRADING = [
    ('shadowHue',220,0,360,'阴影色相',1,0,'°',1),('shadowSaturation',0,0,.3,'阴影饱和度',100,0,'%',.005),
    ('shadowLuminance',0,-.25,.25,'阴影明度',100,0,'',.005),('midtoneHue',35,0,360,'中间调色相',1,0,'°',1),
    ('midtoneSaturation',0,0,.3,'中间调饱和度',100,0,'%',.005),('midtoneLuminance',0,-.25,.25,'中间调明度',100,0,'',.005),
    ('highlightHue',40,0,360,'高光色相',1,0,'°',1),('highlightSaturation',0,0,.3,'高光饱和度',100,0,'%',.005),
    ('highlightLuminance',0,-.25,.25,'高光明度',100,0,'',.005),('balance',0,-1,1,'色轮平衡',100,0,'',.01),
    ('blending',.5,0,1,'区域混合',100,0,'%',.01),('intensity',1,0,1,'分级强度',100,0,'%',.01),
]
RAW = [
    ('exposure',0,-5,5,'RAW 曝光',1,0,' EV',.01),('temperature',None,2000,12000,'RAW 色温',1,0,' K',1),
    ('tint',None,-150,150,'RAW 色调',1,0,'',1),('highlights',.7,0,1,'RAW 局部影调',100,0,'%',.01),
    ('shadows',0,-1,1,'RAW 阴影提升',100,0,'',.01),('contrast',None,0,1,'RAW 解码对比',100,0,'%',.01),
    ('blackLevel',None,-1,1,'RAW 黑电平偏置',100,0,'',.01),('detail',None,0,3,'RAW 解码细节',100,0,'',.01),
    ('colorNoise',None,0,1,'RAW 色彩降噪',100,0,'%',.01),('luminanceNoise',None,0,1,'RAW 亮度降噪',100,0,'%',.01),
    ('sharpness',None,0,1,'RAW 解码锐度',100,0,'%',.01),('moire',None,0,1,'RAW 摩尔纹抑制',100,0,'%',.01),
]
EXPORT = [
    ('quality',.95,.1,1,'JPEG 质量',100,0,'%',.01),('longEdge',0,0,20000,'限制长边',1,0,' px',1),
    ('dpi',300,36,1200,'输出 DPI',1,0,' dpi',1),
]
LEVELS = [
    ('inputBlack',0,0,.49,'输入黑场',255,0,'',1/255),
    ('gamma',1,.2,3,'中间调',1,0,'',.01),
    ('inputWhite',1,.51,1,'输入白场',255,0,'',1/255),
    ('outputBlack',0,0,.49,'输出黑场',255,0,'',1/255),
    ('outputWhite',1,.51,1,'输出白场',255,0,'',1/255),
]
CALIBRATION = [('shadowTint',0,-1,1,'阴影色调',100,0,'',.01)]
for channel,label in [('red','红原色'),('green','绿原色'),('blue','蓝原色')]:
    CALIBRATION += [(channel+'Hue',0,-.15,.15,label+'色相',600,0,'°',1/600),
                    (channel+'Saturation',0,-1,1,label+'饱和度',100,0,'',.01)]
RANGE = [('center',35,0,360,'范围中心色相',1,0,'°',1),('width',45,5,180,'色彩范围宽度',1,0,'°',1),
         ('softness',.5,.05,1,'范围过渡',100,0,'%',.01),('hue',0,-.5,.5,'范围色相偏移',200,0,'',.005),
         ('saturation',0,-1,1,'范围饱和度',100,0,'',.01),('luminance',0,-.5,.5,'范围明度',200,0,'',.005)]
SELECTIVE=[]
for band,title in [('red','红色'),('yellow','黄色'),('green','绿色'),('cyan','青色'),('blue','蓝色'),('magenta','洋红'),('white','白色'),('neutral','中性色'),('black','黑色')]:
    for channel,label in [('Cyan','青色'),('Magenta','洋红'),('Yellow','黄色'),('Black','黑色')]:
        SELECTIVE.append((band+channel,0,-1,1,title+' · '+label,100,0,'',.01))
TABLES = [
    ('GlobalAdjustments','global','tone',GLOBAL,{}),
    ('BeautySettings','beauty','portrait',BEAUTY,{'enabled':('Bool','false')}),
    ('RAWSettings','raw','raw',RAW,{'draft':('Bool','false'),'lensCorrection':('Bool?','nil')}),
    ('DetailSettings','detail','detail',DETAIL,{}),('EffectSettings','effects','style',EFFECTS,{}),
    ('GeometrySettings','geometry','geometry',GEOMETRY,{'cropAspect':('Float','0')}),
    ('ColorGrade','color.grading','grading',GRADING,{}),
    *[('LevelsChannel','color.levels.'+channel,'levels',LEVELS,{}) for channel in ('master','red','green','blue')],
    ('CalibrationSettings','color.calibration','calibration',CALIBRATION,{}),
    ('ColorRangeSettings','color.range','range',RANGE,{}),
    ('SelectiveColorSettings','color.selective','selective',SELECTIVE,{'absolute':('Bool','false')}),
    ('ExportSettings','export','output',EXPORT,{'format':('ExportFormat','.jpeg'),'colorSpace':('ExportColorSpace','.sRGB'),'bitDepth':('Int','16'),'preserveEXIF':('Bool','false'),'nameTemplate':('String','"{name}_Luma_{id}"')}),
]

def literal(value):
    return str(value).lower() if isinstance(value,bool) else str(value)

def struct(name, rows, extra):
    fields = {r[0]:('Float?' if r[1] is None else ('Int' if name=='ExportSettings' and r[0] in ('longEdge','dpi') else 'Float'), 'nil' if r[1] is None else literal(r[1])) for r in rows}
    fields.update(extra)
    lines=[f'public struct {name}: Codable, Equatable, Sendable {{']
    lines += [f'    public var {key}: {typ} = {default}' for key,(typ,default) in fields.items()]
    lines += ['    public init() {}','    private enum CodingKeys: String, CodingKey { case '+','.join(fields)+' }','    public init(from decoder: Decoder) throws {','        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)']
    for key,(typ,default) in fields.items():
        lines.append(f'        {key} = try c.decodeIfPresent({typ.rstrip("?")}.self, forKey: .{key})'+('' if typ.endswith('?') else f' ?? {key}'))
    return '\n'.join(lines+['    }','}'])

def number(row):
    value={'type':'number','minimum':row[2],'maximum':row[3]}
    if row[1] is None:return {'anyOf':[value,{'type':'null'}],'default':None}
    return {**value,'default':row[1]}

def obj(props,required=None):
    result={'type':'object','additionalProperties':False,'properties':props}
    if required:result['required']=required
    return result

def main():
    pro='// Generated by Scripts/generate_pro_parameters.py. Edit definitions there.\nimport Foundation\n\n'
    pro+='public enum ExportColorSpace: String, Codable, CaseIterable, Sendable { case sRGB, displayP3, adobeRGB1998 }\n'
    unique={name:(rows,extra) for name,_,_,rows,extra in TABLES}
    pro+='\n\n'.join(struct(name,rows,extra) for name,(rows,extra) in unique.items())+'\n'
    pro+='''
public struct LevelsSettings: Codable, Equatable, Sendable {
    public var master=LevelsChannel(),red=LevelsChannel(),green=LevelsChannel(),blue=LevelsChannel()
    public init() {}
    private enum CodingKeys: String,CodingKey {case master,red,green,blue}
    public init(from decoder: Decoder)throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        master=try c.decodeIfPresent(LevelsChannel.self,forKey:.master) ?? master
        red=try c.decodeIfPresent(LevelsChannel.self,forKey:.red) ?? red
        green=try c.decodeIfPresent(LevelsChannel.self,forKey:.green) ?? green
        blue=try c.decodeIfPresent(LevelsChannel.self,forKey:.blue) ?? blue
    }
}
'''
    (ROOT/'Packages/PhotoDomain/Sources/ProSettings.swift').write_text(pro)
    defs=[]
    for name,prefix,group,rows,_ in TABLES:
        for row in rows:
            key,default,lo,hi,title,scale,offset,unit,step=row
            fallback=6500 if key=='temperature' else (0.5 if default is None and key in ('contrast','colorNoise','luminanceNoise','sharpness') else 0)
            fn='optional' if default is None else ('integer' if name=='ExportSettings' and key in ('longEdge','dpi') else 'scalar')
            defs.append(f'        .{fn}("{prefix}.{key}", "{title}", .{group}, \\.{prefix}.{key}, {lo}...{hi}, defaultValue: {fallback if default is None else default}, step: {step}, scale: {scale}, offset: {offset}, unit: "{unit}")')
    defs.append('        .scalar("color.intensity", "风格强度", .style, \\.color.intensity, 0...1, defaultValue: 0.8, step: 0.01, scale: 100, offset: 0, unit: "%")')
    for band,title in [('red','红色'),('orange','橙色'),('yellow','黄色'),('green','绿色'),('aqua','青色'),('blue','蓝色'),('purple','紫色'),('magenta','洋红')]:
        for key,label,lo,hi,scale in [('hue','色相',-.2,.2,500),('saturation','饱和度',-1,1,100),('luminance','明度',-.5,.5,200)]:
            defs.append(f'        .hsl(.{band}, "{title}{label}", \\.{key}, {lo}...{hi}, scale: {scale})')
    generated='// Generated by Scripts/generate_pro_parameters.py.\nimport Foundation\n\nextension ParameterCatalog {\n    public static let all: [ParameterDescriptor] = [\n'+',\n'.join(defs)+'\n    ]\n}\n'
    (ROOT/'Packages/PhotoDomain/Sources/ParameterDefinitions.swift').write_text(generated)
    schema_path=ROOT/'Packages/PhotoDomain/Sources/Resources/edit-recipe.schema.json'
    legacy_path=schema_path.with_name('edit-recipe-v1.schema.json')
    if not legacy_path.exists():legacy_path.write_bytes(schema_path.read_bytes())
    legacy=json.loads(legacy_path.read_text());schema=json.loads(json.dumps(legacy))
    schema['$id']='https://lumastudio.local/schema/edit-recipe-v2.json';schema['title']='LumaStudio EditRecipe v2'
    props=schema['properties'];props['version']={'type':'integer','enum':[2]}
    for name,prefix,_,rows,extra in TABLES:
        target=obj({row[0]:number(row) for row in rows})
        for key,(typ,default) in extra.items():
            if typ in ('Bool','Bool?'):target['properties'][key]={'type':'boolean'} if typ=='Bool' else {'anyOf':[{'type':'boolean'},{'type':'null'}]}
        if prefix.startswith('color.'):
            node=props['color']
            parts=prefix.split('.')[1:]
            for part in parts[:-1]:node=node['properties'].setdefault(part,obj({}))
            node['properties'][parts[-1]]=target
        else:props[prefix]=target
    props['color']['properties']['enabled']={'type':'boolean','default':True}
    filter_ids=['natural','portrait','film','warm','cool','clean','ivory','rose','peach','softPortrait','amber','golden','copper','sunset','silver','mono','matteMono','noir','forest','jade','ocean','alpine','faded','vintage','instant','cinema','tealOrange','night','pastel','airy']
    props['color']['properties']['lut']={'anyOf':[{'type':'null'},{'type':'string','enum':filter_ids},{'type':'string','pattern':'^user_[a-f0-9]{64}$'}]}
    props['color']['properties']['hsl']['items']['required']=['band']
    props['geometry']['properties']['cropAspect']={'type':'number','minimum':0,'maximum':3}
    props['export']['properties'].update({'format':{'type':'string','enum':['jpeg','png','tiff']},'colorSpace':{'type':'string','enum':['sRGB','displayP3','adobeRGB1998']},'bitDepth':{'type':'integer','enum':[8,16]},'nameTemplate':{'type':'string','maxLength':128}})
    for points in props['color']['properties']['curve']['properties'].values():points['maxItems']=16
    props['masks']['maxItems']=16
    mask=props['masks']['items'];mask['properties']['kind']['enum'].append('brush')
    mask['properties']['adjustments']=props['global']
    mask['properties'].update({'detail':props['detail'],'inverted':{'type':'boolean'},'feather':{'type':'number','minimum':0,'maximum':.1},'brushSize':{'type':'number','minimum':.002,'maximum':.3},'flow':{'type':'number','minimum':.01,'maximum':1},'strokes':{'type':'array','maxItems':128,'items':obj({'points':{'type':'array','minItems':1,'maxItems':2048,'items':obj({'x':{'type':'number','minimum':0,'maximum':1},'y':{'type':'number','minimum':0,'maximum':1}},['x','y'])},'size':{'type':'number','minimum':.002,'maximum':.3},'flow':{'type':'number','minimum':.01,'maximum':1}},['points','size','flow'])}})
    props['lockedParameters']={'type':'array','maxItems':256,'items':{'type':'string','maxLength':100,'pattern':'^[A-Za-z0-9_.-]+$'}}
    schema['required']=['version']
    schema_path.write_text(json.dumps(schema,ensure_ascii=False,indent=2)+'\n')
    print(f'Generated v2 settings, strict schema and {len(defs)} scalar descriptors.')

if __name__=='__main__':main()
