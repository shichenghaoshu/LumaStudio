import SwiftUI
import PhotoCore
import ImageIO
import AppKit

private enum ProcessTheme {
    static let panel=Color(white:0.095)
    static let canvas=Color(white:0.035)
}
private extension AgentStage {
    var title: String {
        switch self {case .analysis:return "分析照片";case .planning:return "生成编辑方案";case .rendering:return "执行修图工具";case .evaluation:return "检查与修正";case .saving:return "保存处理记录"}
    }
    var symbol: String {
        switch self {case .analysis:return "viewfinder";case .planning:return "list.bullet.clipboard";case .rendering:return "slider.horizontal.3";case .evaluation:return "checkmark.shield";case .saving:return "tray.and.arrow.down"}
    }
    var pendingDetail: String {
        switch self {case .analysis:return "识别人脸、亮度与色彩";case .planning:return "把要求转成可编辑的参数";case .rendering:return "执行参数，生成实际预览";case .evaluation:return "检查指标，按需进行修正";case .saving:return "保存每轮结果与执行记录"}
    }
}
private enum ProcessPreviewMode: String,CaseIterable { case result="效果",original="原图",comparison="对照" }

struct AgentProcessWorkspace: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStage: AgentStage?
    @State private var focusedRound: Int?
    @State private var previewMode: ProcessPreviewMode = .result
    @State private var roundImage: CGImage?
    @State private var sourceThumbnail: CGImage?
    @State private var appliedMessage=""

    private var round: AgentRound? {
        let index=focusedRound ?? model.agentRun?.selectedRound ?? model.agentRounds.last?.index
        return model.agentRounds.first{$0.index==index}
    }
    private var stage: AgentStage { selectedStage ?? model.agentEvents.last?.stage ?? .analysis }
    private var originalImage: CGImage? { model.original ?? sourceThumbnail }
    private var previewKey: String { (model.agentDirectory?.path ?? "")+"/"+(round?.imageFilename ?? "") }
    private var completed: Bool { model.agentProcessState == .completed }
    private var statusTitle: String {
        switch model.agentProcessState {
        case .idle:return "准备开始"
        case .running:return model.agentEvents.last?.stage.title ?? "准备本地环境"
        case .completed:return "处理完成，等待确认"
        case .cancelled:return "处理已停止"
        case .failed:return "本次处理未完成"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing:0) {
                header
                Divider()
                HStack(spacing:0) {
                    executionRail.frame(width:geometry.size.width<1100 ? 220 : 246)
                    Divider()
                    photoWorkspace.frame(maxWidth:.infinity,maxHeight:.infinity)
                    Divider()
                    details.frame(width:geometry.size.width<1100 ? 252 : 282)
                }.frame(maxHeight:.infinity)
                Divider()
                composer
            }.background(ProcessTheme.panel)
        }
        .task(id:previewKey) {
            roundImage=nil
            guard let directory=model.agentDirectory,let round else { return }
            let url=directory.appendingPathComponent(round.imageFilename)
            let image=await Task.detached(priority:.userInitiated) { Self.loadImage(url) }.value
            guard !Task.isCancelled else { return };roundImage=image
        }
        .task(id:model.selectedID) {
            sourceThumbnail=nil
            guard let url=model.selected?.thumbnailURL else { return }
            let image=await Task.detached { Self.loadImage(url) }.value
            guard !Task.isCancelled else { return };sourceThumbnail=image
        }
        .onChange(of:model.agentRounds.count) { _,_ in if model.agentBusy { focusedRound=model.agentRounds.last?.index } }
        .onChange(of:model.agentRun?.selectedRound) { _,index in if let index { focusedRound=index } }
        .onChange(of:model.agentProcessState) { _,state in if state == .completed,selectedStage==nil { selectedStage = .evaluation } }
        .onChange(of:model.agentStartedAt) { _,_ in selectedStage=nil;focusedRound=nil;appliedMessage="";previewMode = .result }
        .onChange(of:model.selectedID) { _,_ in selectedStage=nil;focusedRound=nil;appliedMessage="" }
    }

    private var header: some View {
        HStack(spacing:14) {
            Button { model.agentProcessPresented=false } label:{Image(systemName:"chevron.left").frame(width:24,height:28)}
                .buttonStyle(.borderless).help("返回照片编辑，运行中的任务继续执行").accessibilityLabel("返回照片编辑")
            VStack(alignment:.leading,spacing:4) {
                HStack(spacing:8) {
                    Text("Luma Agent").font(.system(size:17,weight:.semibold))
                    Text("/ 处理过程").font(.system(size:12)).foregroundStyle(.secondary)
                }
                Text(model.selected?.name ?? "选择一张照片开始").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength:12)
            Label("本机渲染",systemImage:"lock.shield").font(.system(size:11)).foregroundStyle(.secondary)
            Divider().frame(height:22)
            if model.agentBusy { ProgressView().controlSize(.small) }
            Text(statusTitle).font(.system(size:12,weight:.medium)).foregroundStyle(model.agentBusy || completed ? studioAccent : .secondary)
            if let start=model.agentStartedAt {
                TimelineView(.periodic(from:start,by:1)) { context in
                    Text(String(format:"%.1f s",max(0,(model.agentEndedAt ?? context.date).timeIntervalSince(start))))
                        .font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).frame(minWidth:50,alignment:.trailing)
                }.accessibilityLabel("实际处理耗时")
            }
        }.padding(.horizontal,18).frame(height:68)
    }

    private var executionRail: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                HStack { Text("执行步骤").font(.system(size:12,weight:.semibold));Spacer();Text("执行记录").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary) }
                    .padding(.bottom,20)
                if !model.agentInstruction.isEmpty {
                    Text("你的要求").font(.system(size:10)).foregroundStyle(.secondary).padding(.bottom,7)
                    Text(model.agentInstruction).font(.system(size:12)).lineSpacing(4).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                        .padding(.bottom,22)
                    Divider().padding(.bottom,20)
                }
                ForEach(Array(AgentStage.allCases.enumerated()),id:\.element) { index,item in
                    ProcessStageRow(stage:item,number:index+1,events:model.agentEvents.filter{$0.stage==item},selected:stage==item,busy:model.agentBusy,terminal:model.agentProcessState == .failed || model.agentProcessState == .cancelled,isLast:index==AgentStage.allCases.count-1) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.16)) { selectedStage=item }
                    }
                }
                if selectedStage != nil,model.agentBusy {
                    Button { selectedStage=nil } label:{Label("跟随当前步骤",systemImage:"location.fill")}.font(.system(size:10)).buttonStyle(.borderless).foregroundStyle(studioAccent).padding(.top,8)
                }
                Divider().padding(.top,18).padding(.bottom,14)
                Text("每一轮都可回看").font(.system(size:11,weight:.medium)).padding(.bottom,6)
                Text("完成检查后才出现该轮预览。你可以选择采用的版本。").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
            }.padding(20)
        }
    }

    private var photoWorkspace: some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Text(round.map{roundTitle($0.index)} ?? "照片预览").font(.system(size:11,weight:.medium))
                if let round,model.agentRun?.selectedRound==round.index {
                    Text("当前采用").font(.system(size:9)).foregroundStyle(studioAccent)
                }
                Spacer(minLength:8)
                Picker("预览方式",selection:$previewMode) { ForEach(ProcessPreviewMode.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width:154).controlSize(.small).disabled(originalImage==nil)
            }.padding(.horizontal,16).frame(height:44)
            ZStack(alignment:.bottomLeading) {
                ProcessTheme.canvas
                if model.selected==nil {
                    VStack(spacing:14) {
                        Image(systemName:"photo.badge.plus").font(.system(size:32,weight:.ultraLight)).foregroundStyle(studioAccent)
                        Text("先选择一张照片").font(.system(size:14))
                        Button("导入照片…"){model.choose(.photos)}.buttonStyle(.bordered)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } else if previewMode == .comparison {
                    HStack(spacing:1) {
                        processPhoto(originalImage,label:"原图")
                        processPhoto(roundImage ?? model.preview ?? originalImage,label:round == nil ? "当前编辑" : "本轮效果")
                    }.padding(18)
                } else {
                    processPhoto(previewMode == .original ? originalImage : (roundImage ?? model.preview ?? originalImage),label:previewMode == .original ? "原图" : (round == nil ? "当前编辑" : "本轮效果"))
                        .padding(22)
                }
                if model.agentBusy {
                    HStack(spacing:8) { ProgressView().controlSize(.mini);Text(model.agentStatus).font(.system(size:10)).lineLimit(2) }
                        .padding(.horizontal,12).padding(.vertical,9).background(Color.black.opacity(0.78),in:RoundedRectangle(cornerRadius:7)).padding(12)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            versionStrip
        }.background(Color(white:0.07))
    }

    private func processPhoto(_ image: CGImage?,label: String)->some View {
        ZStack(alignment:.topLeading) {
            if let image {
                Image(decorative:image,scale:1).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity)
                    .transition(.opacity).animation(reduceMotion ? nil : .easeInOut(duration:0.18),value:previewMode)
            } else { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
            Text(label).font(.system(size:9,weight:.medium)).padding(.horizontal,8).padding(.vertical,5)
                .background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:4)).padding(5)
        }.accessibilityLabel(label)
    }

    private var versionStrip: some View {
        VStack(spacing:10) {
            HStack {
                Text("处理版本").font(.system(size:10)).foregroundStyle(.secondary)
                Spacer()
                if !model.agentRounds.isEmpty { Text("\(model.agentRounds.count) 轮实际渲染").font(.system(size:10)).foregroundStyle(.secondary) }
            }
            if model.agentRounds.isEmpty {
                HStack(spacing:8) { Image(systemName:"rectangle.stack");Text(model.agentBusy ? "完成首轮处理后，预览会出现在这里" : "开始处理后，在这里查看每一轮效果") }
                    .font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:54,alignment:.leading)
            } else {
                HStack(spacing:10) {
                    ForEach(model.agentRounds) { item in
                        ProcessVersionButton(round:item,directory:model.agentDirectory,selected:round?.index==item.index) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration:0.16)) { focusedRound=item.index;selectedStage = .evaluation;appliedMessage="" }
                        }
                    }
                }
            }
        }.padding(.horizontal,16).padding(.vertical,14)
    }

    private var details: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack(spacing:8) { Image(systemName:stage.symbol).foregroundStyle(studioAccent);Text(stage.title).font(.system(size:12,weight:.semibold)) }
                if let failure=model.agentFailure {
                    Label("处理未完成",systemImage:"exclamationmark.triangle").font(.system(size:11)).foregroundStyle(studioAccent)
                    Text(failure).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                } else if model.agentProcessState == .cancelled {
                    Text("任务已停止。已完成的轮次仍可查看，当前编辑保留。").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                switch stage {
                case .analysis:analysisDetails
                case .planning,.rendering:recipeDetails
                case .evaluation:evaluationDetails
                case .saving:savingDetails
                }
                if stage != .analysis,let source=model.agentPlan?.source ?? model.agentRun?.source {
                    Divider()
                    detailHeading("方案来源")
                    Text(source).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    if let reason=model.agentPlan?.fallbackReason ?? model.agentRun?.fallbackReason { Text(reason).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                }
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
        }
    }

    @ViewBuilder private var analysisDetails: some View {
        if let analysis=model.agentAnalysis {
            detailRow("分析预览","\(analysis.width) × \(analysis.height)")
            detailRow("识别人脸","\(analysis.faceCount) 张")
            detailRow("画面类型",analysis.faceCount>0 ? "包含人像" : "一般照片")
            Divider()
            detailHeading("原图采样指标")
            detailRow("平均亮度",String(format:"%.3f",analysis.metrics.meanLuminance))
            detailRow("高光溢出",percent(analysis.metrics.clippedHighlights))
            detailRow("暗部压黑",percent(analysis.metrics.crushedShadows))
            Text("指标来自预览采样，用于辅助后续检查。").font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        } else { pendingDetail("开始后会显示真实的分析结果。") }
    }

    @ViewBuilder private var recipeDetails: some View {
        if let recipe=round?.recipe ?? model.agentPlan?.recipe {
            detailHeading(round.map{roundTitle($0.index)+"参数"} ?? "已校验的参数")
            detailRow("曝光",String(format:"%+.2f EV",recipe.global.exposure))
            detailRow("色温","\(Int(recipe.global.temperature)) K")
            detailRow("对比度",String(format:"%.2f",recipe.global.contrast))
            detailRow("饱和度",String(format:"%.2f",recipe.global.saturation))
            if recipe.beauty.enabled {
                detailRow("皮肤优化","\(Int(recipe.beauty.strength*100))%")
                detailRow("纹理保留","\(Int(recipe.beauty.texturePreservation*100))%")
            } else { detailRow("皮肤优化","关闭") }
            Divider()
            detailHeading(stage == .rendering ? "本轮工具" : "可执行工具")
            ForEach(Array(recipe.resolvedOperations.enumerated()),id:\.offset) { index,operation in
                HStack(alignment:.top,spacing:9) {
                    Text(String(format:"%02d",index+1)).font(.system(size:9,design:.monospaced)).foregroundStyle(studioAccent).padding(.top,2)
                    VStack(alignment:.leading,spacing:4) {
                        Text(toolTitle(operation.tool)).font(.system(size:11))
                        Text(operation.tool.rawValue+(operation.maskID.map{" · "+$0} ?? "")).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            if let milliseconds=round?.renderMilliseconds,stage == .rendering { detailRow("渲染耗时",String(format:"%.2f s",milliseconds/1000)) }
            if let milliseconds=model.agentPlan?.planningMilliseconds,stage == .planning { detailRow("参数生成",String(format:"%.2f s",milliseconds/1000)) }
        } else { pendingDetail("方案生成并通过参数检查后，会在这里显示。") }
    }

    @ViewBuilder private var evaluationDetails: some View {
        if let round {
            let report=round.evaluation
            Text(roundTitle(round.index)).font(.system(size:10)).foregroundStyle(.secondary)
            Label(report.issues.isEmpty ? "本轮指标通过" : "\(report.issues.count) 项需要查看",systemImage:report.issues.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size:12,weight:.medium)).foregroundStyle(studioAccent)
            HStack { Text("采样指标");Spacer();Text("原图 → 本轮") }.font(.system(size:9)).foregroundStyle(.secondary)
            metricRow("平均亮度",before:report.before.meanLuminance,after:report.after.meanLuminance,percentage:false)
            metricRow("高光溢出",before:report.before.clippedHighlights,after:report.after.clippedHighlights)
            metricRow("暗部压黑",before:report.before.crushedShadows,after:report.after.crushedShadows)
            metricRow("平均饱和度",before:report.before.meanSaturation,after:report.after.meanSaturation,percentage:false)
            Divider()
            ForEach(Array(report.issues.enumerated()),id:\.offset) { _,issue in
                Label(issue.message,systemImage:issue.severity == .severe ? "exclamationmark.triangle" : "info.circle")
                    .font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text("使用亮度、色彩与纹理等确定性指标。照片是否符合你的审美，仍需要查看预览确认。").font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
            if !model.agentBusy {
                Button {
                    model.applyRound(round);appliedMessage="已采用"+roundTitle(round.index)
                } label:{Label("采用这一轮",systemImage:"checkmark").frame(maxWidth:.infinity)}
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.rendering)
                if !appliedMessage.isEmpty { Text(appliedMessage).font(.system(size:10)).foregroundStyle(studioAccent) }
            }
        } else { pendingDetail("首轮渲染和检查完成后，显示实际指标与修正提示。") }
    }

    @ViewBuilder private var savingDetails: some View {
        if completed {
            Label("记录已保存在本机",systemImage:"checkmark.circle").font(.system(size:12,weight:.medium)).foregroundStyle(studioAccent)
            detailRow("已保存轮次","\(model.agentRounds.count) 轮")
            detailRow("当前采用",roundTitle(model.agentRun?.selectedRound ?? 0))
            Text("每轮包含照片预览、编辑参数、执行工具与检查结果。原片保持不变。").font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
            if let directory=model.agentDirectory { Button { NSWorkspace.shared.open(directory) } label:{Label("在 Finder 查看记录",systemImage:"folder")}.font(.system(size:11)) }
            Button { selectedStage = .evaluation } label:{Label("查看效果与检查结果",systemImage:"checkmark.shield")}.font(.system(size:11))
            Button { model.agentProcessPresented=false } label:{Label("返回编辑并导出",systemImage:"arrow.right")}.buttonStyle(.borderedProminent).controlSize(.large)
        } else { pendingDetail("处理完成后会在本机保存记录，随后可返回编辑并导出。") }
    }

    private var composer: some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(alignment:.top,spacing:16) {
                Image(systemName:"sparkles").font(.system(size:18,weight:.light)).foregroundStyle(studioAccent).padding(.top,4)
                TextField("描述你想要的效果，例如：自然提亮，暖一点，保留皮肤纹理",text:$model.instruction,axis:.vertical)
                    .font(.system(size:13)).lineLimit(2...3).textFieldStyle(.plain).accessibilityLabel("过程页面修图要求").disabled(model.agentBusy)
                MacVoiceInputButton(model:model)
                if model.agentBusy {
                    Button("停止处理",role:.cancel){model.cancelAgent()}.controlSize(.large).accessibilityLabel("停止处理")
                } else {
                    Button { model.runAgent() } label:{Label(model.agentStartedAt==nil ? "开始处理" : "再次处理",systemImage:"arrow.up").frame(minWidth:92)}
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.selected==nil || model.instruction.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.modelsBusy)
                        .accessibilityLabel("开始 Agent 处理")
                }
            }
            HStack(spacing:14) {
                Toggle("自动修正",isOn:$model.automaticCorrection).toggleStyle(.checkbox).font(.system(size:10)).disabled(model.agentBusy)
                Text("每轮检查，最多修正 2 轮").font(.system(size:10)).foregroundStyle(.secondary)
                Spacer()
                Text("已锁定 \(model.recipe.document.lockedParameters.count) 项 · 本机渲染").font(.system(size:10)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal,24).padding(.vertical,18)
    }

    private func detailHeading(_ text: String)->some View { Text(text).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary) }
    private func detailRow(_ title: String,_ value: String)->some View {
        HStack(alignment:.firstTextBaseline,spacing:10) { Text(title).foregroundStyle(.secondary);Spacer(minLength:8);Text(value).monospacedDigit() }.font(.system(size:11))
    }
    private func pendingDetail(_ text: String)->some View { Text(text).font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal:false,vertical:true) }
    private func metricRow(_ title: String,before: Double,after: Double,percentage: Bool=true)->some View {
        detailRow(title,percentage ? "\(percent(before)) → \(percent(after))" : String(format:"%.3f → %.3f",before,after))
    }
    private func percent(_ value: Double)->String { String(format:"%.1f%%",value*100) }
    private func roundTitle(_ index: Int)->String { index==0 ? "初始方案" : "修正 \(index)" }
    private func toolTitle(_ tool: ToolID)->String { switch tool {case .global:return "全局影调与白平衡";case .beauty:return "皮肤优化与纹理保留";case .color:return "色彩与风格调整";case .local:return "局部区域调整"} }
    nonisolated private static func loadImage(_ url: URL)->CGImage? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source,0,nil)
    }
}

