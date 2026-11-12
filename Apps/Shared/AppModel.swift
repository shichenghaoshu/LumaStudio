import SwiftUI
import UniformTypeIdentifiers
import PhotoCore

@MainActor final class AppModel: ObservableObject {
    enum Page: String,CaseIterable,Identifiable { case capture="拍摄",edit="修图",batch="批量";var id: Self { self };var symbol: String { switch self {case .capture:return "camera";case .edit:return "slider.horizontal.3";case .batch:return "square.grid.2x2"} } }
    enum ImportIntent { case photos,folder,inbox,library,reference,recipe,profile,exportSingle,exportBatch,modelPackage }
    @Published var page: Page = .edit
    @Published var assets: [PhotoAsset]=[]
    @Published var selectedID: UUID?
    @Published var selection=Set<UUID>()
    @Published var recipe=Recipe() { didSet {
        if !restoring,recipe != oldValue {
            if Date().timeIntervalSince(lastUndoDate)>0.4 { undoRecipes.append(oldValue);if undoRecipes.count>40 { undoRecipes.removeFirst() } }
            lastUndoDate=Date();redoRecipes=[];canUndo = !undoRecipes.isEmpty;canRedo=false
        }
        schedulePreview()
    } }
    @Published var instruction=""
    @Published var agentBusy=false
    @Published var agentStatus="用一句话描述你想要的效果"
    @Published var agentRun: AgentRun?
    enum AgentProcessState { case idle,running,completed,cancelled,failed }
    @Published var agentProcessPresented=false
    @Published var agentProcessState: AgentProcessState = .idle
    @Published var agentEvents: [AgentEvent]=[]
    @Published var agentAnalysis: ImageAnalysis?
    @Published var agentPlan: AgentPlan?
    @Published var agentRounds: [AgentRound]=[]
    @Published var agentDirectory: URL?
    @Published var agentStartedAt: Date?
    @Published var agentEndedAt: Date?
    @Published var agentInstruction=""
    @Published var agentFailure: String?
    @Published var automaticCorrection=true
    @Published var useLocalModel=true
    @Published var modelManagerPresented=false
    @Published var integrationsPresented=false
    @Published var cloudSettings: CloudSettings = (UserDefaults.standard.data(forKey:"cloudSettings.v1").flatMap{try? JSONDecoder().decode(CloudSettings.self,from:$0)}) ?? CloudSettings() {
        didSet { if let data=try? JSONEncoder().encode(cloudSettings) { UserDefaults.standard.set(data,forKey:"cloudSettings.v1") };cloudConnectionStatus="配置已更改，尚未测试" }
    }
    @Published var cloudConnectionStatus="尚未测试在线服务"
    @Published var cloudTesting=false
    @Published var cloudKeySaved=false
    @Published var voiceInbox: [VoiceCommand]=[]
    @Published var automaticVoiceExecution=false
    @Published var allowAppleOnlineSpeech=false
    @Published var localVoicePort: UInt16?
    @Published var localVoiceStarting=false
    @Published var localVoiceStatus="本机语音接口未启动"
    @Published var xiaozhiState: VoiceConnectionState = .disconnected
    @Published var xiaozhiEndpointSaved=false
    private let voiceQueue=VoiceCommandQueue()
    private let localVoiceServer=LocalVoiceServer()
    private let xiaozhiClient=XiaozhiMCPClient()
    private var localVoiceToken=""
    private var voiceConnectionGeneration=UUID()
    @Published var installedModels: [InstalledModel]=[]
    @Published var modelsBusy=false
    @Published var preferenceCount=0
    @Published var canUndo=false
    @Published var canRedo=false
    let deviceManager=DeviceCapabilityManager()
    @Published var preview: CGImage?
    @Published var original: CGImage?
    @Published var showingOriginal=false
    @Published var rendering=false
    @Published var importing=false
    @Published var importProgress=""
    @Published var renderStatus="导入照片，开始本地修图"
    @Published var message: String?
    @Published var exportedURL: URL?
    @Published var batchSnapshot: BatchSnapshot?
    @Published var savedRecipes: [URL]=[]
    @Published var profile: ColorProfile?
    @Published var useCompanionJPEG=false { didSet { schedulePreview() } }
    @Published var importerPresented=false
    @Published var syncPresented=false
    @Published var pairingInput=""
    @Published var autoBeauty=true
    @Published var autoSend=false
    @Published var root: URL
    @Published var inbox: URL
    let sync: LocalSyncService
    let tether: LumixTetherFolderAdapter
    #if os(macOS)
    let native: NativeCameraAdapter
    #endif
    private var library: PhotoLibrary?
    private var processor: PhotoProcessor?
    private var batch: BatchProcessor
    private var renderTask: Task<Void,Never>?
    private var renderGeneration=UUID()
    private var importIntent: ImportIntent = .photos
    private var bookmarkURLs=[URL]()
    private var restoring=false
    private var undoRecipes=[Recipe](),redoRecipes=[Recipe]()
    private var lastUndoDate=Date.distantPast
    private var agentTask: Task<Void,Never>?
    private var agentGeneration=UUID()
    private var preferenceMemory: LocalPreferenceMemory?
    private var historyStore: LocalHistoryStore?
    private var modelManager: ModelManager?
    private var activeBeautyModelPath: String?
    var selected: PhotoAsset? { assets.first{$0.id==selectedID} }
    var importTypes: [UTType] {
        switch importIntent {case .photos,.reference:return [.image,.rawImage];case .recipe,.profile:return [.json];default:return [.folder]}
    }
    var importMultiple: Bool { importIntent == .photos }
    init() {
        #if os(macOS)
        let base=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/LumaStudio")
        #else
        let base=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio")
        #endif
        var libraryRoot=base.appendingPathComponent("Library")
        var inboxRoot=base.appendingPathComponent("Inbox")
        for (key,target) in [("libraryBookmark",0),("inboxBookmark",1),("batchExportBookmark",2)] {
            if let data=UserDefaults.standard.data(forKey:key) {
                var stale=false
                if let url=try? URL(resolvingBookmarkData:data,options:[],relativeTo:nil,bookmarkDataIsStale:&stale) {
                    if url.startAccessingSecurityScopedResource() { bookmarkURLs.append(url) }
                    if target==0 { libraryRoot=url } else if target==1 { inboxRoot=url }
                }
            }
        }
        root=libraryRoot;inbox=inboxRoot
        tether=LumixTetherFolderAdapter(folder:inboxRoot)
        sync=LocalSyncService(receivedDirectory:base.appendingPathComponent("Received"))
        #if os(macOS)
        native=NativeCameraAdapter(directory:base.appendingPathComponent("NativeDownloads"))
        #endif
        batch=BatchProcessor(concurrency:ProcessInfo.processInfo.physicalMemory<=8*1024*1024*1024 ? 1 : 2,journalURL:libraryRoot.appendingPathComponent("BatchQueue.json"))
        do { processor=try PhotoProcessor(modelURL:Self.modelURL()) }
        catch { message=error.localizedDescription }
        Task { await configure() }
    }
    private static func modelURL()->URL? {
        let u=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/Models/SkinSegmentation.mlmodelc")
        return FileManager.default.fileExists(atPath:u.path) ? u : nil
    }
    private func configure() async {
        do { let location=root;library=try await Task.detached(priority:.userInitiated) { try PhotoLibrary(root:location) }.value }
        catch { message=error.localizedDescription;return }
        configureLocalAgent()
        await refreshModels()
        sync.onReceived={ [weak self] url in guard let self else { throw LumaError.notConnected };try await self.receive(url,autoProcess:false) }
        tether.onPhoto={ [weak self] url in guard let self else { throw LumaError.notConnected };try await self.receive(url,autoProcess:true) }
        #if os(macOS)
        native.onCapabilitiesChanged={ [weak self] capabilities in self?.sync.updateCaptureCapability(capabilities.supportsRemoteCapture) }
        native.onDownloaded={ [weak self] url in guard let self else { throw LumaError.notConnected };try await self.receive(url,autoProcess:true) }
        sync.onCapture={ [weak self] in guard let self else { throw LumaError.notConnected };return try await self.native.capture().url }
        do { try await tether.connect() } catch { message=error.localizedDescription }
        #endif
        await reload()
        if selectedID==nil,let first=assets.first { select(first) }
        do {
            let recovered=try await batch.recover { [weak self] s in await self?.receiveBatchSnapshot(s) }
            if recovered { batchSnapshot=await batch.current();message="发现未完成的批处理，已暂停恢复。请在批量页面继续。" }
        } catch { message="批量任务恢复失败：\(error.localizedDescription)" }
    }
    func reload() async {
        do { assets=try await library?.list() ?? [];savedRecipes=(try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("Recipes"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}) ?? [] }
        catch { message=error.localizedDescription }
    }
    func select(_ asset: PhotoAsset) {
        agentTask?.cancel();agentGeneration=UUID();agentBusy=false;agentRun=nil;agentStatus="用一句话描述你想要的效果"
        resetAgentProcess()
        undoRecipes=[];redoRecipes=[];canUndo=false;canRedo=false
        renderTask?.cancel();renderGeneration=UUID();selectedID=asset.id;preview=nil;original=nil;useCompanionJPEG=false
        Task {
            let r=(try? await library?.recipe(for:asset.id)) ?? Recipe()
            guard selectedID==asset.id else { return };restoring=true;recipe=r;restoring=false
            if let id=r.color.referenceProfileID {
                do { profile=try JSONDecoder().decode(ColorProfile.self,from:Data(contentsOf:root.appendingPathComponent("Profiles/\(id).json"))) }
                catch { profile=nil;message="配方引用的色彩档案缺失，请重新导入。" }
            } else { profile=nil }
            schedulePreview()
        }
    }
    func schedulePreview() {
        guard !restoring,!agentBusy,let asset=selected,let processor else { return }
        renderTask?.cancel();let token=UUID();renderGeneration=token;rendering=true
        let r=recipe,p=profile,u=workingURL(asset)
        renderTask=Task {
            do {
                try await Task.sleep(for:.milliseconds(140));try Task.checkCancellation()
                let result=try await processor.render(url:u,recipe:r,profile:p)
                try Task.checkCancellation();guard token==renderGeneration else { return }
                preview=result.image;original=result.original;rendering=false
                renderStatus="\(result.faceCount) 张人脸 · \(result.beautyBackend) · \(Int(result.milliseconds)) ms"
                try await library?.saveRecipe(r,for:asset.id)
            } catch is CancellationError {} catch {
                guard token==renderGeneration else { return };rendering=false;renderStatus=error.localizedDescription
                if asset.isRAW,asset.companionURL != nil,!useCompanionJPEG { message=error.localizedDescription+"\n可打开“使用配对 JPEG”继续编辑。" }
                else { message=error.localizedDescription }
            }
        }
    }
    func workingURL(_ asset: PhotoAsset)->URL { useCompanionJPEG ? (asset.companionURL ?? asset.originalURL) : asset.originalURL }
    private func receive(_ url: URL,autoProcess: Bool) async throws {
        guard let library else { throw LumaError.unsupported("图库尚未就绪") }
        let result=try await library.importPhoto(url)
        await reload()
        if !result.duplicate {
            if autoProcess && autoBeauty {
                var r=Recipe();r.beauty.enabled=true
                try await library.saveRecipe(r,for:result.asset.id)
                _ = try await processor?.render(url:result.asset.originalURL,recipe:r)
            }
            select(result.asset)
            if autoProcess,autoSend,sync.connected { try await sendAsset(result.asset) }
        }
    }
    func choose(_ intent: ImportIntent) {
        importIntent=intent
        #if os(macOS)
        let panel=NSOpenPanel();panel.allowsMultipleSelection=importMultiple
        let folder=importTypes == [.folder];panel.canChooseDirectories=folder;panel.canChooseFiles = !folder
        if !folder { panel.allowedContentTypes=importTypes }
        panel.canCreateDirectories=folder
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK { self?.handleImport(.success(panel.urls)) }
        }
        if let window=NSApp.keyWindow { panel.beginSheetModal(for:window,completionHandler:complete) }
        else { panel.begin(completionHandler:complete) }
        #else
        importerPresented=true
        #endif
    }
    func handleImport(_ result: Result<[URL],Error>) {
        let intent=importIntent
        Task {
            do {
                let urls=try result.get();guard let first=urls.first else { return }
                var scoped=[URL]();for url in urls where url.startAccessingSecurityScopedResource() { scoped.append(url) }
                defer { for u in scoped { u.stopAccessingSecurityScopedResource() } }
                switch intent {
                case .photos:await importPhotos(urls)
                case .folder:
                    let e=FileManager.default.enumerator(at:first,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])
                    let files=(e?.allObjects as? [URL] ?? []).filter{PhotoFileType.accepts($0) && ((try? $0.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])).map{$0.isRegularFile==true && $0.isSymbolicLink != true} ?? false)}
                    await importPhotos(files)
                case .inbox:
                    try remember(first,key:"inboxBookmark");await tether.disconnect();inbox=first;tether.folder=first;try await tether.connect()
                case .library:
                    guard batchSnapshot?.active != true,!importing else { throw LumaError.unsupported("请先结束导入和批处理") }
                    let new=try await Task.detached { try PhotoLibrary(root:first) }.value;try remember(first,key:"libraryBookmark");library=new;root=first
                    batch=BatchProcessor(concurrency:1,journalURL:first.appendingPathComponent("BatchQueue.json"));selectedID=nil;preview=nil;original=nil;selection=[];await reload()
                    configureLocalAgent()
                case .reference:
                    guard let processor else { return }
                    let p=try await processor.referenceProfile(url:first,name:first.deletingPathExtension().lastPathComponent)
                    try JSONEncoder().encode(p).write(to:root.appendingPathComponent("Profiles/\(p.id).json"),options:.atomic)
                    profile=p;recipe.color.referenceProfileID=p.id;schedulePreview()
                case .profile:
                    let p=try JSONDecoder().decode(ColorProfile.self,from:Data(contentsOf:first));try p.validate()
                    guard UUID(uuidString:p.id) != nil else { throw LumaError.corruptData("色彩档案 ID") }
                    try JSONEncoder().encode(p).write(to:root.appendingPathComponent("Profiles/\(p.id).json"),options:.atomic)
                    profile=p;recipe.color.referenceProfileID=p.id;schedulePreview()
                case .recipe:try loadRecipe(first)
                case .exportSingle:try await exportSingle(to:first)
                case .exportBatch:try await startBatch(to:first)
                case .modelPackage:try await installModelPackage(first)
                }
            } catch { message=error.localizedDescription }
        }
    }
    private func remember(_ url: URL,key: String) throws {
        #if os(macOS)
        let data=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
        #else
        let data=try url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)
        #endif
        UserDefaults.standard.set(data,forKey:key)
        if url.startAccessingSecurityScopedResource() { bookmarkURLs.append(url) }
    }
    private func importPhotos(_ files: [URL]) async {
        guard let library else { message="图库未就绪，请选择可读写的本地图库目录。";return }
        importing=true;defer{importing=false};var failures=[String](),duplicates=0;var last: PhotoAsset?
        for (i,url) in files.enumerated() {
            importProgress="正在导入 \(i+1) / \(files.count)"
            do { let result=try await library.importPhoto(url);last=result.asset;if result.duplicate { duplicates += 1 } }
            catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        await reload();if let last { select(last) }
        importProgress="已检查 \(files.count) 张 · 重复 \(duplicates) · 失败 \(failures.count)"
        if !failures.isEmpty { message=failures.prefix(6).joined(separator:"\n") }
    }
    func oneClickBeauty() { recipe.beauty.enabled=true }
    func reset() { profile=nil;recipe=Recipe() }
    func removeReference() { profile=nil;recipe.color.referenceProfileID=nil }
    func loadRecipe(_ url: URL) throws {
        let r=try JSONDecoder().decode(Recipe.self,from:Data(contentsOf:url)).validated()
        if let id=r.color.referenceProfileID {
            guard UUID(uuidString:id) != nil else { throw LumaError.corruptData("色彩档案 ID") }
            profile=try JSONDecoder().decode(ColorProfile.self,from:Data(contentsOf:root.appendingPathComponent("Profiles/\(id).json")));try profile?.validate()
        } else { profile=nil }
        recipe=r
    }
    func saveRecipe(named name: String) {
        Task { do { exportedURL=try await library?.storeRecipe(recipe,named:name);await reload() } catch { message=error.localizedDescription } }
    }
    func exportToLibrary() { Task { do { try await exportSingle(to:root.appendingPathComponent("Exports")) } catch { message=error.localizedDescription } } }
    func batchToLibrary() { Task { do { try await startBatch(to:root.appendingPathComponent("Exports")) } catch { message=error.localizedDescription } } }
    func importDropped(_ urls: [URL]) { importIntent = .photos;handleImport(.success(urls)) }
    func exportSingle(to folder: URL) async throws {
        guard let selected,let processor else { throw LumaError.unsupported("请先选择照片") }
        rendering=true;defer{rendering=false}
        let destination=SafeExport.uniqueURL(folder:folder,baseName:selected.name,format:recipe.export.format)
        exportedURL=try await processor.export(url:workingURL(selected),recipe:recipe,destination:destination,libraryRoot:root,profile:profile)
        renderStatus="已完成全分辨率导出 · \(destination.lastPathComponent)"
    }
    func startBatch(to folder: URL) async throws {
        let picked=assets.filter{selection.contains($0.id)}.map { a -> PhotoAsset in var item=a;item.originalURL=workingURL(a);return item }
        try remember(folder,key:"batchExportBookmark")
        try await batch.start(assets:picked,recipe:recipe,profile:profile,exportDirectory:folder,libraryRoot:root) { [weak self] snapshot in await self?.receiveBatchSnapshot(snapshot) }
    }
    private func receiveBatchSnapshot(_ s: BatchSnapshot) { batchSnapshot=s }
    func pauseBatch() { Task { await batch.pause() } }
    func resumeBatch() { Task { await batch.resume() } }
    func cancelBatch() { Task { await batch.cancel() } }
    func retryBatch() { Task { do { try await batch.retryFailures { [weak self] s in await self?.receiveBatchSnapshot(s) } } catch { message=error.localizedDescription } } }
    func exportProfile() {
        do { guard let profile else { return };let url=root.appendingPathComponent("Profiles/\(profile.id).json");exportedURL=url }
    }
    func exportLUT() {
        Task { do {
            guard let selected,let profile,let processor else { return }
            let url=root.appendingPathComponent("Exports/Match_\(profile.id.prefix(8)).cube")
            try await processor.exportLUT(source:workingURL(selected),profile:profile,destination:url);exportedURL=url;renderStatus="已导出当前照片的匹配 LUT；批量配方会逐张重新分析。"
        } catch { message=error.localizedDescription } }
    }
    private func sendAsset(_ asset: PhotoAsset) async throws {
        try await sync.sendPhoto(asset.originalURL,name:asset.name)
        if let companion=asset.companionURL {
            let name=URL(fileURLWithPath:asset.name).deletingPathExtension().lastPathComponent+"."+companion.pathExtension
            try await sync.sendPhoto(companion,name:name)
        }
    }
    func sendSelected() { Task { do { guard let selected else { return };try await sendAsset(selected) } catch { message=error.localizedDescription } } }
    private func configureLocalAgent() {
        do {
            preferenceMemory=try LocalPreferenceMemory(directory:root.appendingPathComponent("LocalMemory"))
            historyStore=try LocalHistoryStore(root:root.appendingPathComponent("AgentHistory"))
            if modelManager==nil { modelManager=try ModelManager(root:ModelManager.defaultRoot) }
            Task { preferenceCount=await preferenceMemory?.preferences().confirmationCount ?? 0 }
        } catch { message="本地 Agent 初始化失败：\(error.localizedDescription)" }
    }
    func runAgent() {
        guard !agentBusy,let asset=selected,let processor,let historyStore else { return }
        let text=instruction.trimmingCharacters(in:.whitespacesAndNewlines);guard !text.isEmpty else { return }
        renderTask?.cancel();renderGeneration=UUID();rendering=false
        let generation=UUID();agentGeneration=generation
        let snapshot=recipe,reference=profile,correction=automaticCorrection,preferModel=useLocalModel,cloud=cloudSettings
        let past=agentRun.map{[$0.instruction]} ?? []
        resetAgentProcess();agentRun=nil;agentBusy=true;agentProcessState = .running
        agentStartedAt=Date();agentInstruction=text;agentStatus="正在准备本地处理环境…"
        var input=asset;input.originalURL=workingURL(asset)
        agentTask=Task {
            defer { if agentGeneration==generation { agentBusy=false;agentEndedAt=Date() } }
            do {
                let prefs=await preferenceMemory?.preferences() ?? EditingPreferences()
                var model: InstalledModel?,loadFailure: String?
                if preferModel,(cloud.mode == .local || cloud.fallbackToLocal) { do { model=try await modelManager?.activeAgent(device:deviceManager.snapshot()) } catch { loadFailure="模型未能通过本地校验，已使用规则："+error.localizedDescription } }
                let local=NativeAgentPlanner(model:model,fallbackReason:loadFailure)
                let planner: any AgentPlanner
                if cloud.mode == .online {
                    guard let key=try IntegrationCredentials.read(cloud.credentialAccount),!key.isEmpty else { throw LumaError.unsupported("请在“模型与语音接入”中保存在线服务 API 密钥") }
                    let preview=cloud.attachPreview ? try CloudPreview.jpeg(input.thumbnailURL) : nil
                    let online=OnlineAgentPlanner(settings:cloud,key:key,previewJPEG:preview)
                    planner=cloud.fallbackToLocal ? OnlineWithLocalFallback(online:online,local:local) : online
                } else { planner=local }
                let engine=NativeImageEngine(processor:processor,profile:reference,raw:snapshot.raw)
                let session=AgentSession(engine:engine,planner:planner,history:historyStore)
                let result=try await session.run(asset:input,instruction:text,preferences:prefs,currentRecipe:(try? snapshot.validated())?.edit,referenceProfileID:reference?.id,previousInstructions:past,automaticCorrection:correction,updates:{ [weak self] update in
                    await self?.receiveAgentUpdate(update,assetID:asset.id,generation:generation)
                },progress:{ [weak self] status in
                    await self?.updateAgentStatus(status,assetID:asset.id,generation:generation)
                })
                try Task.checkCancellation();guard selectedID==asset.id,agentGeneration==generation else { return }
                agentRun=result.run
                agentDirectory=result.directory;agentRounds=result.run.rounds;agentEvents=result.run.events ?? agentEvents
                restoring=true
                undoRecipes.append(snapshot);redoRecipes=[];canUndo=true;canRedo=false
                recipe=try result.run.selectedRecipe.legacyRecipe(export:snapshot.export,raw:snapshot.raw)
                restoring=false;preview=result.preview.image;original=result.preview.original
                agentStatus=result.run.rounds[result.run.selectedRound].evaluation.summary
                renderStatus="\(result.run.source) · \(result.run.rounds.count) 次渲染 · \(Int(result.run.planningMilliseconds)) ms 参数生成"
                try await library?.saveRecipe(recipe,for:asset.id)
                agentProcessState = .completed
            } catch is CancellationError { if agentGeneration==generation { agentStatus="已停止，当前编辑保留";agentProcessState = .cancelled } }
            catch { restoring=false;if agentGeneration==generation { agentStatus="生成失败，当前编辑保留";agentFailure=error.localizedDescription;agentProcessState = .failed;message=error.localizedDescription } }
        }
    }
    private func resetAgentProcess() {
        agentProcessState = .idle;agentEvents=[];agentAnalysis=nil;agentPlan=nil;agentRounds=[]
        agentDirectory=nil;agentStartedAt=nil;agentEndedAt=nil;agentInstruction="";agentFailure=nil
    }
    private func receiveAgentUpdate(_ update: AgentUpdate,assetID: UUID,generation: UUID) {
        guard selectedID==assetID,agentGeneration==generation else { return }
        switch update {
        case .event(let event):agentEvents.append(event)
        case .analysis(let analysis):agentAnalysis=analysis
        case .plan(let plan):agentPlan=plan
        case .round(let round,let directory):agentDirectory=directory;agentRounds.append(round)
        }
    }
    private func updateAgentStatus(_ status: String,assetID: UUID,generation: UUID) { if selectedID==assetID,agentGeneration==generation { agentStatus=status } }
    func cancelAgent() { agentStatus="正在停止，等待当前操作结束…";agentTask?.cancel() }
    func refreshIntegrationCredentials() {
        cloudKeySaved=((try? IntegrationCredentials.read(cloudSettings.credentialAccount)) ?? nil) != nil
        xiaozhiEndpointSaved=((try? IntegrationCredentials.read("xiaozhi.mcp.endpoint")) ?? nil) != nil
    }
    func saveCloudKey(_ value: String) {
        do { _=try cloudSettings.validate();try IntegrationCredentials.save(value.trimmingCharacters(in:.whitespacesAndNewlines),account:cloudSettings.credentialAccount);cloudKeySaved=true;cloudConnectionStatus="密钥已保存在系统钥匙串，尚未测试" }
        catch { message=error.localizedDescription }
    }
    func removeCloudKey() {
        do { try IntegrationCredentials.remove(cloudSettings.credentialAccount);cloudKeySaved=false;cloudConnectionStatus="已移除保存的密钥" } catch { message=error.localizedDescription }
    }
    func testCloudConnection() {
        guard !cloudTesting else { return };cloudTesting=true;cloudConnectionStatus="正在测试…"
        let settings=cloudSettings
        Task {
            defer { cloudTesting=false }
            do {
                guard let key=try IntegrationCredentials.read(settings.credentialAccount) else { throw LumaError.unsupported("请先保存 API 密钥") }
                try await OnlineAgentPlanner(settings:settings,key:key).checkConnection()
                cloudConnectionStatus="在线服务连接和 JSON 返回检查通过"
            } catch { cloudConnectionStatus=error.localizedDescription }
        }
    }
    func startLocalVoiceBridge() {
        guard localVoicePort==nil,!localVoiceStarting else { return };localVoiceStarting=true
        localVoiceToken=UUID().uuidString+UUID().uuidString;let token=localVoiceToken
        Task {
            defer { localVoiceStarting=false }
            do {
                localVoicePort=try await localVoiceServer.start(token:token,onCommand:{ [weak self] command in
                    guard let self else { throw LumaError.notConnected };return try await self.receiveVoiceCommand(command)
                },onStatus:{ [weak self] in await self?.voiceStatus() ?? VoiceBridgeStatus(photo:nil,busy:false,pending:0,status:"应用未连接") })
                localVoiceStatus="本机接口已启动，只接受带令牌的本机请求"
            } catch { localVoiceStatus=error.localizedDescription;localVoiceToken="" }
        }
    }
    func stopLocalVoiceBridge() { Task { await localVoiceServer.stop();localVoicePort=nil;localVoiceToken="";localVoiceStatus="本机语音接口已停止" } }
    func copyVoiceBridgeConfiguration() {
        #if os(macOS)
        guard let port=localVoicePort else { return }
        let object=["base_url":"http://127.0.0.1:\(port)","token":localVoiceToken]
        if let data=try? JSONSerialization.data(withJSONObject:object,options:.prettyPrinted),let text=String(data:data,encoding:.utf8) {
            NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
            localVoiceStatus="接入配置已复制，包含仅本次启动有效的令牌"
        }
        #endif
    }
    func saveXiaozhiEndpoint(_ value: String) {
        do { _=try ServiceEndpoint.validate(value,webSocket:true);try IntegrationCredentials.save(value.trimmingCharacters(in:.whitespacesAndNewlines),account:"xiaozhi.mcp.endpoint");xiaozhiEndpointSaved=true }
        catch { message=error.localizedDescription }
    }
    func connectXiaozhi() {
        let generation=UUID();voiceConnectionGeneration=generation
        Task {
            do {
                guard let value=try IntegrationCredentials.read("xiaozhi.mcp.endpoint") else { throw LumaError.unsupported("请先保存小智 MCP 接入点") }
                let endpoint=try ServiceEndpoint.validate(value,webSocket:true)
                let router=VoiceMCPRouter(onCommand:{ [weak self] command in guard let self else { throw LumaError.notConnected };return try await self.receiveVoiceCommand(command) },onStatus:{ [weak self] in await self?.voiceStatus() ?? VoiceBridgeStatus(photo:nil,busy:false,pending:0,status:"应用未连接") })
                try await xiaozhiClient.connect(endpoint:endpoint,router:router,status:{ [weak self] state in await self?.updateXiaozhi(state,generation:generation) })
            } catch { xiaozhiState = .failed;message=error.localizedDescription }
        }
    }
    private func updateXiaozhi(_ state: VoiceConnectionState,generation: UUID) { if voiceConnectionGeneration==generation { xiaozhiState=state } }
    func disconnectXiaozhi() { voiceConnectionGeneration=UUID();Task { await xiaozhiClient.disconnect();xiaozhiState = .disconnected } }
    func removeXiaozhiEndpoint() {
        disconnectXiaozhi()
        do { try IntegrationCredentials.remove("xiaozhi.mcp.endpoint");xiaozhiEndpointSaved=false } catch { message=error.localizedDescription }
    }
    private func voiceStatus()->VoiceBridgeStatus { VoiceBridgeStatus(photo:selected?.name,busy:agentBusy,pending:voiceInbox.count,status:agentStatus) }
    private func receiveVoiceCommand(_ command: VoiceCommand) async throws -> VoiceReceipt {
        guard command.final else { return VoiceReceipt(id:command.id,status:"partial_ignored",message:"仅最终识别文字会进入修图") }
        guard voiceInbox.count<8 else { throw LumaError.unsupported("语音待处理列表已满") }
        guard await voiceQueue.accept(command) else { return VoiceReceipt(id:command.id,status:"duplicate",message:"已收到同一请求，不会重复执行") }
        guard voiceInbox.count<8 else { await voiceQueue.forget(command.id);throw LumaError.unsupported("语音待处理列表已满") }
        if automaticVoiceExecution,!agentBusy,selected != nil,!modelsBusy {
            instruction=command.text;page = .edit;agentProcessPresented=true;runAgent()
            return VoiceReceipt(id:command.id,status:"running",message:"已启动当前照片的修图处理")
        }
        voiceInbox.append(command)
        return VoiceReceipt(id:command.id,status:"awaiting_review",message:"已进入 LumaStudio 的语音待处理列表")
    }
    func useVoiceCommand(_ command: VoiceCommand,run: Bool) {
        guard !agentBusy else { return };instruction=command.text;voiceInbox.removeAll{$0.id==command.id}
        integrationsPresented=false;page = .edit;agentProcessPresented=true
        if run { runAgent() }
    }
    func undo() {
        guard !agentBusy,let previous=undoRecipes.popLast() else { return }
        redoRecipes.append(recipe);restoring=true;recipe=previous;restoring=false
        canUndo = !undoRecipes.isEmpty;canRedo=true;schedulePreview()
    }
    func redo() {
        guard !agentBusy,let next=redoRecipes.popLast() else { return }
        undoRecipes.append(recipe);restoring=true;recipe=next;restoring=false
        canUndo=true;canRedo = !redoRecipes.isEmpty;schedulePreview()
    }
    func applyRound(_ round: AgentRound) {
        do { recipe=try round.recipe.legacyRecipe(export:recipe.export,raw:recipe.raw);agentRun?.selectedRound=round.index }
        catch { message=error.localizedDescription }
    }
    func rememberStyle() {
        Task { do {
            guard let edit=(try recipe.validated()).edit else { message="先生成一个编辑方案，再记住它的风格。";return }
            try await preferenceMemory?.remember(edit);preferenceCount=await preferenceMemory?.preferences().confirmationCount ?? 0;agentStatus="已在本机记住这组风格参数"
        } catch { message=error.localizedDescription } }
    }
    func clearPreferences() { Task { do { try await preferenceMemory?.clear();preferenceCount=0 } catch { message=error.localizedDescription } } }
    func refreshModels() async { do {
        installedModels=try await modelManager?.list() ?? []
        let beauty=try await modelManager?.active(role:.beauty,device:deviceManager.snapshot())
        if let beauty,beauty.manifest.outputSchema != "LumaStudio skin-probability v1" { throw LumaError.unsupported("皮肤模型输出协议未适配，继续使用传统分割") }
        let target=beauty?.url ?? Self.modelURL()
        if !agentBusy,target?.path != activeBeautyModelPath {
            processor=try PhotoProcessor(modelURL:target);activeBeautyModelPath=target?.path;schedulePreview()
        }
    } catch { message=error.localizedDescription } }
    func installModelPackage(_ folder: URL) async throws {
        guard !modelsBusy,!agentBusy,let modelManager else { return };modelsBusy=true;defer{modelsBusy=false}
        _=try await modelManager.install(package:folder,device:deviceManager.snapshot());await refreshModels()
    }
    func activateModel(_ item: InstalledModel) { Task { do {
        modelsBusy=true;defer{modelsBusy=false};_=try await modelManager?.activate(id:item.manifest.id,version:item.manifest.version,device:deviceManager.snapshot());await refreshModels()
    } catch { message=error.localizedDescription } } }
    func uninstallModel(_ item: InstalledModel) { Task { do {
        modelsBusy=true;defer{modelsBusy=false};try await modelManager?.uninstall(id:item.manifest.id,version:item.manifest.version);await refreshModels()
    } catch { message=error.localizedDescription } } }
}
