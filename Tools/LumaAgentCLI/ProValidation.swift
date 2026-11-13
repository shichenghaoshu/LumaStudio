import Foundation
import PhotoCore
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Reproducible diagnostics. Credentials are read from the same Keychain account as the app.
enum ProValidation {
    static func execute(_ args: [String]) async throws -> Bool {
        guard let command=args.first else {return false}
        if command=="credential-status" {
            do {
                let key=try IntegrationCredentials.read("cloud."+CloudProvider.deepseek.baseURL,allowAuthenticationUI:false)
                try LumaAgentCLI.output(["provider":"DeepSeek","readable":key==nil ? "false" : "true"])
            } catch {try LumaAgentCLI.output(["provider":"DeepSeek","readable":"false","message":error.localizedDescription])}
            return true
        }
        if command=="formats" {
            try LumaAgentCLI.output(["imageIOReadTypes":PhotoFileType.imageTypeIdentifiers,"importExtensions":PhotoFileType.imageExtensions.sorted(),"rawCandidates":PhotoFileType.rawExtensions.sorted(),"supportedCameraModels":CIRAWFilter.supportedCameraModels]);return true
        }
        if command=="validate-formats",args.count>=3 {
            try await validate(folder:URL(fileURLWithPath:args[1]),output:URL(fileURLWithPath:args[2]));return true
        }
        if command=="batch",args.count>=4 {
            try await batch(folder:URL(fileURLWithPath:args[1]),output:URL(fileURLWithPath:args[2]),instruction:args[3],online:args.contains("--deepseek"));return true
        }
        return false
    }
    static func photos(_ folder: URL)throws->[URL] {
        try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isRegularFileKey]).filter{PhotoFileType.accepts($0) && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}.sorted{$0.lastPathComponent<$1.lastPathComponent}
    }
    static func write(_ object: Any,to url: URL)throws {try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)}
    static func save(_ image: CGImage,to url: URL,type: String="public.jpeg")throws {
        guard !FileManager.default.fileExists(atPath:url.path),let dest=CGImageDestinationCreateWithURL(url as CFURL,type as CFString,1,nil) else {throw LumaError.unsafeDestination}
        CGImageDestinationAddImage(dest,image,[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {throw LumaError.invalidImage(url.lastPathComponent)}
    }
    static func validate(folder: URL,output: URL) async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let worker=try PhotoProcessor(),decoder=ImageDecoder()
        var reports=[[String:Any]]()
        for (index,url) in try photos(folder).enumerated() {
            let before=try ContentDigest.sha256(url)
            do {
                var recipe=Recipe();recipe.color.enabled=false;recipe.color.exposure=0.25;recipe.export.longEdge=1600
                let preview=try await worker.render(url:url,recipe:recipe)
                let native=try decoder.decode(url,tier:.fullResolution).extent
                let name=String(format:"%02d",index+1)
                try save(preview.original,to:output.appendingPathComponent(name+"-before.jpg"))
                let export=try await worker.export(url:url,recipe:recipe,destination:output.appendingPathComponent(name+"-after.jpg"))
                let out=try decoder.decode(export,tier:.fullResolution)
                let caps=RAWCapabilities.inspect(url)
                reports.append(["input":url.lastPathComponent,"format":url.pathExtension.lowercased(),"raw":PhotoFileType.isRAW(url),"decoded":true,"nativeWidth":Int(native.width),"nativeHeight":Int(native.height),"exportWidth":Int(out.extent.width),"exportHeight":Int(out.extent.height),"rawParameters":caps.supported.sorted(),"sha256":before,"originalPreserved":try ContentDigest.sha256(url)==before,"previewMilliseconds":preview.milliseconds])
            } catch {reports.append(["input":url.lastPathComponent,"format":url.pathExtension.lowercased(),"decoded":false,"error":error.localizedDescription,"sha256":before,"originalPreserved":try ContentDigest.sha256(url)==before])}
        }
        try write(["scope":"Real independently sourced scenes. Exports use the full-resolution decode path with a 1600px output limit.","files":reports],to:output.appendingPathComponent("format-report.json"))
        try LumaAgentCLI.output(reports.map{["input":$0["input"] as? String ?? "","decoded":String(describing:$0["decoded"] ?? false)]})
    }
    static func batch(folder: URL,output: URL,instruction: String,online: Bool) async throws {
        let inputs=try photos(folder)
        guard !inputs.isEmpty,inputs.count<=64 else {throw LumaError.unsupported("诊断批次需要 1–64 张照片")}
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let before=try inputs.map{try ContentDigest.sha256($0)}
        let history=try LocalHistoryStore(root:output.appendingPathComponent("history"))
        var settings=CloudSettings();settings.mode = .online;settings.provider = .deepseek;settings.baseURL=CloudProvider.deepseek.baseURL;settings.model=CloudProvider.deepseek.model;settings.fallbackToLocal=false
        let key=online ? try IntegrationCredentials.read(settings.credentialAccount,allowAuthenticationUI:false) : nil
        if online,key==nil {throw LumaError.unsupported("请先在 Mac 接入设置中保存 DeepSeek 密钥；诊断不接受命令行密钥")}
        let planner: any AgentPlanner = if let key {OnlineAgentPlanner(settings:settings,key:key)} else {RulesAgentPlanner()}
        let queue=BatchProcessor(concurrency:2,journalURL:output.appendingPathComponent("queue.json"))
        var base=Recipe();base.color.enabled=false;base.export.longEdge=1600;base.export.nameTemplate="{index}_{name}"
        base.document.lockedParameters=["export","geometry","color.enabled"]
        let started=Date()
        try await queue.start(assets:inputs.map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)},recipe:base,profile:nil,exportDirectory:output.appendingPathComponent("exports"),libraryRoot:nil,aiInstruction:instruction,planner:{asset,recipe in
            let session=AgentSession(engine:NativeImageEngine(processor:try PhotoProcessor(),raw:recipe.raw),planner:planner,history:history)
            let result=try await session.run(asset:asset,instruction:instruction,currentRecipe:recipe.document)
            return BatchPlan(recipe:try result.run.selectedRecipe.legacyRecipe(),source:result.run.source,fallbackReason:result.run.fallbackReason,historyDirectory:result.directory)
        }){snapshot in
            if !snapshot.active {print("Batch finished: completed=\(snapshot.completed), failed=\(snapshot.failures)")}
        }
        await queue.waitUntilFinished()
        guard let snapshot=await queue.current() else {throw LumaError.corruptData("批量队列缺失")}
        var reports=[[String:Any]]()
        let worker=try PhotoProcessor()
        for (index,url) in inputs.enumerated() {
            let item=snapshot.items.first{$0.source==url}!
            var report:[String:Any]=["input":url.lastPathComponent,"state":item.state.rawValue,"source":item.plan?.source ?? "none","fallbackReason":item.plan?.fallbackReason ?? "none","originalPreserved":try ContentDigest.sha256(url)==before[index],"sha256":before[index],"output":item.output?.path ?? "none"]
            if let plan=item.plan,let exported=item.output {
                let rendered=try await worker.render(url:url,recipe:plan.recipe)
                try save(rendered.original,to:output.appendingPathComponent(String(format:"%02d-before.jpg",index+1)))
                try save(rendered.image,to:output.appendingPathComponent(String(format:"%02d-after.jpg",index+1)))
                report["beforeMetrics"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(PixelMetrics.measure(rendered.original)))
                report["afterMetrics"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(PixelMetrics.measure(rendered.image)))
                report["recipeFile"]=String(format:"%02d-recipe.json",index+1)
                try plan.recipe.json().write(to:output.appendingPathComponent(String(format:"%02d-recipe.json",index+1)))
                report["outputSHA256"]=try ContentDigest.sha256(exported)
            }
            if let error=item.error {report["error"]=error}
            reports.append(report)
        }
        try write(["provider":online ? "DeepSeek real API, no fallback" : "Offline rules + Vision","instruction":instruction,"count":inputs.count,"completed":snapshot.completed,"failed":snapshot.failures,"elapsedSeconds":Date().timeIntervalSince(started),"files":reports,"scope":"One independent analysis/plan/evaluation per real photograph; deterministic metrics do not measure aesthetic quality."],to:output.appendingPathComponent("batch-report.json"))
        guard snapshot.completed==inputs.count,snapshot.failures==0 else {throw LumaError.unsupported("批量未全部完成，详细原因已写入 batch-report.json")}
    }
}
