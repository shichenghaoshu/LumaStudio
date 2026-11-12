import Foundation
import OSLog

public enum LumaLog {
    public static let library = Logger(subsystem: "studio.luma.local", category: "library")
    public static let pipeline = Logger(subsystem: "studio.luma.local", category: "pipeline")
    public static let camera = Logger(subsystem: "studio.luma.local", category: "camera")
    public static let sync = Logger(subsystem: "studio.luma.local", category: "sync")
}

public enum LumaError: LocalizedError {
    case unsupported(String), invalidImage(String), unsafeDestination, corruptData(String), notConnected
    public var errorDescription: String? {
        switch self {
        case .unsupported(let reason): return reason
        case .invalidImage(let name): return "无法解码照片：\(name)"
        case .unsafeDestination: return "导出位置不能覆盖原始照片或位于图库 Originals 目录内。"
        case .corruptData(let detail): return "数据无效：\(detail)"
        case .notConnected: return "设备尚未连接或配对。"
        }
    }
}

public struct BeautySettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var strength: Float = 0.35
    public var skinTone: Float = 0.25
    public var blemishRemoval: Float = 0.2
    public var texturePreservation: Float = 0.94
    public init() {}
}
public struct ColorSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var presetID: String? = "natural"
    public var intensity: Float = 0.8
    public var exposure: Float = 0
    public var contrast: Float = 1
    public var saturation: Float = 1
    public var temperature: Float = 6500
    public var referenceProfileID: String?
    public init() {}
}
public enum ExportFormat: String, Codable, CaseIterable, Sendable { case jpeg, png, tiff }
public struct ExportSettings: Codable, Equatable, Sendable {
    public var format: ExportFormat = .jpeg
    public var quality: Float = 0.95
    public init() {}
}
public struct Recipe: Codable, Equatable, Sendable {
    public var version = 1
    public var beauty = BeautySettings()
    public var color = ColorSettings()
    public var export = ExportSettings()
    public var raw = RAWSettings()
    public var edit: EditRecipe?
    public init() {}
    public func validated() throws -> Recipe {
        guard version == 1 else { throw LumaError.unsupported("不支持的配方版本 \(version)") }
        if let id=color.referenceProfileID, UUID(uuidString:id)==nil { throw LumaError.corruptData("色彩档案 ID") }
        var r = self
        func unit(_ f: Float) -> Float { f.isFinite ? min(1, max(0, f)) : 0 }
        r.beauty.strength = unit(r.beauty.strength)
        r.beauty.skinTone = unit(r.beauty.skinTone)
        r.beauty.blemishRemoval = unit(r.beauty.blemishRemoval)
        r.beauty.texturePreservation = min(1,max(0.6,r.beauty.texturePreservation))
        r.color.intensity = unit(r.color.intensity)
        r.color.exposure = r.color.exposure.isFinite ? min(5, max(-5, r.color.exposure)) : 0
        r.color.contrast = r.color.contrast.isFinite ? min(2, max(0.2, r.color.contrast)) : 1
        r.color.saturation = r.color.saturation.isFinite ? min(2, max(0, r.color.saturation)) : 1
        r.color.temperature = r.color.temperature.isFinite ? min(12000, max(2000, r.color.temperature)) : 6500
        r.raw.exposure=r.raw.exposure.isFinite ? min(5,max(-5,r.raw.exposure)) : 0
        r.raw.shadows=r.raw.shadows.isFinite ? min(1,max(-1,r.raw.shadows)) : 0
        r.raw.highlights=r.raw.highlights.isFinite ? min(1,max(0,r.raw.highlights)) : 0.7
        if let t=r.raw.temperature { r.raw.temperature=t.isFinite ? min(12000,max(2000,t)) : nil }
        if let t=r.raw.tint { r.raw.tint=t.isFinite ? min(150,max(-150,t)) : nil }
        r.export.quality = max(0.1, unit(r.export.quality))
        if var edit=r.edit {
            // Common controls remain editable after an Agent plan is applied.
            edit.global.exposure=r.color.exposure;edit.global.contrast=r.color.contrast
            edit.global.saturation=r.color.saturation;edit.global.temperature=r.color.temperature
            edit.beauty=r.beauty;edit.color.lut=r.color.presetID;edit.color.intensity=r.color.intensity
            edit.color.referenceProfileID=r.color.referenceProfileID
            edit.operations=[]
            try edit.validateParameters();r.edit=edit
        }
        return r
    }
    public func json() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(validated())
    }
}

