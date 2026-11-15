import SwiftUI
import AppKit
struct MainWindow: View {
    @State private var model=AppModel()
    var body: some View {StudioRoot(model:model).frame(minWidth:1040,minHeight:680).onAppear{MacLifecycleDelegate.model=model}.onOpenURL{url in if url.scheme=="lumastudio" {model.pairingInput=url.absoluteString;model.sync.discover();model.syncPresented=true}}}
}

/// A normal folder browser remains available; paste/drop also lets a studio
/// open a known shared path without traversing the directory hierarchy.
struct MacDirectoryLocationSheet: View {
    @Bindable var model:AppModel
    let intent:AppModel.ImportIntent
    @State private var path=""
    @State private var browser:NSOpenPanel?
    private var title:String {
        switch intent {case .library:return "图库位置";case .folder:return "导入文件夹";case .inbox:return "收片文件夹";case .exportSingle,.exportBatch:return "导出位置";default:return "选择模型目录"}
    }
    private var action:String {
        switch intent {case .library:return "打开图库";case .folder:return "导入照片";case .inbox:return "开始监听";case .exportSingle:return "导出当前照片";case .exportBatch:return "开始批量导出";default:return "载入模型"}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Image(systemName:"folder").foregroundStyle(studioAccent);Text(title).font(.headline);Spacer()}
            Text(intent == .library ? "原片、编辑记录和导出结果将保存在这个文件夹。" : "粘贴文件夹路径，或从访达拖入文件夹。").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("文件夹路径",text:$path).textFieldStyle(.roundedBorder).accessibilityLabel("文件夹路径").onSubmit{submit()}
                Button("浏览…"){browse()}.disabled(browser != nil)
            }
            .dropDestination(for:URL.self) {urls,_ in guard let first=urls.first else{return false};path=first.path;return true}
            Text(intent == .folder || intent == .modelPackage ? "把现有文件夹拖到路径栏，或粘贴它的完整路径。" : "也可以把文件夹直接拖到路径栏。新路径会自动创建文件夹。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消"){model.directoryImportIntent=nil}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(action){submit()}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(path.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || browser != nil)
            }
        }.padding(24).frame(width:540).onAppear {
            switch intent {
            case .library:path=model.root.path
            case .exportSingle,.exportBatch:path=model.root.appendingPathComponent("Exports").path
            default:path=""
            }
        }
    }
    private func submit() {model.useDirectory(path,for:intent)}
    private func browse() {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true
        panel.allowedContentTypes=[.folder];panel.canCreateDirectories=true;panel.prompt="选择文件夹"
        panel.directoryURL=path.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures") : URL(fileURLWithPath:(path as NSString).expandingTildeInPath,isDirectory:true)
        browser=panel
        panel.begin {response in if response == .OK,let url=panel.url {path=url.path};browser=nil}
    }
}
