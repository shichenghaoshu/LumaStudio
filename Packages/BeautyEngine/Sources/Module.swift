import Foundation
import CoreImage
import PhotoDomain

public final class BeautyProcessor {
    public let segmentation: SkinSegmentation
    // Core Image compiles these compact kernels locally and schedules them on Metal.
    private let textureKernel: CIColorKernel
    private let toneKernel: CIColorKernel
    private let detailKernel: CIColorKernel
    private let metalBeauty=MetalPetalBeauty()
    public private(set) var lastBackend="美颜未开启"
    public var metalPetalAvailable: Bool { metalBeauty.available }
    public init(modelURL: URL? = nil) throws {
        segmentation=SkinSegmentation(modelURL:modelURL)
        guard let texture=CIColorKernel(source:"""
        kernel vec4 lumaTexture(__sample original, __sample low, __sample smoothLow, float strength, float repair, float preservation) {
            vec3 detail = original.rgb - low.rgb;
            float redness = max(0.0, original.r - 0.5*(original.g+original.b) - (low.r-0.5*(low.g+low.b)));
            float darkSpot = max(0.0, dot(low.rgb-original.rgb, vec3(0.2126,0.7152,0.0722)));
            // Small red/dark anomalies are attenuated gently; default never erases all marks.
            float anomaly = smoothstep(0.025,0.09,redness) * smoothstep(0.005,0.07,darkSpot);
            float keep = preservation - repair * anomaly * 0.22;
            vec3 retouched = smoothLow.rgb + detail * keep;
            return vec4(mix(original.rgb, retouched, strength), original.a);
        }
        """), let tone=CIColorKernel(source:"""
        kernel vec4 lumaTone(__sample original, __sample low, float amount) {
            float y = dot(original.rgb, vec3(0.2126,0.7152,0.0722));
            float mid = smoothstep(0.08,0.3,y) * (1.0-smoothstep(0.72,0.98,y));
            vec3 chroma = original.rgb - vec3(y);
            float ly = dot(low.rgb, vec3(0.2126,0.7152,0.0722));
            vec3 uniformChroma = low.rgb - vec3(ly);
            vec3 result = vec3(y + 0.018*amount*mid) + mix(chroma,uniformChroma,amount*0.16*mid);
            return vec4(result,original.a);
        }
        """),let detail=CIColorKernel(source:"""
        kernel vec4 lumaMetalDetail(__sample original, __sample low, __sample filtered, float repair, float preservation) {
            vec3 detail = original.rgb-low.rgb;
            float redSpot=max(0.0,detail.r-0.5*(detail.g+detail.b));
            float darkSpot=max(0.0,-dot(detail,vec3(0.2126,0.7152,0.0722)));
            float anomaly=smoothstep(0.025,0.09,redSpot)*smoothstep(0.005,0.07,darkSpot);
            // Restore extended-range energy that the SDR beauty LUT cannot process.
            vec3 headroom=original.rgb-clamp(original.rgb,0.0,1.0);
            vec3 result=filtered.rgb+headroom+detail*preservation*0.04;
            result=mix(result,low.rgb,repair*anomaly*0.18);
            return vec4(result,original.a);
        }
        """) else { throw LumaError.unsupported("Core Image 纹理内核编译失败") }
        textureKernel=texture;toneKernel=tone;detailKernel=detail
    }
    public func apply(_ image: CIImage, settings: BeautySettings, analysis: SkinAnalysis,context: CIContext?=nil) throws -> CIImage {
        guard settings.enabled,settings.strength>0,analysis.faceCount>0 else { lastBackend=analysis.faceCount>0 ? "美颜未开启" : "未检测到人脸，未执行美颜";return image }
        let scale=max(image.extent.width,image.extent.height)/1600
        let low=image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(1.2,2.2*scale)]).cropped(to:image.extent)
        // Edge-preserving smoothing operates on low frequencies, not on the whole face output.
        let smooth=low.applyingFilter("CINoiseReduction",parameters:["inputNoiseLevel":0.035,"inputSharpness":0.2]).cropped(to:image.extent)
        let textured: CIImage?
        do {
            // Resolve the preceding lazy CI graph in its own working color space before
            // crossing into MetalPetal's separate CI context. Keep half-float precision.
            let metalInput: CIImage
            if let context,let cg=context.createCGImage(image,from:image.extent,format:.RGBAh,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) { metalInput=CIImage(cgImage:cg) }
            else { metalInput=image }
            if let filtered=try metalBeauty.apply(metalInput,strength:settings.strength,preservation:settings.texturePreservation) {
                textured=detailKernel.apply(extent:image.extent,arguments:[image,low,filtered,settings.blemishRemoval,settings.texturePreservation])
                lastBackend="MetalPetal 高通磨皮 + 纹理／五官保护"
            } else {
                textured=textureKernel.apply(extent:image.extent,arguments:[image,low,smooth,settings.strength,settings.blemishRemoval,settings.texturePreservation])
                lastBackend="传统频率分离（MetalPetal 在当前设备不可用）"
            }
        } catch {
            textured=textureKernel.apply(extent:image.extent,arguments:[image,low,smooth,settings.strength,settings.blemishRemoval,settings.texturePreservation])
            lastBackend="MetalPetal 失败，已使用传统频率分离"
        }
        guard let textured,
              let toned=toneKernel.apply(extent:image.extent,arguments:[textured,low,settings.skinTone*settings.strength]) else { throw LumaError.invalidImage("美颜纹理合成") }
        return toned.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:analysis.mask]).cropped(to:image.extent)
    }
}
