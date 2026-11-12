import SwiftUI
import PhotoCore
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

let studioAccent=Color(red:0.91,green:0.72,blue:0.43)
struct StudioRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            #if os(macOS)
            HStack(spacing:0) {
                MacWorkspaceRail(model:model)
                Divider()
                pageContent.frame(maxWidth:.infinity,maxHeight:.infinity)
            }.background(Color(white:0.08))
            #else
            TabView(selection:$model.page) {
                PadCaptureView(model:model).tabItem{Label("拍摄",systemImage:"camera")}.tag(AppModel.Page.capture)
                PadEditView(model:model).tabItem{Label("修图",systemImage:"slider.horizontal.3")}.tag(AppModel.Page.edit)
                PadBatchView(model:model).tabItem{Label("批量",systemImage:"square.grid.2x2")}.tag(AppModel.Page.batch)
            }
            #endif
        }
        .tint(studioAccent)
        #if !os(macOS)
        .fileImporter(isPresented:$model.importerPresented,allowedContentTypes:model.importTypes,allowsMultipleSelection:model.importMultiple,onCompletion:model.handleImport)
        #endif
        .alert("LumaStudio",isPresented:Binding(get:{model.message != nil},set:{if !$0 { model.message=nil }})) { Button("好"){model.message=nil} } message:{Text(model.message ?? "")}
        .sheet(isPresented:$model.syncPresented) { SyncPanel(model:model,sync:model.sync) }
        .sheet(isPresented:$model.modelManagerPresented) { LocalModelsPanel(model:model) }
        #if os(macOS)
        .sheet(isPresented:$model.integrationsPresented) { IntegrationSettingsView(model:model) }
        #endif
        .overlay(alignment:.bottom) {
            if model.importing { HStack{ProgressView().controlSize(.small);Text(model.importProgress).font(.callout)}.padding(12).background(.regularMaterial,in:Capsule()).padding(.bottom,12) }
        }
    }
    @ViewBuilder var pageContent: some View {
        #if os(macOS)
        switch model.page {case .capture:MacCaptureView(model:model);case .edit:MacEditView(model:model);case .batch:MacBatchView(model:model)}
        #else
        switch model.page {case .capture:PadCaptureView(model:model);case .edit:PadEditView(model:model);case .batch:PadBatchView(model:model)}
        #endif
    }
}
struct StudioHeader<Actions: View>: View {
    let title: String;let subtitle: String;@ViewBuilder var actions: Actions
    var body: some View { HStack(alignment:.center) { VStack(alignment:.leading,spacing:5){Text(title).font(.title2.weight(.semibold));Text(subtitle).font(.caption).foregroundStyle(.secondary)};Spacer();actions }.padding(.horizontal,24).padding(.vertical,18) }
}
struct ImportButtons: View {
    @ObservedObject var model: AppModel
    var body: some View { Menu {Button("导入照片…"){model.choose(.photos)};Button("导入文件夹…"){model.choose(.folder)};Divider();Button("选择图库位置…"){model.choose(.library)}} label:{Label("导入",systemImage:"plus")}.menuStyle(.borderlessButton).fixedSize().disabled(model.importing) }
}
struct PhotoCanvas: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            Color(white:0.045)
            if let image=(model.showingOriginal ? model.original : model.preview) {
                Image(decorative:image,scale:1).resizable().scaledToFit().padding(24)
                VStack{HStack{Text(model.showingOriginal ? "原图" : "效果预览").font(.caption.weight(.medium)).padding(.horizontal,10).padding(.vertical,6).background(.ultraThinMaterial,in:Capsule());Spacer()};Spacer()}.padding(16)
            } else if model.rendering { ProgressView("正在本地解码…") }
            else {
                VStack(spacing:18) {
                    Image(systemName:"camera.aperture").font(.system(size:62,weight:.ultraLight)).foregroundStyle(studioAccent.opacity(0.75))
                    Text("让照片回到你的工作台").font(.title2.weight(.light))
                    Text("导入 JPEG、HEIC 或 RAW\n在本地完成自然美颜与色彩创作 · 支持拖入照片").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("导入照片…"){model.choose(.photos)}.buttonStyle(.borderedProminent).controlSize(.large).padding(.top,8)
                }.padding(32)
            }
            if model.rendering,model.preview != nil { VStack{Spacer();HStack{Spacer();ProgressView().controlSize(.small).padding(14).background(.regularMaterial,in:Circle())}}.padding(16) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
        .dropDestination(for:URL.self) { urls,_ in
            let photos=urls.filter{PhotoFileType.accepts($0)};guard !photos.isEmpty else {return false};model.importDropped(photos);return true
        }
    }
}
struct PhotoThumbnail: View {
    let asset: PhotoAsset;var selected=false
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            AsyncImage(url:asset.thumbnailURL){image in image.resizable().scaledToFit()} placeholder:{Rectangle().fill(.quaternary).overlay{ProgressView()}}
                .frame(maxWidth:.infinity).frame(height:90).background(Color(white:0.05)).clipShape(RoundedRectangle(cornerRadius:6))
                .overlay(alignment:.topTrailing) { if asset.isRAW {Text(asset.companionURL == nil ? "RAW" : "RAW+J").font(.system(size:9,weight:.bold)).padding(4).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:3)).padding(4)} }
            Text(asset.name).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
        }.padding(6).background(selected ? studioAccent.opacity(0.12) : Color.clear,in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).stroke(selected ? studioAccent : .clear,lineWidth:1.5))
    }
}
struct Filmstrip: View {
    @ObservedObject var model: AppModel
    var body: some View { ScrollView(.horizontal) { LazyHStack(spacing:10) { ForEach(model.assets) { asset in Button{model.select(asset)} label:{PhotoThumbnail(asset:asset,selected:model.selectedID==asset.id).frame(width:118)}.buttonStyle(.plain).accessibilityLabel("编辑 \(asset.name)") } }.padding(.horizontal,16).padding(.vertical,8) }.frame(height:133).background(Color(white:0.08)) }
}
struct EditWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            StudioHeader(title:"修图",subtitle:model.selected?.name ?? "LIGHT, COLOR & THE HUMAN TOUCH") {
                HStack(spacing:18) { ImportButtons(model:model);Button{model.undo()}label:{Image(systemName:"arrow.uturn.backward")}.accessibilityLabel("撤销编辑").keyboardShortcut("z",modifiers:.command).disabled(!model.canUndo || model.agentBusy);Button{model.redo()}label:{Image(systemName:"arrow.uturn.forward")}.accessibilityLabel("重做编辑").keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!model.canRedo || model.agentBusy);Menu{Button("导出到本地图库"){model.exportToLibrary()};Button("选择输出文件夹…"){model.choose(.exportSingle)}}label:{Label("确认并导出",systemImage:"square.and.arrow.up")}primaryAction:{model.exportToLibrary()}.fixedSize().disabled(model.selected==nil || model.rendering || model.agentBusy) }
            }
            Divider()
            GeometryReader { proxy in
                if useSideControls && proxy.size.width>850 {
                    HStack(spacing:0) { VStack(spacing:0){PhotoCanvas(model:model);statusBar;Filmstrip(model:model)};Divider();ScrollView{VStack(alignment:.leading,spacing:22){AgentComposer(model:model);Divider();EditControls(model:model).disabled(model.agentBusy)}}.padding(20).frame(width:330).background(Color(white:0.095)) }
                } else {
                    VStack(spacing:0) { PhotoCanvas(model:model);statusBar;ScrollView(.horizontal){EditControls(model:model,compact:true).padding(16)}.frame(height:280);Filmstrip(model:model) }
                }
            }
        }
    }
    private var useSideControls: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    var statusBar: some View { HStack{Text(model.renderStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2);Spacer();Toggle("原图",isOn:$model.showingOriginal).toggleStyle(.button).font(.caption).disabled(model.original==nil)}.padding(.horizontal,16).padding(.vertical,9).background(Color(white:0.07)) }
}
struct EditControls: View {
    @ObservedObject var model: AppModel
    var compact=false
    @State private var recipeName="我的人像配方"
    var body: some View {
        Group {
            if compact { HStack(alignment:.top,spacing:28){
                ScrollView(.vertical){beauty}.frame(width:220,height:248)
                ScrollView(.vertical){filters}.frame(width:250,height:248)
                ScrollView(.vertical){reference}.frame(width:220,height:248)
                ScrollView(.vertical){extras}.frame(width:220,height:248)
            } }
            else { VStack(alignment:.leading,spacing:26){beauty;Divider();filters;Divider();reference;Divider();extras} }
        }.disabled(model.selected==nil)
    }
    var beauty: some View { VStack(alignment:.leading,spacing:13) {
        HStack{Label("自然美颜",systemImage:"sparkles").font(.headline);Spacer();Toggle("启用美颜",isOn:$model.recipe.beauty.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)}
        Button{model.oneClickBeauty()}label:{Text("一键美颜").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).controlSize(.large)
        HStack{Text("强度");Spacer();Text("\(Int(model.recipe.beauty.strength*100))%").monospacedDigit().foregroundStyle(.secondary)}.font(.caption)
        Slider(value:$model.recipe.beauty.strength,in:0...1).accessibilityLabel("美颜强度")
        Text("保留皮肤纹理 · 保护眼睛与唇部").font(.caption2).foregroundStyle(.secondary)
    } }
    var filters: some View { VStack(alignment:.leading,spacing:13) {
        Text("摄影滤镜").font(.headline)
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
            ForEach(FilterPreset.allCases){preset in Button{model.recipe.color.enabled=true;model.recipe.color.presetID=preset.id}label:{VStack(spacing:7){RoundedRectangle(cornerRadius:5).fill(LinearGradient(colors:swatch(preset),startPoint:.topLeading,endPoint:.bottomTrailing)).frame(height:37);Text(preset.name).font(.caption2)}.padding(5).background(model.recipe.color.presetID==preset.id ? studioAccent.opacity(0.18) : .clear,in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).stroke(model.recipe.color.presetID==preset.id ? studioAccent : .clear))}.buttonStyle(.plain) }
        }
        HStack{Text("滤镜强度");Spacer();Text("\(Int(model.recipe.color.intensity*100))%").monospacedDigit()}.font(.caption).foregroundStyle(.secondary)
        Slider(value:$model.recipe.color.intensity,in:0...1).accessibilityLabel("滤镜强度")
    } }
    func swatch(_ preset: FilterPreset)->[Color] {
        switch preset {case .natural:return [.init(red:0.55,green:0.61,blue:0.48),.init(red:0.79,green:0.67,blue:0.48)];case .portrait:return [.init(red:0.75,green:0.51,blue:0.46),.init(red:0.86,green:0.74,blue:0.63)];case .film:return [.init(red:0.2,green:0.36,blue:0.34),.init(red:0.67,green:0.48,blue:0.31)];case .warm:return [.init(red:0.77,green:0.42,blue:0.21),.init(red:0.93,green:0.73,blue:0.39)];case .cool:return [.init(red:0.22,green:0.39,blue:0.57),.init(red:0.58,green:0.74,blue:0.79)];case .clean:return [.init(red:0.56,green:0.71,blue:0.65),.init(red:0.9,green:0.9,blue:0.79)]}
    }
    var reference: some View { VStack(alignment:.leading,spacing:12) {
        Text("参考色彩").font(.headline)
        Button{model.choose(.reference)}label:{Label("选择参考照片…",systemImage:"photo.on.rectangle")}.controlSize(.large)
        if let p=model.profile {
            HStack{Text(p.name).font(.caption).lineLimit(1);Spacer();Button{model.removeReference()}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain).accessibilityLabel("移除参考色彩")}
            Text("Lab 分布匹配 · 人脸肤色保护").font(.caption2).foregroundStyle(.secondary)
            HStack{Button("保存档案"){model.exportProfile()};Button("导出 LUT"){model.exportLUT()}}.font(.caption)
        } else { Text("从参考照片提取影调，每张照片独立分析。").font(.caption2).foregroundStyle(.secondary);Button("载入色彩档案…"){model.choose(.profile)}.font(.caption) }
    } }
    var extras: some View { VStack(alignment:.leading,spacing:13) {
        AgentAdvancedControls(model:model)
        DisclosureGroup("基础调整") {
            VStack(spacing:10) { LabeledSlider(title:"曝光",value:$model.recipe.color.exposure,range:-3...3);LabeledSlider(title:"对比度",value:$model.recipe.color.contrast,range:0.5...1.5);LabeledSlider(title:"饱和度",value:$model.recipe.color.saturation,range:0...2) }.padding(.top,10)
        }.font(.callout)
        if model.selected?.isRAW == true {
            DisclosureGroup("RAW 显影") { VStack(alignment:.leading,spacing:10) {
                LabeledSlider(title:"RAW 曝光",value:$model.recipe.raw.exposure,range:-3...3)
                LabeledSlider(title:"阴影",value:$model.recipe.raw.shadows,range:-1...1)
                LabeledSlider(title:"局部影调",value:$model.recipe.raw.highlights,range:0...1)
                LabeledSlider(title:"色温",value:Binding(get:{model.recipe.raw.temperature ?? 6500},set:{model.recipe.raw.temperature=$0}),range:2500...10000)
                Button("恢复相机白平衡"){model.recipe.raw.temperature=nil;model.recipe.raw.tint=nil}
                if model.selected?.companionURL != nil {Toggle("使用配对 JPEG",isOn:$model.useCompanionJPEG)}
            }.padding(.top,10) }.font(.callout)
        }
        Picker("导出格式",selection:$model.recipe.export.format){ForEach(ExportFormat.allCases,id:\.self){Text($0.rawValue.uppercased()).tag($0)}}
        TextField("配方名称",text:$recipeName).textFieldStyle(.roundedBorder)
        HStack{Button("保存配方"){model.saveRecipe(named:recipeName)};Menu("载入"){Button("从文件载入…"){model.choose(.recipe)};ForEach(model.savedRecipes,id:\.self){url in Button(url.deletingPathExtension().lastPathComponent){do{try model.loadRecipe(url)}catch{model.message=error.localizedDescription}}}}}
        Button("重置编辑"){model.reset()}.font(.caption).foregroundStyle(.secondary)
        if let url=model.exportedURL { ShareLink(item:url){Label("分享上次导出",systemImage:"square.and.arrow.up")}.font(.caption) }
    } }
}
struct LabeledSlider: View {
    let title: String;@Binding var value: Float;let range: ClosedRange<Float>
    var body: some View { VStack(spacing:3){HStack{Text(title);Spacer();Text(value,format:.number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary)}.font(.caption);Slider(value:$value,in:range).accessibilityLabel(title)} }
}
struct BatchWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View { VStack(spacing:0) {
        StudioHeader(title:"批量修图",subtitle:"当前编辑配方 · \(model.recipe.color.presetID?.capitalized ?? "Natural") · 美颜 \(model.recipe.beauty.enabled ? "\(Int(model.recipe.beauty.strength*100))%" : "关闭")") {
            HStack(spacing:16){ImportButtons(model:model);Button("全选"){model.selection=Set(model.assets.map(\.id))};Button("清空"){model.selection=[]};Menu{Button("处理并导出到本地图库"){model.batchToLibrary()};Button("选择输出文件夹…"){model.choose(.exportBatch)}}label:{Text("处理并导出")}primaryAction:{model.batchToLibrary()}.fixedSize().buttonStyle(.borderedProminent).disabled(model.selection.isEmpty || model.batchSnapshot?.active==true)}
        };Divider()
        if model.assets.isEmpty {ContentUnavailableView("导入一组照片",systemImage:"square.grid.2x2",description:Text("先在修图页预览一张，再把同一配方应用到所选照片。"))}
        else {ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:140,maximum:210))],spacing:16){ForEach(model.assets){asset in Button{if model.selection.contains(asset.id){model.selection.remove(asset.id)}else{model.selection.insert(asset.id)}}label:{PhotoThumbnail(asset:asset,selected:model.selection.contains(asset.id)).overlay(alignment:.topLeading){Image(systemName:model.selection.contains(asset.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(model.selection.contains(asset.id) ? studioAccent : .secondary).padding(10)}}.buttonStyle(.plain)}}.padding(24)}}
        if let s=model.batchSnapshot {Divider();VStack(alignment:.leading,spacing:12) {
            HStack{Text(s.active ? (s.paused ? "已暂停 · 当前照片完成后等待" : "正在处理") : (s.cancelled ? "已取消" : "任务结束")).font(.headline);Spacer();Text("完成 \(s.completed) / \(s.items.count) · 失败 \(s.failures)").font(.caption).monospacedDigit()}
            ProgressView(value:s.progress)
            HStack{
                if s.active {Button(s.paused ? "继续" : "暂停"){if s.paused{model.resumeBatch()}else{model.pauseBatch()}};Button("取消",role:.destructive){model.cancelBatch()}}
                else if s.failures>0 || s.cancelled {Button("重试未完成"){model.retryBatch()}}
                Spacer();Text("有限并发 · 原片保留").font(.caption).foregroundStyle(.secondary)
                ShareLink(item:s.exportDirectory){Label("导出目录",systemImage:"folder")}
            }
            if let failure=s.items.first(where:{$0.state == .failed}) {Text("\(failure.name)：\(failure.error ?? "失败")").font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
        }.padding(20).background(Color(white:0.1))}
    } }
}
struct CaptureWorkspace: View {
    @ObservedObject var model: AppModel
    var body: some View { VStack(spacing:0) {
        StudioHeader(title:"联机拍摄",subtitle:"PANASONIC LUMIX DC-G9 · 第一代") {Button{model.syncPresented=true}label:{Label("Mac ↔ iPad",systemImage:"wifi")}}
        Divider()
        #if os(macOS)
        MacCapturePanel(model:model,tether:model.tether,native:model.native)
        #else
        VStack(spacing:24){Image(systemName:"wifi").font(.system(size:56,weight:.ultraLight)).foregroundStyle(studioAccent);Text("连接 Mac 拍摄工作台").font(.title2);Text("G9 通过 USB 连接 Mac。\niPad 接收照片并独立修图。").foregroundStyle(.secondary).multilineTextAlignment(.center);Button("打开局域网配对"){model.syncPresented=true}.buttonStyle(.borderedProminent).controlSize(.large);PadRemoteShutter(sync:model.sync)}.frame(maxWidth:.infinity,maxHeight:.infinity)
        #endif
        Filmstrip(model:model)
    } }
}
#if os(macOS)
struct MacCapturePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tether: LumixTetherFolderAdapter
    @ObservedObject var native: NativeCameraAdapter
    @State private var nativeEnabled=false
    var body: some View { HStack(spacing:0) {
        VStack(spacing:20){Spacer();Image(systemName:"camera").font(.system(size:68,weight:.ultraLight)).foregroundStyle(studioAccent);Text("在 LUMIX Tether 中取景与拍摄").font(.title2.weight(.light));Text("USB → PC(Tether) → 保存至监听目录\n新照片会自动导入这里").multilineTextAlignment(.center).foregroundStyle(.secondary);HStack{Button("打开 LUMIX Tether"){let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.panasonic.LUMIXTether");if let app{NSWorkspace.shared.open(app)}else{NSWorkspace.shared.open(URL(string:"https://av.jpn.support.panasonic.com/support/global/cs/soft/download/d_lumixtether.html")!)}}.controlSize(.large);Button("打开监听目录"){NSWorkspace.shared.open(model.inbox)}};Text("LumaStudio 尚未提供 G9 内嵌实时取景").font(.caption).foregroundStyle(.secondary);Spacer()}.frame(maxWidth:.infinity).padding(30).background(Color(white:0.045))
        Divider()
        ScrollView{VStack(alignment:.leading,spacing:22){
            Label(tether.status,systemImage:"folder.badge.gearshape").font(.callout)
            Text(model.inbox.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button("更换监听目录…"){model.choose(.inbox)}
            HStack{Button("开始监听"){Task{do{try await tether.connect()}catch{model.message=error.localizedDescription}}};Button("停止"){Task{await tether.disconnect()}}}
            Toggle("自动自然美颜",isOn:$model.autoBeauty)
            Toggle("自动发送新照片",isOn:$model.autoSend)
            Divider()
            DisclosureGroup("原生 USB 独立验证") {
                VStack(alignment:.leading,spacing:12){Text("此实验可能与 Tether 争用 USB，请先关闭 Tether。停止实验后可恢复官方拍摄。").font(.caption).foregroundStyle(.secondary)
                    Toggle("启动设备发现",isOn:$nativeEnabled).onChange(of:nativeEnabled){_,on in Task{if on{try? await native.connect()}else{await native.disconnect()}}}
                    Text(native.status).font(.caption)
                    Button("验证原生快门"){Task{do{_ = try await native.validateRemoteCapture();model.sync.updateCaptureCapability(true)}catch{model.message=error.localizedDescription}}}.disabled(!native.canTestShutter)
                    Button("原生拍摄"){Task{do{_ = try await native.capture()}catch{model.message=error.localizedDescription}}}.disabled(!native.capabilities.supportsRemoteCapture)
                    Button("导入相机文件（\(native.fileCount)）"){Task{do{try await native.downloadPhotos()}catch{model.message=error.localizedDescription}}}.disabled(native.fileCount==0)
                    Text("实时取景、ISO、光圈、快门参数控制：未验证，不可用。").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top,10)
            }
            Text(G9WiFiStatus.explanation).font(.caption2).foregroundStyle(.secondary)
        }.padding(24)}.frame(width:300)
    } }
}
#endif
struct PadRemoteShutter: View {
    @ObservedObject var sync: LocalSyncService
    var body: some View {Button("Mac 远程快门"){Task{try? await sync.requestCapture()}}.disabled(!sync.connected || !sync.remoteCaptureAvailable)}
}
struct SyncPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sync: LocalSyncService
    @Environment(\.dismiss) var dismiss
    
    var body: some View { NavigationStack {ScrollView{VStack(alignment:.leading,spacing:20){
        Label(sync.status,systemImage:sync.connected ? "lock.shield.fill" : "wifi").font(.headline)
        Text("照片只在配对设备之间传输。配对链接包含连接密钥，请仅分享给自己的设备。").font(.callout).foregroundStyle(.secondary)
        HStack{Button("作为 Host"){do{try sync.startHosting()}catch{model.message=error.localizedDescription}};Button("发现 Mac"){sync.discover()};Button("断开"){sync.stop()}}
        if let invitation=sync.invitation,let text=try? invitation.text(){
            HStack(alignment:.top,spacing:20){PairingQR(text:text).frame(width:190,height:190).background(.white);VStack(alignment:.leading,spacing:12){Text("用 iPad 相机扫描，或复制配对链接。邀请 15 分钟内有效。").font(.callout);Button("复制配对链接") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
                        #else
                        UIPasteboard.general.string=text
                        #endif
                    };ShareLink(item:text){Label("分享配对链接",systemImage:"square.and.arrow.up")};Button("撤销全部配对",role:.destructive){do{try sync.revokePairings()}catch{model.message=error.localizedDescription}}}}
        }
        if !sync.discovered.isEmpty{Text("已发现："+sync.discovered.joined(separator:", ")).font(.caption).foregroundStyle(.secondary)}
        TextField("粘贴 lumastudio:// 配对链接",text:$model.pairingInput,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...4).privacySensitive()
        HStack{Button("配对连接"){do{try sync.pair(text:model.pairingInput.trimmingCharacters(in:.whitespacesAndNewlines))}catch{model.message=error.localizedDescription}}.disabled(model.pairingInput.isEmpty);Button("连接已配对 Mac"){do{try sync.reconnectTrusted()}catch{model.message=error.localizedDescription}}}
        Divider()
        HStack{Button("发送当前原片"){model.sendSelected()}.disabled(!sync.connected || model.selected==nil || sync.isSending);PadRemoteShutter(sync:sync)}
        if sync.isSending || sync.progress>0 {ProgressView(value:sync.progress)}
        Text("一次一张 · 分块传输 · SHA256 完整性校验\nUSB 拍摄与设备局域网传输互不依赖。").font(.caption).foregroundStyle(.secondary)
    }.padding(28)}.navigationTitle("局域网协同").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}}} }.frame(minWidth:520,minHeight:480)
    }
}
struct PairingQR: View {
    let text: String
    var body: some View {
        if let image=qr() {Image(decorative:image,scale:1).interpolation(.none).resizable().scaledToFit().padding(8)}
    }
    func qr()->CGImage? {let f=CIFilter.qrCodeGenerator();f.message=Data(text.utf8);f.correctionLevel="M";guard let image=f.outputImage else{return nil};return CIContext().createCGImage(image,from:image.extent)}
}
