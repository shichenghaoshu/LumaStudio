import Foundation
import PhotoDomain

public struct ToolDescriptor: Codable,Sendable,Identifiable {
    public let id: ToolID
    public let title: String
    public let version: Int
    public let timeoutSeconds: Int
    public init(id: ToolID,title: String) { self.id=id;self.title=title;version=1;timeoutSeconds=30 }
}
public struct ToolRegistry: Sendable {
    public let supportedMasks: Set<MaskKind>
    public static let tools: [ToolDescriptor]=[
        .init(id:.global,title:"全局曝光和影调"),.init(id:.beauty,title:"皮肤区域与纹理保护"),
        .init(id:.color,title:"色彩、曲线和参考色匹配"),.init(id:.local,title:"局部区域调整")
    ]
    public init(supportedMasks: Set<MaskKind>=[.face,.skin,.subject,.background]) { self.supportedMasks=supportedMasks }
    public func validate(_ recipe: EditRecipe) throws {
        try recipe.validateParameters()
        for mask in recipe.masks where !supportedMasks.contains(mask.kind) { throw LumaError.unsupported("尚未安装 \(mask.kind.rawValue) 分割模型；请使用人物、背景、人脸或皮肤区域。") }
        for op in recipe.resolvedOperations where !Self.tools.contains(where:{$0.id==op.tool}) { throw LumaError.unsupported("未注册工具") }
    }
    public func decode(_ data: Data) throws -> EditRecipe { let r=try EditRecipe.decodeValidated(data);try validate(r);return r }
}