public enum PhotoFileType {
    public static let rawExtensions: Set<String> = ["rw2", "dng", "cr2", "cr3", "nef", "arw", "orf", "raf"]
    public static let imageExtensions = rawExtensions.union(["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"])
    public static func accepts(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
    public static func isRAW(_ url: URL) -> Bool { rawExtensions.contains(url.pathExtension.lowercased()) }
}
public struct PhotoAsset: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var originalURL: URL
    public var companionURL: URL?
    public var thumbnailURL: URL
    public var importedAt: Date
    public var isRAW: Bool { PhotoFileType.isRAW(originalURL) }
    public init(id: UUID = UUID(), name: String, originalURL: URL, companionURL: URL? = nil, thumbnailURL: URL, importedAt: Date = Date()) {
        self.id = id; self.name = name; self.originalURL = originalURL; self.companionURL = companionURL
        self.thumbnailURL = thumbnailURL; self.importedAt = importedAt
    }
}
public struct CapturedPhoto: Sendable { public let url: URL; public init(url: URL) { self.url = url } }
public struct CameraCapabilities: Codable, Equatable, Sendable {
    public var supportsLiveView = false
    public var supportsRemoteCapture = false
    public var supportsISOControl = false
    public var supportsShutterControl = false
    public var supportsApertureControl = false
    public var supportsWiFi = false
    public var supportsRAWTransfer = false
    public init() {}
}
public enum RenderTier: Sendable { case thumbnail, preview, fullResolution
    public var maxDimension: Int? { switch self { case .thumbnail: return 360; case .preview: return 1600; case .fullResolution: return nil } }
}
public struct RAWSettings: Codable, Equatable, Sendable {
    public var exposure: Float = 0
    public var temperature: Float? = nil
    public var tint: Float? = nil
    public var highlights: Float = 0.7
    public var shadows: Float = 0
    public init() {}
}

// Older and minimal v1 JSON recipes receive the same defaults as the UI.
extension BeautySettings {
    private enum Keys: String,CodingKey { case enabled,strength,skinTone,blemishRemoval,texturePreservation }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:Keys.self)
        enabled=try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? enabled
        strength=try c.decodeIfPresent(Float.self,forKey:.strength) ?? strength
        skinTone=try c.decodeIfPresent(Float.self,forKey:.skinTone) ?? skinTone
        blemishRemoval=try c.decodeIfPresent(Float.self,forKey:.blemishRemoval) ?? blemishRemoval
        texturePreservation=try c.decodeIfPresent(Float.self,forKey:.texturePreservation) ?? texturePreservation
    }
}
extension ColorSettings {
    private enum Keys: String,CodingKey { case enabled,presetID,intensity,exposure,contrast,saturation,temperature,referenceProfileID }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:Keys.self)
        enabled=try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? enabled
        presetID=try c.decodeIfPresent(String.self,forKey:.presetID) ?? presetID
        intensity=try c.decodeIfPresent(Float.self,forKey:.intensity) ?? intensity
        exposure=try c.decodeIfPresent(Float.self,forKey:.exposure) ?? exposure
        contrast=try c.decodeIfPresent(Float.self,forKey:.contrast) ?? contrast
        saturation=try c.decodeIfPresent(Float.self,forKey:.saturation) ?? saturation
        temperature=try c.decodeIfPresent(Float.self,forKey:.temperature) ?? temperature
        referenceProfileID=try c.decodeIfPresent(String.self,forKey:.referenceProfileID)
    }
}
extension ExportSettings {
    private enum Keys: String,CodingKey { case format,quality }
    public init(from decoder: Decoder) throws { self.init();let c=try decoder.container(keyedBy:Keys.self);format=try c.decodeIfPresent(ExportFormat.self,forKey:.format) ?? format;quality=try c.decodeIfPresent(Float.self,forKey:.quality) ?? quality }
}
extension Recipe {
    private enum Keys: String,CodingKey { case version,beauty,color,export,raw,edit }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:Keys.self)
        version=try c.decodeIfPresent(Int.self,forKey:.version) ?? 1
        beauty=try c.decodeIfPresent(BeautySettings.self,forKey:.beauty) ?? beauty
        color=try c.decodeIfPresent(ColorSettings.self,forKey:.color) ?? color
        export=try c.decodeIfPresent(ExportSettings.self,forKey:.export) ?? export
        raw=try c.decodeIfPresent(RAWSettings.self,forKey:.raw) ?? raw
        edit=try c.decodeIfPresent(EditRecipe.self,forKey:.edit)
    }
}
