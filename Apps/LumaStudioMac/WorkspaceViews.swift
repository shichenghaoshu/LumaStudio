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
    case color="调色",portrait="人像",recipe="配方",assistant="助手"
    var symbol: String { switch self {case .color:return "slider.horizontal.3";case .portrait:return "person.crop.square";case .recipe:return "square.stack";case .assistant:return "sparkles"} }
}

struct MacEditWorkspace: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: WorkspaceInspectorTab = .color
    @State private var zoom: CGFloat=1
    @State private var comparing=false
    @State private var comparisonPosition: CGFloat=0.5
    @State private var photoInfoPresented=false
    @State private var recipeName="我的人像配方"

    var body: some View {
        VStack(spacing:0) {
            header
            Divider()
            HStack(spacing:0) {
                VStack(spacing:0) {
                    canvasToolbar
                    Divider()
                    MacPhotoStage(model:model,zoom:zoom,comparing:comparing,comparisonPosition:$comparisonPosition)
                    previewStatus
                    Divider()
                    MacWorkspaceFilmstrip(model:model)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                Divider()
                inspector.frame(width:336)
            }
        }.onChange(of:model.selectedID) { _,_ in zoom=1;comparing=false;comparisonPosition=0.5 }
    }

    private var header: some View {
        HStack(spacing:16) {
            VStack(alignment:.leading,spacing:4) {
                Text("照片编辑").font(.system(size:16,weight:.semibold))
                Text(model.selected?.name ?? "导入照片，开始本地修图").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1).help(model.selected?.name ?? "")
            }
            Spacer(minLength:12)
            Button { model.agentProcessPresented=true } label:{Label("处理过程",systemImage:"list.bullet.rectangle")}
                .font(.system(size:11)).buttonStyle(.borderless).accessibilityLabel("打开处理过程")
            Label("本地工作区",systemImage:"lock.shield").font(.system(size:11)).foregroundStyle(.secondary)
            Divider().frame(height:20)
            ImportButtons(model:model)
            HStack(spacing:4) {
                Button{model.undo()}label:{Image(systemName:"arrow.uturn.backward").frame(width:26,height:26)}
                    .help("撤销编辑 ⌘Z").accessibilityLabel("撤销编辑").keyboardShortcut("z",modifiers:.command).disabled(!model.canUndo || model.agentBusy)
                Button{model.redo()}label:{Image(systemName:"arrow.uturn.forward").frame(width:26,height:26)}
                    .help("重做编辑 ⇧⌘Z").accessibilityLabel("重做编辑").keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!model.canRedo || model.agentBusy)
            }.buttonStyle(.borderless)
        }.padding(.horizontal,20).frame(height:66).background(WorkspaceTheme.panel)
    }

    private var canvasToolbar: some View {
        HStack(spacing:8) {
            Button{zoom=max(0.5,zoom-0.25)}label:{Image(systemName:"minus.magnifyingglass")}.help("缩小预览").accessibilityLabel("缩小预览")
            Button(zoom==1 ? "适应窗口" : String(format:"适应 ×%.2f",Double(zoom))) { zoom=1 }.font(.system(size:11)).frame(width:83).help("恢复适应窗口的尺寸")
            Button{zoom=min(4,zoom+0.25)}label:{Image(systemName:"plus.magnifyingglass")}.help("放大预览").accessibilityLabel("放大预览")
            Spacer()
            Button {
                comparing.toggle();model.showingOriginal=false
            } label:{Label("前后对比",systemImage:"rectangle.lefthalf.inset.filled").font(.system(size:11)).foregroundStyle(comparing ? studioAccent : .secondary)}
                .help("拖动分界线比较原图与效果").accessibilityLabel("前后对比").disabled(model.original==nil)
            Button(model.showingOriginal ? "返回效果" : "查看原图") { model.showingOriginal.toggle();comparing=false }.font(.system(size:11)).disabled(model.original==nil)
        }.buttonStyle(.borderless).padding(.horizontal,18).frame(height:40).background(Color(white:0.08)).disabled(model.preview==nil)
    }

    private var previewStatus: some View {
        HStack(spacing:8) {
            if model.rendering { ProgressView().controlSize(.mini) }
            Text(model.rendering ? "正在更新预览…" : (model.renderStatus.contains(" ms") ? "预览已更新" : model.renderStatus)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength:8)
            if model.selected?.isRAW == true { Text(model.useCompanionJPEG ? "配对 JPEG" : "RAW").font(.system(size:9,weight:.semibold)).foregroundStyle(studioAccent) }
            Button{photoInfoPresented.toggle()}label:{Image(systemName:"info.circle").font(.system(size:11))}.buttonStyle(.borderless).accessibilityLabel("照片与处理信息")
                .popover(isPresented:$photoInfoPresented) {
                    VStack(alignment:.leading,spacing:10) {
                        Text(model.selected?.name ?? "尚未选择照片").font(.headline)
                        if let image=model.preview { Text("当前预览：\(image.width) × \(image.height)") }
                        Text(model.renderStatus).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Text("预览用于编辑；导出时按原片尺寸重新处理。").foregroundStyle(.secondary)
                    }.font(.caption).padding(20).frame(width:320)
                }.disabled(model.selected==nil)
        }.padding(.horizontal,18).frame(height:30).background(Color(white:0.065))
    }

    private var inspector: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                ForEach(WorkspaceInspectorTab.allCases,id:\.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.16)) { tab=item }
                    } label:{
                        VStack(spacing:7) {
                            Image(systemName:item.symbol).font(.system(size:15))
                            Text(item.rawValue).font(.system(size:11,weight:tab==item ? .semibold : .regular))
                        }.frame(maxWidth:.infinity).frame(height:64).foregroundStyle(tab==item ? studioAccent : Color.white.opacity(0.52))
                            .overlay(alignment:.bottom) { Rectangle().fill(tab==item ? studioAccent : .clear).frame(height:2).padding(.horizontal,17) }
                    }.buttonStyle(.plain).accessibilityLabel("\(item.rawValue)面板").accessibilityAddTraits(tab==item ? [.isSelected] : [])
                }
            }
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    switch tab {
                    case .color: colorInspector
                    case .portrait: portraitInspector
                    case .recipe: recipeInspector
                    case .assistant: assistantInspector
                    }
                }.padding(.horizontal,20).padding(.bottom,20)
                    .disabled(model.selected==nil || (model.agentBusy && tab != .assistant))
            }.id(tab)
            Divider()
            exportFooter
        }.background(WorkspaceTheme.panel)
    }

    private var colorInspector: some View {
        Group {
            InspectorSection("基础调整") {
                WorkspaceSlider("曝光",value:$model.recipe.color.exposure,range:-3...3,defaultValue:0,unit:" EV")
                WorkspaceSlider("色温",value:$model.recipe.color.temperature,range:2500...10000,defaultValue:6500,integer:true,unit:" K")
                WorkspaceSlider("对比度",value:$model.recipe.color.contrast,range:0.5...1.5,defaultValue:1)
                WorkspaceSlider("饱和度",value:$model.recipe.color.saturation,range:0...2,defaultValue:1)
            }
            InspectorSection("摄影风格") {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(FilterPreset.allCases) { preset in
                        Button { model.recipe.color.enabled=true;model.recipe.color.presetID=preset.id } label:{
                            PresetPhotoPreview(asset:model.selected,preset:preset,selected:model.recipe.color.presetID==preset.id)
                        }.buttonStyle(.plain).accessibilityLabel("\(presetTitle(preset))滤镜")
                    }
                }
                Text("原片缩略图上的 LUT 预览").font(.system(size:10)).foregroundStyle(.tertiary)
                WorkspaceSlider("风格强度",value:$model.recipe.color.intensity,range:0...1,defaultValue:0.8,percentage:true)
            }
            InspectorSection("影调与色彩",expanded:false) {
                WorkspaceSlider("高光",value:editBinding(\.highlights),range:-1...1,defaultValue:0)
                WorkspaceSlider("阴影",value:editBinding(\.shadows),range:-1...1,defaultValue:0)
                WorkspaceSlider("白色色阶",value:editBinding(\.whites),range:-1...1,defaultValue:0)
                WorkspaceSlider("黑色色阶",value:editBinding(\.blacks),range:-1...1,defaultValue:0)
                WorkspaceSlider("自然饱和度",value:editBinding(\.vibrance),range:-1...1,defaultValue:0)
                WorkspaceSlider("色调",value:editBinding(\.tint),range:-100...100,defaultValue:0,integer:true)
            }
            InspectorSection("参考色彩",expanded:false) {
                Button{model.choose(.reference)}label:{Label("选择参考照片…",systemImage:"photo.on.rectangle")}.frame(maxWidth:.infinity)
                if let profile=model.profile {
                    HStack { Text(profile.name).lineLimit(1);Spacer();Button{model.removeReference()}label:{Image(systemName:"xmark.circle")}.buttonStyle(.plain).accessibilityLabel("移除参考色彩") }.font(.caption)
                    HStack { Button("保存档案"){model.exportProfile()};Button("导出 LUT"){model.exportLUT()} }.font(.caption)
                } else { Text("从参考照片提取色彩，再调整到你满意。").font(.caption).foregroundStyle(.secondary);Button("载入色彩档案…"){model.choose(.profile)}.font(.caption) }
            }
            if model.selected?.isRAW == true {
                InspectorSection("RAW 显影",expanded:false) {
                    WorkspaceSlider("RAW 曝光",value:$model.recipe.raw.exposure,range:-3...3,defaultValue:0,unit:" EV")
                    WorkspaceSlider("阴影恢复",value:$model.recipe.raw.shadows,range:-1...1,defaultValue:0)
                    WorkspaceSlider("局部影调",value:$model.recipe.raw.highlights,range:0...1,defaultValue:0.7)
                    WorkspaceSlider("RAW 色温",value:Binding(get:{model.recipe.raw.temperature ?? 6500},set:{model.recipe.raw.temperature=$0}),range:2500...10000,defaultValue:6500,integer:true,unit:" K")
                    Button("恢复相机白平衡"){model.recipe.raw.temperature=nil;model.recipe.raw.tint=nil}.font(.caption)
                    if model.selected?.companionURL != nil { Toggle("使用配对 JPEG",isOn:$model.useCompanionJPEG).font(.caption) }
                }
            }
        }
    }

    private var portraitInspector: some View {
        Group {
            InspectorSection("自然美颜") {
                Toggle("启用自然美颜",isOn:$model.recipe.beauty.enabled).toggleStyle(.switch).controlSize(.small).font(.caption)
                Button{model.oneClickBeauty()}label:{Label("应用自然美颜",systemImage:"sparkles").frame(maxWidth:.infinity)}.buttonStyle(.borderedProminent).controlSize(.large)
                WorkspaceSlider("磨皮强度",value:$model.recipe.beauty.strength,range:0...1,defaultValue:0.35,percentage:true)
                WorkspaceSlider("肤色优化",value:$model.recipe.beauty.skinTone,range:0...1,defaultValue:0.25,percentage:true)
                WorkspaceSlider("细小瑕疵弱化",value:$model.recipe.beauty.blemishRemoval,range:0...1,defaultValue:0.2,percentage:true)
                WorkspaceSlider("纹理保留",value:$model.recipe.beauty.texturePreservation,range:0.6...1,defaultValue:0.94,percentage:true)
                Text("MetalPetal 高通磨皮结合皮肤区域与纹理保护。开启前后对比，检查五官和皮肤细节；实际后端可在照片信息中查看。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if model.recipe.edit?.masks.isEmpty == false {
                InspectorSection("局部调整") {
                    AgentAdvancedControls(model:model)
                }
            }
        }
    }

    private var recipeInspector: some View {
        Group {
            InspectorSection("保存当前配方") {
                Text("把当前调整保存下来，用于下一张或同组照片。").font(.caption).foregroundStyle(.secondary)
                TextField("配方名称",text:$recipeName).textFieldStyle(.roundedBorder).accessibilityLabel("配方名称")
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
                Text("先选择照片，再确认批量导出。每张照片保留原片。").font(.caption).foregroundStyle(.secondary)
                Button{openBatch()}label:{Label("选择整组并前往批量…",systemImage:"square.grid.2x2")}.font(.caption)
            }
            Button("重置当前编辑"){model.reset()}.font(.caption).foregroundStyle(.secondary).padding(.top,16)
        }
    }

    private var assistantInspector: some View {
        VStack(alignment:.leading,spacing:16) {
            Button { model.agentProcessPresented=true } label:{Label("展开 Agent 处理过程",systemImage:"arrow.up.left.and.arrow.down.right").frame(maxWidth:.infinity)}
                .buttonStyle(.bordered).accessibilityLabel("展开 Agent 处理过程")
            AgentComposer(model:model)
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
    private func openBatch() { model.selection=Set(model.assets.map(\.id));model.page = .batch }
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

private func presetTitle(_ preset: FilterPreset)->String {
    switch preset {case .natural:return "自然";case .portrait:return "人像";case .film:return "胶片";case .warm:return "暖调";case .cool:return "冷调";case .clean:return "清透"}
}

private struct PresetPhotoPreview: View {
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
        if keys.count>18 { cache.removeValue(forKey:keys.removeFirst()) }
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
    @State private var query=""
    @State private var rawOnly=false
    private var photos: [PhotoAsset] { model.assets.filter{(!rawOnly || $0.isRAW) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))} }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Text("照片 · \(photos.count)").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
                Spacer(minLength:8)
                TextField("查找照片",text:$query).textFieldStyle(.plain).font(.system(size:10)).padding(.horizontal,8).padding(.vertical,4).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:4)).frame(width:130).accessibilityLabel("查找照片")
                Toggle("仅 RAW",isOn:$rawOnly).toggleStyle(.button).font(.system(size:10)).buttonStyle(.borderless)
                Button {
                    model.selection=Set(photos.map(\.id));model.page = .batch
                } label:{Label("批量处理…",systemImage:"square.grid.2x2").font(.system(size:10))}.buttonStyle(.borderless).disabled(photos.isEmpty)
            }.padding(.horizontal,16).frame(height:35)
            ScrollView(.horizontal) {
                LazyHStack(spacing:9) {
                    ForEach(photos) { asset in
                        Button{model.select(asset)}label:{
                            VStack(alignment:.leading,spacing:5) {
                                AsyncImage(url:asset.thumbnailURL){image in image.resizable().scaledToFit()}placeholder:{Color(white:0.09)}
                                    .frame(width:96,height:66).background(Color(white:0.035)).clipped().clipShape(RoundedRectangle(cornerRadius:4))
                                    .overlay(alignment:.topTrailing){if asset.isRAW { Text("RAW").font(.system(size:8,weight:.semibold)).padding(3).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:2)).padding(3) }}
                                    .overlay(RoundedRectangle(cornerRadius:4).stroke(model.selectedID==asset.id ? studioAccent : .clear,lineWidth:1.5))
                                Text(asset.name).font(.system(size:9)).foregroundStyle(model.selectedID==asset.id ? studioAccent : .secondary).lineLimit(1).frame(width:96,alignment:.leading)
                            }.padding(4).background(model.selectedID==asset.id ? studioAccent.opacity(0.06) : .clear,in:RoundedRectangle(cornerRadius:5))
                        }.buttonStyle(.plain).accessibilityLabel("编辑 \(asset.name)").help(asset.name)
                    }
                    Button{model.choose(.photos)}label:{Image(systemName:"plus").font(.system(size:18,weight:.light)).foregroundStyle(.secondary).frame(width:50,height:66).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:4))}.buttonStyle(.plain).accessibilityLabel("向图库添加照片").disabled(model.importing)
                }.padding(.horizontal,12).padding(.bottom,10)
            }.scrollIndicators(.hidden)
        }.frame(height:134).background(Color(white:0.075))
    }
}
