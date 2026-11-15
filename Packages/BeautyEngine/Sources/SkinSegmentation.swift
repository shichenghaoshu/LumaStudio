import Foundation
import Vision
import CoreML
import CoreImage
import PhotoDomain

public struct SkinAnalysis {
    public let mask: CIImage
    public let faceCount: Int
    public let backend: String
    public let faces: [FaceFeatures]
    /// Pixel coordinates containing all nonzero skin support. Nil keeps the full
    /// frame for externally supplied masks; this never replaces the actual mask.
    public let processingBounds: CGRect?
    public init(mask: CIImage,faceCount: Int,backend: String,faces: [FaceFeatures]=[],processingBounds:CGRect?=nil) {
        self.mask=mask;self.faceCount=faceCount;self.backend=backend;self.faces=faces;self.processingBounds=processingBounds
    }
}
public struct FaceFeatures {
    public let bounds: CGRect
    public let leftEye: CGPoint?
    public let rightEye: CGPoint?
    public init(bounds: CGRect,leftEye: CGPoint?=nil,rightEye: CGPoint?=nil) {
        self.bounds=bounds;self.leftEye=leftEye;self.rightEye=rightEye
    }
}
/// No unlicensed weights are bundled. A validated single-channel probability Core ML
/// model can be loaded locally; landmarks + adaptive color remain the safe fallback.
public final class SkinSegmentation {
    private var model: VNCoreMLModel?
    public private(set) var modelStatus = "Vision 关键点 + 传统皮肤分割"
    public init(modelURL: URL? = nil) {
        if let modelURL {
            do {
                let configuration=MLModelConfiguration(); configuration.computeUnits = .all
                let compiled=modelURL.pathExtension == "mlmodelc" ? modelURL : try MLModel.compileModel(at:modelURL)
                let ml=try MLModel(contentsOf:compiled,configuration:configuration)
                guard ml.modelDescription.inputDescriptionsByName.values.contains(where:{$0.type == .image}) else { throw LumaError.unsupported("模型需要图像输入") }
                model=try VNCoreMLModel(for:ml); modelStatus="本地 Core ML 皮肤概率模型 + Vision"
            } catch { modelStatus="模型加载失败，已使用传统分割"; LumaLog.pipeline.error("皮肤模型加载失败，使用传统算法") }
        }
    }
    public func analyze(_ image: CIImage, context: CIContext) throws -> SkinAnalysis {
        let extent=image.extent; let scale=min(1,320/max(extent.width,extent.height))
        let small=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        guard let cg=context.createCGImage(small,from:small.extent) else { throw LumaError.invalidImage("人脸分析输入") }
        let request=VNDetectFaceLandmarksRequest()
        #if targetEnvironment(simulator)
        // The simulator has no Neural Engine. Keep genuine Vision inference on CPU.
        request.usesCPUOnly=true
        #endif
        try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
        let faces=request.results ?? []; let w=cg.width,h=cg.height
        guard !faces.isEmpty else {
            return SkinAnalysis(mask:CIImage(color:.black).cropped(to:extent),faceCount:0,backend:modelStatus)
        }
        var pixels=[UInt8](repeating:0,count:w*h*4)
        context.render(small,toBitmap:&pixels,rowBytes:w*4,bounds:CGRect(x:0,y:0,width:w,height:h),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        var mask=[Float](repeating:0,count:w*h), guide=mask,support=mask
        struct FaceGeometry { let rect: CGRect; let excluded: [CGRect]; let cb: Float; let cr: Float }
        let geometry=faces.map { face -> FaceGeometry in
            let rect=face.boundingBox
            let landmarks=face.landmarks
            let regions=[landmarks?.leftEye,landmarks?.rightEye,landmarks?.leftEyebrow,landmarks?.rightEyebrow,landmarks?.outerLips]
            let excluded=regions.compactMap { region -> CGRect? in
                guard let points=region?.normalizedPoints,!points.isEmpty else { return nil }
                let xs=points.map{rect.minX+CGFloat($0.x)*rect.width},ys=points.map{rect.minY+CGFloat($0.y)*rect.height}
                return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!).insetBy(dx:-0.035*rect.width,dy:-0.025*rect.height)
            }
            // Cheek chroma adapts the probability to the individual, not one target skin tone.
            var cbs=[Float](),crs=[Float]()
            for fx in [0.28,0.72] { for fy in [0.36,0.46] {
                let x=min(w-1,max(0,Int((rect.minX+rect.width*fx)*CGFloat(w)))),y=min(h-1,max(0,Int((1-rect.minY-rect.height*fy)*CGFloat(h))))
                // A small median patch is less sensitive to one pore, highlight,
                // compression block or stray landmark than a single pixel.
                for py in max(0,y-1)...min(h-1,y+1) {for px in max(0,x-1)...min(w-1,x+1) {
                    let j=(py*w+px)*4,r=Float(pixels[j])/255,g=Float(pixels[j+1])/255,b=Float(pixels[j+2])/255
                    let l=0.2126*r+0.7152*g+0.0722*b
                    if l>0.04,l<0.96 {cbs.append(-0.168736*r-0.331264*g+0.5*b);crs.append(0.5*r-0.418688*g-0.081312*b)}
                }}
            } }
            func median(_ values:[Float])->Float {let sorted=values.sorted();return sorted.isEmpty ? 0 : sorted[sorted.count/2]}
            return FaceGeometry(rect:rect,excluded:excluded,cb:median(cbs),cr:median(crs))
        }
        for y in 0..<h { for x in 0..<w {
            let i=y*w+x,j=i*4,r=Float(pixels[j])/255,g=Float(pixels[j+1])/255,b=Float(pixels[j+2])/255
            let l=0.2126*r+0.7152*g+0.0722*b; guide[i]=l
            // CIContext bitmap rows run top-to-bottom; Vision coordinates start bottom-left.
            let point=CGPoint(x:Double(x)/Double(w),y:1-Double(y)/Double(h))
            for face in geometry {
                let box=face.rect
                let nx=(point.x-box.midX)/(box.width*0.49), ny=(point.y-(box.midY+box.height*0.03))/(box.height*0.61)
                let ellipse=nx*nx+ny*ny
                let neckX=(point.x-box.midX)/(box.width*0.28),neckY=(point.y-box.minY+box.height*0.06)/(box.height*0.22)
                let neckEllipse=neckX*neckX+neckY*neckY
                guard ellipse<1 || neckEllipse<1 else { continue }
                func smooth(_ value: CGFloat)->Float {let t=min(1,max(0,Float(value)));return t*t*(3-2*t)}
                var protected: Float=1
                for feature in face.excluded {
                    let fx=(point.x-feature.midX)/max(0.0001,feature.width*0.6)
                    let fy=(point.y-feature.midY)/max(0.0001,feature.height*0.7)
                    protected *= smooth((sqrt(fx*fx+fy*fy)-0.75)/0.65)
                }
                guard protected>0 else {continue}
                let cb = -0.168736*r-0.331264*g+0.5*b, cr=0.5*r-0.418688*g-0.081312*b
                let chroma=exp(-pow((cb-face.cb)/0.11,2)-pow((cr-face.cr)/0.13,2))
                // Continuous cues avoid a hard 1 -> .15 jump at the color test.
                let warm=0.15+0.85*smooth(CGFloat((r-b*0.82+0.015)/0.06))*smooth(CGFloat((cr+0.045)/0.04))
                let light=smooth(CGFloat((l-0.02)/0.04))*(1-smooth(CGFloat((l-0.94)/0.055)))
                let faceFeather=smooth((1-ellipse)*6)
                let neckFeather=0.5*smooth((1-neckEllipse)*3)
                let allowed=max(faceFeather,neckFeather)*protected
                support[i]=max(support[i],allowed)
                mask[i]=max(mask[i],chroma*warm*light*allowed)
            }
        } }
        var backend=modelStatus
        if let model {
            do {
                let inference=VNCoreMLRequest(model:model); inference.imageCropAndScaleOption = .scaleFill
                try VNImageRequestHandler(cgImage:cg,options:[:]).perform([inference])
                guard let observation=inference.results?.first as? VNPixelBufferObservation else { throw LumaError.corruptData("模型输出不是概率图") }
                let buffer=observation.pixelBuffer
                guard [kCVPixelFormatType_OneComponent8,kCVPixelFormatType_OneComponent16Half,kCVPixelFormatType_OneComponent32Float].contains(CVPixelBufferGetPixelFormatType(buffer)) else { throw LumaError.unsupported("模型必须输出单通道皮肤概率") }
                let result=CIImage(cvPixelBuffer:buffer).transformed(by:CGAffineTransform(scaleX:CGFloat(w)/CGFloat(CVPixelBufferGetWidth(buffer)),y:CGFloat(h)/CGFloat(CVPixelBufferGetHeight(buffer))))
                var probabilities=[Float](repeating:0,count:w*h)
                context.render(result,toBitmap:&probabilities,rowBytes:w*4,bounds:CGRect(x:0,y:0,width:w,height:h),format:.Rf,colorSpace:nil)
                for i in mask.indices { mask[i] *= min(1,max(0,probabilities[i])) }
            } catch { backend="模型推理失败 · 传统分割"; LumaLog.pipeline.error("皮肤模型推理失败，使用传统算法") }
        }
        let refined=try SkinMaskRefinement.apply(guide:guide,probability:mask,support:support,width:w,height:h)
        // Retain the continuous probability through enlargement. Geometry and
        // feature support cap the refinement, without reintroducing color cuts.
        let data=refined.withUnsafeBytes {Data($0)}
        let maskImage=CIImage(bitmapData:data,bytesPerRow:w*MemoryLayout<Float>.stride,size:CGSize(width:w,height:h),format:.Lf,colorSpace:nil)
            .transformed(by:CGAffineTransform(scaleX:extent.width/CGFloat(w),y:extent.height/CGFloat(h))).cropped(to:extent)
        let features=faces.map { face -> FaceFeatures in
            func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
                guard let points=region?.normalizedPoints,!points.isEmpty else {return nil}
                let x=points.map{CGFloat($0.x)}.reduce(0,+)/CGFloat(points.count)
                let y=points.map{CGFloat($0.y)}.reduce(0,+)/CGFloat(points.count)
                return CGPoint(x:face.boundingBox.minX+x*face.boundingBox.width,y:face.boundingBox.minY+y*face.boundingBox.height)
            }
            return FaceFeatures(bounds:face.boundingBox,leftEye:center(face.landmarks?.leftEye),rightEye:center(face.landmarks?.rightEye))
        }
        let skinBounds=geometry.map {g -> CGRect in
            let b=g.rect
            return CGRect(x:extent.minX+(b.midX-b.width*0.49)*extent.width,
                          y:extent.minY+(b.minY-b.height*0.28)*extent.height,
                          width:b.width*0.98*extent.width,height:b.height*1.42*extent.height)
        }.reduce(CGRect.null){$0.union($1)}.intersection(extent)
        return SkinAnalysis(mask:maskImage,faceCount:faces.count,backend:backend,faces:features,processingBounds:skinBounds.isNull ? nil:skinBounds)
    }
}

enum SkinMaskRefinement {
    static func apply(guide:[Float],probability:[Float],support:[Float],width:Int,height:Int)throws->[Float] {
        guard support.count==probability.count else {throw LumaError.corruptData("皮肤保护区域尺寸")}
        let filtered=try GuidedFilter.apply(guide:guide,input:probability,width:width,height:height,radius:3)
        return filtered.indices.map {min(max(0,support[$0]),filtered[$0])}
    }
}
