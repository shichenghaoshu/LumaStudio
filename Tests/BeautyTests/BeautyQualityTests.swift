import XCTest
import CoreImage
import PhotoDomain
@testable import BeautyEngine

final class BeautyQualityTests: XCTestCase {
    private let context=CIContext()
    private let space=CGColorSpace(name:CGColorSpace.sRGB)!
    private func neutral()->BeautySettings {
        var b=BeautySettings();b.enabled=true;b.strength=0;b.skinTone=0;b.blemishRemoval=0;b.detailRecovery=0;b.texturePreservation=0
        return b
    }
    private func pixels(_ image:CIImage)->[UInt8] {
        let w=Int(image.extent.width),h=Int(image.extent.height)
        var bytes=[UInt8](repeating:0,count:w*h*4)
        context.render(image,toBitmap:&bytes,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
        return bytes
    }
    func testStrongSmoothingReducesNoiseWithoutWashingOutStructure() throws {
        let w=512,h=384,rect=CGRect(x:0,y:0,width:w,height:h)
        var clean=[UInt8](repeating:255,count:w*h*4),noisy=clean
        for y in 0..<h {for x in 0..<w {
            var rgb=x<256 ? [0.55,0.39,0.3] : [0.73,0.58,0.47]
            if (116..<126).contains(x) {rgb=rgb.map{$0*0.55}} // known nose/fold-sized dark structure
            let noise=Double((x*37+y*43)%31-15)/600
            for c in 0..<3 {clean[(y*w+x)*4+c]=UInt8((rgb[c]*255).rounded());noisy[(y*w+x)*4+c]=UInt8(((rgb[c]+noise)*255).rounded())}
        }}
        func image(_ bytes:[UInt8])->CIImage {CIImage(bitmapData:Data(bytes),bytesPerRow:w*4,size:rect.size,format:.RGBA8,colorSpace:space)}
        let input=image(noisy),engine=try BeautyProcessor(),mask=SkinAnalysis(mask:CIImage(color:.white).cropped(to:rect),faceCount:1,backend:"Known mask")
        var settings=neutral();settings.intensiveSmoothing=1;settings.radius=32
        let output=try engine.apply(input,settings:settings,analysis:mask,context:context),after=pixels(output)
        // Independent reference for the preceding whole-image Gaussian mechanism.
        let blurred=input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:32*0.65*Double(w)/1600]).cropped(to:rect)
        let gaussian=pixels(blurred)
        func rmse(_ a:[UInt8],xs:Range<Int>)->Double {
            var sum=0.0,n=0
            for y in 32..<(h-32) {for x in xs {for c in 0..<3 {let i=(y*w+x)*4+c,d=Double(a[i])-Double(clean[i]);sum+=d*d;n+=1}}}
            return sqrt(sum/Double(n))
        }
        let noiseBefore=rmse(noisy,xs:32..<96),noiseAfter=rmse(after,xs:32..<96)
        let edge=rmse(after,xs:248..<264),blurEdge=rmse(gaussian,xs:248..<264)
        let fold=rmse(after,xs:108..<134),blurFold=rmse(gaussian,xs:108..<134)
        XCTAssertLessThan(noiseAfter,noiseBefore*0.75,"Strong smoothing must still remove actual known noise")
        XCTAssertLessThan(edge,blurEdge*0.6,"Preserve the known structural step instead of merely lowering smoothing strength")
        XCTAssertLessThan(fold,blurFold*0.6,"Keep a narrow dark facial structure")
        if let root=ProcessInfo.processInfo.environment["LUMA_BEAUTY_QUALITY"] {
            let folder=URL(fileURLWithPath:root);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let report:[String:Any]=["scope":"Known clean synthetic skin and deterministic noise; no aesthetic score","noise_before_rmse_8bit":noiseBefore,"noise_after_rmse_8bit":noiseAfter,"edge_rmse_8bit":edge,"gaussian_edge_rmse_8bit":blurEdge,"fold_rmse_8bit":fold,"gaussian_fold_rmse_8bit":blurFold]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("quality.json"))
            for (name,result) in [("clean",image(clean)),("noisy",input),("gaussian",blurred),("output",output)] {
                try context.writePNGRepresentation(of:result,to:folder.appendingPathComponent("synthetic-"+name+".png"),format:.RGBA8,colorSpace:space)
            }
        }
    }
}
