import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PhotoDomain
import PhotoPipeline
import ImageEngine
import ToolRegistry
import VisionEngine
import Evaluator
import LocalMemory
import ModelManager

public struct AgentPlan: Sendable {
    public var recipe: EditRecipe
    public let source: String
    public let fallbackReason: String?
    public let planningMilliseconds: Double
    public init(recipe: EditRecipe,source: String,fallbackReason: String?=nil,planningMilliseconds: Double) { self.recipe=recipe;self.source=source;self.fallbackReason=fallbackReason;self.planningMilliseconds=planningMilliseconds }
}
public protocol AgentPlanner: Sendable { func plan(_ context: PlanningContext) async throws -> AgentPlan }
public struct RulesAgentPlanner: AgentPlanner {
    public init() {}
    public func plan(_ context: PlanningContext) async throws -> AgentPlan {
        let start=Date();let r=try LocalRulePlanner().plan(context)
        return AgentPlan(recipe:r,source:"本地规则 + Vision",planningMilliseconds:Date().timeIntervalSince(start)*1000)
    }
}
public struct AgentRound: Codable,Identifiable,Sendable {
    public var id: Int { index }
    public let index: Int
    public let recipe: EditRecipe
    public let evaluation: QualityReport
    public let renderMilliseconds: Double
    public let imageFilename: String
    public let executedOperations: [EditOperation]
    public let timestamp: Date
}
public struct AgentRun: Codable,Identifiable,Sendable {
    public let id: UUID
    public let assetID: UUID
    public let instruction: String
    public let timestamp: Date
    public let analysis: ImageAnalysis
    public let intent: InstructionConstraints
    public let source: String
    public let fallbackReason: String?
    public let planningMilliseconds: Double
    public var rounds: [AgentRound]
    public var selectedRound: Int
    public var completed: Bool
    /// Optional so records made before the process page remain decodable.
    public var events: [AgentEvent]?=nil
    public var selectedRecipe: EditRecipe { rounds[selectedRound].recipe }
}
public struct AgentOutput {
    public let run: AgentRun
    public let preview: RenderResult
    public let directory: URL
}
public actor AgentSession {
    private let engine: any ImageEngine
    private let planner: any AgentPlanner
    private let history: LocalHistoryStore
    public init(engine: any ImageEngine,planner: any AgentPlanner,history: LocalHistoryStore) { self.engine=engine;self.planner=planner;self.history=history }
    public func run(asset: PhotoAsset,instruction: String,preferences: EditingPreferences=EditingPreferences(),currentRecipe: EditRecipe?=nil,referenceProfileID: String?=nil,previousInstructions: [String]=[],automaticCorrection: Bool=true,updates: @Sendable (AgentUpdate) async -> Void = {_ in},progress: @Sendable (String) async -> Void = {_ in}) async throws -> AgentOutput {
        let text=instruction.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=1000 else { throw LumaError.unsupported("请输入 1–1000 字的修图要求") }
        var events=[AgentEvent]()
        func emit(_ stage: AgentStage,_ kind: AgentEvent.Kind,_ detail: String,round: Int?=nil) async -> AgentEvent {
            let event=AgentEvent(stage:stage,kind:kind,roundIndex:round,detail:detail)
            await updates(.event(event));return event
        }
        try Task.checkCancellation();await progress("正在本地分析照片…")
        events.append(await emit(.analysis,.started,"读取照片并检测人脸、亮度与色彩"))
        let analysis=try await engine.analyze(asset)
        try Task.checkCancellation()
        await updates(.analysis(analysis))
        events.append(await emit(.analysis,.finished,"检测到 \(analysis.faceCount) 张人脸，已取得图像指标"))
        let context=PlanningContext(instruction:text,analysis:analysis,preferences:preferences,currentRecipe:currentRecipe,referenceProfileID:referenceProfileID,previousInstructions:previousInstructions)
        await progress("正在生成可执行的编辑方案…")
        events.append(await emit(.planning,.started,"根据指令生成参数，并检查可用工具与参数范围"))
        var plan=try await planner.plan(context)
        try Task.checkCancellation();plan.recipe.evaluation.automaticCorrection=automaticCorrection
        try ToolRegistry().validate(plan.recipe)
        await updates(.plan(plan))
        events.append(await emit(.planning,.finished,"参数与工具校验完成 · \(plan.source)"))
        var intent=InstructionParser.parse(text)
        if intent.beautyRequested,analysis.faceCount==0 { intent.unavailableRequests.append("未检测到人脸，未执行人像美颜");intent.beautyRequested=false }
        if text.contains("参考"),referenceProfileID==nil { intent.unavailableRequests.append("请先导入参考照片，再进行参考色匹配") }
        if intent.requestedLocalRegion != nil { intent.unavailableRequests.append("局部效果与指令符合度请结合预览确认") }
        let id=UUID(),dir=try await history.directory(assetID:asset.id,runID:id)
        var run=AgentRun(id:id,assetID:asset.id,instruction:text,timestamp:events.first?.timestamp ?? Date(),analysis:analysis,intent:intent,source:plan.source,fallbackReason:plan.fallbackReason,planningMilliseconds:plan.planningMilliseconds,rounds:[],selectedRound:0,completed:false,events:events)
        var recipe=plan.recipe,best: RenderResult?,bestPenalty=Int.max
        let evaluator=QualityEvaluator(),deadline=Date().addingTimeInterval(90)
        let maxRounds=automaticCorrection ? recipe.evaluation.maxCorrections : 0
        for round in 0...maxRounds {
            try Task.checkCancellation()
            guard Date()<deadline else { throw LumaError.unsupported("图像处理超时，已保留已完成的编辑记录") }
            await progress(round==0 ? "正在渲染并检查效果…" : "正在执行第 \(round) 轮自动修正…")
            events.append(await emit(.rendering,.started,round==0 ? "执行已校验的编辑工具" : "根据上一轮检查结果执行修正方案",round:round))
            let rendered=try await engine.preview(asset,recipe:recipe)
            try Task.checkCancellation()
            events.append(await emit(.rendering,.finished,"已完成照片预览 · \(Int(rendered.milliseconds)) ms",round:round))
            events.append(await emit(.evaluation,.started,"检查亮度、溢出、色彩及纹理指标",round:round))
            var evaluatedIntent=intent
            if intent.requestedLocalRegion != nil { evaluatedIntent.brightnessDirection=0;evaluatedIntent.saturationDirection=0;evaluatedIntent.warmthDirection=0 }
            let report=try evaluator.evaluate(original:rendered.original,result:rendered.image,recipe:recipe,intent:evaluatedIntent,skinMask:rendered.skinMask)
            try Task.checkCancellation()
            events.append(await emit(.evaluation,.finished,report.summary,round:round))
            let filename="round-\(round).jpg"
            try writePreview(rendered.image,to:dir.appendingPathComponent(filename))
            run.rounds.append(AgentRound(index:round,recipe:recipe,evaluation:report,renderMilliseconds:rendered.milliseconds,imageFilename:filename,executedOperations:recipe.resolvedOperations,timestamp:Date()))
            let penalty=report.issues.reduce(0){$0+($1.severity == .severe ? 10 : 1)}
            if penalty<=bestPenalty { bestPenalty=penalty;best=rendered;run.selectedRound=round }
            run.events=events
            try await history.save(run,assetID:asset.id,runID:id)
            await updates(.round(run.rounds[round],directory:dir))
            guard round<maxRounds,report.needsCorrection else { break }
            let corrected=try evaluator.corrected(recipe,report:report,intent:evaluatedIntent)
            guard corrected != recipe else { break };recipe=corrected
        }
        guard let best else { throw LumaError.invalidImage("没有完成的编辑预览") }
        try Task.checkCancellation()
        events.append(await emit(.saving,.started,"保存每轮预览、参数和检查记录"))
        run.completed=true;run.events=events;try await history.save(run,assetID:asset.id,runID:id)
        try Task.checkCancellation()
        events.append(await emit(.saving,.finished,"记录已保存在本机，原片保持不变"))
        run.events=events;try await history.save(run,assetID:asset.id,runID:id)
        return AgentOutput(run:run,preview:best,directory:dir)
    }
    private func writePreview(_ image: CGImage,to url: URL) throws {
        guard !FileManager.default.fileExists(atPath:url.path),let d=CGImageDestinationCreateWithURL(url as CFURL,UTType.jpeg.identifier as CFString,1,nil) else { throw LumaError.unsafeDestination }
        CGImageDestinationAddImage(d,image,[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw LumaError.invalidImage("编辑历史预览") }
    }
}
