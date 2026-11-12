import Foundation
import CoreImage
#if os(macOS)
import Metal
import MetalPetal
#endif

/// Actual upstream GPU filter, with explicit sRGB conversion and half-float intermediates.
final class MetalPetalBeauty {
    #if os(macOS)
    private let context: MTIContext?
    init() {
        if let device=MTLCreateSystemDefaultDevice(),MTIHighPassSkinSmoothingFilter.isSupported(on:device) { context=try? MTIContext(device:device) }
        else { context=nil }
    }
    var available: Bool { context != nil }
    func apply(_ image: CIImage,strength: Float,preservation: Float) throws -> CIImage? {
        guard let context else { return nil }
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        let options=MTICIImageRenderingOptions(destinationPixelFormat:.rgba16Float,colorSpace:space,flipped:true)
        // Upstream tone-curve LUT coordinates assume SDR [0,1]. Extended highlights
        // from exposure/white balance otherwise sample past the LUT and lose red.
        let bounded=image.applyingFilter("CIColorClamp",parameters:["inputMinComponents":CIVector(x:0,y:0,z:0,w:0),"inputMaxComponents":CIVector(x:1,y:1,z:1,w:1)])
        let input=MTIImage(ciImage:bounded,isOpaque:true,options:options)
        let filter=MTIHighPassSkinSmoothingFilter()
        filter.inputImage=input
        filter.outputPixelFormat = .rgba16Float
        filter.amount=strength*max(0.25,1-(preservation-0.6)*1.3)
        filter.radius=Float(max(2,8*max(image.extent.width,image.extent.height)/1600))
        // The upstream high-pass mask applies this gentle lift to skin texture.
        filter.toneCurveControlPoints=[MTIVector(values:[Float(0),0]),MTIVector(values:[Float(120)/255,Float(138)/255]),MTIVector(values:[Float(1),1])]
        guard let output=filter.outputImage else { return nil }
        let persistent=output.withCachePolicy(.persistent)
        // makeCIImage waits only until scheduling; a different CI command queue must
        // not sample that texture before MetalPetal has actually finished writing it.
        let task=try context.startTask(toRender:persistent,completion:nil)
        task.waitUntilCompleted()
        if let error=task.error { throw error }
        return try context.makeCIImage(from:persistent,options:MTICIImageCreationOptions(colorSpace:space,flipped:true)).cropped(to:image.extent)
    }
    #else
    init() {}
    var available: Bool { false }
    func apply(_ image: CIImage,strength: Float,preservation: Float) throws -> CIImage? { nil }
    #endif
}
