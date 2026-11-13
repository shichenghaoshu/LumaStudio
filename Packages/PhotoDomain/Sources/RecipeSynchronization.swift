import Foundation

/// Explicit groups keep photo-specific edits out of routine style synchronization.
public enum RecipeSyncGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case tone, whiteBalance, color, curves, grading, style, beauty, detail, effects, raw, geometry, masks, output
    public var id: Self { self }
    public static let recommended: Set<Self> = [.tone, .whiteBalance, .color, .curves, .grading, .style, .detail, .effects]
    public var title: String {
        switch self {
        case .tone: return "曝光与影调"
        case .whiteBalance: return "白平衡"
        case .color: return "颜色、HSL 与校准"
        case .curves: return "RGB 曲线"
        case .grading: return "三向色彩分级"
        case .style: return "滤镜与参考色彩"
        case .beauty: return "人像美化"
        case .detail: return "锐化与降噪"
        case .effects: return "质感与效果"
        case .raw: return "RAW 解码设置"
        case .geometry: return "裁剪与几何"
        case .masks: return "局部蒙版与画笔"
        case .output: return "导出设置"
        }
    }
    public var note: String {
        switch self {
        case .tone: return "曝光、对比、高光、阴影、清晰度与去雾"
        case .whiteBalance: return "后期色温与色调；相机白平衡在 RAW 分组"
        case .color: return "饱和度、自然饱和度、HSL、色阶、可选颜色与校准"
        case .curves: return "主曲线及红、绿、蓝通道曲线"
        case .grading: return "阴影、中间调与高光分级"
        case .style: return "滤镜、强度与本地参考色彩档案"
        case .beauty: return "启用状态、磨皮与肤色设置"
        case .detail: return "后期锐化、明度与颜色降噪"
        case .effects: return "暗角、颗粒、柔光与胶片效果"
        case .raw: return "仅同步到 RAW 照片；各相机可用项由解码器决定"
        case .geometry: return "覆盖目标照片各自的构图设置"
        case .masks: return "替换局部区域；画笔使用相同的归一化坐标"
        case .output: return "格式、尺寸、色彩空间、位深、元数据与命名"
        }
    }
}

public enum RecipeSynchronization {
    public static func applying(_ source: Recipe, to target: Recipe, groups: Set<RecipeSyncGroup>, targetIsRAW: Bool) throws -> Recipe {
        try source.document.validateParameters()
        try target.document.validateParameters()
        let s = source.document
        var d = target.document
        if groups.contains(.tone) {
            // White balance and saturation have their own independent groups.
            let temperature = d.global.temperature, tint = d.global.tint
            let saturation = d.global.saturation, vibrance = d.global.vibrance
            d.global = s.global
            d.global.temperature = temperature; d.global.tint = tint
            d.global.saturation = saturation; d.global.vibrance = vibrance
        }
        if groups.contains(.whiteBalance) { d.global.temperature = s.global.temperature; d.global.tint = s.global.tint }
        if groups.contains(.color) {
            d.global.saturation = s.global.saturation; d.global.vibrance = s.global.vibrance
            d.color.hsl = s.color.hsl; d.color.levels = s.color.levels
            d.color.calibration = s.color.calibration; d.color.range = s.color.range; d.color.selective = s.color.selective
        }
        if groups.contains(.curves) { d.color.curve = s.color.curve }
        if groups.contains(.grading) { d.color.grading = s.color.grading }
        if groups.contains(.style) { d.color.lut = s.color.lut; d.color.intensity = s.color.intensity; d.color.referenceProfileID = s.color.referenceProfileID }
        if !groups.isDisjoint(with: [.color, .curves, .grading, .style]) { d.color.enabled = s.color.enabled }
        if groups.contains(.beauty) { d.beauty = s.beauty }
        if groups.contains(.detail) { d.detail = s.detail }
        if groups.contains(.effects) { d.effects = s.effects }
        if groups.contains(.raw), targetIsRAW { d.raw = s.raw }
        if groups.contains(.geometry) { d.geometry = s.geometry }
        if groups.contains(.masks) { d.masks = s.masks }
        if groups.contains(.output) { d.export = s.export }
        d.operations = []
        // A target keeps its locks, evaluation settings and every unselected group.
        d = ParameterLockPolicy.applying(d, preserving: target.document)
        try d.validateParameters()
        return Recipe(document: d)
    }
}

public struct RecipeSyncChange: Codable, Equatable, Sendable {
    public let id: UUID
    public let before: Recipe
    public let after: Recipe
    public init(id: UUID, before: Recipe, after: Recipe) { self.id = id; self.before = before; self.after = after }
}

public struct RecipeSyncTransaction: Codable, Sendable {
    public let sourceID: UUID
    public let changes: [RecipeSyncChange]
    public let skippedRAWCount: Int
    public init(sourceID: UUID, changes: [RecipeSyncChange], skippedRAWCount: Int) {
        self.sourceID = sourceID; self.changes = changes; self.skippedRAWCount = skippedRAWCount
    }
}
