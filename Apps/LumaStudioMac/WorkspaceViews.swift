import SwiftUI
import PhotoCore
import CoreImage

private enum WorkspaceTheme {
    static let rail=Color(white:0.075)
    static let panel=Color(white:0.105)
    static let canvas=Color(white:0.035)
    static let separator=Color.white.opacity(0.08)
}

struct MacWorkspaceRail: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing:8) {
            VStack(spacing:7) {
                Image(systemName:"camera.aperture").font(.system(size:25,weight:.light)).foregroundStyle(studioAccent)
                Text("LUMA").font(.system(size:9,weight:.semibold,design:.rounded)).tracking(2)
            }.padding(.top,20).padding(.bottom,24).accessibilityElement(children:.combine).accessibilityLabel("LumaStudio")
            ForEach(AppModel.Page.allCases) { page in
                WorkspaceRailButton(title:page.rawValue,symbol:page.symbol,selected:model.page==page) { model.page=page }
            }
            Spacer(minLength:24)
            WorkspaceRailButton(title:"导入",symbol:"plus",selected:false) { model.choose(.photos) }.disabled(model.importing)
            WorkspaceRailButton(title:"接入",symbol:"network",selected:model.integrationsPresented) { model.integrationsPresented=true }
            WorkspaceRailButton(title:"模型",symbol:"slider.horizontal.2.square",selected:model.modelManagerPresented) { model.modelManagerPresented=true }
            Image(systemName:"lock.shield").font(.system(size:14)).foregroundStyle(.secondary).padding(.top,12).padding(.bottom,20).help("照片与编辑记录保存在本机")
        }.frame(width:76).background(WorkspaceTheme.rail)
    }
}

private struct WorkspaceRailButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: ()->Void
    @State private var hovered=false
    var body: some View {
        Button(action:action) {
            VStack(spacing:7) {
                Image(systemName:symbol).font(.system(size:19,weight:selected ? .medium : .regular)).frame(height:23)
                Text(title).font(.system(size:10,weight:selected ? .semibold : .regular))
            }.frame(width:56,height:60)
                .foregroundStyle(selected ? studioAccent : Color.white.opacity(hovered ? 0.9 : 0.55))
                .background(selected ? studioAccent.opacity(0.1) : (hovered ? Color.white.opacity(0.04) : .clear),in:RoundedRectangle(cornerRadius:9))
                .overlay(alignment:.leading) { if selected { RoundedRectangle(cornerRadius:2).fill(studioAccent).frame(width:2,height:22).offset(x:-10) } }
        }.buttonStyle(.plain).onHover{hovered=$0}.help(title).accessibilityLabel(title)
    }
}

private enum WorkspaceInspectorTab: String,CaseIterable {
    case assistant="AI 助手",color="调色",masks="局部",portrait="人像",style="滤镜",geometry="裁剪",raw="RAW",recipe="预设",output="导出"
    var symbol: String {switch self{case .assistant:return "sparkles";case .color:return "paintpalette";case .masks:return "square.dashed";case .portrait:return "person.crop.circle";case .style:return "camera.filters";case .geometry:return "crop";case .raw:return "camera.aperture";case .recipe:return "cube";case .output:return "square.and.arrow.up"}}
}

