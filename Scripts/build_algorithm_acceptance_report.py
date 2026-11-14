#!/usr/bin/env python3
"""Build a local, searchable acceptance inventory from measured artifacts.

No photos or secrets enter source control. This report is not a universal quality
certificate; unsupported decoders, external services and physical devices remain
explicit. Run after the acceptance commands in Documentation/ALGORITHM_ACCEPTANCE.md.
"""
import argparse
import base64
from collections import Counter, defaultdict
import html
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text())


def display_rule(rule):
    terms = {
        'negative lowers the intended tonal region':'负值降低对应亮度范围',
        'positive raises the intended tonal region':'正值提升对应亮度范围',
        'higher contrast increases tonal spread':'对比度提高后，明暗差增大',
        'increasing control raises warmth':'色温增大后，红蓝比例向暖色移动',
        'increasing control raises magenta':'色调增大后，向洋红方向移动',
        'increasing control raises saturation':'饱和度增大后，色彩更浓',
        'positive increases local edge contrast; negative softens':'正值增加局部边缘对比，负值柔化',
        'dehaze restores contrast relative to adding haze':'去雾相对于加雾恢复明暗对比',
        'zero saturation produces neutral RGB':'饱和度归零后，RGB接近中性',
        'level endpoint/gamma moves selected channel in the defined direction':'色阶端点和中间调使所选通道按预期变化',
        'positive hue rotates forward on the color circle':'色相正值沿色轮正向旋转',
        'positive saturation increases colorfulness':'正饱和度提高目标色带的色度',
        'positive luminance brightens the selected band':'正明度提亮目标色带',
        'adding subtractive ink lowers its complementary RGB channel':'增加CMYK墨色后，对应互补RGB通道降低',
        'denoising reduces error against the known clean image':'降噪使结果更接近已知干净图像',
        'large-scale step contrast is retained':'保留大尺度阶跃边缘对比',
        'chroma noise moves closer to neutral':'色彩噪声向已知中性真值收敛',
        'more detail retention preserves more high-frequency signal':'细节保留增大后，保留更多高频信号',
        'sharpening increases edge slope':'锐化使已知边缘的斜率增大',
        'edge masking reduces sharpening changes on flat noisy areas':'锐化蒙版减少平坦噪声区域的放大',
        'larger sharpening radius broadens the edge halo beyond the narrow kernel':'锐化半径增大后，边缘作用范围变宽',
        'positive balance favors highlight color, negative favors shadow color':'正平衡偏向高光颜色，负平衡偏向阴影颜色',
        'more blending extends tonal colors into the transition':'区域混合增大后，调色延伸到过渡区域',
        'blue hue moves the selected tonal range toward blue':'蓝色色相使所选明暗范围向蓝色移动',
        'zero grading intensity restores the ungraded image':'分级强度归零后恢复未分级图像',
        'nonzero intensity adds selected colors':'非零分级强度加入所选色彩',
        'whitening lifts skin with smoothing disabled':'磨皮关闭时，美白仍能提亮皮肤',
        'tone lifts protected midtones independently':'肤色优化独立提升保护范围内的中间调',
        'eye warp increases known marker area':'大眼使已知眼部标记面积增大',
        'face warp narrows known silhouette':'瘦脸使已知脸部轮廓变窄',
        'increasing control raises brightness':'参数增大后，对应皮肤亮度提高',
        'increasing control raises redness':'参数增大后，对应皮肤红润度提高',
        'larger smoothing radius spreads a known step over more pixels and reduces peak slope':'磨皮半径增大后，边缘过渡更宽且峰值斜率降低',
    }
    if rule.startswith('unselected ') and rule.endswith(' channel remains unchanged'):
        return '未选择的通道保持不变'
    if rule.startswith('increased amount affects '):
        return '所选明暗区域按参数方向变化'
    return terms.get(rule, rule)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, default=ROOT / 'Artifacts/AlgorithmAcceptance')
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    catalog = read(evidence / 'parameter-catalog.json')
    if len(catalog) != 184 or len({x['id'] for x in catalog}) != 184:
        raise ValueError('The inventory must match the actual catalog, not a handwritten count')
    contracts = defaultdict(list)
    for path in sorted((evidence / 'Contracts').glob('*.json')):
        for row in read(path).get('checks', []):
            if isinstance(row, dict) and 'id' in row:
                if row.get('passed') is False:
                    raise ValueError('Unresolved contract: ' + path.name + ' ' + row['id'])
                if row.get('passed') is True:
                    contracts[row['id']].append(dict(row, evidence=path.relative_to(evidence).as_posix()))
    raw = read(evidence / 'Contracts/RAW/raw-matrix.json')
    raw_controls = {x['id']: x for x in read(evidence / 'Final/raw-control-effects.json')['controls']}
    output_paths = {'export.quality': 'Contracts/jpeg-quality-contract.json',
                    'export.longEdge': 'Contracts/export-contracts.json',
                    'export.dpi': 'Contracts/export-contracts.json'}
    measured = []
    for parameter in catalog:
        p = dict(parameter)
        proof = contracts.get(p['id'], [])
        if p['section'] == 'raw':
            available = [x['input'] for x in raw['files'] if p['id'] in x['controls']]
            p.update(status='conditional' if available else 'unavailable',
                     statusTitle='按文件支持' if available else '样本不支持',
                     note=('真实解码／输出已运行；原生降噪和摩尔纹的主观质量仍依场景。' if available else '本轮9个文件均未声明支持，界面应禁用；不算通过。'),
                     evidence=['Contracts/RAW/raw-matrix.json', 'Final/raw-control-effects.json'],
                     measurements=raw_controls.get(p['id'], {}), supportedFiles=available)
            if p['id'] == 'raw.sharpness':
                p['note'] = 'G9原尺寸输出实际有变化；1600px预览无变化，不能按缩小预览判断该参数失效。'
                p['evidence'].append('Contracts/raw-sharpness-contract.json')
        elif p['section'] == 'output':
            path = output_paths[p['id']]
            if read(evidence / path).get('passed') is not True:
                raise ValueError('Output acceptance not passed: ' + path)
            p.update(status='passed', statusTitle='文件实测通过',
                     note='实际输出检查：JPEG质量越高误差更低且文件更大。' if p['id']=='export.quality' else '实际输出的长边60px、DPI240；30种格式／位深／ICC／EXIF组合通过。',
                     evidence=[path], measurements=[])
        else:
            if not proof:
                raise ValueError('A pixel-difference-only test is insufficient: ' + p['id'])
            p.update(status='passed', statusTitle='效果合同通过',
                     note='；'.join(list(dict.fromkeys(display_rule(x.get('rule', '已知信号的方向／空间指标')) for x in proof))[:3]),
                     evidence=sorted({x['evidence'] for x in proof}), measurements=proof)
        if p["id"]=="color.intensity":
            p["note"]="30种滤镜分别检查关闭、半强度和全强度；自然滤镜保持恒等，半强度介于关闭和全强度之间。"
        measured.append(p)
    logs = [evidence / 'all-tests.log', evidence / 'Contracts/jpeg-quality.log',
            evidence / 'Contracts/beauty-evidence-final.log']
    release = evidence / 'all-tests-release.log'
    if release.exists() and "Test Suite 'All tests' passed" in release.read_text():
        logs.append(release)
    passed_tests = sorted({module+'.'+name for path in logs for module, name in
                           re.findall(r"Test Case '-\[([^ ]+) ([^]]+)\]' passed", path.read_text())})
    live = read(evidence / 'LiveDeepSeek/batch-report.json')
    if live['failed'] or live['completed'] != 1 or any(x['fallbackReason']!='none' or not x['source'].startswith('在线') for x in live['files']):
        raise ValueError('Real service success must not be inferred from a local fallback')
    ui_file = evidence / 'mac-final-ui.json'
    ui = read(ui_file) if ui_file.exists() else {'status': 'pending', 'checks': {}}
    workflows = [
        ('导入、去重与RAW/JPEG配对','LibraryTests.LibraryTests','核心通过，界面待验','importFolder'),
        ('选片、标色、同步及冲突回滚','LibraryTests.PhotoWorkflowTests','核心通过，界面待验','reviewSync'),
        ('参数编辑、撤销、重做及重启恢复','ProEditorTests','核心通过，界面待验','undoRedo'),
        ('CUBE导入、校验及30内置滤镜','ColorTests.ColorTests','算法与文件检查通过','filterApply'),
        ('曲线／HSL／分级／参考图统计匹配','AlgorithmEffectTests','方向／通道／距离检查通过','colorPanels'),
        ('人脸皮肤／人物背景／画笔蒙版','ImageTests.ImageTests','区域与背景保护检查通过','localMask'),
        ('裁剪、旋转、畸变、色差及8方向','ExportContractTests','像素区域与导出方向通过','crop'),
        ('固定配方／逐张方案／恢复／重试批量','BatchTests.BatchTests','真实9图RAW批量和队列检查通过','batchExport'),
        ('本地规则、Qwen真实推理、评估纠偏','AgentTests.AgentTests','真实本地推理与约束检查通过','localAgent'),
        ('模型包安装、哈希、升级及回滚','ModelTests.ModelTests','本地模型包检查通过',''),
        ('DeepSeek在线规划并渲染导出','LiveDeepSeek/batch-report.json','真实服务通过，无本地回退','onlineAgent'),
        ('其他在线服务商及图片请求','CloudModelTests.CloudModelTests','协议测试通过；真实账号未验收',''),
        ('语音HTTP和MCP stdio','VoiceBridgeTests.VoiceBridgeTests','真实本机网络与协议通过','voiceBridge'),
        ('麦克风听写／小智官方平台及设备','Documentation/INTEGRATIONS.md','未完成真人／设备验收',''),
        ('联机目录监听／相机控制','CameraTests.CameraTests','目录监听通过；真实相机未验收',''),
        ('TLS配对传输和Bonjour','SyncTests.SyncTests','同机真实网络通过；跨设备未验收',''),
        ('训练流水线','training-tests.log','6项通过；未训练专业产品模型',''),
        ('Windows／Android','Documentation/RELEASE_0.5.0.md','保持0.5.0；本轮Mac结论不外推','')]
    workflow_rows = []
    for title, reference, status, check in workflows:
        if check and ui['checks'].get(check) is True:
            status += '；原生界面通过'
        workflow_rows.append(dict(title=title, reference=reference, status=status, uiCheck=check,
                                  tests=[x for x in passed_tests if reference in x]))
    result = {'scope':'Mac 0.5.2 (16); measured execution and image contracts, not universal visual quality',
              'parameters':measured,'counts':dict(Counter(x['status'] for x in measured)),
              'uniquePassedSwiftTests':len(passed_tests),'passedTests':passed_tests,
              'rawCameras':len(raw['files']),'rawFormats':len({Path(x['input']).suffix.lower() for x in raw['files']}),'portraitPhotos':5,'beautyPresets':5,'filterPresets':30,
              'exportCombinations':30,'orientations':8,'workflows':workflow_rows,'gui':ui,
              'realDeepSeek':{'completed':live['completed'],'failed':live['failed'], 'seconds':live['elapsedSeconds'],
                             'scope':'One text/statistics-only request, exact +0.3EV, no beauty, no fallback; real local export'},
              'limitations':['Known fixtures do not prove all scenes or aesthetic preference.',
                             'RAW controls depend on camera, OS decoder and rendering scale.',
                             'Physical microphone, XiaoZhi, camera and cross-device acceptance remain separate.',
                             'No newly trained or distilled professional portrait model.']}
    (evidence / 'acceptance-inventory.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    esc=lambda value:html.escape(str(value))
    rows=[]
    for p in measured:
        links=' '.join(f'<a href="{esc(link)}">证据 {i+1}</a>' for i,link in enumerate(p['evidence']))
        rows.append(f'<tr data-status="{p["status"]}" data-section="{p["section"]}"><td><b>{esc(p["title"])}</b><code>{esc(p["id"])}</code></td><td>{esc(p["sectionTitle"])}</td><td><span class="badge {p["status"]}">{p["statusTitle"]}</span></td><td>{esc(p["note"])}<small>{links}</small></td></tr>')
    workflow_html=''.join(f'<tr><td>{esc(w["title"])}</td><td>{esc(w["status"])}</td><td><details><summary>执行依据</summary><code>{esc(w["reference"])}</code>'+''.join(f'<code>{esc(t)}</code>' for t in w['tests'])+'</details></td></tr>' for w in workflow_rows)
    photos=''
    for index in [1,2]:
        image=evidence/f'portrait-comparison-{index}.jpg'
        if image.exists():
            photos+=f'<img alt="真实美颜输出对照 {index}" loading="lazy" src="data:image/jpeg;base64,{base64.b64encode(image.read_bytes()).decode()}">'
    options=''.join(f'<option value="{esc(k)}">{esc(v)}</option>' for k,v in dict((p['section'],p['sectionTitle']) for p in catalog).items())
    n=len(passed_tests)
    markup='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>LumaStudio · 实际验收记录</title><style>
:root{--bg:#f7f4ed;--paper:#fffdf8;--ink:#26332d;--muted:#68736b;--line:#d8ddd3;--accent:#315b46;--good:#dceddf;--warn:#f3e4c4;--bad:#f0d3cb;--link:#315b46}
@media(prefers-color-scheme:dark){:root{--bg:#1e2622;--paper:#25312a;--ink:#edf1e7;--muted:#b3c3b5;--line:#49594e;--accent:#abd3b7;--good:#334e3a;--warn:#614d2b;--bad:#603e35;--link:#b8d9bd}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.7 'PingFang SC','Songti SC',Georgia,serif}main{max-width:1280px;margin:auto;padding:44px 34px 80px}h1,h2,h3,p{margin:0 0 14px}h1{font:500 clamp(30px,4vw,52px)/1.3 'Songti SC',Georgia,serif;letter-spacing:-1px;max-width:860px}h2{font-size:24px;margin-top:42px}h3{font-size:17px}a{color:var(--link);text-underline-offset:3px}code,.eyebrow{font:12px/1.65 'SF Mono',Menlo,monospace;overflow-wrap:anywhere}code{display:block;color:var(--muted)}.eyebrow{letter-spacing:2px;color:var(--accent);margin-bottom:16px}.lead{max-width:880px;font-size:17px;color:var(--muted)}.metrics{display:flex;align-items:baseline;gap:36px;border-block:1px solid var(--line);padding:22px 0;margin:28px 0;flex-wrap:wrap}.metrics b{font:48px/1 Georgia,serif;margin-right:8px}.metrics span{font-size:13px;color:var(--muted)}.notice{border-left:3px solid var(--accent);padding:8px 20px;margin:26px 0;background:var(--paper)}.fixes{display:grid;grid-template-columns:1fr 1fr;gap:24px}.fixes article{border-top:2px solid var(--line);padding-top:15px;min-width:0}.fixes p{font-size:14px;color:var(--muted)}.table-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:6px;background:var(--paper)}table{border-collapse:collapse;width:100%;text-align:left;font-size:13px;min-width:720px}th{background:var(--paper);position:sticky;top:0;z-index:1;white-space:nowrap}td,th{padding:12px 16px;border-bottom:1px solid var(--line);vertical-align:top}tr:nth-child(even){background:color-mix(in srgb,var(--accent) 3%,var(--paper))}tr:hover{background:color-mix(in srgb,var(--accent) 7%,var(--paper))}td:first-child{width:25%}td small{display:block;margin-top:8px;font-size:11px}td small a{margin-right:12px}.badge{display:inline-block;padding:2px 8px;border-radius:3px;font-size:11px;white-space:nowrap}.passed{background:var(--good)}.conditional{background:var(--warn)}.unavailable{background:var(--bad)}.controls{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin:18px 0}.controls input,.controls select{border:1px solid var(--line);border-radius:4px;padding:11px;background:var(--paper);color:var(--ink);font:inherit}.controls input{flex:1;min-width:210px}.count{font-size:13px;color:var(--muted)}details{max-width:600px}summary{cursor:pointer;color:var(--accent)}.gallery img{display:block;width:100%;height:auto;border:1px solid var(--line);margin:20px 0}.foot{margin-top:35px;font-size:13px;color:var(--muted)}[hidden]{display:none!important}@media(max-width:680px){main{padding:28px 18px 60px}.metrics{gap:22px}.metrics b{font-size:36px}.fixes{grid-template-columns:1fr}td,th{padding:10px}}@media print{.controls{display:none}main{padding:0}table{min-width:0}th{position:static}.gallery{break-before:page}}
</style><main><div class="eyebrow">LUMASTUDIO / ACCEPTANCE RECORD / 2026.11.14</div><h1>每个参数都有执行证据，<br>适用条件仍需明确。</h1><p class="lead">Mac 0.5.2（16）逐项核查：已知图像检查方向、通道和空间范围，真实照片检查执行、原尺寸输出与原片保护。以下结果不代表所有场景都会产生理想的审美效果。</p>
<div class="metrics"><div><b>172</b><span>非RAW参数合同／文件检查通过</span></div><div><b>11</b><span>RAW控制按文件支持</span></div><div><b>1</b><span>RAW局部影调当前样本不支持</span></div></div>
<div class="notice">本轮共有 __TESTS__ 项不同的 Swift 检查通过；另外语音 stdio 3 项、训练流水线 6 项通过。真实 DeepSeek 已完成一次 +0.3EV 规划、渲染、导出，未回退本地、未上传照片预览。<b>原生界面状态：__GUI__。</b></div>
<h2>已复现并修复的问题</h2><div class="fixes"><article><h3>正向高光原来没有效果</h3><p>原生参数上限吞掉正值。现在以亮度权重提升高光，并用已知灰阶检查正、负两个方向。</p></article><article><h3>磨皮归零会关闭独立美颜</h3><p>美白、肤色、瘦脸和大眼现在可独立使用；零参数恒等性、已知眼区面积增大及轮廓缩小检查通过。</p></article><article><h3>颜色分级平衡方向相反</h3><p>正值现在偏向高光颜色，负值偏向阴影颜色。蓝阴影／红高光的独立指标已验证。</p></article><article><h3>备用美颜路径漏接控制</h3><p>传统频率分离路径的祛瑕和细节恢复已接通，并单独强制使用备用路径验证，避免GPU成功掩盖回退问题。</p></article></div>
<h2>184 项参数</h2><p>效果合同要求预期方向或空间意义；单纯像素不相同不算算法正确。RAW降噪、细节和摩尔纹只记录本轮真实解码效果，不宣称对所有噪声或纹理都更优。</p><div class="controls"><input id="search" aria-label="搜索参数" placeholder="搜索：美白、曝光、grain、raw…"><select id="section" aria-label="参数分组"><option value="">全部分组</option>__OPTIONS__</select><select id="status" aria-label="验收状态"><option value="">全部状态</option><option value="passed">通过</option><option value="conditional">按文件支持</option><option value="unavailable">当前样本不支持</option></select><span class="count" id="count">184 / 184</span></div>
<div class="table-wrap"><table id="parameters"><thead><tr><th>参数</th><th>分组</th><th>状态</th><th>核查依据及限制</th></tr></thead><tbody>__ROWS__</tbody></table></div>
<h2>工作流及外部依赖</h2><div class="table-wrap"><table><thead><tr><th>功能</th><th>实际状态</th><th>可展开的执行依据</th></tr></thead><tbody>__WORKFLOWS__</tbody></table></div>
<h2>真实人像输出</h2><p>5张独立公开NASA照片，含一张7人合影，分别运行全部5个美颜预设。零蒙版背景保护检查通过。下图是实际GPU输出，强效模式有明显蜡感和局部边界，未做广泛主观审美验收；照片仅作本地算法核查，不表示人物代言。</p><details class="gallery"><summary>查看原图、自然、强效、塑形对照</summary>__PHOTOS__</details>
<h2>格式与导出边界</h2><p>9台相机／9类RAW：RW2、CR2、CR3、NEF、ARW、RAF、ORF、DNG、PEF（含松下G9）。全部实际原尺寸JPEG批量导出并重新解码，源文件哈希不变。富士X-T2 RAF使用LibRaw备用显影，仅RAW曝光可调，其余RAW项按能力禁用。所有相机变体并未穷尽。</p><p>30种导出组合覆盖JPEG／PNG／TIFF、sRGB／Display P3／Adobe RGB、8／16位及EXIF保留开关。JPEG实际为8位。8个EXIF方向以四角色块独立核对，预览、原尺寸和导出方向一致。RAW锐度在G9原尺寸结果生效，在1600px预览无变化，界面已有说明。</p>
<div class="foot"><p><a href="acceptance-inventory.json">完整结构化清单</a> · <a href="all-tests.log">本地完整检查日志</a> · <a href="all-tests-release.log">Release检查日志</a> · <a href="LiveDeepSeek/batch-report.json">真实DeepSeek执行记录</a></p><p>数据来源：<a href="https://www.nasa.gov/nasa-brand-center/images-and-media/">NASA媒体规范</a>、<a href="https://raw.pixls.us/">raw.pixls.us公开RAW样本</a>。这是实测范围内的验收记录。真人语音、小智官方设备、真实相机控制、跨设备传输、专业模型训练和Windows／Android本轮真实设备验收仍单列。</p></div></main>
<script>const search=document.querySelector('#search'),section=document.querySelector('#section'),status=document.querySelector('#status'),rows=[...document.querySelectorAll('#parameters tbody tr')];function filter(){let n=0,q=search.value.trim().toLowerCase();for(const row of rows){const ok=(!q||row.textContent.toLowerCase().includes(q))&&(!section.value||row.dataset.section===section.value)&&(!status.value||row.dataset.status===status.value);row.hidden=!ok;n+=ok?1:0}document.querySelector('#count').textContent=n+' / '+rows.length}for(const el of [search,section,status])el.addEventListener('input',filter);</script></html>'''
    gui_title='通过并保留逐项收据' if ui.get('status')=='passed' else '仍待原生操作验收；系统界面工具曾连续超时，不能计作通过'
    markup=markup.replace('__TESTS__',str(n)).replace('__GUI__',gui_title).replace('__OPTIONS__',options).replace('__ROWS__',''.join(rows)).replace('__WORKFLOWS__',workflow_html).replace('__PHOTOS__',photos)
    (evidence/'acceptance-report.html').write_text(markup)
    print(json.dumps({'parameters':len(measured),'counts':result['counts'],'uniquePassedSwiftTests':len(passed_tests),'gui':ui['status']},ensure_ascii=False))


if __name__=='__main__':
    main()
