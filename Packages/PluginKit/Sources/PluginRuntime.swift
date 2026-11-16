import Foundation
import PhotoDomain
import ColorEngine
import ToolRegistry

public struct PluginExecution: Codable, Sendable {
    public let pluginID: String, version: String, context: PluginContext
    public let recipe: EditRecipe
    public let changedParameters: [String]
}
public enum PluginRuntime {
    public typealias Planner = @Sendable (_ instruction: String,_ current: EditRecipe) async throws -> EditRecipe
    /// One operation compiler is shared by the editor, per-photo batch planning and Agent tools.
    public static func execute(_ package: PluginPackage, on current: EditRecipe, context: PluginContext, request: String="", lutDirectory: URL=UserFilterLibrary.root, planner: Planner?=nil) async throws -> PluginExecution {
        try package.validate();try ToolRegistry().validate(current)
        guard package.manifest.supports.contains(context) else {throw LumaError.unsupported("此插件未声明支持当前调用场景")}
        guard request.count<=1000 else {throw LumaError.corruptData("修图要求超过 1000 字")}
        var result=current
        switch package.manifest.kind {
        case .lut:
            let asset=package.assets[0], bytes=Data(base64Encoded:asset.data)!
            let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".cube")
            try bytes.write(to:temporary,options:.atomic);defer{try? FileManager.default.removeItem(at:temporary)}
            let filter=try UserFilterLibrary.importCube(temporary,at:lutDirectory)
            result.color.enabled=true;result.color.lut=filter.id;result.color.intensity=package.payload.intensity!
        case .recipe:
            result=try RecipeSynchronization.applying(Recipe(document:package.payload.recipe!),to:Recipe(document:current),groups:Set(package.payload.groups!),targetIsRAW:false).document
        case .localAdjustment:
            var mask=package.payload.mask!
            mask.id="plugin_"+PluginPackage.digest(Data(package.manifest.id.utf8)).prefix(16)
            if let i=result.masks.firstIndex(where:{$0.id==mask.id}) {result.masks[i]=mask}
            else {result.masks.append(mask)}
        case .aiTool:
            guard let planner else {throw LumaError.unsupported("当前宿主未提供 AI 规划器")}
            let instruction=package.payload.instruction!.replacingOccurrences(of:"${request}",with:request)
            guard instruction.count<=3000 else {throw LumaError.corruptData("展开后的 AI 指令超过 3000 字，请减少模板占位符")}
            let proposal=try await planner(instruction,current)
            try ToolRegistry().validate(proposal)
            // Instruction tools may alter editing controls, never the target's crop,
            // masks, RAW decoding, output destination or lock/evaluation policy.
            result=try RecipeSynchronization.applying(Recipe(document:proposal),to:Recipe(document:current),groups:PluginPackage.allowedGroups,targetIsRAW:false).document
        }
        result.operations=[]
        result=ParameterLockPolicy.applying(result,preserving:current)
        try ToolRegistry().validate(result)
        return PluginExecution(pluginID:package.manifest.id,version:package.manifest.version,context:context,recipe:result,changedParameters:ParameterCatalog.changed(from:current,to:result).map(\.id))
    }
}
