import Foundation
import PhotoCore

/// Developer/Agent tool entry point. Compiles the same package as the native editor.
enum PluginCommands {
    static func execute(_ args: [String]) async throws -> Bool {
        guard args.first=="plugin" else {return false}
        guard args.count>=3 else {throw LumaError.unsupported("plugin validate PACKAGE | plugin run PACKAGE IMAGE CURRENT_RECIPE OUTPUT RECEIPTS editor|batch|agent [REQUEST]")}
        let package=try PluginPackage.decode(Data(contentsOf:URL(fileURLWithPath:args[2])))
        if args[1]=="validate" {try LumaAgentCLI.output(package.manifest);return true}
        guard args[1]=="run",args.count>=8,let context=PluginContext(rawValue:args[7]) else {throw LumaError.unsupported("plugin run PACKAGE IMAGE CURRENT_RECIPE OUTPUT RECEIPTS editor|batch|agent [REQUEST]")}
        let input=URL(fileURLWithPath:args[3]),base=try Recipe.decodeValidated(Data(contentsOf:URL(fileURLWithPath:args[4]))),output=URL(fileURLWithPath:args[5])
        // args[6] is an explicit working directory for receipts, separate from outputs.
        let receipt=URL(fileURLWithPath:args[6]);try FileManager.default.createDirectory(at:receipt,withIntermediateDirectories:true)
        let processor=try PhotoProcessor(),neutral=try await processor.render(url:input,recipe:base)
        let analysis=try VisionAnalyzer.analyze(neutral.original)
        let planner=NativeAgentPlanner(model:nil)
        let execution=try await PluginRuntime.execute(package,on:base.document,context:context,request:args.count>8 ? args[8] : "",planner:{ instruction,current in
            let context=PlanningContext(instruction:instruction,analysis:analysis,preferences:EditingPreferences(),currentRecipe:current)
            return try IntentSafetyGate.enforce(await planner.plan(context).recipe,context:context)
        })
        let hash=try ModelManager.sha256(input)
        _=try await processor.export(url:input,recipe:Recipe(document:execution.recipe),destination:output)
        guard try ModelManager.sha256(input)==hash else {throw LumaError.corruptData("原图发生变化")}
        try execution.recipe.json().write(to:receipt.appendingPathComponent("recipe.json"),options:.atomic)
        try JSONEncoder().encode(execution).write(to:receipt.appendingPathComponent("execution.json"),options:.atomic)
        try LumaAgentCLI.output(execution);return true
    }
}
