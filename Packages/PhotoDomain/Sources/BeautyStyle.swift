import Foundation

public enum BeautyIntensity: String, CaseIterable, Sendable {
    case gentle, standard, strong
    public var title: String {
        switch self {case .gentle:return "轻柔";case .standard:return "标准";case .strong:return "更强"}
    }
}

public enum BeautyStyle: String, CaseIterable, Sendable {
    case natural, studio, retouch, porcelain, intensive, reshape
    public var title: String {
        switch self {case .natural:return "自然";case .studio:return "柔肤";case .retouch:return "AI 精修";case .porcelain:return "瓷白";case .intensive:return "高强度";case .reshape:return "塑形"}
    }
    public var settings: BeautySettings {
        var b=BeautySettings();b.enabled=true
        switch self {
        case .natural: break
        case .studio:
            b.strength=0.78;b.radius=14;b.texturePreservation=0.68;b.blemishRemoval=0.6;b.skinTone=0.55;b.toneUniformity=0.55;b.skinBrightness=0.1;b.intensiveSmoothing=0.25
        case .retouch:
            // Local learned correction and blend layers keep the source texture.
            // Whitening, blur and face reshaping remain independent opt-in edits.
            b.strength=0;b.detailRecovery=0;b.blemishRemoval=0;b.skinTone=0
            b.retouchBlemishes=0.9;b.retouchDodgeBurn=0.85
        case .porcelain:
            b.strength=0.95;b.radius=22;b.texturePreservation=0.2;b.blemishRemoval=0.8;b.skinTone=0.8;b.toneUniformity=0.85;b.skinBrightness=0.3;b.skinSaturation=0.85;b.intensiveSmoothing=0.65;b.skinWhitening=0.75;b.skinRosiness=0.06
        case .intensive, .reshape:
            b.strength=1;b.radius=32;b.texturePreservation=0;b.detailRecovery=0;b.blemishRemoval=1;b.skinTone=0.9;b.toneUniformity=0.95;b.skinBrightness=0.25;b.skinSaturation=0.8;b.intensiveSmoothing=1;b.skinWhitening=0.55;b.skinRosiness=0.2
            if self == .reshape {b.faceSlimming=0.7;b.eyeEnlargement=0.6}
        }
        return b
    }

    /// A preset is expanded into existing v2 parameters, so saved recipes and
    /// per-photo batch exports do not depend on temporary inspector state.
    public func settings(intensity: BeautyIntensity) -> BeautySettings {
        var b=settings
        if self == .retouch {
            switch intensity {
            case .gentle:b.retouchBlemishes=0.6;b.retouchDodgeBurn=0.55
            case .standard:break
            case .strong:b.retouchBlemishes=1;b.retouchDodgeBurn=1
            }
            return b
        }
        switch intensity {
        case .standard: break
        case .gentle:
            b.strength *= 0.65;b.intensiveSmoothing *= 0.55
            b.blemishRemoval *= 0.7;b.skinTone *= 0.7;b.toneUniformity *= 0.7
            b.skinBrightness *= 0.65;b.skinSaturation=1+(b.skinSaturation-1)*0.65
            b.skinWhitening *= 0.6;b.skinRosiness *= 0.6
            b.faceSlimming *= 0.7;b.eyeEnlargement *= 0.7
            b.texturePreservation=max(0.55,b.texturePreservation)
        case .strong:
            b.strength=min(1,b.strength*1.3);b.radius=min(32,b.radius*1.2)
            b.intensiveSmoothing=min(1,b.intensiveSmoothing*1.25+0.16)
            b.blemishRemoval=min(1,b.blemishRemoval*1.25)
            b.skinTone=min(1,b.skinTone*1.2);b.toneUniformity=min(1,b.toneUniformity*1.2)
            b.skinBrightness=min(1,b.skinBrightness*1.2+0.08)
            b.skinWhitening=min(1,b.skinWhitening*1.35+0.12)
            b.skinRosiness=min(1,b.skinRosiness*1.2+0.03)
            b.faceSlimming=min(1,b.faceSlimming*1.2);b.eyeEnlargement=min(1,b.eyeEnlargement*1.2)
            b.texturePreservation=max(0,b.texturePreservation-0.2)
        }
        return b
    }

    public func applying(to original: EditRecipe, intensity: BeautyIntensity = .standard) throws -> EditRecipe {
        try original.validateParameters()
        var proposed=original;proposed.beauty=settings(intensity:intensity)
        let result=ParameterLockPolicy.applying(proposed,preserving:original)
        try result.validateParameters()
        return result
    }
}
