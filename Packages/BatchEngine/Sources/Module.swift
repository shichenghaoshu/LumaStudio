import Foundation
import PhotoDomain
import PhotoPipeline
import ColorEngine

public enum BatchItemState: String, Codable, Sendable { case pending, running, completed, failed, cancelled }
public enum BatchItemPhase: String, Codable, Sendable { case analyzing, exporting, finished }
public struct BatchPlan: Codable, Sendable {
    public var recipe: Recipe
    public var source: String
    public var fallbackReason: String?
    public var historyDirectory: URL?
    public init(recipe: Recipe,source: String,fallbackReason: String?=nil,historyDirectory: URL?=nil) {
        self.recipe=recipe;self.source=source;self.fallbackReason=fallbackReason;self.historyDirectory=historyDirectory
    }
}
public struct BatchItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let source: URL
    public let name: String
    public var state: BatchItemState = .pending
    public var output: URL?
    public var error: String?
    public var attempts = 0
    public var thumbnailURL: URL?
    public var startingRecipe: Recipe?
    public var plan: BatchPlan?
    public var phase: BatchItemPhase?
    public init(id: UUID = UUID(), source: URL,name: String,thumbnailURL: URL?=nil) { self.id=id; self.source=source; self.name=name;self.thumbnailURL=thumbnailURL }
}
public struct BatchSnapshot: Codable, Sendable {
    public var items: [BatchItem]
    public var paused: Bool
    public var active: Bool
    public var cancelled: Bool
    public var recipe: Recipe
    public var profile: ColorProfile?
    public var exportDirectory: URL
    public var libraryRoot: URL?
    public var aiInstruction: String?=nil
    public var completed: Int { items.filter{$0.state == .completed}.count }
    public var failures: Int { items.filter{$0.state == .failed}.count }
    public var progress: Double { items.isEmpty ? 0 : Double(items.filter{[.completed,.failed,.cancelled].contains($0.state)}.count)/Double(items.count) }
}
public actor BatchProcessor {
    public typealias Update = @Sendable (BatchSnapshot) async -> Void
    public typealias Planner = @Sendable (PhotoAsset,Recipe) async throws -> BatchPlan
    private let concurrency: Int
    private let journalURL: URL?
    private var snapshot: BatchSnapshot?
    private var task: Task<Void,Never>?
    private var update: Update?
    private var planner: Planner?
    public init(concurrency: Int = 2,journalURL: URL? = nil) { self.concurrency=max(1,min(2,concurrency)); self.journalURL=journalURL }
    public func start(assets: [PhotoAsset],recipe: Recipe,profile: ColorProfile?,exportDirectory: URL,libraryRoot: URL?,aiInstruction: String?=nil,perPhotoRecipes: [UUID:Recipe]=[:],planner: Planner?=nil,update: @escaping Update) throws {
        guard task == nil else { throw LumaError.unsupported("已有批量任务正在运行") }
        let recipe=try recipe.validated()
        var seen=Set<URL>()
        let items=try assets.filter{seen.insert($0.originalURL.resolvingSymlinksInPath()).inserted}.map {asset -> BatchItem in
            var item=BatchItem(id:asset.id,source:asset.originalURL,name:asset.name,thumbnailURL:asset.thumbnailURL)
            if aiInstruction != nil,let personal=perPhotoRecipes[asset.id] {
                var document=ParameterLockPolicy.applying(recipe.document,preserving:personal.document)
                document.lockedParameters=Array(Set(recipe.document.lockedParameters+personal.document.lockedParameters)).sorted()
                item.startingRecipe=try Recipe(document:document).validated()
            } else if let personal=perPhotoRecipes[asset.id] {
                item.startingRecipe=try personal.validated()
            }
            return item
        }
        guard !items.isEmpty else { throw LumaError.unsupported("请先选择照片") }
        if let aiInstruction { guard !aiInstruction.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,aiInstruction.count<=1000,planner != nil else {throw LumaError.unsupported("请填写批量 AI 要求并连接方案来源")} }
        try FileManager.default.createDirectory(at:exportDirectory,withIntermediateDirectories:true)
        for item in items { try SafeExport.validate(destination:exportDirectory.appendingPathComponent("batch.jpg"),originals:[item.source],libraryRoot:libraryRoot) }
        self.update=update;self.planner=planner
        snapshot=BatchSnapshot(items:items,paused:false,active:true,cancelled:false,recipe:recipe,profile:profile,exportDirectory:exportDirectory,libraryRoot:libraryRoot,aiInstruction:aiInstruction)
        try persist(); task=Task { await run() }
    }
    public func current() -> BatchSnapshot? { snapshot }
    public func configurePlanner(_ planner: Planner?) { self.planner=planner }
    public func pause() async { snapshot?.paused=true; await publish() }
    public func resume() async { snapshot?.paused=false; await publish() }
    public func cancel() async { snapshot?.cancelled=true; snapshot?.paused=false; task?.cancel(); await publish() }
    public func retryFailures(update: @escaping Update) throws {
        guard task == nil, var s=snapshot else { throw LumaError.unsupported("当前任务未结束") }
        for i in s.items.indices where [.failed,.cancelled].contains(s.items[i].state) { s.items[i].state = .pending; s.items[i].error=nil }
        guard s.items.contains(where:{$0.state == .pending}) else { throw LumaError.unsupported("没有失败任务") }
        s.active=true;s.cancelled=false;s.paused=false;snapshot=s;self.update=update;try persist();task=Task { await run() }
    }
    public func recover(update: @escaping Update) throws -> Bool {
        guard task == nil, let journalURL,FileManager.default.fileExists(atPath:journalURL.path) else { return false }
        var s=try JSONDecoder().decode(BatchSnapshot.self,from:Data(contentsOf:journalURL))
        _=try s.recipe.validated(); try s.profile?.validate()
        for item in s.items {if let starting=item.startingRecipe {_=try starting.validated()};if let plan=item.plan {_=try plan.recipe.validated()} }
        for i in s.items.indices where s.items[i].state == .running { s.items[i].state = .pending }
        guard s.items.contains(where:{$0.state == .pending}) else { snapshot=s;return false }
        s.active=true;s.cancelled=false;s.paused=true;snapshot=s;self.update=update;task=Task { await run() };return true
    }
    public func waitUntilFinished() async { await task?.value }
    private func run() async {
        await publish()
        await withTaskGroup(of:(UUID,Result<URL,Error>).self) { group in
            var inFlight=0
            while true {
                if Task.isCancelled { group.cancelAll(); break }
                if snapshot?.paused != true, let s=snapshot {
                    for _ in inFlight..<concurrency {
                        guard let i=snapshot?.items.firstIndex(where:{$0.state == .pending}) else { break }
                        let item=snapshot!.items[i]
                        let planner=self.planner
                        snapshot!.items[i].state = .running;snapshot!.items[i].attempts += 1
                        inFlight += 1
                        group.addTask {
                            do {
                                try Task.checkCancellation()
                                let recipe: Recipe
                                if s.aiInstruction != nil {
                                    if let saved=item.plan { recipe=try saved.recipe.validated() }
                                    else {
                                        guard let planner else {throw LumaError.unsupported("请重新连接 AI 方案来源后重试，已完成的方案会保留")}
                                        await self.setPhase(.analyzing,id:item.id)
                                        let asset=PhotoAsset(id:item.id,name:item.name,originalURL:item.source,thumbnailURL:item.thumbnailURL ?? item.source)
                                        var plan=try await planner(asset,item.startingRecipe ?? s.recipe)
                                        plan.recipe=try plan.recipe.validated()
                                        try await self.savePlan(plan,id:item.id)
                                        recipe=plan.recipe
                                    }
                                } else {recipe=item.startingRecipe ?? s.recipe}
                                try Task.checkCancellation()
                                await self.setPhase(.exporting,id:item.id)
                                let worker=try PhotoProcessor()
                                let index=(s.items.firstIndex(where:{$0.id==item.id}) ?? 0)+1
                                let url=SafeExport.uniqueURL(folder:s.exportDirectory,baseName:item.name,format:recipe.export.format,settings:recipe.export,index:index)
                                let reference: ColorProfile?
                                if let id=recipe.color.referenceProfileID {
                                    if s.profile?.id==id {reference=s.profile}
                                    else if let root=s.libraryRoot,UUID(uuidString:id) != nil {
                                        let p=try JSONDecoder().decode(ColorProfile.self,from:Data(contentsOf:root.appendingPathComponent("Profiles/\(id).json")))
                                        try p.validate();reference=p
                                    } else {throw LumaError.unsupported("照片引用的色彩档案缺失，请重新导入后重试")}
                                } else {reference=nil}
                                let output=try await worker.export(url:item.source,recipe:recipe,destination:url,libraryRoot:s.libraryRoot,profile:reference)
                                return (item.id,.success(output))
                            } catch { return (item.id,.failure(error)) }
                        }
                    }
                    await publish()
                }
                if inFlight>0,let (id,result)=await group.next() {
                    inFlight -= 1
                    if let i=snapshot?.items.firstIndex(where:{$0.id==id}) {
                        switch result {
                        case .success(let url): snapshot!.items[i].state = .completed;snapshot!.items[i].output=url;snapshot!.items[i].phase = .finished
                        case .failure(let error): snapshot!.items[i].state = error is CancellationError ? .cancelled : .failed;snapshot!.items[i].error=error.localizedDescription
                        }
                    }
                    await publish()
                } else if snapshot?.items.contains(where:{$0.state == .pending}) == true {
                    do { try await Task.sleep(for:.milliseconds(150)) } catch { break }
                } else { break }
            }
            // Drain running work so cancel never reports completion while a writer is active.
            while let (id,result)=await group.next() {
                if let i=snapshot?.items.firstIndex(where:{$0.id==id}) {
                    if case .success(let output)=result { snapshot!.items[i].state = .completed;snapshot!.items[i].output=output }
                    else { snapshot!.items[i].state = .cancelled }
                }
            }
        }
        if snapshot != nil {
            for i in snapshot!.items.indices where [.pending,.running].contains(snapshot!.items[i].state) { snapshot!.items[i].state = .cancelled }
            snapshot!.active=false
        }
        task=nil;await publish()
    }
    private func setPhase(_ phase: BatchItemPhase,id: UUID) async {
        if let i=snapshot?.items.firstIndex(where:{$0.id==id}) {snapshot!.items[i].phase=phase};await publish()
    }
    private func savePlan(_ plan: BatchPlan,id: UUID) async throws {
        guard let i=snapshot?.items.firstIndex(where:{$0.id==id}) else {throw CancellationError()}
        snapshot!.items[i].plan=plan
        // Persist a paid plan before exporting, so retry/recovery reuses the exact same recipe.
        try persist();await publish()
    }
    private func persist() throws {
        if let journalURL,let snapshot { try JSONEncoder().encode(snapshot).write(to:journalURL,options:.atomic) }
    }
    private func publish() async {
        do { try persist() } catch { LumaLog.pipeline.error("批处理任务记录写入失败") }
        if let snapshot { await update?(snapshot) }
    }
}
