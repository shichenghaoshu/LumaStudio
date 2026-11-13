import SwiftUI
import Observation
import OSLog
import UniformTypeIdentifiers
import PhotoCore

@MainActor @Observable final class AppModel {
    enum Page: String,CaseIterable,Identifiable { case capture="拍摄",edit="修图",batch="批量";var id: Self { self };var symbol: String { switch self {case .capture:return "camera";case .edit:return "slider.horizontal.3";case .batch:return "square.grid.2x2"} } }
    enum ImportIntent { case photos,folder,inbox,library,reference,recipe,profile,lut,exportSingle,exportBatch,modelPackage }
    var page: Page = .edit
    var assets: [PhotoAsset]=[]
    var selectedID: UUID?
    var selection=Set<UUID>()
    var photoReviews=[UUID:PhotoReview]()
    var photoFilter=PhotoFilter() { didSet { if photoFilter != oldValue { pruneHiddenSelection() } } }
    var reviewBusy=false
    var recipeSyncPresented=false
    var workflowBusy=false
    var lastRecipeSync: RecipeSyncTransaction?
    var workflowStatus=""
    var recipe=Recipe() { didSet {
        if recipe != oldValue {
            if !restoring,parameterGestureBase==nil {pushUndo(oldValue)}
            schedulePreview()
        }
    } }
    var rawCapabilities=RAWCapabilities.unavailable
    var faceCount=0
    var activeMaskID: String? {didSet{if activeMaskID != oldValue {schedulePreview()}}}
    var showMaskOverlay=false {didSet{schedulePreview()}}
    var maskPreview: CGImage?
    var drawingBrush=false
    var previewBypassedParameters: [String]=[] {didSet{if previewBypassedParameters != oldValue {schedulePreview()}}}
    var agentParameterChanges: [ParameterChange]=[]
    @ObservationIgnored private var parameterGestureBase: Recipe?
    @ObservationIgnored private var agentStartingRecipe: EditRecipe?
    var instruction=""
    var agentBusy=false
    var agentStatus="用一句话描述你想要的效果"
    var agentRun: AgentRun?
    enum AgentProcessState { case idle,running,completed,cancelled,failed }
    var agentProcessPresented=false
    var agentProcessState: AgentProcessState = .idle
    var agentEvents: [AgentEvent]=[]
    var agentAnalysis: ImageAnalysis?
    var agentPlan: AgentPlan?
    var agentRounds: [AgentRound]=[]
    var agentDirectory: URL?
    var agentStartedAt: Date?
    var agentEndedAt: Date?
    var agentInstruction=""
    var agentFailure: String?
    var automaticCorrection=true
    var useLocalModel=true
    var modelManagerPresented=false
    var integrationsPresented=false
    var cloudSettings: CloudSettings = (UserDefaults.standard.data(forKey:"cloudSettings.v1").flatMap{try? JSONDecoder().decode(CloudSettings.self,from:$0)}) ?? CloudSettings() {
        didSet { if let data=try? JSONEncoder().encode(cloudSettings) { UserDefaults.standard.set(data,forKey:"cloudSettings.v1") };cloudConnectionStatus="配置已更改，尚未测试" }
    }
    var cloudConnectionStatus="尚未测试在线服务"
    var cloudTesting=false
    var cloudKeySaved=false
    var cloudSessionKeyAvailable=false
    @ObservationIgnored private var sessionCloudKey: (account:String,value:String)?
    var voiceInbox: [VoiceCommand]=[]
    var automaticVoiceExecution=false
    var allowAppleOnlineSpeech=false
    var localVoicePort: UInt16?
    var localVoiceStarting=false
    var localVoiceStatus="本机语音接口未启动"
    var xiaozhiState: VoiceConnectionState = .disconnected
    var xiaozhiEndpointSaved=false
    private let voiceQueue=VoiceCommandQueue()
    private let localVoiceServer=LocalVoiceServer()
    private let xiaozhiClient=XiaozhiMCPClient()
    @ObservationIgnored private var localVoiceToken=""
    @ObservationIgnored private var voiceConnectionGeneration=UUID()
    var installedModels: [InstalledModel]=[]
    var modelsBusy=false
    var preferenceCount=0
    var canUndo=false
    var canRedo=false
    let deviceManager=DeviceCapabilityManager()
    var preview: CGImage?
    var original: CGImage?
    var showingOriginal=false
    var rendering=false
    var importing=false
    var importProgress=""
    var renderStatus="导入照片，开始本地修图"
    var message: String?
    var exportedURL: URL?
    var batchSnapshot: BatchSnapshot?
    enum BatchMode: String,CaseIterable,Identifiable {
        case uniform="统一当前配方",saved="每张已存设置",ai="逐张 AI 调整"
        var id: Self {self}
    }
    var batchMode: BatchMode = .uniform
    var batchAIEnabled: Bool { get {batchMode == .ai} set {batchMode = newValue ? .ai : .uniform} }
    var batchInstruction="逐张自然校正曝光和白平衡，适度恢复高光和阴影，保持同组色彩协调，保留细节，不要美颜。"
    var batchPreparing=false
    var savedRecipes: [URL]=[]
    var userFilters: [UserFilter]=UserFilterLibrary.all()
    var profile: ColorProfile?
    var useCompanionJPEG=false { didSet { schedulePreview() } }
    var importerPresented=false
    var syncPresented=false
    var pairingInput=""
    var autoBeauty=true
    var autoSend=false
    var root: URL
    var inbox: URL
    let sync: LocalSyncService
    let tether: LumixTetherFolderAdapter
    #if os(macOS)
    let native: NativeCameraAdapter
    #endif
    @ObservationIgnored private var library: PhotoLibrary?
    @ObservationIgnored private var processor: PhotoProcessor?
    @ObservationIgnored private var batch: BatchProcessor
    @ObservationIgnored private var renderTask: Task<Void,Never>?
    @ObservationIgnored private var renderGeneration=UUID()
    @ObservationIgnored private var previewWorkerID=UUID()
    @ObservationIgnored private var importIntent: ImportIntent = .photos
    @ObservationIgnored private var bookmarkURLs=[URL]()
    @ObservationIgnored private var restoring=false
    @ObservationIgnored private var undoRecipes=[Recipe]()
    @ObservationIgnored private var redoRecipes=[Recipe]()