struct MacEditWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var tab: WorkspaceInspectorTab = .color
    @State private var assistantOpen=false
    @State private var fineEditing=true
    @State private var referenceLines=false
    @State private var zoom: CGFloat=1
    @State private var comparing=false
    @State private var comparisonPosition: CGFloat=0.5
    @State private var photoInfoPresented=false
    @State private var recipeName="我的人像配方"
    var body: some View {
        VStack(spacing:0) {
            header
            HStack(spacing:0) {
                if assistantOpen {MacAgentConversation(model:model).frame(width:310);Divider()}
                VStack(spacing:0) {
                    canvasToolbar
                    MacPhotoStage(model:model,zoom:zoom,comparing:comparing,comparisonPosition:$comparisonPosition)
                        .overlay {if referenceLines {GeometryReader{proxy in Path{path in for i in 1...2{let t=CGFloat(i)/3;path.move(to:CGPoint(x:proxy.size.width*t,y:0));path.addLine(to:CGPoint(x:proxy.size.width*t,y:proxy.size.height));path.move(to:CGPoint(x:0,y:proxy.size.height*t));path.addLine(to:CGPoint(x:proxy.size.width,y:proxy.size.height*t))}}.stroke(.white.opacity(0.28),lineWidth:0.5)}.allowsHitTesting(false)}}
                        .overlay(alignment:.bottomTrailing){if assistantOpen {Button{fineEditing.toggle();if tab == .assistant{tab = .color}}label:{Label(fineEditing ? "收起参数" : "精细调整",systemImage:"slider.horizontal.3")}.buttonStyle(.bordered).padding(16)}}
                    previewStatus
                    MacWorkspaceFilmstrip(model:model)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                if fineEditing {inspector.frame(width:354)}
                moduleRail
            }
        }.background(Color(white:0.07))
            .onChange(of:model.selectedID){_,_ in zoom=1;comparing=false;comparisonPosition=0.5}
    }
    private var header: some View {
        HStack(spacing:14) {
            HStack(spacing:8){Image(systemName:"camera.aperture").font(.system(size:22,weight:.light)).foregroundStyle(studioAccent);Text("LumaStudio").font(.system(size:13,weight:.semibold))}
            ImportButtons(model:model)
            Spacer(minLength:10)
            HStack(spacing:2) {
                headerMode("精修",symbol:"slider.horizontal.3",selected:!assistantOpen){assistantOpen=false;fineEditing=true;tab = .color}
                headerMode("AI 助手",symbol:"sparkles",selected:assistantOpen){assistantOpen=true;fineEditing=false;model.drawingBrush=false}
                headerMode("批量",symbol:"square.grid.2x2",selected:false){model.page = .batch}
            }.padding(3).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:7))
            Spacer(minLength:10)
            HStack(spacing:12) {
                Button{model.page = .capture}label:{Image(systemName:"camera")}.help("拍摄工作区").accessibilityLabel("拍摄工作区")
                Button{model.integrationsPresented=true}label:{Image(systemName:"network")}.help("模型 API 与语音接入").accessibilityLabel("接入设置")
                Button{model.modelManagerPresented=true}label:{Image(systemName:"cpu")}.help("本地模型").accessibilityLabel("本地模型设置")
                Button{model.agentProcessPresented=true}label:{Image(systemName:"list.bullet.rectangle")}.help("Agent 处理过程").accessibilityLabel("打开处理过程")
            }.buttonStyle(.plain).font(.system(size:14)).foregroundStyle(.secondary)
            HStack(spacing:0) {
                Button("导出"){model.exportToLibrary()}.buttonStyle(.plain).padding(.leading,19).padding(.trailing,12).accessibilityLabel("导出当前照片")
                Menu{Button("选择输出文件夹…"){model.choose(.exportSingle)};Button("导出设置…"){show(.output)}}label:{Image(systemName:"chevron.down").padding(.trailing,10)}.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多导出选项")
            }.font(.system(size:12,weight:.semibold)).foregroundStyle(.black).frame(height:31).background(studioAccent,in:RoundedRectangle(cornerRadius:6)).disabled(model.selected==nil || model.rendering || model.agentBusy)
        }.padding(.horizontal,16).frame(height:58).background(Color(white:0.08))
    }
    private func headerMode(_ title: String,symbol: String,selected: Bool,action: @escaping ()->Void)->some View {
        Button(action:action){Label(title,systemImage:symbol).font(.system(size:11,weight:.medium)).padding(.horizontal,15).padding(.vertical,7).background(selected ? .white.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:5)).foregroundStyle(selected ? .white : .secondary)}.buttonStyle(.plain).accessibilityLabel(title+"工作区")
    }
    private func tool(_ title: String,_ symbol: String,active: Bool=false,action: @escaping ()->Void)->some View {
        Button(action:action){VStack(spacing:5){Image(systemName:symbol).font(.system(size:17,weight:.light));Text(title).font(.system(size:9))}.frame(minWidth:39).frame(height:49).foregroundStyle(active ? studioAccent : Color.white.opacity(0.68))}.buttonStyle(.plain).accessibilityLabel(title+"工具")
    }
    private var canvasToolbar: some View {
        HStack(spacing:10) {
            Menu(zoom==1 ? "适应" : String(format:"×%.2f",Double(zoom))){Button("适应窗口"){zoom=1};Button("放大"){zoom=min(4,zoom+0.25)};Button("缩小"){zoom=max(0.5,zoom-0.25)}}.font(.system(size:11)).menuStyle(.borderlessButton).frame(width:62)
            ScrollView(.horizontal){HStack(spacing:12){
                tool("浏览","hand.draw",active:!model.drawingBrush){model.drawingBrush=false}
                tool("裁剪","crop",active:tab == .geometry){show(.geometry)}
                tool("参考线","squareshape.split.3x3",active:referenceLines){referenceLines.toggle()}
                tool("画笔","paintbrush.pointed",active:model.drawingBrush){if model.activeMask?.kind != .brush{model.addMask(.brush)};show(.masks);model.drawingBrush=true}
                tool("局部","square.dashed",active:tab == .masks){show(.masks)}
                tool("AI 调整","sparkles",active:assistantOpen){assistantOpen=true;fineEditing=false;model.drawingBrush=false}
                tool("参考图","photo.on.rectangle"){model.choose(.reference)}
                tool("滤镜","camera.filters",active:tab == .style){show(.style)}
            }}.scrollIndicators(.hidden)
            HStack(spacing:11){
                Button{model.undo()}label:{Image(systemName:"arrow.uturn.backward")}.help("撤销 ⌘Z").accessibilityLabel("撤销编辑").keyboardShortcut("z",modifiers:.command).disabled(!model.canUndo || model.agentBusy)
                Button{model.redo()}label:{Image(systemName:"arrow.uturn.forward")}.help("重做 ⇧⌘Z").accessibilityLabel("重做编辑").keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!model.canRedo || model.agentBusy)
                Button{model.reset()}label:{Image(systemName:"arrow.counterclockwise")}.help("重置当前编辑").accessibilityLabel("重置当前编辑")
            }.buttonStyle(.plain).font(.system(size:14)).foregroundStyle(.secondary)
            tool("预设","cube",active:tab == .recipe){show(.recipe)}
        }.padding(.horizontal,14).frame(height:60).background(Color(white:0.055)).disabled(model.preview==nil)
    }
    private func show(_ value: WorkspaceInspectorTab) {tab=value;fineEditing=true;if value != .masks{model.drawingBrush=false;model.showMaskOverlay=false}}
    private var previewStatus: some View {
        HStack(spacing:8) {
            if model.rendering{ProgressView().controlSize(.mini)}
            Text(model.selected?.name ?? "尚未选择照片").font(.system(size:10)).lineLimit(1).foregroundStyle(.secondary)
            if model.selected?.isRAW==true{Text("RAW").font(.system(size:8,weight:.semibold)).foregroundStyle(studioAccent)}
            Spacer(minLength:5)
            Button{comparing.toggle();model.showingOriginal=false}label:{Label("前后对比",systemImage:"rectangle.lefthalf.inset.filled")}.foregroundStyle(comparing ? studioAccent : .secondary).accessibilityLabel("前后对比")
            Button(model.showingOriginal ? "返回效果" : "查看原图"){model.showingOriginal.toggle();comparing=false}.foregroundStyle(.secondary)
            Button{photoInfoPresented.toggle()}label:{Image(systemName:"info.circle")}.accessibilityLabel("照片与处理信息").popover(isPresented:$photoInfoPresented){VStack(alignment:.leading,spacing:10){Text(model.selected?.name ?? "").font(.headline);if let image=model.preview{Text("预览：\(image.width) × \(image.height)")};Text(model.renderStatus);Text("导出时按原片重新处理。").foregroundStyle(.secondary)}.font(.caption).padding(20).frame(width:300)}
        }.buttonStyle(.plain).font(.system(size:10)).padding(.horizontal,14).frame(height:31).background(Color(white:0.055))
    }
    private var moduleRail: some View {
        VStack(spacing:3){
            ForEach(WorkspaceInspectorTab.allCases,id:\.self){item in Button{
                if item == .assistant{assistantOpen.toggle();fineEditing = !assistantOpen;model.drawingBrush=false}
                else{show(item)}
            }label:{VStack(spacing:6){Image(systemName:item.symbol).font(.system(size:18,weight:.light)).frame(width:32,height:28).background((item == .assistant ? assistantOpen : tab==item && fineEditing) ? Color.white.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:6));Text(item.rawValue).font(.system(size:9))}.foregroundStyle((item == .assistant ? assistantOpen : tab==item && fineEditing) ? studioAccent : Color.white.opacity(0.56)).frame(width:52,height:59)}.buttonStyle(.plain).accessibilityLabel(item.rawValue+"面板")}
            Spacer(minLength:0)
        }.padding(.top,12).frame(width:58).background(Color(white:0.075))
    }
    private var inspector: some View {
        VStack(spacing:0){
            HStack{Label(tab.rawValue=="调色" ? "色彩调节" : tab.rawValue,systemImage:tab.symbol).font(.system(size:12,weight:.medium));Spacer();if tab == .color{Text("\(ParameterCatalog.all.count) 项参数").font(.system(size:9)).foregroundStyle(.tertiary)}}.padding(.horizontal,16).frame(height:42)
            ScrollView{
                VStack(alignment:.leading,spacing:0){
                    switch tab{
                    case .color:ProInspectorView(model:model)
                    case .portrait:ProInspectorView(model:model,section:.portrait)
                    case .masks:ProInspectorView(model:model,section:.masks)
                    case .style:ProInspectorView(model:model,section:.style)
                    case .geometry:ProInspectorView(model:model,section:.geometry)
                    case .raw:ProInspectorView(model:model,section:.raw)
                    case .output:ProInspectorView(model:model,section:.output)
                    case .recipe:recipeInspector
                    case .assistant:assistantInspector
                    }
                }.padding(.horizontal,12).padding(.bottom,16).disabled(model.selected==nil || (model.agentBusy && tab != .assistant))
            }.id(tab)
            HStack(spacing:8){Button("保存预设"){show(.recipe)};Button("同步所选参数…"){model.recipeSyncPresented=true}.disabled(!model.canSynchronize)}.font(.system(size:10)).buttonStyle(.bordered).controlSize(.small).padding(12)
        }.background(Color(white:0.095))
    }
    private var recipeInspector: some View {
        Group {
            InspectorSection("保存当前配方") {
                Text("把当前调整保存下来，用于下一张或同组照片。").font(.caption).foregroundStyle(.secondary)
                TextField("配方名称",text:$recipeName).textFieldStyle(.roundedBorder).accessibilityLabel("配方名称")
                HStack {Button("复制 v2 配方"){model.copyRecipe()};Button("粘贴配方"){model.pasteRecipe()}}.font(.caption)
                Button("载入配方文件…"){model.choose(.recipe)}.font(.caption)
                Button("保存配方") { model.saveRecipe(named:recipeName) }.disabled(recipeName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            InspectorSection("已保存配方") {
                if model.savedRecipes.isEmpty { Text("还没有保存的配方").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.savedRecipes,id:\.self) { url in
                    Button { do { try model.loadRecipe(url) } catch { model.message=error.localizedDescription } } label:{
                        HStack { Image(systemName:"square.stack").foregroundStyle(studioAccent);Text(url.deletingPathExtension().lastPathComponent).lineLimit(1);Spacer();Image(systemName:"arrow.down.to.line").foregroundStyle(.secondary) }.font(.caption).padding(.vertical,5)
                    }.buttonStyle(.plain).accessibilityLabel("载入配方 \(url.deletingPathExtension().lastPathComponent)")
                }
                Button("从文件载入…"){model.choose(.recipe)}.font(.caption)
            }
            InspectorSection("应用到同组照片") {
                Text("按分组同步到所选照片，保留各自的裁剪、局部区域与已锁定参数。").font(.caption).foregroundStyle(.secondary)
                Button{model.recipeSyncPresented=true}label:{Label("选择照片并同步…",systemImage:"arrow.triangle.2.circlepath")}.font(.caption).disabled(!model.canSynchronize)
                Button{openBatch()}label:{Label("前往批量导出…",systemImage:"square.grid.2x2")}.font(.caption)
                if !model.workflowStatus.isEmpty {Text(model.workflowStatus).font(.caption).foregroundStyle(studioAccent)}
                if model.lastRecipeSync != nil {Button("撤回上次同步"){model.undoRecipeSynchronization()}.font(.caption).disabled(!model.canSynchronize)}
            }
            Button("重置当前编辑"){model.reset()}.font(.caption).foregroundStyle(.secondary).padding(.top,16)
        }
    }

    private var assistantInspector: some View {
        VStack(alignment:.leading,spacing:16) {
            Button { model.agentProcessPresented=true } label:{Label("展开 Agent 处理过程",systemImage:"arrow.up.left.and.arrow.down.right").frame(maxWidth:.infinity)}
                .buttonStyle(.bordered).accessibilityLabel("展开 Agent 处理过程")
            AgentComposer(model:model)
            Label("AI 已锁定 \(model.recipe.document.lockedParameters.count) 项",systemImage:"lock").font(.caption).foregroundStyle(.secondary)
            if !model.agentParameterChanges.isEmpty {
                Divider();Text("本次参数修改").font(.caption.weight(.semibold))
                ForEach(model.agentParameterChanges){change in HStack(alignment:.top){Text(change.title);Spacer();Text(change.before+" → "+change.after).monospacedDigit().foregroundStyle(.secondary)}.font(.caption2)}
            }
            Divider()
            Label("照片在本机处理 · 效果由你确认",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
            Text(model.cloudSettings.mode == .online ? "当前选择在线模型规划，返回参数仍经过本机工具与指令检查。" : "当前为通用基础模型与规则辅助，尚未完成专业修图训练。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button("在线模型与语音接入…"){model.integrationsPresented=true}.font(.caption)
            Button("查看模型与偏好…"){model.modelManagerPresented=true}.font(.caption)
        }.padding(.top,22)
    }

    private var exportFooter: some View {
        VStack(spacing:12) {
            HStack {
                Text("导出格式").font(.system(size:11)).foregroundStyle(.secondary)
                Spacer()
                Picker("导出格式",selection:$model.recipe.export.format) { ForEach(ExportFormat.allCases,id:\.self) { Text($0.rawValue.uppercased()).tag($0) } }.labelsHidden().controlSize(.small).frame(width:100)
            }
            Menu {
                Button("导出到本地图库"){model.exportToLibrary()}
                Button("选择输出文件夹…"){model.choose(.exportSingle)}
            } label:{Label("确认并导出",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity)} primaryAction:{model.exportToLibrary()}
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.selected==nil || model.rendering || model.agentBusy)
            if let url=model.exportedURL { ShareLink(item:url){Label("分享上次导出",systemImage:"square.and.arrow.up")}.font(.system(size:10)) }
        }.padding(18).background(Color(white:0.09))
    }

    private func editBinding(_ key: WritableKeyPath<GlobalAdjustments,Float>)->Binding<Float> {
        Binding(get:{model.recipe.edit?.global[keyPath:key] ?? GlobalAdjustments()[keyPath:key]},set:{ value in
            var recipe=model.recipe
            var edit=recipe.edit ?? EditRecipe()
            edit.global[keyPath:key]=value;recipe.edit=edit;model.recipe=recipe
        })
    }
    private func openBatch() { if model.selection.isEmpty {model.selection=Set(model.visibleAssets.map(\.id))};model.page = .batch }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content
    @State private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String,expanded: Bool=true,@ViewBuilder content: ()->Content) { self.title=title;self.content=content();_expanded=State(initialValue:expanded) }
    var body: some View {
        DisclosureGroup(isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:13) { content }.padding(.top,14).padding(.bottom,3)
        } label:{Text(title).font(.system(size:12,weight:.semibold)).foregroundStyle(Color.white.opacity(0.86))}
            .padding(.vertical,17).overlay(alignment:.bottom){WorkspaceTheme.separator.frame(height:1)}
            .animation(reduceMotion ? nil : .easeInOut(duration:0.16),value:expanded)
    }
}

