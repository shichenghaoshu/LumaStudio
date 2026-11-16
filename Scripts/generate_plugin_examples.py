#!/usr/bin/env python3
"""Reproducible original example contributions; no copied camera/firmware assets."""
import base64, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Resources/Plugins/Examples'
AUTHOR={'id':'lumastudio','name':'LumaStudio 示例作者','roles':['photographer','colorist','developer']}
LICENSE={'type':'openSource','spdx':'MIT','sourceURL':'https://github.com/shichenghaoshu/LumaStudio/tree/main/Resources/Plugins/Examples','terms':'MIT License. Copyright (c) 2026 LumaStudio contributors. Permission is granted to use, copy, modify, merge, publish, distribute, sublicense and sell copies, subject to retaining the copyright and permission notice. Provided AS IS, without warranty. Full license: Resources/Plugins/LICENSE.txt.'}
def package(slug,name,summary,kind,tags,caps,payload,assets=None):
    return {'schemaVersion':1,'manifest':{'id':'studio.luma.'+slug,'version':'1.0.0','name':name,'summary':summary,'author':AUTHOR,'kind':kind,'license':LICENSE,'tags':tags,'capabilities':caps,'supports':['editor','batch','agent']},'payload':payload,'assets':assets or []}
def examples():
    # Smooth, subtle warm transform, red-fastest standard CUBE order.
    lines=['TITLE "Luma Original Warm"','LUT_3D_SIZE 17','DOMAIN_MIN 0 0 0','DOMAIN_MAX 1 1 1']
    for b in range(17):
        for g in range(17):
            for r in range(17):
                rgb=[r/16,g/16,b/16];rgb=[min(1,max(0,v+(1-v)*v*a)) for v,a in zip(rgb,[.10,.018,-.08])]
                lines.append(' '.join(f'{v:.7f}' for v in rgb))
    cube=('\n'.join(lines)+'\n').encode()
    return [
      package('warm-light','暖光 · 原创 LUT','轻暖肤色与较冷暗部，适合日常人像。首版原创示例，可修改后重新发布。','lut',['人像','暖调','示例'],['asset.lut','edit.recipe'],{'lutAsset':'warm-light.cube','intensity':.8},[{'path':'warm-light.cube','sha256':hashlib.sha256(cube).hexdigest(),'data':base64.b64encode(cube).decode()}]),
      package('clear-portrait','通透人像配方','调整影调、肤质与色彩。只同步声明的分组，保留目标照片构图和局部蒙版。','recipe',['人像','通透','示例'],['edit.recipe'],{'groups':['tone','color','beauty'],'recipe':{'version':2,'global':{'exposure':.18,'contrast':1.06,'highlights':-.15,'shadows':.1,'saturation':.96},'beauty':{'enabled':True,'strength':.65,'texturePreservation':.72},'color':{'enabled':True}}}),
      package('subject-light','人物补光 · 局部工具','调用 Apple Vision 人物区域并提亮，不改动背景与已有局部编辑。需要照片中可识别的人物。','localAdjustment',['局部','人物','示例'],['edit.localMask'],{'mask':{'id':'subject_light','kind':'subject','amount':.75,'adjustments':{'exposure':.55,'shadows':.12},'feather':.02}}),
      package('portrait-assistant','人像精修助手','把作者的修图方法交给宿主规划器执行；使用当前模型设置，不携带 API 密钥。','aiTool',['AI','人像','示例'],['agent.plan','edit.recipe'],{'instruction':'适度提亮人物，保留高光，做通透自然美颜，不要瘦脸，不要大眼。用户补充：${request}'})]
if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    for item in examples():
        p=OUT/(item['manifest']['id']+'.lumaplugin');p.write_text(json.dumps(item,ensure_ascii=False,indent=2)+'\n')
    print(f'{len(examples())} original example packages → {OUT}')
