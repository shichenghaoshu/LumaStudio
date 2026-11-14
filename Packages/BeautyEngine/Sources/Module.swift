import Foundation
import CoreImage
import PhotoDomain

public final class BeautyProcessor {
    public let segmentation: SkinSegmentation
    // Core Image compiles these compact kernels locally and schedules them on Metal.
    private let textureKernel: CIColorKernel
    private let toneKernel: CIColorKernel
    private let detailKernel: CIColorKernel
    private let intensiveKernel: CIColorKernel
    private let shape: FaceShapeProcessor
    private let metalBeauty=MetalPetalBeauty()
    private let useMetalPetal: Bool
    public private(set) var lastBackend="美颜未开启"
    public var metalPetalAvailable: Bool { metalBeauty.available }
    public init(modelURL: URL? = nil,useMetalPetal: Bool = true) throws {
        self.useMetalPetal=useMetalPetal
        segmentation=SkinSegmentation(modelURL:modelURL)
        shape=try FaceShapeProcessor()
        guard let texture=CIColorKernel(source:"""
        kernel vec4 lumaTexture(__sample original, __sample low, __sample smoothLow, float strength, float repair, float preservation, float recovery, float threshold) {
            vec3 detail = original.rgb - low.rgb;
            float redness = max(0.0, original.r - 0.5*(original.g+original.b) - (low.r-0.5*(low.g+low.b)));
            float darkSpot = max(0.0, dot(low.rgb-original.rgb, vec3(0.2126,0.7152,0.0722)));
            // Small red/dark anomalies are attenuated gently; default never erases all marks.
            float anomaly = smoothstep(threshold,threshold+0.065,redness) * smoothstep(0.005,0.07,darkSpot);
            vec3 retouched = smoothLow.rgb + detail * preservation;
            vec3 result = mix(original.rgb, retouched, strength) + detail * preservation * recovery;
            result = mix(result,low.rgb,repair * anomaly * 0.18);
            return vec4(result, original.a);
        }
        """), let tone=CIColorKernel(source:"""
        kernel vec4 lumaTone(__sample original, __sample low, float amount, float uniformity) {
            float y = dot(original.rgb, vec3(0.2126,0.7152,0.0722));
            float mid = smoothstep(0.08,0.3,y) * (1.0-smoothstep(0.72,0.98,y));
            vec3 chroma = original.rgb - vec3(y);
            float ly = dot(low.rgb, vec3(0.2126,0.7152,0.0722));
            vec3 uniformChroma = low.rgb - vec3(ly);
            vec3 result = vec3(y + 0.018*amount*mid) + mix(chroma,uniformChroma,amount*uniformity*mid);
            return vec4(result,original.a);
        }
        """),let detail=CIColorKernel(source:"""
        kernel vec4 lumaMetalDetail(__sample original, __sample low, __sample filtered, float repair, float preservation, float recovery, float threshold) {
            vec3 detail = original.rgb-low.rgb;
            float redSpot=max(0.0,detail.r-0.5*(detail.g+detail.b));
            float darkSpot=max(0.0,-dot(detail,vec3(0.2126,0.7152,0.0722)));
            float anomaly=smoothstep(threshold,threshold+0.065,redSpot)*smoothstep(0.005,0.07,darkSpot);
            // Restore extended-range energy that the SDR beauty LUT cannot process.
            vec3 headroom=original.rgb-clamp(original.rgb,0.0,1.0);
            vec3 result=filtered.rgb+headroom+detail*preservation*recovery;
            result=mix(result,low.rgb,repair*anomaly*0.18);
            return vec4(result,original.a);
        }
        """),let intensive=CIColorKernel(source:"""
        kernel vec4 lumaIntensive(__sample original, __sample soft, float smoothing, float whitening, float rosy) {
            vec3 c=mix(original.rgb,soft.rgb,smoothing*0.97);
            vec3 headroom=c-clamp(c,0.0,1.0);
            vec3 porcelain=1.0-pow(1.0-clamp(c,0.0,1.0),vec3(1.8));
            float y=dot(porcelain,vec3(0.2126,0.7152,0.0722));
            porcelain=mix(vec3(y),porcelain,0.72)+headroom;
            c=mix(c,porcelain,whitening);
            float mid=smoothstep(0.04,0.25,dot(c,vec3(0.2126,0.7152,0.0722)));
            c+=rosy*mid*vec3(0.12,-0.025,-0.015);
            return vec4(c,original.a);
        }
        """) else { throw LumaError.unsupported("Core Image 纹理内核编译失败") }
        textureKernel=texture;toneKernel=tone;detailKernel=detail;intensiveKernel=intensive
    }
    public func apply(_ image: CIImage, settings: BeautySettings, analysis: SkinAnalysis,context: CIContext?=nil) throws -> CIImage {
        guard settings.enabled,analysis.faceCount>0 else { lastBackend=analysis.faceCount>0 ? "美颜未开启" : "未检测到人脸，未执行美颜";return image }
        let scale=max(image.extent.width,image.extent.height)/1600
        let low=image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.4,CGFloat(settings.radius)*0.275*scale)]).cropped(to:image.extent)
        // Edge-preserving smoothing operates on low frequencies, not on the whole face output.
        let smooth=low.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.035,"inputSharpness":0.2]).cropped(to:image.extent)
        let textured: CIImage?
        if settings.strength>0 || settings.blemishRemoval>0 || settings.detailRecovery>0 { do {
            // Resolve the preceding lazy CI graph in its own working color space before
            // crossing into MetalPetal's separate CI context. Keep half-float precision.
            let metalInput: CIImage
            if let context,let cg=context.createCGImage(image,from:image.extent,format:.RGBAh,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) { metalInput=CIImage(cgImage:cg) }
            else { metalInput=image }
            if useMetalPetal,let filtered=try metalBeauty.apply(metalInput,settings:settings) {
                textured=detailKernel.apply(extent:image.extent,arguments:[image,low,filtered,settings.blemishRemoval,settings.texturePreservation,settings.detailRecovery,settings.blemishThreshold])
                lastBackend="MetalPetal 高通磨皮 + 纹理／五官保护"
            } else {
                textured=textureKernel.apply(extent:image.extent,arguments:[image,low,smooth,settings.strength*settings.smoothing,settings.blemishRemoval,settings.texturePreservation,settings.detailRecovery,settings.blemishThreshold])
                lastBackend="传统频率分离（MetalPetal 未启用或不可用）"
            }
        } catch {
            textured=textureKernel.apply(extent:image.extent,arguments:[image,low,smooth,settings.strength*settings.smoothing,settings.blemishRemoval,settings.texturePreservation,settings.detailRecovery,settings.blemishThreshold])
            lastBackend="MetalPetal 失败，已使用传统频率分离"
        }} else {textured=image;lastBackend="Core Image 独立肤色处理"}
        guard let textured,
              var toned=toneKernel.apply(extent:image.extent,arguments:[textured,low,settings.skinTone,settings.toneUniformity]) else { throw LumaError.invalidImage("美颜纹理合成") }
        if settings.skinTemperature != 6500 || settings.skinTint != 0 {toned=toned.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:CGFloat(settings.skinTemperature),y:CGFloat(settings.skinTint)),"inputTargetNeutral":CIVector(x:6500,y:0)])}
        if settings.skinBrightness != 0 {toned=toned.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:settings.skinBrightness])}
        if settings.skinSaturation != 1 {toned=toned.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:settings.skinSaturation])}
        if settings.shadowRepair>0 {toned=toned.applyingFilter("CIHighlightShadowAdjust",parameters:["inputShadowAmount":settings.shadowRepair,"inputHighlightAmount":1])}
        if settings.sharpness>0 {toned=toned.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:settings.sharpness*0.5])}
        var mask=analysis.mask
        if settings.intensiveSmoothing>0 || settings.skinWhitening>0 || settings.skinRosiness>0 {
            let wide=toned.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(1,CGFloat(settings.radius)*0.65*scale)]).cropped(to:image.extent)
            guard let strong=intensiveKernel.apply(extent:image.extent,arguments:[toned,wide,settings.intensiveSmoothing,settings.skinWhitening,settings.skinRosiness]) else {throw LumaError.invalidImage("强效美颜")}
            toned=strong
            let amount=CGFloat(settings.intensiveSmoothing*0.8),curve=CIVector(x:0,y:1+amount,z:-amount,w:0)
            mask=mask.applyingFilter("CIColorPolynomial",parameters:["inputRedCoefficients":curve,"inputGreenCoefficients":curve,"inputBlueCoefficients":curve])
            lastBackend += " + 强效磨皮／肤色"
        }
        let result=toned.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:mask]).cropped(to:image.extent)
        if settings.faceSlimming>0 || settings.eyeEnlargement>0 {lastBackend += " + Vision 人脸塑形"}
        return try shape.apply(result,settings:settings,faces:analysis.faces)
    }
}
