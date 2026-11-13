import Foundation
import CoreImage
import PhotoDomain

public struct RAWCapabilities: Sendable {
    public let supported: Set<String>
    public let defaults: [String:Float]
    public let lensCorrection: Bool
    public let description: String
    public static let unavailable=RAWCapabilities(supported:[],defaults:[:],lensCorrection:false,description:"当前文件不是可解码的 RAW")
    public static func inspect(_ url: URL)->RAWCapabilities {
        guard PhotoFileType.isRAW(url) else {return .unavailable}
        if !RAWBackendRouter.nativeAvailable(url) {
            return LibRawFallback.canOpen(url) ? RAWCapabilities(supported:["raw.exposure"],defaults:["raw.exposure":0],lensCorrection:false,description:"LibRaw 0.22.3 备用显影 · 16-bit · 相机白平衡 · RAW 曝光可调") : .unavailable
        }
        guard let f=CIRAWFilter(imageURL:url) else {return .unavailable}
        var available:Set<String>=["raw.exposure","raw.temperature","raw.tint","raw.shadows","raw.blackLevel"]
        for (id,yes) in [("raw.highlights",f.isLocalToneMapSupported),("raw.contrast",f.isContrastSupported),("raw.detail",f.isDetailSupported),("raw.colorNoise",f.isColorNoiseReductionSupported),("raw.luminanceNoise",f.isLuminanceNoiseReductionSupported),("raw.sharpness",f.isSharpnessSupported),("raw.moire",f.isMoireReductionSupported)] where yes {available.insert(id)}
        return RAWCapabilities(supported:available,defaults:["raw.exposure":f.exposure,"raw.temperature":f.neutralTemperature,"raw.tint":f.neutralTint,"raw.shadows":0,"raw.highlights":f.localToneMapAmount,"raw.contrast":f.contrastAmount,"raw.blackLevel":0,"raw.detail":f.detailAmount,"raw.colorNoise":f.colorNoiseReductionAmount,"raw.luminanceNoise":f.luminanceNoiseReductionAmount,"raw.sharpness":f.sharpnessAmount,"raw.moire":f.moireReductionAmount,"raw.lensCorrection":f.isLensCorrectionEnabled ? 1 : 0],lensCorrection:f.isLensCorrectionSupported,description:"CIRAWFilter · \(Int(f.nativeSize.width)) × \(Int(f.nativeSize.height)) · \(available.count) 项解码控制")
    }
}
