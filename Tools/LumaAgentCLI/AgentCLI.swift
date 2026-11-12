import Foundation
import PhotoCore
import ImageIO
import Darwin

@main struct LumaAgentCLI {
    static func output<T: Encodable>(_ value: T) throws {
        let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];e.dateEncodingStrategy = .iso8601
        print(String(decoding:try e.encode(value),as:UTF8.self))
    }
    static func asset(_ path: String)->PhotoAsset {
        let url=URL(fileURLWithPath:path);return PhotoAsset(name:url.lastPathComponent,originalURL:url,thumbnailURL:url)
    }
    static func packageModel(_ path: String?) throws -> InstalledModel? {
        guard let path,path != "--rules" else { return nil }
        let root=URL(fileURLWithPath:path),m=try JSONDecoder().decode(ModelManifest.self,from:Data(contentsOf:root.appendingPathComponent("manifest.json")))
        try m.validate();let u=root.appendingPathComponent(m.filename)
        guard try ModelManager.sha256(u)==m.sha256 else { throw LumaError.corruptData("模型校验失败") }
        return InstalledModel(manifest:m,url:u,active:true)
    }
    static func main() async {
        do { try await execute(Array(CommandLine.arguments.dropFirst())) }
        catch { FileHandle.standardError.write(Data(("LumaAgentCLI: "+error.localizedDescription+"\n").utf8));exit(1) }
    }
    static func execute(_ args: [String]) async throws {
        guard let command=args.first else { throw LumaError.unsupported("device | analyze IMAGE | plan IMAGE INSTRUCTION [MODEL_PACKAGE] | run IMAGE INSTRUCTION OUTPUT [MODEL_PACKAGE] | render IMAGE RECIPE OUTPUT INSTRUCTION | install-model PACKAGE [ROOT]") }
        if command=="device" { try output(DeviceCapabilityManager().snapshot());return }
        if command=="install-model",args.count>=2 {
            let manager=try ModelManager(root:args.count>2 ? URL(fileURLWithPath:args[2]) : ModelManager.defaultRoot)
            let installed=try await manager.install(package:URL(fileURLWithPath:args[1]),device:DeviceCapabilityManager().snapshot());try output(installed.manifest);return
        }
        guard args.count>=2 else { throw LumaError.unsupported("缺少照片路径") }
        let input=asset(args[1]),processor=try PhotoProcessor(),engine=NativeImageEngine(processor:processor)
        if command=="preprocess",args.count>=3 {
            let destination=URL(fileURLWithPath:args[2]);try SafeExport.validate(destination:destination,originals:[input.originalURL],libraryRoot:nil)
            guard !FileManager.default.fileExists(atPath:destination.path) else { throw LumaError.unsafeDestination }
            var r=Recipe();r.color.enabled=false
            let result=try await processor.render(url:input.originalURL,recipe:r)
            guard let target=CGImageDestinationCreateWithURL(destination as CFURL,"public.jpeg" as CFString,1,nil) else { throw LumaError.invalidImage("预处理输出") }
            CGImageDestinationAddImage(target,result.original,[kCGImageDestinationLossyCompressionQuality:0.95] as CFDictionary)
            guard CGImageDestinationFinalize(target) else { throw LumaError.invalidImage("预处理保存") }
            struct Preprocessed: Encodable { let width: Int;let height: Int;let output: String }
            try output(Preprocessed(width:result.original.width,height:result.original.height,output:destination.path));return
        }
        if command=="analyze" { try output(try await engine.analyze(input));return }
        if command=="prompt",args.count>=3 {
            let context=PlanningContext(instruction:args[2],analysis:try await engine.analyze(input),preferences:EditingPreferences())
            struct Prompt: Encodable { let prompt: String }
            try output(Prompt(prompt:NativeAgentPlanner.prompt(context)));return
        }
        if command=="plan",args.count>=3 {
            let analysis=try await engine.analyze(input)
            let planner=NativeAgentPlanner(model:try packageModel(args.count>3 ? args[3] : nil))
            let planned=try await planner.plan(PlanningContext(instruction:args[2],analysis:analysis,preferences:EditingPreferences()))
            struct Planned: Encodable { let analysis: ImageAnalysis;let recipe: EditRecipe;let source: String;let fallbackReason: String?;let planningMilliseconds: Double }
            try output(Planned(analysis:analysis,recipe:planned.recipe,source:planned.source,fallbackReason:planned.fallbackReason,planningMilliseconds:planned.planningMilliseconds));return
        }
        if command=="run",args.count>=4 {
            let directory=URL(fileURLWithPath:args[3]);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let originalHash=try ModelManager.sha256(input.originalURL)
            let session=AgentSession(engine:engine,planner:NativeAgentPlanner(model:try packageModel(args.count>4 ? args[4] : nil)),history:try LocalHistoryStore(root:directory.appendingPathComponent("history")))
            let result=try await session.run(asset:input,instruction:args[2])
            let recipe=result.run.selectedRecipe
            try recipe.json().write(to:directory.appendingPathComponent("recipe.json"),options:.atomic)
            let exported=try await processor.export(url:input.originalURL,recipe:recipe.legacyRecipe(),destination:directory.appendingPathComponent("result.jpg"))
            guard try ModelManager.sha256(input.originalURL)==originalHash else { throw LumaError.corruptData("原图哈希发生变化") }
            struct Completed: Encodable { let run: AgentRun;let renderedResult: String;let originalSHA256: String;let originalPreserved: Bool }
            try output(Completed(run:result.run,renderedResult:exported.path,originalSHA256:originalHash,originalPreserved:true));return
        }
        if command=="render",args.count>=5 {
            let recipe=try ToolRegistry().decode(Data(contentsOf:URL(fileURLWithPath:args[2])))
            let directory=URL(fileURLWithPath:args[3]);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let originalHash=try ModelManager.sha256(input.originalURL),rendered=try await engine.preview(input,recipe:recipe)
            let intent=InstructionParser.parse(args[4]),evaluator=QualityEvaluator()
            let report=try evaluator.evaluate(original:rendered.original,result:rendered.image,recipe:recipe,intent:intent,skinMask:rendered.skinMask)
            let exported=try await processor.export(url:input.originalURL,recipe:recipe.legacyRecipe(),destination:directory.appendingPathComponent("result.jpg"))
            guard try ModelManager.sha256(input.originalURL)==originalHash else { throw LumaError.corruptData("原图哈希发生变化") }
            struct Evaluated: Encodable { let analysis: ImageAnalysis;let evaluation: QualityReport;let correctedRecipe: EditRecipe;let renderedResult: String;let originalSHA256: String;let originalPreserved: Bool }
            try output(Evaluated(analysis:try await engine.analyze(input),evaluation:report,correctedRecipe:try evaluator.corrected(recipe,report:report,intent:intent),renderedResult:exported.path,originalSHA256:originalHash,originalPreserved:true));return
        }
        throw LumaError.unsupported("未知命令或缺少参数")
    }
}
