import Foundation
import CoreImage
import PhotoDomain

/// Local inverse-coordinate warps; no generated pixels or facial model weights.
final class FaceShapeProcessor {
    private let kernel: CIWarpKernel
    init() throws {
        guard let kernel=CIWarpKernel(source:"""
        kernel vec2 lumaFaceShape(vec4 face, vec2 leftEye, vec2 rightEye, float radius, float eyeAmount, float slimming) {
            vec2 p=destCoord();
            float nx=(p.x-face.x-face.z*0.5)/(face.z*0.55);
            float ny=(p.y-face.y-face.w*0.38)/(face.w*0.7);
            float lower=1.0-smoothstep(face.y+face.w*0.48,face.y+face.w*0.78,p.y);
            float shape=clamp(1.0-nx*nx-ny*ny,0.0,1.0)*lower;
            p.x+=(p.x-face.x-face.z*0.5)*slimming*0.45*shape;
            vec2 d=p-leftEye;
            float q=clamp(length(d)/radius,0.0,1.0);
            p-=d*eyeAmount*0.55*pow(1.0-q*q,2.0);
            d=p-rightEye;
            q=clamp(length(d)/radius,0.0,1.0);
            p-=d*eyeAmount*0.55*pow(1.0-q*q,2.0);
            return p;
        }
        """) else {throw LumaError.unsupported("人脸塑形内核编译失败")}
        self.kernel=kernel
    }
    func apply(_ image: CIImage,settings: BeautySettings,faces: [FaceFeatures]) throws -> CIImage {
        guard settings.faceSlimming>0 || settings.eyeEnlargement>0 else {return image}
        var output=image
        let extent=image.extent
        for features in faces {
            let b=features.bounds
            let bounds=CGRect(x:extent.minX+b.minX*extent.width,y:extent.minY+b.minY*extent.height,width:b.width*extent.width,height:b.height*extent.height)
            guard bounds.width>2,bounds.height>2 else {continue}
            func pixel(_ point: CGPoint?) -> CIVector {
                guard let point else {return CIVector(x:-100000,y:-100000)}
                return CIVector(x:extent.minX+point.x*extent.width,y:extent.minY+point.y*extent.height)
            }
            let padding=bounds.width*0.3
            guard let warped=kernel.apply(extent:extent,roiCallback:{_,rect in rect.insetBy(dx:-padding,dy:-padding)},image:output.clampedToExtent(),arguments:[CIVector(x:bounds.minX,y:bounds.minY,z:bounds.width,w:bounds.height),pixel(features.leftEye),pixel(features.rightEye),max(1,bounds.width*0.17),settings.eyeEnlargement,settings.faceSlimming]) else {throw LumaError.invalidImage("人脸塑形")}
            output=warped.cropped(to:extent)
        }
        return output
    }
}
