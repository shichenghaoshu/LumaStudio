import Foundation

public enum BeautyStyle: String, CaseIterable, Sendable {
    case natural, studio, porcelain, intensive, reshape
    public var title: String {
        switch self {case .natural:return "自然";case .studio:return "精修";case .porcelain:return "瓷白";case .intensive:return "高强度";case .reshape:return "塑形"}
    }
    public var settings: BeautySettings {
        var b=BeautySettings();b.enabled=true
        switch self {
        case .natural: break
        case .studio:
            b.strength=0.78;b.radius=14;b.texturePreservation=0.68;b.blemishRemoval=0.6;b.skinTone=0.55;b.toneUniformity=0.55;b.skinBrightness=0.1;b.intensiveSmoothing=0.25
        case .porcelain:
            b.strength=0.95;b.radius=22;b.texturePreservation=0.2;b.blemishRemoval=0.8;b.skinTone=0.8;b.toneUniformity=0.85;b.skinBrightness=0.3;b.skinSaturation=0.85;b.intensiveSmoothing=0.65;b.skinWhitening=0.75;b.skinRosiness=0.06
        case .intensive, .reshape:
            b.strength=1;b.radius=32;b.texturePreservation=0;b.detailRecovery=0;b.blemishRemoval=1;b.skinTone=0.9;b.toneUniformity=0.95;b.skinBrightness=0.25;b.skinSaturation=0.8;b.intensiveSmoothing=1;b.skinWhitening=0.55;b.skinRosiness=0.2
            if self == .reshape {b.faceSlimming=0.7;b.eyeEnlargement=0.6}
        }
        return b
    }
}
