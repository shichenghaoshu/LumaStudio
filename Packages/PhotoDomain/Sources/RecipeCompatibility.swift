import Foundation

/// Compatibility API only. Every setter writes into this one v2 document;
/// no parallel color/beauty/raw/export values are stored or encoded.
public struct Recipe: Codable, Equatable, Sendable {
    public var document: EditRecipe
    public init() { document=EditRecipe();document.color.lut="natural" }
    public init(document: EditRecipe) { self.document=document }
    public var version: Int { get {document.version} set {document.version=newValue} }
    public var beauty: BeautySettings { get {document.beauty} set {document.beauty=newValue} }
    public var raw: RAWSettings { get {document.raw} set {document.raw=newValue} }
    public var export: ExportSettings { get {document.export} set {document.export=newValue} }
    public var edit: EditRecipe? { get {document} set {if let newValue {document=newValue}} }
    public var color: ColorSettings {
        get {
            var c=ColorSettings();c.enabled=document.color.enabled;c.presetID=document.color.lut;c.intensity=document.color.intensity
            c.referenceProfileID=document.color.referenceProfileID;c.exposure=document.global.exposure;c.contrast=document.global.contrast
            c.saturation=document.global.saturation;c.temperature=document.global.temperature;return c
        }
        set {
            document.color.enabled=newValue.enabled;document.color.lut=newValue.presetID;document.color.intensity=newValue.intensity
            document.color.referenceProfileID=newValue.referenceProfileID;document.global.exposure=newValue.exposure;document.global.contrast=newValue.contrast
            document.global.saturation=newValue.saturation;document.global.temperature=newValue.temperature
        }
    }
    public func validated() throws -> Recipe {
        guard document.version==2 else { throw LumaError.unsupported("不支持的配方版本 \(document.version)") }
        var r=self
        for p in ParameterCatalog.all where !p.isAutomatic(r.document) { p.write(&r.document,p.bounded(p.read(r.document))) }
        r.document.operations=[];try r.document.validateParameters();return r
    }
    public func json() throws -> Data { try validated().document.json() }
    private enum Keys: String,CodingKey { case version,global,color,beauty,export,raw,edit,detail,effects,geometry,masks }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:Keys.self)
        let v=try c.decodeIfPresent(Int.self,forKey:.version) ?? 1
        guard v==1 || v==2 else { throw LumaError.unsupported("不支持的配方版本 \(v)") }
        if v==2 || c.contains(.global) || c.contains(.detail) || c.contains(.masks) { document=try EditRecipe(from:decoder);return }
        // Historical wrapper v1 stored common controls twice. Its validated legacy
        // mirrors were what the UI saved; migrate them once, then discard the mirrors.
        let embedded=try c.decodeIfPresent(EditRecipe.self,forKey:.edit)
        if let embedded {document=embedded}
        if let legacy=try c.decodeIfPresent(ColorSettings.self,forKey:.color) { color=legacy }
        if let b=try c.decodeIfPresent(BeautySettings.self,forKey:.beauty) { document.beauty=b }
        if let r=try c.decodeIfPresent(RAWSettings.self,forKey:.raw) { document.raw=r }
        if let e=try c.decodeIfPresent(ExportSettings.self,forKey:.export) { document.export=e }
        document.version=2;document.operations=[]
    }
    public func encode(to encoder: Encoder) throws { try document.encode(to:encoder) }
    public static func decodeValidated(_ data: Data) throws -> Recipe {
        guard data.count<=512*1024 else { throw LumaError.corruptData("配方超过 512KB") }
        if let o=try JSONSerialization.jsonObject(with:data) as? [String:Any],o["version"] as? Int==2 { try RecipeSchema.validate(data) }
        return try JSONDecoder().decode(Self.self,from:data).validated()
    }
}