private struct WorkspaceSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    var integer=false
    var percentage=false
    var unit=""
    init(_ title: String,value: Binding<Float>,range: ClosedRange<Float>,defaultValue: Float,integer: Bool=false,percentage: Bool=false,unit: String="") {
        self.title=title;_value=value;self.range=range;self.defaultValue=defaultValue;self.integer=integer;self.percentage=percentage;self.unit=unit
    }
    private var display: String { percentage ? "\(Int((value*100).rounded()))%" : (integer ? "\(Int(value.rounded()))\(unit)" : String(format:"%.2f",value)+unit) }
    var body: some View {
        VStack(spacing:4) {
            HStack {
                Text(title).foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Button(display){value=defaultValue}.buttonStyle(.plain).foregroundStyle(.secondary).monospacedDigit().help("点击恢复默认值").accessibilityLabel("重置\(title)")
            }.font(.system(size:11))
            Slider(value:$value,in:range).controlSize(.small).accessibilityLabel(title).accessibilityValue(display)
        }
    }
}

func presetTitle(_ preset: FilterPreset)->String {
    preset.title
}

struct PresetPhotoPreview: View {
    let asset: PhotoAsset?
    let preset: FilterPreset
    let selected: Bool
    @State private var image: CGImage?
    var body: some View {
        VStack(spacing:6) {
            ZStack {
                Color(white:0.065)
                if let image { Image(decorative:image,scale:1).resizable().scaledToFit() }
                else { Image(systemName:"photo").foregroundStyle(.tertiary) }
            }.frame(height:66).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:5))
                .overlay(RoundedRectangle(cornerRadius:5).stroke(selected ? studioAccent : .clear,lineWidth:1.5))
            Text(presetTitle(preset)).font(.system(size:10,weight:selected ? .semibold : .regular)).foregroundStyle(selected ? studioAccent : Color.white.opacity(0.62))
        }.task(id:(asset?.id.uuidString ?? "")+preset.id) {
            image=nil
            guard let asset else { return }
            let result=try? await StylePreviewRenderer.shared.render(url:asset.thumbnailURL,preset:preset)
            guard !Task.isCancelled else { return };image=result
        }
    }
}

