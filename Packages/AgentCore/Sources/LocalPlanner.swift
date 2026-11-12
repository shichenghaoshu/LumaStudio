import Foundation
import PhotoDomain
import VisionEngine
import LocalMemory

public enum InstructionParser {
    public static func parse(_ text: String) -> InstructionConstraints {
        let t=text.lowercased();var intent=InstructionConstraints()
        func positive(_ word: String)->Bool {
            guard t.contains(word) else { return false }
            return t.range(of:"(?:不要|不用|不必|别|不需要|禁止)[^，。；,;]{0,3}"+NSRegularExpression.escapedPattern(for:word),options:.regularExpression)==nil
        }
        if ["提亮","亮一点","更亮","增亮","brighten","brighter"].contains(where:positive) { intent.brightnessDirection=1 }
        if ["压暗","暗一点","更暗","降低曝光","darker","darken"].contains(where:positive) { intent.brightnessDirection = -1 }
        if ["降饱和","降低饱和","低饱和","淡一点","desaturat"].contains(where:positive) { intent.saturationDirection = -1 }
        else if ["提高饱和","增加饱和","鲜艳","saturate","vivid"].contains(where:positive) { intent.saturationDirection=1 }
        if ["暖一点","暖色","暖调","暖一些","偏暖","warmer","warm"].contains(where:positive) { intent.warmthDirection=1 }
        if ["冷一点","冷色","冷调","偏冷","cooler","cool"].contains(where:positive) { intent.warmthDirection = -1 }
        intent.beautyForbidden=["不磨皮","不要磨皮","关闭美颜","不要美颜","不用美颜","不美颜","no retouch","no smoothing"].contains(where:t.contains)
        intent.beautyRequested = !intent.beautyForbidden && ["磨皮","美颜","皮肤","肤色","瑕疵","retouch","skin"].contains(where:positive)
        intent.preserveTexture=true
        if ["背景","background"].contains(where:t.contains) { intent.requestedLocalRegion = .background }
        else if ["人物","主体","subject"].contains(where:t.contains) { intent.requestedLocalRegion = .subject }
        else if ["人脸","脸部","face"].contains(where:t.contains) { intent.requestedLocalRegion = .face }
        else if ["皮肤局部","只调皮肤"].contains(where:t.contains) { intent.requestedLocalRegion = .skin }
        if ["头发","hair"].contains(where:t.contains) { intent.unavailableRequests.append("头发分割模型尚未安装") }
        if ["天空","sky"].contains(where:t.contains) { intent.unavailableRequests.append("天空分割模型尚未安装") }
        for word in ["瘦脸","瘦身","大眼","换脸","换背景","去掉路人","消除路人","生成","液化"] where t.contains(word) { intent.unavailableRequests.append("“\(word)”尚未提供可执行工具") }
        return intent
    }
}
public struct PlanningContext: Codable,Sendable {
    public let instruction: String
    public let analysis: ImageAnalysis
    public let preferences: EditingPreferences
    public let currentRecipe: EditRecipe?
    public let referenceProfileID: String?
    public let previousInstructions: [String]
    public init(instruction: String,analysis: ImageAnalysis,preferences: EditingPreferences,currentRecipe: EditRecipe?=nil,referenceProfileID: String?=nil,previousInstructions: [String]=[]) {
        self.instruction=instruction;self.analysis=analysis;self.preferences=preferences;self.currentRecipe=currentRecipe;self.referenceProfileID=referenceProfileID;self.previousInstructions=Array(previousInstructions.suffix(3))
    }
}
public struct LocalRulePlanner: Sendable {
    public init() {}
    public func plan(_ context: PlanningContext) throws -> EditRecipe {
        let t=context.instruction.lowercased(),intent=InstructionParser.parse(context.instruction)
        let continuation=["再","继续","更","保持","在此基础","a little more","keep"].contains(where:t.contains)
        var r=continuation ? (context.currentRecipe ?? EditRecipe()) : EditRecipe()
        if context.preferences.confirmationCount>0 {
            r.beauty.strength=context.preferences.beautyStrength;r.beauty.texturePreservation=context.preferences.texturePreservation
            if !continuation { r.global.temperature=context.preferences.temperature;r.global.saturation=context.preferences.saturation;r.color.lut=context.preferences.preferredLUT }
        }
        if t.contains("日系") || t.contains("日式") { r.global.contrast=0.92;r.global.shadows=0.12;r.global.highlights = -0.12;r.global.saturation=0.88;r.global.temperature=6750;r.color.lut="film";r.color.intensity=0.3 }
        else if t.contains("电影") || t.contains("cinematic") { r.global.contrast=1.12;r.global.highlights = -0.15;r.global.blacks=0.04;r.color.lut="film";r.color.intensity=0.45;r.color.grading.shadowSaturation=0.07;r.color.grading.highlightSaturation=0.04 }
        else if t.contains("胶片") || t.contains("film") { r.color.lut="film";r.color.intensity=0.55;r.global.blacks=0.1;r.global.highlights = -0.1 }
        if t.contains("通透") || t.contains("clean") { r.color.lut="clean";r.color.intensity=0.5;r.global.contrast=1.05;r.global.shadows=0.08;r.global.vibrance=0.1 }
        if t.contains("自然") || t.contains("natural") { r.beauty.strength=min(r.beauty.strength,0.35);r.beauty.texturePreservation=0.96;if continuation { r.color.intensity *= 0.7 } }
        if intent.beautyRequested,context.analysis.faceCount>0 { r.beauty.enabled=true }
        if intent.beautyForbidden { r.beauty.enabled=false }
        if t.contains("不美白") || t.contains("不要美白") { r.beauty.skinTone=0 }
        if t.contains("重置") || t.contains("恢复原图") || t.contains("reset") { return EditRecipe() }
        var adjustment=GlobalAdjustments()
        if intent.brightnessDirection != 0 { adjustment.exposure=Float(intent.brightnessDirection)*0.35 }
        if intent.saturationDirection != 0 { adjustment.saturation=1+Float(intent.saturationDirection)*0.15 }
        if intent.warmthDirection != 0 { adjustment.temperature=6500+Float(intent.warmthDirection)*700 }
        if t.contains("高光") && ["压","降","恢复"].contains(where:t.contains) { adjustment.highlights = -0.3 }
        if t.contains("阴影") && ["提","亮","恢复"].contains(where:t.contains) { adjustment.shadows=0.25 }
        if t.contains("对比") {
            if ["降低","柔和","减少"].contains(where:t.contains) { adjustment.contrast=0.9 }
            else if ["提高","增加","增强"].contains(where:t.contains) { adjustment.contrast=1.1 }
        }
        if let region=intent.requestedLocalRegion {
            let local=LocalMask(id:"local_"+region.rawValue,kind:region,adjustments:adjustment)
            r.masks.removeAll{$0.kind==region};r.masks.append(local)
        } else {
            r.global.exposure=min(3,max(-3,r.global.exposure+adjustment.exposure))
            if adjustment.saturation != 1 { r.global.saturation=adjustment.saturation }
            if adjustment.temperature != 6500 { r.global.temperature=adjustment.temperature }
            if adjustment.contrast != 1 { r.global.contrast=adjustment.contrast }
            if adjustment.highlights != 0 { r.global.highlights=adjustment.highlights }
            if adjustment.shadows != 0 { r.global.shadows=adjustment.shadows }
        }
        // Explicit EV requests are bounded by the same executable contract as model output.
        if let range=t.range(of:"[+-]?[0-9]+(?:\\.[0-9]+)?\\s*ev",options:.regularExpression),let v=Float(t[range].replacingOccurrences(of:"ev",with:"").trimmingCharacters(in:.whitespaces)) {
            if let region=intent.requestedLocalRegion,let i=r.masks.firstIndex(where:{$0.kind==region}) { r.masks[i].adjustments.exposure=v }
            else { r.global.exposure=v }
        }
        if t.contains("参考") || t.contains("reference") { r.color.referenceProfileID=context.referenceProfileID }
        r.operations=[];try r.validateParameters();return r
    }
}
