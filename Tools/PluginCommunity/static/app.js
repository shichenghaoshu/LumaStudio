'use strict';
const $=s=>document.querySelector(s), $$=s=>Array.from(document.querySelectorAll(s));
const kinds={lut:'LUT',recipe:'调色配方',localAdjustment:'局部工具',aiTool:'AI 工具'},icons={lut:'◐',recipe:'≋',localAdjustment:'◌',aiTool:'✧'},roles={photographer:'摄影师',colorist:'调色师',developer:'开发者'};
const state={user:null,nav:'explore',kind:'',selected:null,items:[],installed:[],native:!!window.webkit?.messageHandlers?.lumaPlugins,authRegister:false,file:null,package:null,preview:null,busy:false,plannerMode:'current',requests:{},request:0,detailRequest:0,offset:0,total:0,hasMore:false,author:''};
const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=l=>l.type==='commercial'?`${l.currency==='CNY'?'¥':'$'}${(l.priceCents/100).toFixed(2)} · 商业授权`:l.type==='openSource'?`开源 · ${l.spdx}`:'免费 · 作者许可';
function notice(message=''){ $('#notice').textContent=message; }
async function api(path,options={}){
  const response=await fetch(path,{...options,credentials:'same-origin',headers:{'Content-Type':'application/json',...(options.headers||{})}});
  let data;try{data=await response.json();}catch{throw new Error('服务返回内容无效，请检查社区服务');}
  if(!response.ok)throw new Error(data.error?.message||`服务请求失败（${response.status}）`);
  return data;
}
function host(action,extra={}){
  if(!state.native){notice('请在 Mac 编辑器的创作中心中试用与执行。此页面可以搜索、收藏、投稿和下载插件。');return;}
  window.webkit.messageHandlers.lumaPlugins.postMessage({action,...extra});
}
window.lumaHostResult=result=>{
  state.busy=false;
  if(!result.ok){notice(result.message||'操作未完成');return;}
  if(result.installed)state.installed=result.installed;
  if(result.recipe){state.file={name:'Mac 当前配方.json',text:JSON.stringify(result.recipe)};state.package=null;$('#package-file').value='';$('#file-status').textContent='已载入 Mac 当前配方';$('#publish-form').elements.kind.value='recipe';$('#wizard').hidden=false;$$('#wizard input,#wizard select,#wizard textarea').forEach(x=>x.disabled=false);updateWizard();}
  if(result.preview){state.preview={id:result.id,...result.preview};if(state.selected?.manifest.id===result.id)renderDetail(state.selected);}
  if(result.message)notice(result.message);
  if(state.nav==='installed')load();else if(state.selected)renderDetail(state.selected);
};
function account(){ $('#account').textContent=state.user?`${state.user.name} · ${state.user.id}`:'登录 / 成为创作者'; }
async function load(keepPage=false){
  if(keepPage!==true)state.offset=0;
  $('#pagination').hidden=true;
  const request=++state.request;notice();
  if(state.nav==='installed'){
    if(!state.native){$('#results').innerHTML='<p class="empty">已安装列表由 Mac 编辑器维护。<br>请从编辑器打开创作中心。</p>';$('#detail').innerHTML='';return;}
    state.items=state.installed.map(i=>({manifest:i.manifest,installed:true,sha256:i.sha256,rating:{count:0,average:null}}));renderList();return;
  }
  if(['favorites','mine','following'].includes(state.nav)&&!state.user){$('#results').innerHTML='<p class="empty">登录后查看你的收藏与作品。</p>';$('#detail').innerHTML='';return;}
  $('#results').innerHTML='<p class="empty">正在读取作品…</p>';
  try{
    const q=new URLSearchParams({q:$('#search').value,kind:state.kind,sort:$('#sort').value,offset:state.offset,limit:24});
    if(state.author)q.set('author',state.author);
    if(state.nav==='following')q.set('following','1');
    if(state.nav==='favorites')q.set('favorites','1');if(state.nav==='mine')q.set('mine','1');
    const result=await api('/api/plugins?'+q);if(request!==state.request)return;
    state.items=result.items;state.total=result.total;state.hasMore=result.hasMore;renderList();
    $('#pagination').hidden=result.total===0;$('#page-status').textContent=`${state.offset+1}–${state.offset+result.items.length} / ${result.total} 个作品`;$('#previous-page').disabled=state.offset===0;$('#next-page').disabled=!result.hasMore;
  }catch(error){if(request!==state.request)return;$('#results').innerHTML='<p class="empty">无法读取作品，请启动社区服务后刷新。</p>';notice(error.message);}
}
function renderList(){
  $('#results').innerHTML=state.items.length?state.items.map(item=>{const m=item.manifest;return `<button class="result ${state.selected?.manifest.id===m.id?'selected':''}" data-plugin="${escape(m.id)}"><div class="result-head"><span class="kind-icon">${icons[m.kind]}</span><div><strong>${escape(m.name)}</strong><small>${escape(m.author.name)} · ${kinds[m.kind]}</small></div></div><p>${escape(m.summary)}</p><div class="meta"><span>${escape(money(m.license))}</span><span>${item.installed?'已安装':item.example?'<span class="badge">原创示例</span>':item.rating.count?`★ ${item.rating.average} · ${item.rating.count} 条`:'暂无评分'}</span></div></button>`;}).join(''):'<p class="empty">暂无作品。<br>发布你的风格或调整搜索条件。</p>';
  $$('[data-plugin]').forEach(b=>b.onclick=()=>select(b.dataset.plugin));
  if(state.selected&&state.items.some(i=>i.manifest.id===state.selected.manifest.id))select(state.selected.manifest.id);
  else if(state.items.length)select(state.items[0].manifest.id);
  else $('#detail').innerHTML='<div class="empty-detail"><span>◈</span><h2>这里等待你的作品</h2><p>上传 LUT、调色配方、局部工具或 AI 方法。</p></div>';
}
async function select(id){
  const request=++state.detailRequest;
  try{
    const item=state.nav==='installed'?state.items.find(i=>i.manifest.id===id):await api('/api/plugins/'+encodeURIComponent(id));
    if(request!==state.detailRequest)return;
    state.selected=item;$$('[data-plugin]').forEach(b=>b.classList.toggle('selected',b.dataset.plugin===id));renderDetail(item);
  }catch(error){notice(error.message);}
}
function aiControls(id){
  return `<label>本次规划器<select id="plugin-planner"><option value="current" ${state.plannerMode==='current'?'selected':''}>使用当前模型设置</option><option value="rules" ${state.plannerMode==='rules'?'selected':''}>本地规则（无需密钥）</option></select></label><label>补充修图要求<input id="plugin-request" maxlength="1000" placeholder="可选，例如：不要美白" value="${escape(state.requests[id]||'')}"></label>`;
}
function renderDetail(item){
  const m=item.manifest, installed=state.installed.find(i=>i.manifest.id===m.id),p=state.preview?.id===m.id?state.preview:null;
  const commercial=m.license.type==='commercial',canInstall=item.canInstall||!commercial;
  $('#detail').innerHTML=`<div class="reveal"><div class="plugin-top"><div><span class="eyebrow">${kinds[m.kind]} / V${escape(m.version)}</span><h2>${escape(m.name)}</h2><button class="author" id="view-author">${escape(m.author.name)} ↗</button></div><button class="star ${item.favorite?'saved':''}" id="favorite" aria-label="${item.favorite?'取消收藏':'收藏作品'}">${item.favorite?'★':'☆'}</button></div><p class="description">${escape(m.summary)}</p><div class="tags">${m.tags.map(t=>`<span># ${escape(t)}</span>`).join('')}${item.example?'<span>原创示例作品</span>':''}</div><div class="actions"><button id="trial" class="primary" ${!state.native||state.busy?'disabled':''}>${state.busy?'正在处理…':'在当前照片试用'}</button><button id="install" class="quiet" ${!state.native||!canInstall?'disabled':''}>${installed?(installed.manifest.version===m.version?'重新安装':'安装新版本'):'安装插件'}</button><button id="download" class="quiet" ${!canInstall?'disabled':''}>下载包</button></div>${commercial?'<p class="hint">'+escape(money(m.license))+' · 购买与分账尚未开放。非作者目前仅可在 Mac 中预览。</p>':''}${!state.native?'<p class="hint">此浏览器可投稿与下载；真实照片试用需要从 Mac 编辑器打开。</p>':''}<div class="preview">${p?`<img src="${p.after}" alt="当前照片的插件试用效果"><span class="label" id="preview-label">试用效果 · 尚未应用</span>`:'<p>选择编辑器里的照片，点击试用<br>在此查看真实渲染结果</p>'}</div>${p?'<div class="inline"><button class="quiet" id="before-after">按住查看原图</button><span class="hint">预览未写入当前编辑</span></div>':''}${installed?`<div class="installed-actions"><button data-run="apply">应用到当前照片</button><button data-run="batch">导出已选照片</button><button data-run="agent">Agent 调用</button><button id="uninstall">卸载</button></div><p class="hint">已安装 v${escape(installed.manifest.version)}。批量逐张保留构图、蒙版与锁定；输出到图库 Exports。</p>`:''}<div class="details"><section><h3>执行范围</h3><p>${m.supports.map(c=>({editor:'单张编辑',batch:'批量处理',agent:'AI Agent'}[c])).join(' / ')}<br>${m.capabilities.map(c=>({'edit.recipe':'修改已声明的修图参数','edit.localMask':'添加或更新此插件自己的局部区域','asset.lut':'读取包内校验过的 LUT','agent.plan':'调用宿主已配置的 AI 规划器'}[c])).join(' · ')}</p>${m.kind==='aiTool'?aiControls(m.id):''}</section><section><h3>许可与来源</h3><p>${escape(money(m.license))}</p><details><summary>查看使用条款</summary><p class="terms">${escape(m.license.terms)}</p></details>${m.license.sourceURL?`<p><a href="${safeURL(m.license.sourceURL)}" target="_blank" rel="noreferrer">源码与创作来源 ↗</a></p>`:''}</section>${!item.installed?`<section><h3>使用反馈 ${item.rating.count?`· ${item.rating.average} / 5`:'· 暂无评分'}</h3>${(item.reviews||[]).map(r=>`<div class="review"><small>${escape(r.name)} · ${r.score} / 5</small><p>${escape(r.comment||'已评分')}</p></div>`).join('')}${state.user&&!item.owner?`<form id="rating-form" class="rating-form"><select name="score" aria-label="作品评分">${[5,4,3,2,1].map(n=>`<option value="${n}" ${item.myRating?.score===n?'selected':''}>${n} / 5</option>`).join('')}</select><textarea name="comment" maxlength="600" rows="2" placeholder="描述适用照片与实际效果">${escape(item.myRating?.comment||'')}</textarea><button class="quiet">保存评分与评论</button></form>`:`<p>${item.owner?'你是此作品作者，不能给自己的作品评分。':'登录后分享使用反馈。'}</p>`}<p class="hint">下载 ${item.downloads||0} 次 · 试用请求 ${item.trials||0} 次 · 收藏 ${item.favorites||0} 人<br>下载次数包括版本重取，不等于安装人数。</p><button id="report" class="quiet">反馈资源或许可问题</button></section>`:''}<section><h3>版本记录</h3>${(item.versions||[{version:m.version,sha256:item.sha256}]).map(v=>`<p>v${escape(v.version)} <span class="hint">${escape((v.sha256||'').slice(0,16))}…</span></p>`).join('')}${state.native?`<div class="inline"><select id="install-version" aria-label="安装版本">${(item.versions||[{version:m.version}]).map(v=>`<option value="${escape(v.version)}">v${escape(v.version)}</option>`).join('')}</select><button id="use-version" class="quiet">安装此版本</button></div>`:''}<p class="hint">版本不可覆盖。更新与回退均保留原有编辑结果。</p></section></div></div>`;
  $('#view-author').onclick=()=>showAuthor(m.author.id);
  $('#favorite').onclick=async()=>{if(!needUser())return;try{state.selected=await api(`/api/plugins/${m.id}/favorite`,{method:'PUT',body:JSON.stringify({value:!item.favorite})});renderDetail(state.selected);}catch(e){notice(e.message);}};
  if($('#plugin-request'))$('#plugin-request').oninput=e=>state.requests[m.id]=e.target.value;
  if($('#plugin-planner'))$('#plugin-planner').onchange=e=>state.plannerMode=e.target.value;
  if($('#use-version'))$('#use-version').onclick=()=>{host('install',{id:m.id,version:$('#install-version').value});};
  $('#trial').onclick=()=>run('trial');$('#install').onclick=()=>run('install');
  $('#download').onclick=async()=>{if(state.native){host('download',{id:m.id});return;}try{const r=await api(`/api/plugins/${m.id}/package?mode=download`);download(r,m.id+'.lumaplugin');notice('已下载插件包；在 Mac 安装前仍会验证内容。');}catch(e){notice(e.message);}};
  $$('[data-run]').forEach(b=>b.onclick=()=>run(b.dataset.run));
  if($('#uninstall'))$('#uninstall').onclick=()=>host('uninstall',{id:m.id});
  if($('#before-after')){const b=$('#before-after'),image=$('.preview img');const reset=()=>{image.src=p.after;$('#preview-label').textContent='试用效果 · 尚未应用';};b.onpointerdown=()=>{image.src=p.before;$('#preview-label').textContent='原图';};b.onpointerup=reset;b.onpointerleave=reset;b.onblur=reset;}
  if($('#rating-form'))$('#rating-form').onsubmit=async e=>{e.preventDefault();try{const f=e.currentTarget;state.selected=await api(`/api/plugins/${m.id}/rating`,{method:'PUT',body:JSON.stringify({score:Number(f.elements.score.value),comment:f.elements.comment.value})});renderDetail(state.selected);notice('反馈已保存');}catch(error){notice(error.message);}};
  if($('#report'))$('#report').onclick=()=>{const reason=prompt('请描述资源、效果或许可问题（会记录到当前社区）');if(reason)api(`/api/plugins/${m.id}/report`,{method:'POST',body:JSON.stringify({reason})}).then(r=>notice(r.message)).catch(e=>notice(e.message));};
}
function run(action){if(state.busy)return;if(['apply','agent'].includes(action))state.preview=null;state.busy=true;notice(action==='batch'?'正在准备已选照片的独立输出…':'正在执行…');const request=$('#plugin-request')?.value||'';host(action,{id:state.selected.manifest.id,request,localRules:state.plannerMode==='rules'});}
function safeURL(value){try{const u=new URL(value);return u.protocol==='https:'?escape(u.href):'#';}catch{return '#';}}
function needUser(){if(state.user)return true;$('#auth-dialog').showModal();return false;}
function download(value,name){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(value,null,2)],{type:'application/json'}));a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);}
async function showAuthor(id){
  try{
    const a=await api('/api/authors/'+id),own=state.user?.id===id;
    $('#profile-content').innerHTML=`<h2>${escape(a.name)}</h2><p>${a.roles.map(r=>roles[r]).join(' / ')}</p><p class="profile-bio">${escape(a.bio||'这位创作者还没有填写介绍。')}</p><p>${a.pluginCount} 个作品 · ${a.followers} 位关注者 · 关注 ${a.followingCount} 人</p>${!own?`<button id="follow-author" class="primary">${a.following?'取消关注':'关注创作者'}</button>`:''}<button id="author-works" class="quiet">查看全部作品</button>${a.plugins.map(p=>`<button class="profile-line" data-profile-plugin="${escape(p.manifest.id)}">${escape(p.manifest.name)}<span class="hint">${escape(money(p.manifest.license))} · ${p.rating.count?`${p.rating.average} / 5`:'暂无评分'}</span></button>`).join('')}${own?`<form id="profile-form"><h3>编辑创作者资料</h3><label>昵称<input name="name" required maxlength="80" value="${escape(a.name)}"></label><label>个人介绍<textarea name="bio" rows="3" maxlength="600">${escape(a.bio)}</textarea></label><fieldset><legend>创作身份</legend>${Object.entries(roles).map(([r,label])=>`<label><input type="checkbox" name="profileRole" value="${r}" ${a.roles.includes(r)?'checked':''}>${label}</label>`).join('')}</fieldset><button class="primary">保存资料</button></form><button id="logout" class="quiet">退出登录</button>`:''}<p id="profile-status" role="status" class="hint"></p><p class="hint">作品与关注数来自当前社区真实记录。收益与结算尚未接通。</p>`;
    if(!$('#profile-dialog').open)$('#profile-dialog').showModal();
    if($('#follow-author'))$('#follow-author').onclick=async()=>{if(!state.user){$('#profile-dialog').close();needUser();return;}try{await api('/api/authors/'+id+'/follow',{method:'PUT',body:JSON.stringify({value:!a.following})});await showAuthor(id);if(state.nav==='following')load();}catch(e){$('#profile-status').textContent=e.message;}};
    const openWorks=async()=>{state.author=id;state.nav='author';state.selected=null;$('#search').value='';state.kind='';$$('[data-kind]').forEach(b=>b.classList.toggle('active',b.dataset.kind===''));$$('[data-nav]').forEach(b=>b.classList.remove('active'));$('#page-title').textContent=a.name+' 的作品';$('#profile-dialog').close();await load();};
    $('#author-works').onclick=openWorks;
    $$('[data-profile-plugin]').forEach(b=>b.onclick=async()=>{await openWorks();await select(b.dataset.profilePlugin);});
    if($('#profile-form'))$('#profile-form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,button=f.querySelector('button');button.disabled=true;try{const result=await api('/api/me',{method:'PUT',body:JSON.stringify({name:f.elements.name.value,bio:f.elements.bio.value,roles:$$('input[name=profileRole]:checked').map(c=>c.value)})});state.user=result.user;account();await showAuthor(id);$('#profile-status').textContent='资料已保存。已发布插件包保留发布时的作者信息。';}catch(error){$('#profile-status').textContent=error.message;}finally{button.disabled=false;}};
    if($('#logout'))$('#logout').onclick=async()=>{try{await api('/api/logout',{method:'POST',body:'{}'});state.user=null;account();$('#profile-dialog').close();load();}catch(e){$('#profile-status').textContent=e.message;}};
  }catch(e){notice(e.message);}
}
$('#previous-page').onclick=()=>{state.offset=Math.max(0,state.offset-24);load(true);};
$('#next-page').onclick=()=>{if(state.hasMore){state.offset+=24;load(true);}};
$$('[data-close]').forEach(b=>b.onclick=()=>$('#'+b.dataset.close).close());
$$('[data-nav]').forEach(b=>b.onclick=()=>{state.nav=b.dataset.nav;state.author='';$$('[data-nav]').forEach(x=>x.classList.toggle('active',x===b));$('#page-title').textContent=b.firstChild.textContent;state.selected=null;load();if(state.nav==='installed')host('installed');});
$$('[data-kind]').forEach(b=>b.onclick=()=>{state.kind=b.dataset.kind;$$('[data-kind]').forEach(x=>x.classList.toggle('active',x===b));load();});
let searchTimer;$('#search').oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(load,220);};$('#sort').onchange=load;$('#refresh').onclick=()=>{if(state.native)host('installed');load();};
$('#account').onclick=()=>state.user?showAuthor(state.user.id):$('#auth-dialog').showModal();
$('#auth-mode').onclick=()=>{state.authRegister=!state.authRegister;$('#auth-title').textContent=state.authRegister?'创建创作者账号':'登录创作中心';$('#auth-submit').textContent=state.authRegister?'创建账号':'登录';$('#auth-mode').textContent=state.authRegister?'已有账号，返回登录':'创建创作者账号';$('#name-label').hidden=!state.authRegister;$('#roles').hidden=!state.authRegister;$('#auth-form').elements.name.required=state.authRegister;$('#auth-error').textContent='';};
$('#auth-form').onsubmit=async e=>{e.preventDefault();$('#auth-submit').disabled=true;$('#auth-error').textContent='';try{const f=e.currentTarget,body={id:f.elements.id.value,password:f.elements.password.value};if(state.authRegister){body.name=f.elements.name.value;body.roles=$$('input[name=role]:checked').map(c=>c.value);}const r=await api(state.authRegister?'/api/register':'/api/login',{method:'POST',body:JSON.stringify(body)});state.user=r.user;f.elements.password.value='';account();$('#auth-dialog').close();load();}catch(error){$('#auth-error').textContent=error.message;}finally{$('#auth-submit').disabled=false;}};
$('#create').onclick=()=>{if(!needUser())return;$('#publish-dialog').showModal();};
$('#package-file').onchange=async e=>{state.file=null;state.package=null;try{const file=e.target.files[0];if(!file)return;if(file.size>12*1024*1024)throw new Error('文件超过 12 MB');const text=await file.text();state.file={name:file.name,text};if(file.name.endsWith('.lumaplugin'))state.package=JSON.parse(text);$('#wizard').hidden=!!state.package;$$('#wizard input,#wizard select,#wizard textarea').forEach(x=>x.disabled=!!state.package);$('#file-status').textContent=state.package?`${state.package.manifest.name} · ${state.package.manifest.version} · 作者 ${state.package.manifest.author.id}（作者需与账号一致）`:file.name;if(file.name.endsWith('.cube'))$('#publish-form').elements.kind.value='lut';else if(!state.package)$('#publish-form').elements.kind.value=JSON.parse(text).version===2?'recipe':'localAdjustment';updateWizard();}catch(error){$('#publish-error').textContent=error.message;}};
$('#current-recipe').onclick=()=>host('exportRecipe');
async function draft(){
  if(state.package)return state.package;
  const f=$('#publish-form'),v=n=>f.elements[n].value;
  const m={id:v('pluginID'),version:v('version'),name:v('title'),summary:v('summary'),author:{id:state.user.id,name:state.user.name,roles:state.user.roles},kind:v('kind'),tags:v('tags').split(/[,，]/).map(t=>t.trim()).filter(Boolean),license:{type:v('licenseType'),terms:v('terms')},supports:['editor','batch','agent']};
  if(m.license.type==='openSource'){m.license.spdx=v('spdx');m.license.sourceURL=v('sourceURL');}if(m.license.type==='commercial'){m.license.priceCents=Math.round(Number(v('price'))*100);m.license.currency=v('currency');}
  let payload,assets=[];
  if(m.kind==='lut'){if(!state.file?.name.endsWith('.cube'))throw new Error('请选择 CUBE 文件');const bytes=new TextEncoder().encode(state.file.text),hash=await crypto.subtle.digest('SHA-256',bytes);let binary='';for(const n of bytes)binary+=String.fromCharCode(n);assets=[{path:'look.cube',sha256:Array.from(new Uint8Array(hash)).map(b=>b.toString(16).padStart(2,'0')).join(''),data:btoa(binary)}];payload={lutAsset:'look.cube',intensity:.8};m.capabilities=['asset.lut','edit.recipe'];}
  if(m.kind==='recipe'){if(!state.file)throw new Error('请选择 v2 配方 JSON 或使用当前配方');const recipe=JSON.parse(state.file.text);if(recipe.version!==2)throw new Error('需要 v2 配方');payload={groups:$$('#recipe-groups input:checked').map(c=>c.value),recipe};m.capabilities=['edit.recipe'];}
  if(m.kind==='localAdjustment'){payload={mask:JSON.parse(state.file?state.file.text:v('instruction'))};m.capabilities=['edit.localMask'];}
  if(m.kind==='aiTool'){payload={instruction:v('instruction')};m.capabilities=['agent.plan','edit.recipe'];}
  return {schemaVersion:1,manifest:m,payload,assets};
}
$('#download-draft').onclick=async()=>{try{const p=await draft();if(state.native){host('exportDraft',{package:p});return;}download(p,p.manifest.id+'.lumaplugin');$('#publish-error').textContent='已导出草稿；发布时会校验完整协议。';}catch(e){$('#publish-error').textContent=e.message;}};
$('#publish-form').onsubmit=async e=>{e.preventDefault();$('#publish-submit').disabled=true;$('#publish-error').textContent='';try{if(!state.user)throw new Error('请先登录');const p=await draft();const result=await api('/api/plugins',{method:'POST',body:state.package?state.file.text:JSON.stringify(p)});$('#publish-dialog').close();state.selected=result;state.nav='mine';state.author='';$$('[data-nav]').forEach(b=>b.classList.toggle('active',b.dataset.nav==='mine'));$('#page-title').textContent='我的作品';await load();notice('作品已通过服务端校验并发布到当前社区');}catch(error){$('#publish-error').textContent=error.message;}finally{$('#publish-submit').disabled=false;}};
(async()=>{try{const config=await api('/api/config');if(!config.localOnly){$('#community-storage').innerHTML='在线社区 · 创作者共享作品<br>商业收款与分账尚未接通';$('#account-storage').textContent='账号与加盐密码摘要保存在社区服务器；插件投稿对社区用户可见。照片试用在 Mac 本地完成。';}state.user=(await api('/api/me')).user;account();if(state.native)host('installed');await load();}catch(error){notice(error.message);}})();

function updateWizard(){
  const f=$('#publish-form'),kind=f.elements.kind.value,type=f.elements.licenseType.value;
  $('#recipe-groups').hidden=kind!=='recipe';$('#instruction-label').hidden=!['aiTool','localAdjustment'].includes(kind);
  f.elements.spdx.closest('label').hidden=type!=='openSource';f.elements.sourceURL.closest('label').hidden=type!=='openSource';
  f.elements.price.closest('label').hidden=type!=='commercial';f.elements.currency.closest('label').hidden=type!=='commercial';
  f.elements.sourceURL.required=type==='openSource';f.elements.price.required=type==='commercial';
  $('#current-recipe').hidden=!state.native;
}
$('#publish-form').elements.kind.onchange=updateWizard;$('#publish-form').elements.licenseType.onchange=updateWizard;updateWizard();