private actor StylePreviewRenderer {
    static let shared=StylePreviewRenderer()
    private let context=CIContext(options:[.cacheIntermediates:false])
    private var cache=[String:CGImage]()
    private var keys=[String]()
    func render(url: URL,preset: FilterPreset) throws -> CGImage {
        let key=url.path+"/"+preset.id
        if let image=cache[key] { return image }
        guard let source=CIImage(contentsOf:url,options:[.applyOrientationProperty:true]) else { throw LumaError.invalidImage(url.lastPathComponent) }
        let filtered=try preset.lut().apply(to:source)
        guard let image=context.createCGImage(filtered,from:source.extent) else { throw LumaError.invalidImage(url.lastPathComponent) }
        cache[key]=image;keys.append(key)
        if keys.count>64 { cache.removeValue(forKey:keys.removeFirst()) }
        return image
    }
}

private struct MacPhotoStage: View {
    @ObservedObject var model: AppModel
    let zoom: CGFloat
    let comparing: Bool
    @Binding var comparisonPosition: CGFloat
    var body: some View {
        Group {
            if let preview=model.preview {
                GeometryReader { proxy in
                    let available=CGSize(width:max(1,proxy.size.width-48),height:max(1,proxy.size.height-48))
                    let factor=min(available.width/CGFloat(preview.width),available.height/CGFloat(preview.height))*zoom
                    let size=CGSize(width:CGFloat(preview.width)*factor,height:CGFloat(preview.height)*factor)
                    ScrollView([.horizontal,.vertical]) {
                        comparisonImage(preview:preview,size:size)
                            .padding(24).frame(minWidth:proxy.size.width,minHeight:proxy.size.height)
                    }.scrollIndicators(.hidden)
                }.background(WorkspaceTheme.canvas)
                    .overlay(alignment:.bottomTrailing) { if model.rendering { ProgressView().controlSize(.small).padding(12).background(.regularMaterial,in:Circle()).padding(16) } }
                    .dropDestination(for:URL.self) { urls,_ in let photos=urls.filter{PhotoFileType.accepts($0)};guard !photos.isEmpty else {return false};model.importDropped(photos);return true }
            } else { PhotoCanvas(model:model) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
    }
    private func photo(_ image: CGImage,size: CGSize)->some View { Image(decorative:image,scale:1).resizable().frame(width:size.width,height:size.height) }
    private func badge(_ text: String)->some View { Text(text).font(.system(size:10,weight:.medium)).padding(.horizontal,9).padding(.vertical,5).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:4)).padding(10) }
    private func comparisonImage(preview: CGImage,size: CGSize)->some View {
        ZStack {
            photo(model.showingOriginal ? (model.original ?? preview) : preview,size:size)
            if !model.showingOriginal {ProPhotoMaskOverlay(model:model,size:size,paintingAllowed:!comparing)}
            if comparing,let original=model.original {
                photo(original,size:size).mask(alignment:.leading){Rectangle().frame(width:size.width*comparisonPosition)}
                ZStack {
                    Rectangle().fill(.white.opacity(0.85)).frame(width:1)
                    Circle().fill(.black.opacity(0.7)).frame(width:30,height:30).overlay(Circle().stroke(.white.opacity(0.8),lineWidth:1))
                    Image(systemName:"arrow.left.and.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.white)
                }.frame(width:36,height:size.height).contentShape(Rectangle()).position(x:size.width*comparisonPosition,y:size.height/2)
                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("photoComparison")).onChanged{value in comparisonPosition=min(0.98,max(0.02,value.location.x/max(1,size.width)))})
                    .accessibilityElement(children:.ignore).accessibilityLabel("前后对比分界线").accessibilityValue("\(Int(comparisonPosition*100))%")
                    .accessibilityAdjustableAction{direction in if direction == .increment { comparisonPosition=min(0.98,comparisonPosition+0.05) } else if direction == .decrement { comparisonPosition=max(0.02,comparisonPosition-0.05) } }
            }
        }.frame(width:size.width,height:size.height).coordinateSpace(name:"photoComparison")
            .overlay(alignment:.topLeading){if comparing || model.showingOriginal { badge("原图") }}
            .overlay(alignment:.topTrailing){if comparing { badge("当前效果") }}
    }
}

