import Foundation
import OSLog
import ImageIO
import UniformTypeIdentifiers

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
public enum PhotoFileType {
    /// Camera extensions identify candidates; CIRAWFilter still checks the actual camera/codec.
    public static let rawExtensions: Set<String> = ["3fr","ari","arw","bay","cap","crw","cr2","cr3","data","dcs","dcr","dng","drf","eip","erf","fff","gpr","iiq","k25","kdc","mdc","mef","mos","mrw","nef","nrw","obm","orf","pef","ptx","pxn","r3d","raf","raw","rwl","rw2","rwz","sr2","srf","srw","x3f"]
    public static let imageTypeIdentifiers: [String] = (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).sorted()
    /// Follow the OS decoder registry, including HEIF, AVIF, WebP, JPEG XL, GIF, BMP and PSD
    /// when available on this Mac. Vector/document formats are deliberately excluded.
    public static let imageExtensions: Set<String> = {
        let extensions=imageTypeIdentifiers.compactMap(UTType.init).filter { $0.conforms(to:.image) && !$0.conforms(to:.svg) }
            .flatMap { $0.tags[.filenameExtension] ?? [] }.map { $0.lowercased() }
        return rawExtensions.union(extensions)
    }()
    public static func accepts(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
    public static func isRAW(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased()) || UTType(filenameExtension:url.pathExtension)?.conforms(to:.rawImage)==true
    }
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
public enum RenderTier: Sendable { case thumbnail, interactive, preview, fullResolution
    public var maxDimension: Int? { switch self { case .thumbnail: return 360; case .interactive: return 960; case .preview: return 1600; case .fullResolution: return nil } }
    public var isPreview: Bool {self == .interactive || self == .preview}
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