    @ObservationIgnored private var agentTask: Task<Void,Never>?
    @ObservationIgnored private var agentGeneration=UUID()
    @ObservationIgnored private var preferenceMemory: LocalPreferenceMemory?
    @ObservationIgnored private var historyStore: LocalHistoryStore?
    @ObservationIgnored private var modelManager: ModelManager?
    @ObservationIgnored private var activeBeautyModelPath: String?
    var selected: PhotoAsset? { assets.first{$0.id==selectedID} }
    var visibleAssets: [PhotoAsset] { photoFilter.apply(to:assets,reviews:photoReviews) }
    var canSynchronize: Bool { selected != nil && preview != nil && !rendering && !agentBusy && !workflowBusy && !batchPreparing && batchSnapshot?.active != true }
    var importTypes: [UTType] {
        switch importIntent {case .photos,.reference:return [.image,.rawImage];case .recipe,.profile:return [.json];case .lut:return [UTType(filenameExtension:"cube") ?? .plainText];default:return [.folder]}
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
        do { assets=try await library?.list() ?? [];photoReviews=try await library?.reviews() ?? [:];pruneHiddenSelection();savedRecipes=(try? FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("Recipes"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="json"}.sorted{$0.lastPathComponent<$1.lastPathComponent}) ?? [] }
        catch { message=error.localizedDescription }
    }
    func select(_ asset: PhotoAsset,proposal: Recipe?=nil) {
        guard !workflowBusy else {return}
        // A fast switch can cancel a pending preview before its save. Persist
        // the departing photo independently of the preview's cancellation.
        if let previous=selected,let library,!restoring {
            let snapshot=recipe
            Task {do {try await library.saveRecipe(snapshot,for:previous.id)}catch{message="保存上一张照片的设置失败："+error.localizedDescription}}
        }
        agentTask?.cancel();agentGeneration=UUID();agentBusy=false;agentRun=nil;agentStatus="用一句话描述你想要的效果"
        resetAgentProcess()
        undoRecipes=[];redoRecipes=[];canUndo=false;canRedo=false
        restoring=true
        cancelPreviewWorker();selectedID=asset.id;preview=nil;original=nil;useCompanionJPEG=false
        activeMaskID=nil;maskPreview=nil;showMaskOverlay=false;drawingBrush=false;faceCount=0;previewBypassedParameters=[]
        rawCapabilities = .unavailable
        restoring=false
        // Probing a RAW decoder may open a large file or start LibRaw. It must
        // never block photo selection or layout on the main actor.
        Task {
            let capabilities=await Task.detached(priority:.utility){RAWCapabilities.inspect(asset.originalURL)}.value
            guard selectedID==asset.id else {return};rawCapabilities=capabilities
        }
        Task {
            let r=(try? await library?.recipe(for:asset.id)) ?? Recipe()
            guard selectedID==asset.id else { return };restoring=true;recipe=r;restoring=false
            if let proposal {recipe=proposal}
            if let id=recipe.color.referenceProfileID {
                do { profile=try JSONDecoder().decode(ColorProfile.self,from:Data(contentsOf:root.appendingPathComponent("Profiles/\(id).json"))) }
                catch { profile=nil;message="配方引用的色彩档案缺失，请重新导入。" }
            } else { profile=nil }
            schedulePreview()
        }
    }
    func flushRecipeBeforeQuit() async -> Bool {
        cancelPreviewWorker()
        agentTask?.cancel();agentGeneration=UUID()
        if agentBusy {agentBusy=false;agentProcessState = .cancelled}
        guard let asset=selected,let library else {return true}
        do {try await library.saveRecipe(recipe,for:asset.id);return true}
        catch {message="保存当前照片的设置失败，应用暂未退出："+error.localizedDescription;return false}
    }
    private func cancelPreviewWorker() {
        renderTask?.cancel()
        renderTask=nil;previewWorkerID=UUID();renderGeneration=UUID();rendering=false
    }
    func schedulePreview() {
        guard !restoring,!agentBusy,selected != nil,processor != nil else {return}
        renderGeneration=UUID();rendering=true
        // At most one render runs. State changes replace its pending successor;
        // they do not restart a debounce or cancel a useful interactive frame.
        guard renderTask==nil else {return}
        let worker=UUID();previewWorkerID=worker
        renderTask=Task {
            defer {if previewWorkerID==worker {renderTask=nil;rendering=false}}
            while !Task.isCancelled {
                guard previewWorkerID==worker,!agentBusy,let asset=selected,let processor else {return}
                let token=renderGeneration,start=Date()
                var previewRecipe=recipe
                for id in previewBypassedParameters {ParameterCatalog.find(id)?.reset(&previewRecipe.document)}
                if previewBypassedParameters.contains("color.curve") {previewRecipe.document.color.curve=RGBCurve()}
                if previewBypassedParameters.contains("color.lut") {previewRecipe.document.color.lut=nil}
                if previewBypassedParameters.contains("color.referenceProfileID") {previewRecipe.document.color.referenceProfileID=nil}
                if previewBypassedParameters.contains("beauty.enabled") {previewRecipe.document.beauty.enabled=false}
                if previewBypassedParameters.contains("masks") {previewRecipe.document.masks=[]}
                let persistedRecipe=recipe,url=workingURL(asset),reference=profile,maskID=showMaskOverlay ? activeMaskID : nil
                do {
                    let result=try await processor.render(url:url,recipe:previewRecipe,profile:reference,maskPreviewID:maskID)
                    try Task.checkCancellation()
                    guard previewWorkerID==worker,selectedID==asset.id else {return}
                    // During a gesture, completed frames are useful even while a
                    // newer value waits. A stable final value is always rendered.
                    if token==renderGeneration || parameterGestureBase != nil {
                        preview=result.image;original=result.original;faceCount=result.faceCount;maskPreview=result.localMaskPreview
                        renderStatus="\(result.faceCount) 张人脸 · \(result.beautyBackend) · \(Int(result.milliseconds)) ms"
                        if parameterGestureBase != nil {LumaLog.pipeline.debug("Interactive preview frame completed")}
                    }
                    if token==renderGeneration {
                        rendering=false
                        // Save the authoritative document, not a bypassed preview.
                        try await library?.saveRecipe(persistedRecipe,for:asset.id)
                    }
                } catch is CancellationError {return}
                catch {
                    guard previewWorkerID==worker,selectedID==asset.id else {return}
                    if token==renderGeneration {
                        rendering=false;renderStatus=error.localizedDescription
                        message=error.localizedDescription+(asset.isRAW && asset.companionURL != nil && !useCompanionJPEG ? "\n可打开“使用配对 JPEG”继续编辑。" : "")
                    }
                }
                guard previewWorkerID==worker,token != renderGeneration else {return}
                // Cap cheap frames at about 30 Hz without delaying slower work.
                let remaining=0.033-Date().timeIntervalSince(start)
                if remaining>0 {do {try await Task.sleep(nanoseconds:UInt64(remaining*1_000_000_000))}catch{return}}
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
        let folder: Bool
        switch intent {case .photos,.reference,.recipe,.profile,.lut:folder=false;default:folder=true}
        panel.canChooseFiles = !folder;panel.canChooseDirectories=folder
        panel.prompt=folder ? "选择文件夹" : "导入"
        // Some downloaded/created JSON and CUBE files retain a plain-text UTI.
        // Keep them selectable; the bounded importer validates actual contents.
        if !folder {panel.allowedContentTypes=importTypes;panel.allowsOtherFileTypes=true}
        panel.canCreateDirectories=folder
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK { self?.handleImport(.success(panel.urls)) }
        }
        NSApp.activate(ignoringOtherApps:true)
        if let window=NSApp.keyWindow ?? NSApp.mainWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for:window,completionHandler:complete)
        } else { panel.begin(completionHandler:complete) }
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
                    guard batchSnapshot?.active != true,!importing,!workflowBusy,!reviewBusy else { throw LumaError.unsupported("请先结束导入、标记、同步和批处理") }
                    let new=try await Task.detached { try PhotoLibrary(root:first) }.value;try remember(first,key:"libraryBookmark");library=new;root=first
                    batch=BatchProcessor(concurrency:1,journalURL:first.appendingPathComponent("BatchQueue.json"));selectedID=nil;preview=nil;original=nil;selection=[];lastRecipeSync=nil;workflowStatus="";await reload()
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
                case .lut:
                    let filter=try await Task.detached {try UserFilterLibrary.importCube(first)}.value
                    userFilters=UserFilterLibrary.all();applyPreset(filter.id)
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
    func applyBeautyStyle(_ style: BeautyStyle) {
        endParameterGesture()
        recipe.beauty=style.settings
    }
    func reset() { profile=nil;recipe=Recipe() }
    func removeReference() { profile=nil;recipe.color.referenceProfileID=nil }
    func loadRecipe(_ url: URL) throws {
        let r=try Recipe.decodeValidated(Data(contentsOf:url))
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
        let destination=SafeExport.uniqueURL(folder:folder,baseName:selected.name,format:recipe.export.format,settings:recipe.export)
        exportedURL=try await processor.export(url:workingURL(selected),recipe:recipe,destination:destination,libraryRoot:root,profile:profile)
        renderStatus="已完成全分辨率导出 · \(destination.lastPathComponent)"
    }
    func startBatch(to folder: URL) async throws {
        guard !batchPreparing,!workflowBusy,batchSnapshot?.active != true else {throw LumaError.unsupported("批量或同步任务正在准备或运行")}
        batchPreparing=true;defer{batchPreparing=false}
        let picked=visibleAssets.filter{selection.contains($0.id)}.map { a -> PhotoAsset in var item=a;item.originalURL=workingURL(a);return item }
        guard !picked.isEmpty else {throw LumaError.unsupported("请先选择照片")}
        let text=batchAIEnabled ? batchInstruction.trimmingCharacters(in:.whitespacesAndNewlines) : nil
        let planner: BatchProcessor.Planner? = if let text {try await makeBatchPlanner(instruction:text,reference:profile)} else {nil}
        var perPhoto=[UUID:Recipe]()
        if batchMode != .uniform,let library {
            // Include the current document even when its preview has not finished saving.
            for asset in picked {
                if asset.id==selectedID,preview != nil {perPhoto[asset.id]=try recipe.validated()}
                else {perPhoto[asset.id]=try await library.recipe(for:asset.id)}
            }
        }
        try remember(folder,key:"batchExportBookmark")
        try await batch.start(assets:picked,recipe:recipe,profile:profile,exportDirectory:folder,libraryRoot:root,aiInstruction:text,perPhotoRecipes:perPhoto,planner:planner) { [weak self] snapshot in await self?.receiveBatchSnapshot(snapshot) }
    }
    private func makeBatchPlanner(instruction: String,reference: ColorProfile?) async throws -> BatchProcessor.Planner {
        guard !instruction.isEmpty,instruction.count<=1000,let historyStore else {throw LumaError.unsupported("请输入 1–1000 字的批量修图要求")}
        let settings=cloudSettings,prefs=await preferenceMemory?.preferences() ?? EditingPreferences()
        var installed: InstalledModel?
        if useLocalModel,(settings.mode == .local || settings.fallbackToLocal) {installed=try await modelManager?.activeAgent(device:deviceManager.snapshot())}
        // Reuse one local planner actor: native inference stays serialized even with two exports.
        let local=NativeAgentPlanner(model:installed)
        let key: String?
        if settings.mode == .online {
            _=try settings.validate();key=try await cloudKey(for:settings)
            guard key != nil else {throw LumaError.unsupported("请在接入设置中保存在线服务密钥")}
        } else {key=nil}
        return { asset,base in
            let planner: any AgentPlanner
            if let key {
                let preview=settings.attachPreview ? try CloudPreview.jpeg(asset.thumbnailURL) : nil
                let online=OnlineAgentPlanner(settings:settings,key:key,previewJPEG:preview)
                planner=settings.fallbackToLocal ? OnlineWithLocalFallback(online:online,local:local) : online
            } else {planner=local}
            let worker=try PhotoProcessor()
            let session=AgentSession(engine:NativeImageEngine(processor:worker,profile:reference,raw:base.raw),planner:planner,history:historyStore)
            let result=try await session.run(asset:asset,instruction:instruction,preferences:prefs,currentRecipe:base.document,referenceProfileID:reference?.id,automaticCorrection:base.document.evaluation.automaticCorrection)
            return BatchPlan(recipe:try result.run.selectedRecipe.legacyRecipe(),source:result.run.source,fallbackReason:result.run.fallbackReason,historyDirectory:result.directory)
        }
    }
    private func receiveBatchSnapshot(_ s: BatchSnapshot) { batchSnapshot=s }
    func loadBatchPlan(_ item: BatchItem) {
        guard !agentBusy,let plan=item.plan,let asset=assets.first(where:{$0.id==item.id}) else {return}
        page = .edit;select(asset,proposal:plan.recipe)
    }
    func pauseBatch() { Task { await batch.pause() } }
    func resumeBatch() { Task { do {
        if let snapshot=batchSnapshot,let instruction=snapshot.aiInstruction {await batch.configurePlanner(try await makeBatchPlanner(instruction:instruction,reference:snapshot.profile))}
        await batch.resume()
    } catch {message=error.localizedDescription} } }
    func cancelBatch() { Task { await batch.cancel() } }
    func retryBatch() { Task { do {
        if let snapshot=batchSnapshot,let instruction=snapshot.aiInstruction {await batch.configurePlanner(try await makeBatchPlanner(instruction:instruction,reference:snapshot.profile))}
        try await batch.retryFailures { [weak self] s in await self?.receiveBatchSnapshot(s) }
    } catch { message=error.localizedDescription } } }
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
        cancelPreviewWorker();rendering=false
        let generation=UUID();agentGeneration=generation
        let snapshot=recipe,reference=profile,correction=automaticCorrection,preferModel=useLocalModel,cloud=cloudSettings
        let past=agentRun.map{[$0.instruction]} ?? []
        agentStartingRecipe=snapshot.document;agentParameterChanges=[]
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
                    guard let key=try await cloudKey(for:cloud),!key.isEmpty else { throw LumaError.unsupported("请在“模型与语音接入”中填写在线服务 API 密钥") }
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
                recipe=try result.run.selectedRecipe.legacyRecipe()
                agentParameterChanges=ParameterCatalog.changed(from:snapshot.document,to:recipe.document)
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
        case .plan(let plan):agentPlan=plan;agentParameterChanges=ParameterCatalog.changed(from:agentStartingRecipe ?? EditRecipe(),to:plan.recipe)
        case .round(let round,let directory):agentDirectory=directory;agentRounds.append(round)
        }
    }
    private func updateAgentStatus(_ status: String,assetID: UUID,generation: UUID) { if selectedID==assetID,agentGeneration==generation { agentStatus=status } }
    func cancelAgent() { agentStatus="正在停止，等待当前操作结束…";agentTask?.cancel() }
    func refreshIntegrationCredentials() {
        cloudSessionKeyAvailable=sessionCloudKey?.account==cloudSettings.credentialAccount
        do {cloudKeySaved=try IntegrationCredentials.read(cloudSettings.credentialAccount) != nil}
        catch {cloudKeySaved=false;cloudConnectionStatus=error.localizedDescription}
        xiaozhiEndpointSaved=((try? IntegrationCredentials.read("xiaozhi.mcp.endpoint")) ?? nil) != nil
    }
    private func cloudKey(for settings: CloudSettings) async throws -> String? {
        if let session=sessionCloudKey,session.account==settings.credentialAccount {return session.value}
        let account=settings.credentialAccount
        return try await Task.detached {try IntegrationCredentials.read(account)}.value
    }
    func useCloudKeyForSession(_ value: String) {
        do {
            _=try cloudSettings.validate();let key=value.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !key.isEmpty,key.count<=8192,!key.contains("\n"),!key.contains("\r") else {throw LumaError.unsupported("密钥格式无效")}
            sessionCloudKey=(cloudSettings.credentialAccount,key);cloudSessionKeyAvailable=true
            cloudConnectionStatus="本次会话密钥已就绪；退出应用后清除，尚未测试"
        } catch {cloudConnectionStatus=error.localizedDescription}
    }
    func saveCloudKey(_ value: String) {
        useCloudKeyForSession(value)
        guard cloudSessionKeyAvailable,let session=sessionCloudKey else {return}
        do {try IntegrationCredentials.save(session.value,account:session.account);cloudKeySaved=true;cloudConnectionStatus="密钥已保存在系统钥匙串，尚未测试" }
        catch {cloudConnectionStatus="本次会话可用；持久保存未完成："+error.localizedDescription}
    }
    func removeCloudKey() {
        sessionCloudKey=nil;cloudSessionKeyAvailable=false
        do { try IntegrationCredentials.remove(cloudSettings.credentialAccount);cloudKeySaved=false;cloudConnectionStatus="已移除保存的密钥" } catch { message=error.localizedDescription }
    }
    func testCloudConnection() {
        guard !cloudTesting else { return };cloudTesting=true;cloudConnectionStatus="正在测试…"
        let settings=cloudSettings
        Task {
            defer { cloudTesting=false }
            do {
                guard let key=try await cloudKey(for:settings) else { throw LumaError.unsupported("请先填写 API 密钥") }
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
        do { recipe=try ParameterLockPolicy.applying(round.recipe,preserving:recipe.document).legacyRecipe();agentRun?.selectedRound=round.index }
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

extension AppModel {
    private func pushUndo(_ previous: Recipe) {
        undoRecipes.append(previous);if undoRecipes.count>64 {undoRecipes.removeFirst()}
        redoRecipes=[];canUndo=true;canRedo=false
    }
    func beginParameterGesture() {if parameterGestureBase==nil {parameterGestureBase=recipe}}
    func endParameterGesture() {
        guard let previous=parameterGestureBase else {return};parameterGestureBase=nil
        if previous != recipe {pushUndo(previous)}
    }
    func editDocument(_ change: (inout EditRecipe)->Void) {
        guard !agentBusy else {return};var d=recipe.document;change(&d);d.operations=[]
        do {try d.validateParameters();recipe=Recipe(document:d)}catch {message=error.localizedDescription}
    }
    func parameterValue(_ p: ParameterDescriptor)->Float {p.isAutomatic(recipe.document) ? (rawCapabilities.defaults[p.id] ?? p.defaultValue) : p.read(recipe.document)}
    func setParameter(_ p: ParameterDescriptor,_ value: Float) {editDocument{p.write(&$0,p.bounded(value))}}
    func resetParameter(_ p: ParameterDescriptor) {editDocument{p.reset(&$0)}}
    func resetParameterSection(_ section: ParameterSection) {editDocument{ParameterCatalog.reset(section,in:&$0)}}
    func toggleParameterLock(_ id: String) {
        editDocument {d in
            if ParameterLockPolicy.isLocked(id,in:d) {
                let targets=ParameterCatalog.lockTargets(in:d)
                var expanded=[String]()
                for lock in d.lockedParameters {
                    if lock==id {continue}
                    if id.hasPrefix(lock+".") {expanded += targets.filter{$0 != id && ($0==lock || $0.hasPrefix(lock+"."))}}
                    else {expanded.append(lock)}
                }
                d.lockedParameters=Array(Set(expanded)).sorted()
            } else {d.lockedParameters.append(id)}
        }
    }
    func toggleParameterLocks(_ ids: [String]) {
        editDocument {d in
            if ids.allSatisfy({ParameterLockPolicy.isLocked($0,in:d)}) {
                let targets=ParameterCatalog.lockTargets(in:d)
                for id in ids {
                    var remaining=[String]()
                    for lock in d.lockedParameters {
                        if lock==id || lock.hasPrefix(id+".") {continue}
                        if id.hasPrefix(lock+".") {remaining += targets.filter{$0 != id && !$0.hasPrefix(id+".") && ($0==lock || $0.hasPrefix(lock+"."))}}
                        else {remaining.append(lock)}
                    }
                    d.lockedParameters=Array(Set(remaining)).sorted()
                }
            } else {d.lockedParameters=Array(Set(d.lockedParameters+ids)).sorted()}
        }
    }
    func lockParameterSection(_ section: ParameterSection) {
        editDocument {d in
            let prefix: String
            switch section {case .raw:prefix="raw";case .tone:prefix="global";case .hsl:prefix="color.hsl";case .curves:prefix="color.curve";case .portrait:prefix="beauty";case .masks:prefix="masks";case .detail:prefix="detail";case .style:prefix="effects";case .geometry:prefix="geometry";case .output:prefix="export"
            case .levels:prefix="color.levels";case .range:prefix="color.range";case .grading:prefix="color.grading";case .selective:prefix="color.selective";case .calibration:prefix="color.calibration"}
            var ids=ParameterCatalog.section(section).map(\.id)
            if section == .curves {ids += ["color.curve.master","color.curve.red","color.curve.green","color.curve.blue"]}
            if section == .portrait {ids.append("beauty.enabled")}
            if section == .selective {ids.append("color.selective.absolute")}
            if section == .style {ids += ["color.lut","color.referenceProfileID"]}
            if section == .masks {ids=["masks"]}
            if section == .raw || section == .geometry || section == .output {ids=[prefix]}
            if ids.allSatisfy({ParameterLockPolicy.isLocked($0,in:d)}) {d.lockedParameters.removeAll{lock in ids.contains(lock) || lock==prefix || ((section == .raw || section == .geometry || section == .output) && lock.hasPrefix(prefix+"."))}}
            else {d.lockedParameters=Array(Set(d.lockedParameters+ids)).sorted()}
        }
    }
    func setCurve(_ points: [CurvePoint],channel: String) {editDocument{$0.color.curve.setPoints(points,channel:channel)}}
    func setColorWheel(_ zone: String,hue: Float,saturation: Float) {
        editDocument {d in
            switch zone {case "shadow":d.color.grading.shadowHue=hue;d.color.grading.shadowSaturation=saturation
            case "midtone":d.color.grading.midtoneHue=hue;d.color.grading.midtoneSaturation=saturation
            default:d.color.grading.highlightHue=hue;d.color.grading.highlightSaturation=saturation}
        }
    }
    func applyPreset(_ id: String?) {editDocument{$0.color.enabled=true;$0.color.lut=id}}
    var activeMask: LocalMask? {recipe.document.masks.first{$0.id==activeMaskID}}
    var canDrawBrush: Bool {
        guard activeMask?.kind == .brush,!agentBusy else {return false}
        var g=recipe.document.geometry;g.chromaticAberration=0;g.lensVignette=0
        return g==GeometrySettings()
    }
    func addMask(_ kind: MaskKind) {
        guard recipe.document.masks.count<16 else {message="最多使用 16 个局部蒙版";return}
        let id="mask_"+UUID().uuidString.prefix(12).replacingOccurrences(of:"-",with:"")
        editDocument{$0.masks.append(LocalMask(id:id,kind:kind))}
        activeMaskID=id;showMaskOverlay=true;drawingBrush=kind == .brush
    }
    func removeActiveMask() {
        guard let id=activeMaskID else {return};editDocument{$0.masks.removeAll{$0.id==id};$0.lockedParameters.removeAll{$0.hasPrefix("masks."+id+".") || $0=="masks."+id}}
        activeMaskID=recipe.document.masks.last?.id;drawingBrush=false
    }
    func updateActiveMask(_ update: (inout LocalMask)->Void) {
        guard let id=activeMaskID else {return}
        editDocument {d in if let i=d.masks.firstIndex(where:{$0.id==id}) {update(&d.masks[i])}}
    }
    func localValue(_ p: ParameterDescriptor)->Float {
        guard let m=activeMask else {return p.defaultValue};var d=EditRecipe();d.global=m.adjustments;d.detail=m.detail;return p.read(d)
    }
    func setLocalParameter(_ p: ParameterDescriptor,_ value: Float) {
        updateActiveMask {m in var d=EditRecipe();d.global=m.adjustments;d.detail=m.detail;p.write(&d,p.bounded(value));m.adjustments=d.global;m.detail=d.detail}
    }
    func resetLocalParameter(_ p: ParameterDescriptor) {setLocalParameter(p,p.defaultValue)}
    func localLockID(_ p: ParameterDescriptor)->String {
        "masks.\(activeMaskID ?? "none")."+(p.section == .tone ? "adjustments."+p.id.dropFirst("global.".count) : p.id)
    }
    func addBrushStroke(_ points: [BrushPoint]) {
        guard canDrawBrush,!points.isEmpty else {return}
        updateActiveMask {m in guard m.strokes.count<128 else {return};m.strokes.append(BrushStroke(points:Array(points.prefix(2048)),size:m.brushSize,flow:m.flow))}
    }
    func pruneHiddenSelection() { selection.formIntersection(Set(visibleAssets.map(\.id))) }
    func review(for id: UUID)->PhotoReview {photoReviews[id] ?? PhotoReview()}
    func updateReview(for ids: Set<UUID>,rating: Int?=nil,flag: PhotoFlag?=nil) {
        guard !reviewBusy,!workflowBusy,let library,!ids.isEmpty else {return}
        reviewBusy=true
        Task {defer{reviewBusy=false};do {
            try await library.updateReviews(for:ids,rating:rating,flag:flag)
            photoReviews=try await library.reviews();pruneHiddenSelection()
        } catch {message=error.localizedDescription}}
    }
    func synchronizeRecipe(_ source: Recipe,from sourceID: UUID,to ids: Set<UUID>,groups: Set<RecipeSyncGroup>) async throws {
        guard canSynchronize,selectedID==sourceID,let library else {throw LumaError.unsupported("请等待当前照片处理完成，并结束批量任务后再同步")}
        workflowBusy=true;defer{workflowBusy=false}
        let transaction=try await library.synchronizeRecipe(source,from:sourceID,to:ids,groups:groups)
        if !transaction.changes.isEmpty {lastRecipeSync=transaction}
        workflowStatus="已同步 \(transaction.changes.count) 张照片"
        if transaction.skippedRAWCount>0 {workflowStatus += " · \(transaction.skippedRAWCount) 张非 RAW 跳过解码设置"}
        selection=ids.intersection(Set(visibleAssets.map(\.id)));batchMode = .saved
    }
    func undoRecipeSynchronization() {
        guard !workflowBusy,!agentBusy,!batchPreparing,batchSnapshot?.active != true,let transaction=lastRecipeSync,let library else {return}
        if let change=transaction.changes.first(where:{$0.id==selectedID}),recipe != change.after {
            message="当前照片在同步后有新的修改，请先保留这些修改，无法整组撤回。";return
        }
        workflowBusy=true
        // Stop an older preview save from racing with the atomic restore.
        let refreshSelected=transaction.changes.contains(where:{$0.id==selectedID})
        let pendingRender=refreshSelected ? renderTask : nil
        if refreshSelected {cancelPreviewWorker();rendering=false}
        Task {do {
            await pendingRender?.value
            try await library.undoSynchronization(transaction)
            lastRecipeSync=nil;workflowStatus="已撤回 \(transaction.changes.count) 张照片的同步"
            workflowBusy=false
            if refreshSelected,let asset=selected {select(asset)}
        } catch {workflowBusy=false;message=error.localizedDescription;if refreshSelected{schedulePreview()}}}
    }
    func copyRecipe() {
        #if os(macOS)
        do {let data=try recipe.json();NSPasteboard.general.clearContents();NSPasteboard.general.setString(String(decoding:data,as:UTF8.self),forType:.string);renderStatus="已复制 v2 配方"}catch {message=error.localizedDescription}
        #endif
    }
    func pasteRecipe() {
        #if os(macOS)
        do {
            guard let text=NSPasteboard.general.string(forType:.string) else {throw LumaError.corruptData("剪贴板中没有配方 JSON")}
            let parsed=try Recipe.decodeValidated(Data(text.utf8))
            if let id=parsed.document.color.referenceProfileID {profile=try JSONDecoder().decode(ColorProfile.self,from:Data(contentsOf:root.appendingPathComponent("Profiles/\(id).json")))}else{profile=nil}
            recipe=parsed;renderStatus="已载入并迁移为 v2 配方"
        }catch{message=error.localizedDescription}
        #endif
    }
}
