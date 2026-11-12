import Foundation
import CoreImage
import Vision
import PhotoDomain

public struct PixelMetrics: Codable,Equatable,Sendable {
    public let meanLuminance: Double
    public let clippedHighlights: Double
    public let crushedShadows: Double
    public let meanSaturation: Double
    public let edgeEnergy: Double
    public let meanRed: Double,meanGreen: Double,meanBlue: Double
    public static func measure(_ image: CGImage,mask: CGImage?=nil) throws -> PixelMetrics {
        let scale=min(1,256/Double(max(image.width,image.height)))
        let w=max(2,Int(Double(image.width)*scale)),h=max(2,Int(Double(image.height)*scale))
        var bytes=[UInt8](repeating:0,count:w*h*4)
        guard let ctx=CGContext(data:&bytes,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LumaError.invalidImage("评价采样") }
        ctx.interpolationQuality = .medium;ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
        var weights=[UInt8](repeating:255,count:w*h)
        if let mask,let gray=CGContext(data:&weights,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) { gray.draw(mask,in:CGRect(x:0,y:0,width:w,height:h)) }
        var sum=0.0,lum=0.0,hi=0.0,lo=0.0,sat=0.0,edges=0.0,edgeCount=0.0,r=0.0,g=0.0,b=0.0
        var ys=[Double](repeating:0,count:w*h)
        for y in 0..<h { for x in 0..<w {
            let i=y*w+x,j=i*4,rr=Double(bytes[j])/255,gg=Double(bytes[j+1])/255,bb=Double(bytes[j+2])/255
            let v=0.2126*rr+0.7152*gg+0.0722*bb;ys[i]=v
            let weight=Double(weights[i])/255;sum += weight;lum += v*weight;r += rr*weight;g += gg*weight;b += bb*weight
            if v>=0.985 { hi += weight };if v<=0.015 { lo += weight }
            let mx=max(rr,max(gg,bb)),mn=min(rr,min(gg,bb));sat += (mx>0.001 ? (mx-mn)/mx : 0)*weight
            if x>0,y>0 { edges += (abs(v-ys[i-1])+abs(v-ys[i-w]))*weight;edgeCount += 2*weight }
        } }
        guard sum>1 else { throw LumaError.invalidImage("评价区域为空") }
        return PixelMetrics(meanLuminance:lum/sum,clippedHighlights:hi/sum,crushedShadows:lo/sum,meanSaturation:sat/sum,edgeEnergy:edges/max(1,edgeCount),meanRed:r/sum,meanGreen:g/sum,meanBlue:b/sum)
    }
}
public struct ImageAnalysis: Codable,Equatable,Sendable {
    public let width: Int,height: Int,faceCount: Int
    public let scene: String
    public let metrics: PixelMetrics
    public let availableMasks: [MaskKind]
    public let backend: String
    public init(image: CGImage,faceCount: Int,metrics: PixelMetrics) {
        width=image.width;height=image.height;self.faceCount=faceCount;self.metrics=metrics
        scene=faceCount>0 ? "portrait" : "general"
        availableMasks=[.face,.skin,.subject,.background];backend="Apple Vision + 确定性图像指标"
    }
}
public enum VisionAnalyzer {
    public static func analyze(_ image: CGImage) throws -> ImageAnalysis {
        let r=VNDetectFaceRectanglesRequest()
        #if targetEnvironment(simulator)
        r.usesCPUOnly=true
        #endif
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([r])
        return ImageAnalysis(image:image,faceCount:r.results?.count ?? 0,metrics:try PixelMetrics.measure(image))
    }
}
public final class SemanticMaskEngine {
    public init() {}
    public func masks(for image: CIImage,kinds: Set<MaskKind>,skin: CIImage?,context: CIContext) throws -> [MaskKind:CIImage] {
        let extent=image.extent
        var output=[MaskKind:CIImage]()
        if kinds.contains(.skin),let skin { output[.skin]=skin }
        if kinds.contains(.hair)||kinds.contains(.sky) { throw LumaError.unsupported("头发与天空的专用分割模型尚未安装") }
        guard !kinds.subtracting([.skin]).isEmpty else { return output }
        let scale=min(1,512/max(extent.width,extent.height))
        let small=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        guard let cg=context.createCGImage(small,from:small.extent) else { throw LumaError.invalidImage("局部分割输入") }
        if kinds.contains(.face) {
            let r=VNDetectFaceRectanglesRequest();try VNImageRequestHandler(cgImage:cg,options:[:]).perform([r])
            guard let faces=r.results,!faces.isEmpty else { throw LumaError.unsupported("未检测到人脸，未应用人脸局部调整") }
            let w=cg.width,h=cg.height;var pixels=[UInt8](repeating:0,count:w*h)
            for face in faces { let box=face.boundingBox
                for y in 0..<h { for x in 0..<w {
                    let dx=(Double(x)/Double(w)-box.midX)/(box.width*0.55),dy=(1-Double(y)/Double(h)-box.midY)/(box.height*0.65)
                    let a=max(0,min(1,(1-dx*dx-dy*dy)*6));let i=y*w+x;pixels[i]=max(pixels[i],UInt8(a*255))
                } }
            }
            output[.face]=CIImage(bitmapData:Data(pixels),bytesPerRow:w,size:CGSize(width:w,height:h),format:.L8,colorSpace:nil).transformed(by:CGAffineTransform(scaleX:extent.width/CGFloat(w),y:extent.height/CGFloat(h)))
        }
        if kinds.contains(.subject)||kinds.contains(.background) {
            let r=VNGeneratePersonSegmentationRequest();r.qualityLevel = .balanced;r.outputPixelFormat=kCVPixelFormatType_OneComponent8
            #if targetEnvironment(simulator)
            r.usesCPUOnly=true
            #endif
            try VNImageRequestHandler(cgImage:cg,options:[:]).perform([r])
            guard let result=r.results?.first else { throw LumaError.unsupported("人物分割没有返回结果") }
            let buffer=result.pixelBuffer
            let mask=CIImage(cvPixelBuffer:buffer).transformed(by:CGAffineTransform(scaleX:extent.width/CGFloat(CVPixelBufferGetWidth(buffer)),y:extent.height/CGFloat(CVPixelBufferGetHeight(buffer)))).cropped(to:extent)
            if kinds.contains(.subject) { output[.subject]=mask }
            if kinds.contains(.background) { output[.background]=mask.applyingFilter("CIColorInvert").cropped(to:extent) }
        }
        return output
    }
}
