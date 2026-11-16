import SwiftUI
import WebKit
import PhotoCore

/// The marketplace shares its web UI with browser users. Only this fixed loopback
/// origin may ask the native host to install or process a photograph.
struct PluginCenterView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var service=PluginCommunityService()
    @State private var ready=false
    @State private var status="正在连接本机社区…"
    @State private var generation=UUID()
    private let endpoint=URL(string:"http://127.0.0.1:8791")!
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Label("创作中心",systemImage:"square.stack.3d.up").font(.headline)
                Spacer()
                Text("本机社区").font(.caption).foregroundStyle(.secondary)
                Button("关闭"){dismiss()}.keyboardShortcut(.cancelAction)
            }.padding(.horizontal,20).frame(height:49)
            Divider()
            if ready {PluginCommunityWebView(model:model,endpoint:endpoint).id(generation)}
            else {
                VStack(spacing:18) {
                    Image(systemName:"square.stack.3d.up").font(.system(size:44,weight:.ultraLight)).foregroundStyle(studioAccent)
                    Text("创作、分享与使用修图工具").font(.title2)
                    Text(status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:520)
                    Button("启动 / 重新连接本机社区"){Task{await connect()}}.buttonStyle(.borderedProminent)
                    Text("照片由 Mac 本地处理。投稿只上传插件包。\n收款和创作者分账服务尚未连接。").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.frame(minWidth:970,idealWidth:1120,minHeight:650,idealHeight:760).background(Color(white:0.07))
        .task {await connect()}
    }
    private func connect() async {
        do {try await service.ensureStarted(endpoint:endpoint);ready=true;generation=UUID()}
        catch {status=error.localizedDescription}
    }
}
@MainActor @Observable final class PluginCommunityService {
    private var process: Process?
    func ensureStarted(endpoint: URL) async throws {
        if await healthy(endpoint) {return}
        guard let resources=Bundle.main.resourceURL else {throw LumaError.notConnected}
        let bundled=resources.appendingPathComponent("PluginCommunity/LumaCommunity")
        let task=Process()
        if FileManager.default.isExecutableFile(atPath:bundled.path) {task.executableURL=bundled;task.arguments=["--seed-examples","--parent-pid",String(ProcessInfo.processInfo.processIdentifier)]}
        else {
            throw LumaError.unsupported("此开发构建尚未包含社区服务。请在项目目录运行 python3 Tools/PluginCommunity/server.py --seed-examples，再点击连接。正式安装包会附带本机服务。")
        }
        let logs=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/Community")
        try FileManager.default.createDirectory(at:logs,withIntermediateDirectories:true)
        let log=logs.appendingPathComponent("service.log")
        if !FileManager.default.fileExists(atPath:log.path){FileManager.default.createFile(atPath:log.path,contents:nil)}
        let handle=try FileHandle(forWritingTo:log);try handle.seekToEnd();task.standardOutput=handle;task.standardError=handle
        try task.run();process=task
        for _ in 0..<30 {
            if await healthy(endpoint) {return}
            if !task.isRunning {break}
            try await Task.sleep(for:.milliseconds(150))
        }
        throw LumaError.unsupported("本机社区启动失败，请检查服务日志或端口 8791 是否被占用。")
    }
    private func healthy(_ endpoint: URL) async -> Bool {
        var request=URLRequest(url:endpoint.appendingPathComponent("health"));request.timeoutInterval=1
        guard let (data,response)=try? await URLSession.shared.data(for:request),(response as? HTTPURLResponse)?.statusCode==200,
              let result=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {return false}
        return result["service"] as? String=="luma-plugin-community" && result["protocol"] as? Int==1
    }
}
struct PluginCommunityWebView: NSViewRepresentable {
    let model: AppModel,endpoint: URL
    func makeCoordinator()->Coordinator {Coordinator(model:model,endpoint:endpoint)}
    func makeNSView(context: Context)->WKWebView {
        let config=WKWebViewConfiguration();config.userContentController.add(context.coordinator,name:"lumaPlugins")
        let web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=context.coordinator;web.uiDelegate=context.coordinator
        context.coordinator.web=web;web.load(URLRequest(url:endpoint));return web
    }
    func updateNSView(_ nsView: WKWebView,context: Context) {}
    static func dismantleNSView(_ web: WKWebView,coordinator: Coordinator) {web.configuration.userContentController.removeScriptMessageHandler(forName:"lumaPlugins");web.navigationDelegate=nil;web.uiDelegate=nil}
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let model: AppModel,endpoint: URL
        weak var web: WKWebView?
        private var busy=false
        init(model: AppModel,endpoint: URL){self.model=model;self.endpoint=endpoint}
        private func sameOrigin(_ url: URL?)->Bool {url?.scheme==endpoint.scheme && url?.host==endpoint.host && url?.port==endpoint.port}
        func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            if sameOrigin(action.request.url) {decisionHandler(.allow)}
            else {decisionHandler(.cancel);if action.navigationType == .linkActivated,let url=action.request.url,url.scheme=="https" {NSWorkspace.shared.open(url)}}
        }
        func webView(_ webView: WKWebView,createWebViewWith configuration: WKWebViewConfiguration,for action: WKNavigationAction,windowFeatures: WKWindowFeatures)->WKWebView? {
            if let url=action.request.url,url.scheme=="https" {NSWorkspace.shared.open(url)};return nil
        }
        func webView(_ webView: WKWebView,runJavaScriptTextInputPanelWithPrompt prompt: String,defaultText: String?,initiatedByFrame frame: WKFrameInfo,completionHandler: @escaping (String?)->Void) {
            guard sameOrigin(frame.request.url) else {completionHandler(nil);return}
            let alert=NSAlert();alert.messageText="反馈作品问题";alert.informativeText=prompt
            let input=NSTextField(frame:NSRect(x:0,y:0,width:380,height:56));input.stringValue=defaultText ?? "";alert.accessoryView=input;alert.addButton(withTitle:"提交");alert.addButton(withTitle:"取消")
            completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
        }
        func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,sameOrigin(message.frameInfo.request.url),sameOrigin(web?.url),
                  let body=message.body as? [String:Any],let action=body["action"] as? String else {return}
            guard !busy else {respond(["ok":false,"message":"上一个插件操作尚未结束"]);return}
            busy=true
            Task {
                defer{busy=false}
                do {
                    if action=="installed" {respond(["ok":true,"installed":try await installedJSON()]);return}
                    if action=="exportRecipe" {respond(["ok":true,"recipe":try model.shareablePluginRecipe()]);return}
                    if action=="exportDraft" {
                        guard let package=body["package"] as? [String:Any] else {throw LumaError.corruptData("缺少插件草稿")}
                        let data=try JSONSerialization.data(withJSONObject:package),path=try model.savePluginPackage(data)
                        respond(["ok":true,"message":"插件包已验证并保存："+path]);return
                    }
                    guard let id=body["id"] as? String,id.count<=100,id.range(of:"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+){1,7}$",options:.regularExpression) != nil else {throw LumaError.corruptData("插件 ID 无效")}
                    let store=try PluginStore()
                    if action=="uninstall" {try await store.uninstall(id:id);respond(["ok":true,"installed":try await installedJSON(),"message":"插件已卸载；已生成的修图结果与 LUT 资源保留"]);return}
                    let request=body["request"] as? String ?? ""
                    guard request.count<=1000 else {throw LumaError.corruptData("补充要求过长")}
                    if ["install","trial","download"].contains(action) {
                        let (data,commercialAuthorized)=try await download(id:id,mode:action=="trial" ? "trial" : action=="download" ? "download" : "install",version:body["version"] as? String)
                        if action=="download" {
                            let path=try model.savePluginPackage(data)
                            respond(["ok":true,"message":"插件包已保存："+path])
                        } else if action=="install" {
                            _=try await store.install(data,commercialAuthorized:commercialAuthorized)
                            respond(["ok":true,"installed":try await installedJSON(),"message":"已安装。可应用到当前照片、批量导出或交给 Agent。"])
                        } else {
                            let preview=try await model.previewPlugin(try PluginPackage.decode(data),request:request)
                            respond(["ok":true,"id":id,"preview":preview,"message":"试用已完成，当前编辑尚未改变"])
                        }
                    } else if ["apply","batch","agent"].contains(action) {
                        let package=try await store.package(id:id)
                        let message=try await model.runInstalledPlugin(package,action:action,request:request)
                        respond(["ok":true,"message":message])
                    } else {throw LumaError.unsupported("未知的插件操作")}
                } catch {respond(["ok":false,"message":error.localizedDescription])}
            }
        }
        private func installedJSON() async throws -> Any {let items=await (try PluginStore()).all();return try JSONSerialization.jsonObject(with:JSONEncoder().encode(items))}
        private func download(id: String,mode: String,version: String?) async throws -> (Data,Bool) {
            if let version,version.range(of:"^(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})$",options:.regularExpression)==nil {throw LumaError.corruptData("版本格式错误")}
            var items=[URLQueryItem(name:"mode",value:mode)]
            if let version {items.append(URLQueryItem(name:"version",value:version))}
            let url=endpoint.appendingPathComponent("api/plugins/\(id)/package").appending(queryItems:items)
            var request=URLRequest(url:url);request.timeoutInterval=20
            let cookies=await web?.configuration.websiteDataStore.httpCookieStore.allCookies() ?? []
            request.allHTTPHeaderFields=HTTPCookie.requestHeaderFields(with:cookies.filter{$0.name=="luma_session" && $0.domain==endpoint.host})
            let config=URLSessionConfiguration.ephemeral;config.httpShouldSetCookies=false
            let session=URLSession(configuration:config);defer{session.finishTasksAndInvalidate()}
            let (data,response)=try await session.data(for:request)
            guard let http=response as? HTTPURLResponse,http.url?.host==endpoint.host,http.url?.port==endpoint.port else {throw LumaError.notConnected}
            guard http.statusCode==200 else {
                let error=(try? JSONSerialization.jsonObject(with:data) as? [String:Any])?["error"] as? [String:Any]
                throw LumaError.unsupported(error?["message"] as? String ?? "无法下载插件")
            }
            guard data.count<=PluginPackage.maxBytes,http.value(forHTTPHeaderField:"X-Package-SHA256")==PluginPackage.digest(data) else {throw LumaError.corruptData("社区插件下载校验失败")}
            // The origin's install endpoint enforces commercial ownership/entitlement.
            return (data,mode=="install")
        }
        private func respond(_ object: [String:Any]) {
            guard let data=try? JSONSerialization.data(withJSONObject:object),let json=String(data:data,encoding:.utf8) else {return}
            web?.evaluateJavaScript("window.lumaHostResult(\(json));",completionHandler:{_,_ in})
        }
    }
}
