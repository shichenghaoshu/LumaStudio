import SwiftUI
import PhotoCore

struct AgentComposer: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("描述你想要的照片",systemImage:"sparkles").font(.headline);Spacer()
                #if os(macOS)
                MacVoiceInputButton(model:model)
                #endif
            }
            TextField("例如：自然提亮，保留皮肤纹理，暖一点",text:$model.instruction,axis:.vertical)
                .lineLimit(2...4).textFieldStyle(.plain).padding(12).background(Color(white:0.065),in:RoundedRectangle(cornerRadius:10))
                .accessibilityLabel("修图要求")
            HStack(spacing:8) {
                ForEach(["自然人像","日系胶片","通透暖调"],id:\.self) { sample in
                    Button(sample) { model.instruction=sample=="自然人像" ? "自然人像美颜，保留皮肤纹理，不要过度磨皮" : sample=="通透暖调" ? "照片通透一点，轻微提亮，暖一点" : "自然日系胶片风格，降低饱和度，压低高光" }
                        .font(.caption2).buttonStyle(.bordered).controlSize(.small)
                }
            }.disabled(model.agentBusy)
            HStack {
                if model.agentBusy {
                    ProgressView().controlSize(.small)
                    Button("停止"){model.cancelAgent()}.font(.caption)
                } else {
                    Button { model.runAgent() } label:{Label(model.agentRun==nil ? "生成并预览" : "重新生成方案",systemImage:"sparkles").frame(maxWidth:.infinity)}
                        .buttonStyle(.borderedProminent).disabled(model.selected==nil || model.instruction.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.modelsBusy)
                        .accessibilityLabel("生成并预览")
                }
            }
            Text(model.agentStatus).font(.caption).foregroundStyle(model.agentBusy ? studioAccent : .secondary).fixedSize(horizontal:false,vertical:true)
            Toggle("自动检查并修正（最多两轮）",isOn:$model.automaticCorrection).font(.caption).toggleStyle(.checkbox).disabled(model.agentBusy)
            if let run=model.agentRun {
                AgentPlanView(model:model,run:run)
            }
        }
    }
}
struct AgentPlanView: View {
    @Bindable var model: AppModel
    let run: AgentRun
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Divider()
            HStack { Text("编辑方案").font(.subheadline.weight(.semibold));Spacer();Text(run.source).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            let current=(try? model.recipe.validated())?.edit ?? run.selectedRecipe
            VStack(alignment:.leading,spacing:5) {
                Text("曝光 \(current.global.exposure,specifier:"%+.2f") EV · 色温 \(Int(current.global.temperature)) K")
                Text("对比 \(current.global.contrast,specifier:"%.2f") · 饱和 \(current.global.saturation,specifier:"%.2f")")
                if current.beauty.enabled { Text("皮肤优化 \(Int(current.beauty.strength*100))% · 纹理保留 \(Int(current.beauty.texturePreservation*100))%") }
                if !current.masks.isEmpty { Text("局部区域："+current.masks.map{maskName($0.kind)}.joined(separator:"、")) }
            }.font(.caption).foregroundStyle(.secondary)
            if let reason=run.fallbackReason { Text(reason).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            DisclosureGroup("渲染与检查记录 · \(run.rounds.count) 轮") {
                VStack(alignment:.leading,spacing:8) {
                    ForEach(run.rounds) { round in
                        Button { model.applyRound(round) } label:{
                            VStack(alignment:.leading,spacing:4) {
                                HStack { Image(systemName:run.selectedRound==round.index ? "checkmark.circle.fill" : "circle");Text(round.index==0 ? "初始方案" : "第 \(round.index) 轮修正");Spacer();Text("\(Int(round.renderMilliseconds)) ms").monospacedDigit() }
                                Text(round.evaluation.summary).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            }.font(.caption).padding(8).background(Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:6))
                        }.buttonStyle(.plain).disabled(model.agentBusy)
                    }
                }.padding(.top,8)
            }.font(.caption)
            HStack { Button("记住这个风格"){model.rememberStyle()};Spacer();Text("仅保存在本机").foregroundStyle(.secondary) }.font(.caption2).disabled(model.agentBusy)
        }
    }
    private func maskName(_ kind: MaskKind)->String { switch kind {case .face:return "人脸";case .skin:return "皮肤";case .subject:return "人物";case .background:return "背景";case .hair:return "头发";case .sky:return "天空";case .brush:return "画笔"} }
}
struct AgentAdvancedControls: View {
    @Bindable var model: AppModel
    var body: some View {
        if model.recipe.edit != nil {
            DisclosureGroup("影调与局部调整") {
                VStack(alignment:.leading,spacing:12) {
                    editSlider("高光",\.highlights,-1...1)
                    editSlider("阴影",\.shadows,-1...1)
                    editSlider("白色色阶",\.whites,-1...1)
                    editSlider("黑色色阶",\.blacks,-1...1)
                    editSlider("自然饱和度",\.vibrance,-1...1)
                    LabeledSlider(title:"色温",value:$model.recipe.color.temperature,range:2500...10000)
                    if let masks=model.recipe.edit?.masks {
                        ForEach(masks.indices,id:\.self) { index in
                            VStack(alignment:.leading,spacing:6) {
                                Text("区域 \(index+1) · \(masks[index].kind.rawValue)").font(.caption)
                                LabeledSlider(title:"局部曝光",value:Binding(get:{model.recipe.edit?.masks[index].adjustments.exposure ?? 0},set:{model.recipe.edit?.masks[index].adjustments.exposure=$0}),range:-3...3)
                                LabeledSlider(title:"局部强度",value:Binding(get:{model.recipe.edit?.masks[index].amount ?? 1},set:{model.recipe.edit?.masks[index].amount=$0}),range:0...1)
                            }
                        }
                    }
                }.padding(.top,10)
            }.font(.callout)
        }
    }
    private func editSlider(_ label: String,_ key: WritableKeyPath<GlobalAdjustments,Float>,_ range: ClosedRange<Float>)->some View {
        LabeledSlider(title:label,value:Binding(get:{model.recipe.edit?.global[keyPath:key] ?? 0},set:{model.recipe.edit?.global[keyPath:key]=$0}),range:range)
    }
}
struct LocalModelsPanel: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { VStack(alignment:.leading,spacing:5) { Text("本地模型与偏好").font(.title2.weight(.semibold));Text("照片与编辑记录保留在当前图库；模型安装后可离线使用。").font(.caption).foregroundStyle(.secondary) };Spacer();Button("完成"){dismiss()} }
            let device=model.deviceManager.snapshot()
            Text("\(device.gpu) · \(device.physicalMemoryBytes/1024/1024/1024) GB 统一内存").font(.callout)
            Toggle("优先使用已安装的本地 Agent",isOn:$model.useLocalModel)
            Text("没有可用模型、内存不足或模型输出未通过检查时，自动使用本地规则与 Vision。").font(.caption).foregroundStyle(.secondary)
            Divider()
            if model.installedModels.isEmpty { Text("尚未安装语言模型。基础修图与明确指令仍可离线执行。").font(.callout).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    ForEach(model.installedModels) { item in
                        VStack(alignment:.leading,spacing:7) {
                            HStack { Text(item.manifest.displayName).font(.headline);Spacer();if item.active { Label("使用中",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(studioAccent) } }
                            Text("\(item.manifest.version) · \(item.manifest.precision) · \(ByteCountFormatter.string(fromByteCount:Int64(item.manifest.bytes),countStyle:.file)) · \(item.manifest.license)").font(.caption).foregroundStyle(.secondary)
                            Text(item.manifest.trainingStatus).font(.caption).foregroundStyle(.secondary)
                            if item.manifest.role == .vision || item.manifest.role == .evaluator { Text("此专用模型的运行适配尚未接入；当前仍使用 Vision 与确定性评价。").font(.caption).foregroundStyle(.secondary) }
                            HStack { if !item.active { Button("使用此版本／回滚"){model.activateModel(item)} };Button("卸载",role:.destructive){model.uninstallModel(item)} }.font(.caption)
                        }.padding(14).background(Color.white.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }
                }
            }.frame(minHeight:90,maxHeight:280)
            HStack { Button("从本地文件夹安装模型包…"){model.choose(.modelPackage)};if model.modelsBusy { ProgressView().controlSize(.small) };Spacer() }
            Divider()
            HStack { Text("已确认的本地风格：\(model.preferenceCount) 次").font(.callout);Spacer();Button("清除风格记忆",role:.destructive){model.clearPreferences()} }
            DisclosureGroup("设备详情") {
                VStack(alignment:.leading,spacing:5) { Text(device.model+" · "+device.operatingSystem);Text("可回收内存估计："+ByteCountFormatter.string(fromByteCount:Int64(device.availableMemoryEstimateBytes),countStyle:.memory));Text("内存压力："+device.memoryPressure);Text(device.neuralEngine) }.font(.caption).foregroundStyle(.secondary).padding(.top,8)
            }.font(.caption)
        }.padding(28).frame(minWidth:580,idealWidth:640,minHeight:460).disabled(model.agentBusy || model.modelsBusy)
    }
}
