#!/usr/bin/env python3
"""Build an offline gallery from actual Core Image test outputs, never synthetic edits.

Visual thesis: quiet darkroom, one large aligned photograph, restrained warm accent.
Content: scene/style controls, original/result split, contact sheet, short provenance.
Interaction: instant scene/style selection and a movable comparison boundary.
"""
import argparse
import base64
import html
import io
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
LOOKS=[('original','原图'),('xiaomiLeicaClassic','徕卡 · 经典'),('xiaomiLeicaVivid','徕卡 · 生动'),('hasselbladNatural','哈苏 · 自然'),('hasselbladXPan','哈苏 · XPan 色彩'),('leicaStandard','徕卡 · 微暖'),('leicaChrome','徕卡 · Chrome'),('leicaMonochrom','徕卡 · 黑白'),('fujiClassicChrome','富士 · 经典灰调'),('fujiVelvia','富士 · 鲜艳'),('fujiAstia','富士 · 柔和'),('fujiAcros','富士 · 黑白')]
SCENES={'1645822':'户外人像','13427041':'低照度人像','26953099':'影棚人像','5097939':'山林湖水','9680246':'城市落日','1936741':'霓虹夜景'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--evidence',default='Artifacts/ColorEmulation');parser.add_argument('--output',default='Deliverables/Candidates/0.5.5-24/Color-Comparison.html');args=parser.parse_args()
    evidence=ROOT/args.evidence;sources=json.loads((ROOT/'work/color-emulation/sources.json').read_text())
    records={x['id']:x for x in sources};ordered=['1645822','13427041','26953099','5097939','9680246','1936741']
    boards=evidence/'Boards';boards.mkdir(parents=True,exist_ok=True)
    font=ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc',21)
    data=[]
    for id in ordered:
        photos={};board=Image.new('RGB',(1680,1140),'#131514');draw=ImageDraw.Draw(board)
        for i,(look,title) in enumerate(LOOKS):
            path=evidence/'Photos'/f'pexels-{id}-{look}.png'
            with Image.open(path) as original:
                original.load();image=original.convert('RGB')
            stream=io.BytesIO();image.save(stream,format='JPEG',quality=91,icc_profile=Image.open(path).info.get('icc_profile'))
            photos[look]='data:image/jpeg;base64,'+base64.b64encode(stream.getvalue()).decode()
            thumb=image.copy();thumb.thumbnail((404,326))
            x=(i%4)*420;y=(i//4)*380
            board.paste(thumb,(x+(420-thumb.width)//2,y+10+(326-thumb.height)//2))
            draw.text((x+12,y+346),title,font=font,fill='#e5e5db')
        board.save(boards/f'pexels-{id}.jpg',quality=92)
        data.append({'id':id,'name':SCENES[id],'source':records[id]['source'],'creator':records[id]['creator'],'images':photos})
    payload=json.dumps(data,ensure_ascii=False,separators=(',',':'))
    labels=json.dumps(LOOKS,ensure_ascii=False)
    document='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LumaStudio · 相机仿色对照</title><style>
:root{color-scheme:dark;--paper:#e8e7dd;--muted:#a5aaa4;--accent:#d9bc80}*{box-sizing:border-box}body{margin:0;background:#101311;color:var(--paper);font:15px -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}header,main,footer{max-width:1440px;margin:auto;padding:26px 34px}header{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #ffffff18}header b{font-size:25px;letter-spacing:-1px}header span{font-size:12px;color:var(--muted)}h1{font-size:30px;font-weight:500;letter-spacing:-1px;margin:9px 0 10px}.intro{color:var(--muted);line-height:1.7;margin:0 0 24px}.controls{display:flex;gap:18px;flex-wrap:wrap;align-items:center;margin-bottom:18px}.controls label{display:flex;align-items:center;gap:9px;color:var(--muted);font-size:13px}select,button{font:inherit;color:var(--paper);background:#1d231f;border:1px solid #ffffff25;padding:9px 12px;border-radius:5px}select:focus-visible,button:focus-visible,input:focus-visible{outline:2px solid var(--accent);outline-offset:3px}.stage{position:relative;height:min(62vh,680px);min-height:300px;background:#090c0a;overflow:hidden}.stage img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}.stage .label{position:absolute;top:16px;background:#101311db;padding:7px 10px;font-size:12px;z-index:3}.before{left:16px}.after{right:16px}#line{position:absolute;top:0;bottom:0;left:50%;width:1px;background:var(--accent);z-index:2;pointer-events:none}.splitbar{display:flex;align-items:center;gap:20px;padding:16px 0;border-bottom:1px solid #ffffff18}.splitbar label{white-space:nowrap;color:var(--muted);font-size:12px}input[type=range]{accent-color:var(--accent);flex:1;min-width:0}.splitbar button{font-size:12px;padding:7px 11px;white-space:nowrap}.caption{display:flex;justify-content:space-between;gap:14px;flex-wrap:wrap;font-size:12px;color:var(--muted);margin:14px 0 26px}.caption a,footer a{color:var(--muted)}.gallery{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:20px 14px}.look{padding:0;border:0;background:transparent;text-align:left;min-width:0;border-radius:0}.look img{width:100%;height:140px;object-fit:contain;background:#090c0a;display:block;outline:1px solid transparent}.look span{display:block;font-size:12px;padding-top:9px}.look[aria-pressed=true] img{outline-color:var(--accent)}.look[aria-pressed=true] span{color:var(--accent)}footer{margin-top:24px;border-top:1px solid #ffffff18;color:var(--muted);font-size:12px;line-height:1.8;padding-bottom:40px}footer p{max-width:950px}footer ul{padding-left:18px}.note{font-size:12px;color:var(--accent)}@media(max-width:900px){header,main,footer{padding-left:20px;padding-right:20px}.gallery{grid-template-columns:repeat(4,minmax(0,1fr))}.look img{height:120px}.stage{height:54vh}.splitbar{gap:9px}}@media(max-width:560px){.gallery{grid-template-columns:repeat(3,minmax(0,1fr));gap:16px 10px}.look img{height:110px}header b{font-size:22px}.splitbar button{padding:7px}.controls{gap:10px}.controls label{width:100%}select{flex:1;min-width:0}.splitbar label{display:none}h1{font-size:26px}}
</style><header><b>LumaStudio</b><span>0.5.5 · 相机仿色</span></header><main><h1>同一张照片，比较不同色彩</h1><p class="intro">选择场景与风格，移动分界线对照原图。以下为实际引擎导出的效果，仿色力度均为 100%。</p>
<div class="controls"><label>场景<select id="scene" aria-label="选择场景"></select></label><label>风格<select id="look" aria-label="选择风格"></select></label><span class="note">品牌风格的独立近似 · 非官方色彩配置</span></div>
<div class="stage"><img id="base" alt="原始色彩"><img id="result" alt="仿色后的照片"><span class="label before">原图</span><span class="label after" id="title"></span><div id="line"></div></div>
<div class="splitbar"><label for="split">对照分界</label><button id="before">只看原图</button><input id="split" aria-label="原图与仿色分界线" type="range" min="0" max="100" value="50"><button id="after">只看效果</button></div>
<div class="caption"><span id="credit"></span><span>只改变色彩 · 不裁切 · 本页未叠加美颜</span></div><div class="gallery" id="gallery" aria-label="所有风格预览"></div>
</main><footer><p>小米徕卡经典／生动为 LumaStudio 原创调色；其余 9 种色彩变换基于 <a href="https://github.com/yingwang/filmic/tree/219e30356cc80ae90e98d78be2af5da149d49116">Filmic（MIT，Ying Wang）</a>。这些仿色没有经过真实相机配对校准，不代表徕卡、哈苏、富士、小米或 OPPO 的专有算法。XPan 仅应用色彩，没有改变照片比例；颗粒与暗角可在软件中单独调整。</p><p>照片依 <a href="https://www.pexels.com/license/">Pexels License</a> 使用，摄影师与原始页面链接见上方署名。不暗示摄影师或人物对软件的认可。所有照片均为已经处理的公开 JPEG，不能据此评估手机 RAW 或 Log 视频匹配精度。本文件包含全部照片与界面资源，使用时不上传图片。</p></footer>
<script>const scenes=__SCENES__,looks=__LOOKS__;
const byId=id=>document.getElementById(id),scene=byId('scene'),look=byId('look');
for(const s of scenes){const o=document.createElement('option');o.value=s.id;o.textContent=s.name;scene.append(o)}
for(const [id,title] of looks){if(id==='original')continue;const o=document.createElement('option');o.value=id;o.textContent=title;look.append(o)}
for(const [id,title] of looks){if(id==='original')continue;const b=document.createElement('button');b.className='look';b.type='button';b.dataset.look=id;b.setAttribute('aria-label','查看'+title);const img=document.createElement('img');img.alt=title;const label=document.createElement('span');label.textContent=title;b.append(img,label);b.onclick=()=>{look.value=id;update()};byId('gallery').append(b)}
function split(){const v=Number(byId('split').value);byId('result').style.clipPath=`inset(0 0 0 ${v}%)`;byId('line').style.left=v+'%'}
function update(){const s=scenes.find(s=>s.id===scene.value);byId('base').src=s.images.original;byId('result').src=s.images[look.value];byId('title').textContent=looks.find(x=>x[0]===look.value)[1];byId('credit').replaceChildren();const a=document.createElement('a');a.href=s.source;a.textContent='照片：'+s.creator+' / Pexels';a.target='_blank';a.rel='noopener';byId('credit').append(a);for(const b of document.querySelectorAll('.look')){b.querySelector('img').src=s.images[b.dataset.look];b.setAttribute('aria-pressed',String(b.dataset.look===look.value))}split()}
scene.onchange=look.onchange=update;byId('split').oninput=split;byId('before').onclick=()=>{byId('split').value=100;split()};byId('after').onclick=()=>{byId('split').value=0;split()};update();
</script></html>'''.replace('__SCENES__',payload).replace('__LOOKS__',labels)
    out=ROOT/args.output;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(document)
    print(f'{out}: {out.stat().st_size} bytes, {len(data)*len(LOOKS)} embedded actual photographs')

if __name__=='__main__':main()
