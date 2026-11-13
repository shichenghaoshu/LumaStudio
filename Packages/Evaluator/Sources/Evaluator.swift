import Foundation
import CoreGraphics
import PhotoDomain
import VisionEngine

public enum IssueSeverity: String,Codable,Sendable { case warning,severe }
public enum QualityIssueKind: String,Codable,Sendable { case highlights,shadows,skinColor,texture,brightnessAlignment,saturationAlignment,warmthAlignment,beautyAlignment,unsupported }
public struct QualityIssue: Codable,Equatable,Sendable {
    public var kind: QualityIssueKind
    public var severity: IssueSeverity
    public var message: String
    public init(_ kind: QualityIssueKind,_ severity: IssueSeverity,_ message: String) { self.kind=kind;self.severity=severity;self.message=message }
}
public struct QualityReport: Codable,Equatable,Sendable {
    public let before: PixelMetrics
    public let after: PixelMetrics
    public let issues: [QualityIssue]
    public let backend: String
    public var accepted: Bool { !issues.contains{$0.severity == .severe} }
    public var needsCorrection: Bool { !issues.filter{$0.kind != .unsupported}.isEmpty }
    public var summary: String { issues.isEmpty ? "曝光、色彩与纹理指标通过，请确认视觉效果" : issues.map(\.message).joined(separator:"；") }
    public init(before: PixelMetrics,after: PixelMetrics,issues: [QualityIssue]) { self.before=before;self.after=after;self.issues=issues;backend="确定性指标 v1 · 无训练评价网络" }
}
public struct QualityEvaluator: Sendable {
    public init() {}
    public func evaluate(original: CGImage,result: CGImage,recipe: EditRecipe,intent: InstructionConstraints,skinMask: CGImage?=nil) throws -> QualityReport {
        let a=try PixelMetrics.measure(original),b=try PixelMetrics.measure(result)
        var issues=[QualityIssue]()
        if b.clippedHighlights>a.clippedHighlights+0.035 && b.clippedHighlights>0.06 { issues.append(.init(.highlights,b.clippedHighlights>0.2 ? .severe : .warning,"新增高光溢出，建议降低曝光")) }
        if b.crushedShadows>a.crushedShadows+0.06 && b.crushedShadows>0.15 { issues.append(.init(.shadows,b.crushedShadows>0.4 ? .severe : .warning,"暗部细节明显减少")) }
        // The whole-image check is conservative; a skin mask improves specificity when provided.
        let skinBefore=try skinMask.map{try PixelMetrics.measure(original,mask:$0)},skinAfter=try skinMask.map{try PixelMetrics.measure(result,mask:$0)}
        let ta=skinBefore ?? a,tb=skinAfter ?? b
        if recipe.beauty.enabled,intent.preserveTexture,ta.edgeEnergy>0.005,tb.edgeEnergy<ta.edgeEnergy*0.55 {
            issues.append(.init(.texture,.warning,skinMask==nil ? "图像纹理下降，需要检查磨皮强度" : "皮肤纹理下降，需要降低磨皮强度"))
        }
        if let sa=skinBefore,let sb=skinAfter,recipe.evaluation.preserveSkin,
           abs((sb.meanRed-sb.meanBlue)-(sa.meanRed-sa.meanBlue))>0.16 {
            issues.append(.init(.skinColor,.warning,"肤色冷暖偏移较大"))
        }
        if intent.brightnessDirection>0,b.meanLuminance<a.meanLuminance+0.008 { issues.append(.init(.brightnessAlignment,.warning,"整体亮度未达到提亮要求")) }
        if intent.brightnessDirection<0,b.meanLuminance>a.meanLuminance-0.008 { issues.append(.init(.brightnessAlignment,.warning,"整体亮度未达到压暗要求")) }
        if intent.saturationDirection>0,b.meanSaturation<a.meanSaturation+0.008 { issues.append(.init(.saturationAlignment,.warning,"饱和度未按要求提高")) }
        if intent.saturationDirection<0,b.meanSaturation>a.meanSaturation-0.008 { issues.append(.init(.saturationAlignment,.warning,"饱和度未按要求降低")) }
        let warmBefore=a.meanRed-a.meanBlue,warmAfter=b.meanRed-b.meanBlue
        if intent.warmthDirection>0,warmAfter<warmBefore+0.006 { issues.append(.init(.warmthAlignment,.warning,"暖调要求需要进一步检查")) }
        if intent.warmthDirection<0,warmAfter>warmBefore-0.006 { issues.append(.init(.warmthAlignment,.warning,"冷调要求需要进一步检查")) }
        if intent.beautyForbidden,recipe.beauty.enabled { issues.append(.init(.beautyAlignment,.severe,"指令要求关闭美颜")) }
        if intent.beautyRequested,!recipe.beauty.enabled { issues.append(.init(.beautyAlignment,.warning,"人像优化尚未按要求启用")) }
        for u in intent.unavailableRequests { issues.append(.init(.unsupported,.warning,u)) }
        return QualityReport(before:a,after:b,issues:issues)
    }
    public func corrected(_ recipe: EditRecipe,report: QualityReport,intent: InstructionConstraints) throws -> EditRecipe {
        var r=recipe
        for issue in report.issues {
            switch issue.kind {
            case .highlights:r.global.exposure=max(-5,r.global.exposure-0.25);r.global.highlights=max(-1,r.global.highlights-0.15)
            case .shadows:r.global.shadows=min(1,r.global.shadows+0.2);r.global.blacks=min(1,r.global.blacks+0.1)
            case .texture:r.beauty.strength *= 0.7;r.beauty.texturePreservation=max(0.94,r.beauty.texturePreservation)
            case .skinColor:r.global.temperature=6500+(r.global.temperature-6500)*0.5;r.color.intensity *= 0.7
            case .brightnessAlignment:r.global.exposure=min(5,max(-5,r.global.exposure+Float(intent.brightnessDirection)*0.2))
            case .saturationAlignment:r.global.saturation=min(2,max(0,r.global.saturation+Float(intent.saturationDirection)*0.1))
            case .warmthAlignment:r.global.temperature=min(12000,max(2000,r.global.temperature+Float(intent.warmthDirection)*350))
            case .beautyAlignment:r.beauty.enabled = intent.beautyRequested && !intent.beautyForbidden
            case .unsupported:break
            }
        }
        r.operations=[];try r.validateParameters();return r
    }
}