private struct ProcessVersionButton: View {
    let round: AgentRound
    let directory: URL?
    let selected: Bool
    let action: ()->Void
    private var title: String { round.index==0 ? "初始方案" : "修正 \(round.index)" }
    var body: some View {
        Button(action:action) {
            HStack(spacing:8) {
                if let directory {
                    AsyncImage(url:directory.appendingPathComponent(round.imageFilename)) { image in image.resizable().scaledToFit() } placeholder:{ Color.white.opacity(0.04) }
                        .frame(width:36,height:44).background(Color.black.opacity(0.25)).clipped()
                }
                VStack(alignment:.leading,spacing:5) {
                    Text(title).font(.system(size:10,weight:.medium))
                    Text(round.evaluation.issues.isEmpty ? "指标通过" : "\(round.evaluation.issues.count) 项提示").font(.system(size:9)).foregroundStyle(.secondary)
                }
            }.padding(6).frame(maxWidth:.infinity,alignment:.leading)
                .background(selected ? studioAccent.opacity(0.08) : Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:6))
                .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(selected ? studioAccent.opacity(0.6) : Color.clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel("查看\(title)").accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct ProcessStageRow: View {
    let stage: AgentStage
    let number: Int
    let events: [AgentEvent]
    let selected: Bool
    let busy: Bool
    let terminal: Bool
    let isLast: Bool
    let action: ()->Void
    @State private var hovered=false
    private var running: Bool { events.last?.kind == .started }
    private var finished: Bool { events.last?.kind == .finished }
    private var duration: Double? {
        let starts=events.filter{$0.kind == .started}
        let pairs=starts.compactMap { start -> Double? in
            guard let end=events.first(where:{$0.kind == .finished && $0.roundIndex==start.roundIndex && $0.timestamp>=start.timestamp}) else { return nil }
            return end.timestamp.timeIntervalSince(start.timestamp)
        }
        return pairs.isEmpty ? nil : pairs.reduce(0,+)
    }
    var body: some View {
        Button(action:action) {
            HStack(alignment:.top,spacing:12) {
                VStack(spacing:5) {
                    ZStack {
                        Circle().strokeBorder(selected || finished ? studioAccent.opacity(0.7) : Color.white.opacity(0.17),lineWidth:1).frame(width:27,height:27)
                        if running,busy { ProgressView().controlSize(.mini) }
                        else { Image(systemName:finished ? "checkmark" : (running && terminal ? "stop.fill" : stage.symbol)).font(.system(size:11)).foregroundStyle(selected || finished ? studioAccent : .secondary) }
                    }
                    if !isLast { Rectangle().fill(finished ? studioAccent.opacity(0.25) : Color.white.opacity(0.09)).frame(width:1).frame(minHeight:36) }
                }
                VStack(alignment:.leading,spacing:7) {
                    HStack(spacing:6) {
                        Text(stage.title).font(.system(size:12,weight:selected ? .semibold : .regular))
                        Spacer(minLength:0)
                        if let duration { Text(duration<0.1 ? "<0.1s" : String(format:"%.1fs",duration)).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary) }
                    }
                    Text(running && terminal ? "此步骤未完成" : (events.last?.detail ?? stage.pendingDetail))
                        .font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3).lineLimit(3).fixedSize(horizontal:false,vertical:true)
                }.padding(.top,5).padding(.bottom,isLast ? 0 : 22)
            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                .foregroundStyle(selected || hovered ? Color.white : Color.white.opacity(events.isEmpty ? 0.45 : 0.8))
        }.buttonStyle(.plain).onHover{hovered=$0}.accessibilityLabel("查看步骤：\(stage.title)")
            .accessibilityValue(running ? (busy ? "进行中" : "未完成") : (finished ? "已完成" : "等待执行"))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
