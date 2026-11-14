import SwiftUI
import PhotoCore

struct ProInspectorView: View {
    @Bindable var model: AppModel
    let section: ParameterSection?
    @State private var query=""
    @State private var hue: HueBand = .red
    @State private var levelChannel="master"
    @State private var selectiveBand="red"
    @State private var filterCategory="全部"
    @State private var myFilters=false
    @State private var expanded: Set<String>=["whiteBalance","tone"]
    init(model: AppModel,section: ParameterSection? = nil) {self.model=model;self.section=section}
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            if section == nil {ProHistogramPanel(model:model)}
            HStack(spacing:7) {
                Image(systemName:"magnifyingglass").foregroundStyle(.tertiary)
                TextField("搜索参数与工具",text:$query).textFieldStyle(.plain).accessibilityLabel("查找专业参数")
                if !query.isEmpty {Button{query=""}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain)}
            }.font(.system(size:11)).padding(9).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:6))
            if !model.previewBypassedParameters.isEmpty {
                Button{model.previewBypassedParameters=[]}label:{Label("正在隐藏一组效果 · 恢复",systemImage:"eye.slash")}.font(.caption).foregroundStyle(studioAccent)
            }
            if query.isEmpty {modules}
            else {
                let matches=ParameterCatalog.all.filter{$0.title.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)}
                Text("找到 \(matches.count) 个参数").font(.caption2).foregroundStyle(.secondary)
                ForEach(matches){p in VStack(alignment:.leading,spacing:5){Text(p.section.title).font(.system(size:9)).foregroundStyle(.tertiary);ProParameterRow(model:model,parameter:p)}.padding(.vertical,4)}
            }
        }.padding(.top,12).onDisappear{model.previewBypassedParameters=[]}
    }
    @ViewBuilder private var modules: some View {
        if let section {
            switch section {
            case .portrait:portraitModule
            case .masks:maskModule
            case .style:styleModule
            case .raw:fold("raw","RAW 显影",section:.raw,defaultOpen:true){rawModule}
            case .geometry:fold("geometry","镜头与构图",section:.geometry,defaultOpen:true){geometryModule}
            case .output:fold("output","导出设置",section:.output,defaultOpen:true){outputModule}
            default:colorModules
            }
        } else {colorModules}
    }
    private var colorModules: some View {
        Group {
            fold("filter","滤镜",section:.style,ids:["color.intensity","color.lut"]){filterBrowser}
            fold("whiteBalance","白平衡",section:.tone,ids:["global.temperature","global.tint"]){
                HStack {ForEach([("日光",Float(5500)),("阴天",6500),("钨丝灯",2850)],id:\.0){name,value in Button(name){model.editDocument{$0.global.temperature=value;$0.global.tint=0}}.font(.caption2).buttonStyle(.bordered)}}
                rows(ParameterCatalog.section(.tone).filter{["global.temperature","global.tint"].contains($0.id)})
            }
            fold("tone","影调",section:.tone,ids:ParameterCatalog.section(.tone).filter{!["global.temperature","global.tint"].contains($0.id)}.map(\.id)){
                rows(ParameterCatalog.section(.tone).filter{!["global.temperature","global.tint"].contains($0.id)})
            }
            fold("levels","色阶",section:.levels){levelsModule}
            fold("curves","曲线",section:.curves){ProCurveEditor(model:model)}
            fold("hsl","HSL",section:.hsl){hslModule}
            fold("range","色彩编辑器",section:.range){rangeModule}
            fold("grading","颜色分级",section:.grading){gradingModule}
            fold("selective","可选颜色",section:.selective){selectiveModule}
            fold("detail","细节",section:.detail){rows(ParameterCatalog.section(.detail))}
            fold("grain","颗粒与胶片效果",section:.style,ids:ParameterCatalog.section(.style).filter{!$0.id.contains("vignette") && $0.id != "color.intensity"}.map(\.id)){rows(ParameterCatalog.section(.style).filter{!$0.id.contains("vignette") && $0.id != "color.intensity"})}
            fold("vignette","暗角",section:.style,ids:ParameterCatalog.section(.style).filter{$0.id.contains("vignette")}.map(\.id)){rows(ParameterCatalog.section(.style).filter{$0.id.contains("vignette")})}
            fold("geometry","镜头与透视",section:.geometry){geometryModule}
            fold("calibration","校准",section:.calibration){rows(ParameterCatalog.section(.calibration))}
        }
    }
    private func fold<Content: View>(_ id: String,_ title: String,section: ParameterSection,ids: [String]?=nil,defaultOpen: Bool=false,@ViewBuilder content: @escaping ()->Content)->some View {
        let targets=ids ?? (ParameterCatalog.section(section).map(\.id)+(section == .curves ? ["color.curve"] : (section == .style ? ["color.lut"] : [])))
        return ProInspectorGroup(model:model,title:title,ids:targets,expanded:Binding(get:{expanded.contains(id) || (defaultOpen && !expanded.contains("closed."+id))},set:{on in if on{expanded.insert(id);expanded.remove("closed."+id)}else{expanded.remove(id);expanded.insert("closed."+id)}}),reset:{
            model.editDocument{doc in
                if ids==nil {ParameterCatalog.reset(section,in:&doc)} else {
                    for target in targets{ParameterCatalog.find(target)?.reset(&doc)}
                    if targets.contains("color.lut"){doc.color.lut=nil}
                    if targets.contains("color.referenceProfileID"){doc.color.referenceProfileID=nil}
                }
            }
        },content:content)
    }
    private func rows(_ values: [ParameterDescriptor])->some View {ForEach(values){ProParameterRow(model:model,parameter:$0)}}
    private var levelsModule: some View {
        VStack(spacing:13) {
            Picker("色阶通道",selection:$levelChannel){Text("RGB").tag("master");Text("红").tag("red");Text("绿").tag("green");Text("蓝").tag("blue")}.pickerStyle(.segmented)
            LinearGradient(colors:[.black,.gray,.white],startPoint:.leading,endPoint:.trailing).frame(height:9).clipShape(Capsule())
            rows(ParameterCatalog.section(.levels).filter{$0.id.contains(".\(levelChannel).")})
        }
    }
    private var rangeModule: some View {
        VStack(alignment:.leading,spacing:13) {
            LinearGradient(colors:(0...12).map{Color(hue:Double($0)/12,saturation:0.85,brightness:0.9)},startPoint:.leading,endPoint:.trailing).frame(height:12).clipShape(Capsule())
            rows(ParameterCatalog.section(.range))
            Text("按色相范围调整；低饱和度区域受保护。").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var selectiveModule: some View {
        VStack(alignment:.leading,spacing:13) {
            Picker("可选颜色范围",selection:$selectiveBand){ForEach([("red","红色"),("yellow","黄色"),("green","绿色"),("cyan","青色"),("blue","蓝色"),("magenta","洋红色"),("white","白色"),("neutral","中性色"),("black","黑色")],id:\.0){key,label in Text(label).tag(key)}}
            Picker("颜色调整方式",selection:$model.recipe.document.color.selective.absolute){Text("相对").tag(false);Text("绝对").tag(true)}.pickerStyle(.segmented)
            rows(ParameterCatalog.section(.selective).filter{$0.id.hasPrefix("color.selective."+selectiveBand)})
        }
    }
    private var gradingModule: some View {
        VStack(spacing:14) {
            HStack(spacing:10){ProColorWheel(model:model,zone:"shadow",title:"阴影");ProColorWheel(model:model,zone:"midtone",title:"中间调");ProColorWheel(model:model,zone:"highlight",title:"高光")}
            rows(ParameterCatalog.section(.grading))
        }
    }
    private var rawModule: some View {
        VStack(alignment:.leading,spacing:15) {
            Text(model.rawCapabilities.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if model.selected?.isRAW != true || model.useCompanionJPEG {Text("RAW 解码控制仅作用于原始 RAW 文件。").font(.caption).foregroundStyle(.secondary)}
            rows(ParameterCatalog.section(.raw))
            Text("缩小预览可能看不到 RAW 解码细节的变化。RAW 锐度请在原尺寸导出中检查；预览锐化可使用“细节”面板。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button("恢复相机白平衡"){model.editDocument{$0.raw.temperature=nil;$0.raw.tint=nil}}.font(.caption)
            Toggle("快速草稿解码",isOn:$model.recipe.document.raw.draft).font(.caption).disabled(!model.rawCapabilities.description.hasPrefix("CIRAWFilter"))
            Toggle("使用内建镜头校正",isOn:Binding(get:{model.recipe.raw.lensCorrection ?? ((model.rawCapabilities.defaults["raw.lensCorrection"] ?? 0)>0)},set:{v in model.editDocument{$0.raw.lensCorrection=v}})).font(.caption).disabled(!model.rawCapabilities.lensCorrection)
            Text(model.rawCapabilities.lensCorrection ? "镜头校正由当前 RAW 解码器提供。" : "此文件未提供内建镜头校正，可使用镜头与构图中的手动补偿。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if model.selected?.companionURL != nil {Toggle("使用配对 JPEG",isOn:$model.useCompanionJPEG).font(.caption)}
        }.disabled(model.selected?.isRAW != true || model.useCompanionJPEG)
    }
    private var colorEnabled: some View {Toggle("启用色彩处理",isOn:$model.recipe.document.color.enabled).font(.caption)}
    private var hslModule: some View {
        VStack(alignment:.leading,spacing:18) {
            colorEnabled
            ScrollView(.horizontal) {
                HStack(spacing:8) {ForEach(HueBand.allCases,id:\.self){band in
                    Button{hue=band}label:{VStack(spacing:6){Circle().fill(band.swatch).frame(width:18,height:18).overlay(Circle().stroke(.white.opacity(hue==band ? 0.9 : 0),lineWidth:2).padding(-3));Text(band.title).font(.system(size:9))}.frame(width:30).padding(.vertical,5)}.buttonStyle(.plain).accessibilityLabel("HSL "+band.title)
                }}
            }.scrollIndicators(.hidden)
            rows(ParameterCatalog.section(.hsl).filter{$0.id.contains(".\(hue.rawValue).")}).disabled(!model.recipe.document.color.enabled)
            Text("八种颜色各自调整色相、饱和度和明度。").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var portraitModule: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Image(systemName:"person.crop.square");Text("人像美化").font(.system(size:13,weight:.semibold));Spacer();Text("\(model.faceCount) 张人脸").font(.caption).foregroundStyle(.secondary)}
            Toggle("启用美颜",isOn:$model.recipe.beauty.enabled).toggleStyle(.switch).font(.caption)
            HStack(spacing:5){ForEach(BeautyStyle.allCases,id:\.self){style in Button(style.title){model.applyBeautyStyle(style)}.font(.system(size:11)).frame(maxWidth:.infinity).buttonStyle(.bordered).accessibilityLabel("\(style.title)美颜预设")}}
            Text("高强度可明显磨平纹理；塑形预设同时启用瘦脸与大眼。可整体撤销，未检测到人脸时不执行。").font(.caption2).foregroundStyle(.secondary)
            fold("skin","高低频磨皮",section:.portrait,ids:["beauty.strength","beauty.radius","beauty.smoothing","beauty.texturePreservation","beauty.detailRecovery","beauty.sharpness","beauty.intensiveSmoothing"],defaultOpen:true){rows(ParameterCatalog.section(.portrait).filter{["strength","radius","smoothing","texturePreservation","detailRecovery","sharpness","intensiveSmoothing"].contains(String($0.id.split(separator:".").last!))})}
            fold("blemish","细小瑕疵弱化",section:.portrait,ids:["beauty.blemishRemoval","beauty.blemishThreshold"],defaultOpen:true){rows(ParameterCatalog.section(.portrait).filter{$0.id.contains("blemish")});Text("按局部红／暗变化弱化细小瑕疵，不能区分痣与痘痘。").font(.caption2).foregroundStyle(.secondary)}
            fold("skinTone","肤色调整",section:.portrait,ids:ParameterCatalog.section(.portrait).filter{$0.id.contains("skin") || $0.id.contains("toneUniformity") || $0.id.contains("shadowRepair")}.map(\.id),defaultOpen:true){rows(ParameterCatalog.section(.portrait).filter{$0.id.contains("skin") || $0.id.contains("toneUniformity") || $0.id.contains("shadowRepair")})}
            fold("faceShape","人脸塑形",section:.portrait,ids:["beauty.faceSlimming","beauty.eyeEnlargement"],defaultOpen:true){rows(ParameterCatalog.section(.portrait).filter{["beauty.faceSlimming","beauty.eyeEnlargement"].contains($0.id)});Text("基于 Vision 关键点进行局部像素变形，多人分别处理；大幅调整可能产生夸张效果。").font(.caption2).foregroundStyle(.secondary)}
            Text("磨皮与肤色蒙版保护眼、眉、嘴；塑形单独调整眼睛与下半脸。牙齿专用美白和生成式重绘尚未接入。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var styleModule: some View {
        VStack(alignment:.leading,spacing:14) {
            filterBrowser
            fold("styleEffects","胶片效果",section:.style,ids:ParameterCatalog.section(.style).filter{$0.id != "color.intensity"}.map(\.id)){rows(ParameterCatalog.section(.style).filter{$0.id != "color.intensity"})}
            fold("reference","参考图追色",section:.style,ids:["color.referenceProfileID"],defaultOpen:true){
                Button("选择参考照片…"){model.choose(.reference)}
                if let profile=model.profile {Text(profile.name).font(.caption);HStack{Button("移除参考"){model.removeReference()};Button("导出色彩档案"){model.exportProfile()};Button("导出 LUT"){model.exportLUT()}}.font(.caption)}
                else {Button("载入色彩档案…"){model.choose(.profile)}.font(.caption)}
            }
        }
    }
    private var filterBrowser: some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("滤镜来源",selection:$myFilters){Text("推荐 · 30").tag(false);Text("我的").tag(true)}.pickerStyle(.segmented)
            if !myFilters {
                ScrollView(.horizontal){HStack(spacing:6){ForEach(["全部","基础","人像","暖光","胶片","风光","电影","黑白","清新"],id:\.self){category in Button(category){filterCategory=category}.font(.system(size:10)).buttonStyle(.plain).padding(.horizontal,9).padding(.vertical,6).background(category==filterCategory ? studioAccent.opacity(0.14) : .white.opacity(0.04),in:Capsule()).foregroundStyle(category==filterCategory ? studioAccent : .secondary)}}}.scrollIndicators(.hidden)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:11){
                    ForEach(FilterPreset.allCases.filter{filterCategory=="全部" || $0.category==filterCategory}){preset in Button{model.applyPreset(preset.id)}label:{PresetPhotoPreview(asset:model.selected,preset:preset,selected:model.recipe.color.presetID==preset.id)}.buttonStyle(.plain).accessibilityLabel(preset.title+"滤镜")}
                }
            } else {
                if model.userFilters.isEmpty {Text("导入自己的 .cube 滤镜，保存在本机。").font(.caption).foregroundStyle(.secondary)}
                ForEach(model.userFilters){filter in Button{model.applyPreset(filter.id)}label:{HStack{Image(systemName:"cube.transparent");Text(filter.name);Spacer();if model.recipe.color.presetID==filter.id{Image(systemName:"checkmark")}}.font(.caption).foregroundStyle(model.recipe.color.presetID==filter.id ? studioAccent : .primary)}.buttonStyle(.plain).accessibilityLabel("应用自定义滤镜 "+filter.name)}
                Button{model.choose(.lut)}label:{Label("导入 CUBE…",systemImage:"plus")}.font(.caption)
            }
            if let p=ParameterCatalog.find("color.intensity"){ProParameterRow(model:model,parameter:p)}
            Button("移除滤镜"){model.applyPreset(nil)}.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var geometryModule: some View {
        VStack(alignment:.leading,spacing:15) {
            Picker("裁切比例",selection:$model.recipe.document.geometry.cropAspect) {
                Text("原始比例").tag(Float(0));Text("1 : 1").tag(Float(1));Text("4 : 3").tag(Float(4.0/3));Text("3 : 2").tag(Float(1.5));Text("16 : 9").tag(Float(16.0/9));Text("4 : 5").tag(Float(0.8));Text("2 : 3").tag(Float(2.0/3))
                if ![Float(0),1,Float(4.0/3),1.5,Float(16.0/9),0.8,Float(2.0/3)].contains(model.recipe.document.geometry.cropAspect) {Text("自定义").tag(model.recipe.document.geometry.cropAspect)}
            }.font(.caption)
            rows(ParameterCatalog.section(.geometry))
            Text("透视与旋转会自动裁去边缘；原图对照保持相同构图。镜头补偿为手动调整，未使用相机镜头档案。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var outputModule: some View {
        VStack(alignment:.leading,spacing:15) {
            Picker("输出格式",selection:$model.recipe.export.format){ForEach(ExportFormat.allCases,id:\.self){Text($0.rawValue.uppercased()).tag($0)}}.font(.caption)
            rows(ParameterCatalog.section(.output))
            Text("长边为 0 时保留裁切后的原始尺寸；不会放大照片。").font(.caption2).foregroundStyle(.secondary)
            Picker("输出色彩空间",selection:$model.recipe.document.export.colorSpace){Text("sRGB").tag(ExportColorSpace.sRGB);Text("Display P3").tag(ExportColorSpace.displayP3);Text("Adobe RGB (1998)").tag(ExportColorSpace.adobeRGB1998)}.font(.caption)
            if model.recipe.export.format == .jpeg {LabeledContent("输出位深",value:"8 位（JPEG）").font(.caption)}
            else {Picker("输出位深",selection:$model.recipe.document.export.bitDepth){Text("8 位").tag(8);Text("16 位").tag(16)}.font(.caption)}
            Toggle("保留原片 EXIF 元数据",isOn:$model.recipe.document.export.preserveEXIF).font(.caption)
            Text("开启后可保留相机、拍摄与位置等元数据。").font(.caption2).foregroundStyle(.secondary)
            TextField("文件命名规则",text:$model.recipe.document.export.nameTemplate).textFieldStyle(.roundedBorder).font(.caption).accessibilityLabel("文件命名规则")
            Text("可用：{name}、{id}、{index}、{date}").font(.caption2).foregroundStyle(.secondary)
            Button("选择批量导出目录…"){model.choose(.exportBatch)}.disabled(model.selection.isEmpty)
        }
    }
    private var maskModule: some View {
        VStack(alignment:.leading,spacing:15) {
            Menu("添加局部蒙版") {
                ForEach([MaskKind.face,.skin,.subject,.background,.brush],id:\.self){kind in Button(kind.title){model.addMask(kind)}.disabled((kind == .face || kind == .skin) && model.faceCount==0)}
            }.disabled(model.recipe.document.masks.count>=16)
            Text("人脸／皮肤需要检测到人脸；人物主体由 Vision 人物分割提供。头发、天空、衣服、眼睛、嘴唇专用分割未安装。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            ForEach(Array(model.recipe.document.masks.enumerated()),id:\.element.id) {index,mask in
                Button{model.activeMaskID=mask.id}label:{HStack{Image(systemName:mask.kind == .brush ? "paintbrush.pointed" : "circle.dashed");Text("\(index+1). "+mask.kind.title);Spacer();Text("\(Int(mask.amount*100))%").monospacedDigit();if model.activeMaskID==mask.id{Image(systemName:"checkmark")}}.font(.caption).foregroundStyle(model.activeMaskID==mask.id ? studioAccent : .secondary).padding(.vertical,5)}.buttonStyle(.plain).accessibilityLabel("选择蒙版 \(index+1) "+mask.kind.title)
            }
            if let mask=model.activeMask {
                Divider()
                HStack{Toggle("显示蒙版",isOn:$model.showMaskOverlay);Spacer();Button("删除蒙版",role:.destructive){model.removeActiveMask()}}.font(.caption)
                Toggle("蒙版反选",isOn:Binding(get:{model.activeMask?.inverted ?? false},set:{v in model.updateActiveMask{$0.inverted=v}})).font(.caption)
                maskScalar("amount","蒙版强度",0...1,0.01,1)
                maskScalar("feather","羽化（短边）",0...0.1,0.001,0.01)
                if mask.kind == .brush {
                    maskScalar("brushSize","画笔大小（短边）",0.002...0.3,0.001,0.06)
                    maskScalar("flow","画笔流量",0.01...1,0.01,1)
                    Toggle("在照片上绘制",isOn:$model.drawingBrush).font(.caption).disabled(!model.canDrawBrush)
                    Text(model.canDrawBrush ? "在画布上拖动画笔；每次笔触可以撤销。" : "绘制前请恢复构图；已有笔触会随构图同步。").font(.caption2).foregroundStyle(.secondary)
                    HStack{Text("\(mask.strokes.count) 条笔触").font(.caption2).foregroundStyle(.secondary);Spacer();Button("清空笔触"){model.updateActiveMask{$0.strokes=[]}}.font(.caption)}
                }
                Divider();Text("局部影调与色彩").font(.system(size:12,weight:.medium))
                ForEach(ParameterCatalog.section(.tone)){ProParameterRow(model:model,parameter:$0,local:true)}
                Divider();Text("局部细节").font(.system(size:12,weight:.medium))
                ForEach(ParameterCatalog.section(.detail)){ProParameterRow(model:model,parameter:$0,local:true)}
            }
        }
    }
    private func maskScalar(_ key: String,_ title: String,_ range: ClosedRange<Float>,_ step: Float,_ value: Float)->some View {
        let binding=Binding<Float>(get:{guard let m=model.activeMask else{return value};switch key{case "amount":return m.amount;case "feather":return m.feather;case "brushSize":return m.brushSize;default:return m.flow}},set:{v in model.updateActiveMask{m in switch key{case "amount":m.amount=v;case "feather":m.feather=v;case "brushSize":m.brushSize=v;default:m.flow=v}}})
        return ProScalarRow(model:model,id:"masks.\(model.activeMaskID ?? "none").\(key)",title:title,value:binding,range:range,step:step,scale:100,offset:0,unit:"%",reset:{binding.wrappedValue=value})
    }
}

struct ProParameterRow: View {
    @Bindable var model: AppModel
    let parameter: ParameterDescriptor
    var local=false
    private var available: Bool {
        if model.agentBusy {return false}
        if local {return model.activeMask != nil}
        if parameter.section == .raw {return model.selected?.isRAW==true && !model.useCompanionJPEG && model.rawCapabilities.supported.contains(parameter.id)}
        if parameter.section == .portrait {return model.faceCount>0 && model.recipe.beauty.enabled}
        if parameter.id=="export.quality" {return model.recipe.export.format == .jpeg}
        return true
    }
    var body: some View {
        ProScalarRow(model:model,id:local ? model.localLockID(parameter) : parameter.id,title:local ? "局部 "+parameter.title : parameter.title,value:Binding(get:{local ? model.localValue(parameter) : model.parameterValue(parameter)},set:{v in if local {model.setLocalParameter(parameter,v)}else{model.setParameter(parameter,v)}}),range:parameter.range,step:parameter.step,scale:parameter.scale,offset:parameter.offset,unit:parameter.unit,automatic:!local && parameter.isAutomatic(model.recipe.document),reset:{if local{model.resetLocalParameter(parameter)}else{model.resetParameter(parameter)}}).disabled(!available)
    }
}

struct ProScalarRow: View {
    @Bindable var model: AppModel
    let id: String,title: String
    @Binding var value: Float
    let range: ClosedRange<Float>,step: Float,scale: Float,offset: Float,unit: String
    var automatic=false
    let reset: ()->Void
    @FocusState private var numberFocused: Bool
    private var display: Binding<Double> {Binding(get:{Double(value*scale+offset)},set:{n in let v=(Float(n)-offset)/scale;if v.isFinite{value=min(range.upperBound,max(range.lowerBound,v))}})}
    // A stepped SwiftUI Slider creates a native tick for every step on macOS.
    // Keep the native track continuous and quantize the value instead; large
    // ranges must not allocate thousands of AppKit tick marks during layout.
    private var sliderValue: Binding<Float> {Binding(get:{value},set:{v in
        let snapped=range.lowerBound+((v-range.lowerBound)/step).rounded()*step
        value=min(range.upperBound,max(range.lowerBound,snapped))
    })}
    private var locked: Bool {ParameterLockPolicy.isLocked(id,in:model.recipe.document)}
    var body: some View {
        VStack(spacing:3) {
            HStack(spacing:6) {
                Text(title).foregroundStyle(.primary.opacity(0.75)).onTapGesture(count:2,perform:reset)
                if automatic {Text("相机").font(.system(size:8)).foregroundStyle(.tertiary)}
                Spacer(minLength:2)
                TextField("数值",value:display,format:.number.precision(.fractionLength(step*scale>=0.99 ? 0 : (step*scale>=0.09 ? 1 : 2)))).textFieldStyle(.plain).multilineTextAlignment(.trailing).monospacedDigit().frame(width:60).focused($numberFocused).accessibilityLabel(title+"数值").onSubmit{numberFocused=false}
                if !unit.isEmpty {Text(unit.trimmingCharacters(in:.whitespaces)).foregroundStyle(.secondary).frame(minWidth:11)}
                Button{model.toggleParameterLock(id)}label:{Image(systemName:locked ? "lock.fill" : "lock.open").font(.system(size:9)).foregroundStyle(locked ? studioAccent : .secondary)}.buttonStyle(.plain).help("锁定只限制 AI，仍可手动调整").accessibilityLabel((locked ? "解锁" : "锁定")+title)
                Button(action:reset){Image(systemName:"arrow.counterclockwise").font(.system(size:9))}.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("重置"+title)
            }.font(.system(size:11))
            Slider(value:sliderValue,in:range,onEditingChanged:{editing in if editing{model.beginParameterGesture()}else{model.endParameterGesture()}}).controlSize(.small).accessibilityLabel(title)
                .accessibilityAdjustableAction{direction in
                    switch direction {case .increment:sliderValue.wrappedValue=value+step;case .decrement:sliderValue.wrappedValue=value-step;@unknown default:break}
                }
        }.onChange(of:numberFocused){_,focused in if focused{model.beginParameterGesture()}else{model.endParameterGesture()}}
    }
}

private struct ProCurveEditor: View {
    @Bindable var model: AppModel
    @State private var channel="master"
    @State private var selected=0
    @State private var dragging: Int?
    private var points: [CurvePoint] {let p=model.recipe.document.color.curve.points(channel);return p.isEmpty ? [CurvePoint(0,0),CurvePoint(1,1)] : p}
    private var color: Color {switch channel{case "red":return .red;case "green":return .green;case "blue":return .blue;default:return studioAccent}}
    var body: some View {
        VStack(spacing:12) {
            HStack {
                Picker("曲线通道",selection:$channel){Text("RGB").tag("master");Text("R").tag("red");Text("G").tag("green");Text("B").tag("blue")}.pickerStyle(.segmented)
                Button{model.toggleParameterLock("color.curve."+channel)}label:{Image(systemName:ParameterLockPolicy.isLocked("color.curve."+channel,in:model.recipe.document) ? "lock.fill" : "lock.open")}.buttonStyle(.plain).accessibilityLabel("锁定当前曲线")
            }
            Canvas {ctx,size in
                var grid=Path();for i in 0...4 {let t=CGFloat(i)/4;grid.move(to:CGPoint(x:t*size.width,y:0));grid.addLine(to:CGPoint(x:t*size.width,y:size.height));grid.move(to:CGPoint(x:0,y:t*size.height));grid.addLine(to:CGPoint(x:size.width,y:t*size.height))};ctx.stroke(grid,with:.color(.white.opacity(0.08)),lineWidth:1)
                var line=Path();for i in 0...160 {let x=Float(i)/160,y=CurveSampler.value(x,points:points),p=CGPoint(x:CGFloat(x)*size.width,y:(1-CGFloat(y))*size.height);if i==0{line.move(to:p)}else{line.addLine(to:p)}};ctx.stroke(line,with:.color(color),lineWidth:2)
                for (i,p) in points.enumerated(){let dot=CGRect(x:CGFloat(p.x)*size.width-4,y:(1-CGFloat(p.y))*size.height-4,width:8,height:8);ctx.fill(Path(ellipseIn:dot),with:.color(i==selected ? .white : color))}
            }.frame(height:220).background(Color(white:0.06)).contentShape(Rectangle()).overlay{GeometryReader{proxy in Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in drag(v.location,size:proxy.size)}.onEnded{_ in dragging=nil;model.endParameterGesture()})}}.accessibilityLabel("曲线控制点画布")
            HStack(spacing:10) {
                Text("输入").font(.caption2);TextField("X",value:coordinate(true),format:.number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width:56).disabled(selected==0 || selected==points.count-1).accessibilityLabel("曲线输入值")
                Text("输出").font(.caption2);TextField("Y",value:coordinate(false),format:.number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).frame(width:56).accessibilityLabel("曲线输出值")
                Spacer();Button("删除"){var p=points;guard selected>0,selected<p.count-1 else{return};p.remove(at:selected);selected=max(0,selected-1);model.setCurve(p,channel:channel)}.disabled(selected==0 || selected>=points.count-1).font(.caption)
            }.monospacedDigit()
            HStack{Button("增加控制点"){addPoint()};Spacer();Button("重置曲线"){model.setCurve([],channel:channel);selected=0}}.font(.caption)
            Text("点按曲线添加节点，拖动调整；输入／输出使用 0–100。双击参数名称可重置。").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.onChange(of:channel){_,_ in selected=0;dragging=nil}
    }
    private func coordinate(_ x: Bool)->Binding<Double> {Binding(get:{Double(x ? points[min(selected,points.count-1)].x : points[min(selected,points.count-1)].y)*100},set:{v in guard v.isFinite else{return};var p=points;let i=min(selected,p.count-1);if x {guard i>0,i<p.count-1 else{return};p[i].x=min(p[i+1].x-0.001,max(p[i-1].x+0.001,Float(v)/100))}else{p[i].y=min(1,max(0,Float(v)/100))};model.setCurve(p,channel:channel)})}
    private func addPoint() {var p=points;guard p.count<16 else{return};let i=(0..<(p.count-1)).max{p[$0+1].x-p[$0].x<p[$1+1].x-p[$1].x}!;let x=(p[i].x+p[i+1].x)/2;p.insert(CurvePoint(x,CurveSampler.value(x,points:p)),at:i+1);selected=i+1;model.setCurve(p,channel:channel)}
    private func drag(_ location: CGPoint,size: CGSize) {
        var p=points;let x=Float(min(1,max(0,location.x/max(1,size.width)))),y=Float(1-min(1,max(0,location.y/max(1,size.height))))
        if dragging==nil {
            model.beginParameterGesture()
            let nearest=p.indices.min{hypot(CGFloat(p[$0].x-x)*size.width,CGFloat(p[$0].y-y)*size.height)<hypot(CGFloat(p[$1].x-x)*size.width,CGFloat(p[$1].y-y)*size.height)}!
            if hypot(CGFloat(p[nearest].x-x)*size.width,CGFloat(p[nearest].y-y)*size.height)<18 {dragging=nearest}
            else if p.count<16,x>0.005,x<0.995,!p.contains(where:{abs($0.x-x)<0.003}) {p.append(CurvePoint(x,y));p.sort{$0.x<$1.x};dragging=p.firstIndex{$0.x==x}}
            else {dragging=nearest}
        }
        let i=dragging ?? 0;selected=i
        if i>0,i<p.count-1 {p[i].x=min(p[i+1].x-0.001,max(p[i-1].x+0.001,x))};p[i].y=y
        model.setCurve(p,channel:channel)
    }
}

private struct ProColorWheel: View {
    @Bindable var model: AppModel
    let zone: String,title: String
    private var hue: Float {ParameterCatalog.find("color.grading."+zone+"Hue")!.read(model.recipe.document)}
    private var saturation: Float {ParameterCatalog.find("color.grading."+zone+"Saturation")!.read(model.recipe.document)}
    var body: some View {
        VStack(spacing:8) {
            GeometryReader {proxy in
                let center=CGPoint(x:proxy.size.width/2,y:proxy.size.height/2),r=min(proxy.size.width,proxy.size.height)/2
                Circle().fill(AngularGradient(colors:[.red,.purple,.blue,.cyan,.green,.yellow,.red],center:.center)).overlay(Circle().fill(RadialGradient(colors:[Color(white:0.7),.clear],center:.center,startRadius:0,endRadius:r)))
                    .overlay{Circle().stroke(.white,lineWidth:2).background(Circle().fill(.black.opacity(0.4))).frame(width:9,height:9).position(x:center.x+CGFloat(cos(Double(hue) * .pi/180))*r*CGFloat(saturation/0.3),y:center.y-CGFloat(sin(Double(hue) * .pi/180))*r*CGFloat(saturation/0.3))}
                    .contentShape(Circle()).gesture(DragGesture(minimumDistance:0).onChanged{v in model.beginParameterGesture();let dx=v.location.x-center.x,dy=center.y-v.location.y;let angle=atan2(dy,dx)*180 / .pi;model.setColorWheel(zone,hue:Float(angle<0 ? angle+360 : angle),saturation:Float(min(1,hypot(dx,dy)/max(1,r)))*0.3)}.onEnded{_ in model.endParameterGesture()})
            }.frame(height:88).accessibilityLabel(title+"色轮")
            Text(title).font(.system(size:10)).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity)
    }
}

extension HueBand {
    var title: String {switch self{case .red:return "红色";case .orange:return "橙色";case .yellow:return "黄色";case .green:return "绿色";case .aqua:return "青色";case .blue:return "蓝色";case .purple:return "紫色";case .magenta:return "洋红"}}
    var swatch: Color {switch self{case .red:return .red;case .orange:return .orange;case .yellow:return .yellow;case .green:return .green;case .aqua:return .cyan;case .blue:return .blue;case .purple:return .purple;case .magenta:return .pink}}
}
extension MaskKind {
    var title: String {switch self{case .face:return "人脸";case .skin:return "皮肤";case .subject:return "人物主体";case .background:return "背景";case .hair:return "头发（未安装）";case .sky:return "天空（未安装）";case .brush:return "画笔"}}
}
