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
    private let momentKernel: CIColorKernel
    private let structureKernel: CIColorKernel
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
        """),let moment=CIColorKernel(source:"""
        kernel vec4 lumaSecondMoment(__sample original) {
            float y=dot(original.rgb,vec3(0.2126,0.7152,0.0722));
            return vec4(vec3(y*y),1.0);
        }
        """),let structure=CIColorKernel(source:"""
        kernel vec4 lumaStructure(__sample original, __sample mean, __sample moment, __sample toned, __sample soft, float smoothing, float preservation) {
            float y=dot(mean.rgb,vec3(0.2126,0.7152,0.0722));
            float variance=max(0.0,moment.r-y*y);
            // A local variance gate retains large facial structures while
            // shrinking small texture in flat skin. Keep a configurable floor.
            float edge=variance/(variance+0.0015);
            float retain=mix(0.04+0.50*preservation,1.0,edge);
            // Multiplicative reconstruction cannot introduce negative-channel
            // cyan halos at a dark nose/crease. Variance is measured on the fine
            // low-pass, so fine noise alone cannot trigger full reconstruction.
            vec3 detail=clamp(original.rgb/max(mean.rgb,vec3(0.015)),vec3(0.25),vec3(3.0));
            vec3 filtered=soft.rgb*mix(vec3(1.0),detail,retain);
            return vec4(mix(toned.rgb,filtered,smoothing*0.97),toned.a);
        }
        """),let intensive=CIColorKernel(source:"""
        kernel vec4 lumaIntensive(__sample original, float whitening, float rosy) {
            vec3 c=original.rgb;
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
        textureKernel=texture;toneKernel=tone;detailKernel=detail;intensiveKernel=intensive;momentKernel=moment;structureKernel=structure
    }
    public func apply(_ image: CIImage, settings: BeautySettings, analysis: SkinAnalysis,context: CIContext?=nil) throws -> CIImage {
        guard settings.enabled,analysis.faceCount>0 else { lastBackend=analysis.faceCount>0 ? "美颜未开启" : "未检测到人脸，未执行美颜";return image }
        let scale=max(image.extent.width,image.extent.height)/1600
        let low=image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.4,CGFloat(settings.radius)*0.275*scale)]).cropped(to:image.extent)
        let smoothing=settings.strength*settings.smoothing
        // No cross-context GPU synchronization is needed for independent repair
        // or recovery. The same frequency kernel handles both at strength zero.
        let smooth=smoothing>0 ? low.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.035,"inputSharpness":0.2]).cropped(to:image.extent) : low
        let textured: CIImage?
        if smoothing>0 || settings.blemishRemoval>0 || settings.texturePreservation*settings.detailRecovery>0 { do {
            // Resolve the preceding lazy CI graph in its own working color space before
            // crossing into MetalPetal's separate CI context. Keep half-float precision.
            let proposed=analysis.processingBounds.map{$0.insetBy(dx:-(CGFloat(settings.radius)*scale*3+12),dy:-(CGFloat(settings.radius)*scale*3+12)).integral.intersection(image.extent)} ?? image.extent
            let region=proposed.isNull || proposed.isEmpty ? image.extent:proposed
            let local=image.cropped(to:region).transformed(by:CGAffineTransform(translationX:-region.minX,y:-region.minY))
            let metalInput: CIImage
            if smoothing>0,useMetalPetal,metalBeauty.available,let context,let cg=context.createCGImage(local,from:local.extent,format:.RGBAh,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) { metalInput=CIImage(cgImage:cg) }
            else { metalInput=local }
            if smoothing>0,useMetalPetal,let processed=try metalBeauty.apply(metalInput,settings:settings,scale:scale) {
                // Only materialize the face union + blur support across the GPU
                // contexts. Translate it back before any mask/geometry operation.
                let filtered=processed.transformed(by:CGAffineTransform(translationX:region.minX,y:region.minY)).cropped(to:region).composited(over:image)
                textured=detailKernel.apply(extent:image.extent,arguments:[image,low,filtered,settings.blemishRemoval,settings.texturePreservation,settings.detailRecovery,settings.blemishThreshold])
                lastBackend="MetalPetal 高通磨皮 + 纹理／五官保护"
            } else {
                textured=textureKernel.apply(extent:image.extent,arguments:[image,low,smooth,smoothing,settings.blemishRemoval,settings.texturePreservation,settings.detailRecovery,settings.blemishThreshold])
                lastBackend=smoothing>0 ? "传统频率分离（MetalPetal 未启用或不可用）" : "传统频率分离 · 独立祛瑕／细节"
            }
        } catch {
            textured=textureKernel.apply(extent:image.extent,arguments:[image,low,smooth,settings.strength*settings.smoothing,settings.blemishRemoval,settings.texturePreservation,settings.detailRecovery,settings.blemishThreshold])
            lastBackend="MetalPetal 失败，已使用传统频率分离"
        }} else {textured=image;lastBackend="Core Image 独立肤色处理"}
        guard let textured else {throw LumaError.invalidImage("美颜纹理合成")}
        var toned=textured
        if settings.skinTone>0 {
            guard let tone=toneKernel.apply(extent:image.extent,arguments:[textured,low,settings.skinTone,settings.toneUniformity]) else {throw LumaError.invalidImage("肤色优化")}
            toned=tone
        }
        if settings.skinTemperature != 6500 || settings.skinTint != 0 {toned=toned.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:CGFloat(settings.skinTemperature),y:CGFloat(settings.skinTint)),"inputTargetNeutral":CIVector(x:6500,y:0)])}
        if settings.skinBrightness != 0 {toned=toned.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:settings.skinBrightness])}
        if settings.skinSaturation != 1 {toned=toned.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:settings.skinSaturation])}
        if settings.shadowRepair>0 {toned=toned.applyingFilter("CIHighlightShadowAdjust",parameters:["inputShadowAmount":settings.shadowRepair,"inputHighlightAmount":1])}
        if settings.intensiveSmoothing>0 {
            let radius=max(1,CGFloat(settings.radius)*0.65*scale)
            func blur(_ input:CIImage)->CIImage {input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:radius]).cropped(to:image.extent)}
            guard let moments=momentKernel.apply(extent:image.extent,arguments:[low]),
                  let strong=structureKernel.apply(extent:image.extent,arguments:[image,blur(low),blur(moments),toned,blur(toned),settings.intensiveSmoothing,settings.texturePreservation]) else {throw LumaError.invalidImage("保边强效磨皮")}
            toned=strong;lastBackend += " + 局部方差保边磨皮"
        }
        if settings.skinWhitening>0 || settings.skinRosiness>0 {
            guard let strong=intensiveKernel.apply(extent:image.extent,arguments:[toned,settings.skinWhitening,settings.skinRosiness]) else {throw LumaError.invalidImage("强效肤色")}
            toned=strong;lastBackend += " + 美白／红润"
        }
        if settings.sharpness>0 {toned=toned.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:settings.sharpness*0.5])}
        let result=toned.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:analysis.mask]).cropped(to:image.extent)
        if settings.faceSlimming>0 || settings.eyeEnlargement>0 {lastBackend += " + Vision 人脸塑形"}
        return try shape.apply(result,settings:settings,faces:analysis.faces)
    }
}
