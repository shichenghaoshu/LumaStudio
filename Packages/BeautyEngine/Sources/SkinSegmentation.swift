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
    public init(mask: CIImage,faceCount: Int,backend: String,faces: [FaceFeatures]=[]) {
        self.mask=mask;self.faceCount=faceCount;self.backend=backend;self.faces=faces
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
        var pixels=[UInt8](repeating:0,count:w*h*4)
        context.render(small,toBitmap:&pixels,rowBytes:w*4,bounds:CGRect(x:0,y:0,width:w,height:h),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        var mask=[Float](repeating:0,count:w*h), guide=mask
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
                let i=(y*w+x)*4, r=Float(pixels[i])/255,g=Float(pixels[i+1])/255,b=Float(pixels[i+2])/255
                cbs.append(-0.168736*r-0.331264*g+0.5*b); crs.append(0.5*r-0.418688*g-0.081312*b)
            } }
            return FaceGeometry(rect:rect,excluded:excluded,cb:cbs.reduce(0,+)/4,cr:crs.reduce(0,+)/4)
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
                let neck=point.y<box.minY+box.height*0.08 && point.y>box.minY-box.height*0.28 && abs(point.x-box.midX)<box.width*0.28
                guard (ellipse<1 || neck),l>0.025,l<0.985 else { continue }
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
                let warm: Float = r>b*0.82 && cr > -0.025 ? 1 : 0.15
                let faceFeather=smooth((1-ellipse)*6)
                let neckFeather=neck ? 0.5*smooth((1-abs(point.x-box.midX)/(box.width*0.28))*3)*smooth((point.y-box.minY+box.height*0.28)/(box.height*0.12)) : 0
                mask[i]=max(mask[i],chroma*warm*max(faceFeather,neckFeather)*protected)
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
        let refined=try GuidedFilter.apply(guide:guide,input:mask,width:w,height:h,radius:3)
        // Reapply exclusion after guided filtering so eyes/lips remain exactly protected.
        let bytes=refined.indices.map { UInt8(min(255,max(0,mask[$0] == 0 ? 0 : refined[$0]*255))) }
        let maskImage=CIImage(bitmapData:Data(bytes),bytesPerRow:w,size:CGSize(width:w,height:h),format:.L8,colorSpace:nil)
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
        return SkinAnalysis(mask:maskImage,faceCount:faces.count,backend:backend,faces:features)
    }
}