private struct MacWorkspaceFilmstrip: View {
    @ObservedObject var model: AppModel
    private var photos: [PhotoAsset] {model.visibleAssets}
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:9) {
                Text("\(photos.count) 张 · 选中 \(model.selection.count)").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary).fixedSize()
                Spacer(minLength:0)
                TextField("查找照片",text:$model.photoFilter.query).textFieldStyle(.plain).font(.system(size:10)).padding(.horizontal,8).padding(.vertical,4).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:4)).frame(width:100).accessibilityLabel("查找照片")
                PhotoFilterMenu(model:model).font(.system(size:10)).fixedSize()
                PhotoReviewMenu(model:model,ids:Set([model.selectedID].compactMap{$0})).font(.system(size:10)).fixedSize()
                Button("同步…"){model.recipeSyncPresented=true}.font(.system(size:10)).disabled(!model.canSynchronize)
                Button {
                    if model.selection.isEmpty {model.selection=Set(photos.map(\.id))};model.page = .batch
                } label:{Label("批量…",systemImage:"square.grid.2x2").font(.system(size:10))}.buttonStyle(.borderless).disabled(photos.isEmpty)
            }.controlSize(.small).padding(.horizontal,12).frame(height:35)
            ScrollView(.horizontal) {
                LazyHStack(spacing:9) {
                    ForEach(photos) { asset in
                        VStack(alignment:.leading,spacing:5) {
                            Button{model.select(asset)}label:{
                                AsyncImage(url:asset.thumbnailURL){image in image.resizable().scaledToFit()}placeholder:{Color(white:0.09)}
                                    .frame(width:96,height:66).background(Color(white:0.035)).clipped().clipShape(RoundedRectangle(cornerRadius:4))
                                    .overlay(alignment:.topTrailing){if asset.isRAW { Text("RAW").font(.system(size:8,weight:.semibold)).padding(3).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:2)).padding(3) }}
                                    .overlay(RoundedRectangle(cornerRadius:4).stroke(model.selectedID==asset.id ? studioAccent : .clear,lineWidth:1.5))
                                    .overlay(alignment:.bottomLeading){PhotoReviewBadge(review:model.review(for:asset.id)).padding(3)}
                            }.buttonStyle(.plain).disabled(model.workflowBusy).accessibilityLabel("编辑 \(asset.name)").help(asset.name)
                                .contextMenu{PhotoReviewActions(model:model,ids:[asset.id])}
                            HStack(spacing:4) {
                                Button{if model.selection.contains(asset.id){model.selection.remove(asset.id)}else{model.selection.insert(asset.id)}}label:{Image(systemName:model.selection.contains(asset.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(model.selection.contains(asset.id) ? studioAccent : .secondary)}.buttonStyle(.plain).accessibilityLabel((model.selection.contains(asset.id) ? "取消选择 " : "选为同步目标 ")+asset.name)
                                Text(asset.name).font(.system(size:9)).foregroundStyle(model.selectedID==asset.id ? studioAccent : .secondary).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                            }.frame(width:96,alignment:.leading).clipped()
                        }.padding(4).background(model.selectedID==asset.id ? studioAccent.opacity(0.06) : .clear,in:RoundedRectangle(cornerRadius:5))
                    }
                    Button{model.choose(.photos)}label:{Image(systemName:"plus").font(.system(size:18,weight:.light)).foregroundStyle(.secondary).frame(width:50,height:66).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:4))}.buttonStyle(.plain).accessibilityLabel("向图库添加照片").disabled(model.importing)
                }.padding(.horizontal,12).padding(.bottom,10)
            }.scrollIndicators(.hidden)
        }.frame(height:134).background(Color(white:0.075))
    }
}
