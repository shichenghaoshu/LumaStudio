import XCTest
import CoreImage
import Vision
import PhotoDomain
@testable import BeautyEngine
final class BeautyTests: XCTestCase {
    func testGuidedConstantPreserved() throws {
        let result=try GuidedFilter.apply(guide:[Float](repeating:0.4,count:64),input:[Float](repeating:0.7,count:64),width:8,height:8)
        XCTAssertTrue(result.allSatisfy{abs($0-0.7)<0.0001})
    }
    func testGuidedEdgePreservation() throws {
        let step=(0..<64).map{Float($0%8>=4 ? 1 : 0)}
        let result=try GuidedFilter.apply(guide:step,input:step,width:8,height:8,radius:3,epsilon:0.0001)
        XCTAssertLessThan(result[3],0.01);XCTAssertGreaterThan(result[4],0.99)
    }
    func testInvalidDimensionsRejected() {XCTAssertThrowsError(try GuidedFilter.apply(guide:[0],input:[0],width:2,height:2))}
    func testNoFaceHasZeroSkinMask() throws {
        let image=CIImage(color:CIColor(red:0.7,green:0.5,blue:0.4)).cropped(to:CGRect(x:0,y:0,width:64,height:64))
        let context=CIContext();let segmentation=SkinSegmentation();let analysis=try segmentation.analyze(image,context:context)
        XCTAssertEqual(analysis.faceCount,0)
        var bytes=[UInt8](repeating:255,count:64*64)
        context.render(analysis.mask,toBitmap:&bytes,rowBytes:64,bounds:image.extent,format:.L8,colorSpace:nil)
        XCTAssertEqual(bytes.max(),0)
        let engine=try BeautyProcessor();var settings=BeautySettings();settings.enabled=true
        let output=try engine.apply(image,settings:settings,analysis:analysis)
        XCTAssertEqual(output.extent,image.extent)
    }
    func testMissingModelFallsBack() {let s=SkinSegmentation(modelURL:URL(fileURLWithPath:"/missing/model.mlmodelc"));XCTAssertTrue(s.modelStatus.contains("传统"))}
    func testRealPortraitMaskExcludesBackground() throws {
        guard let fixture=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Set LUMA_PORTRAIT_FIXTURE for real portrait validation") }
        let url=URL(fileURLWithPath:fixture);let image=try XCTUnwrap(CIImage(contentsOf:url));let context=CIContext()
        let result=try SkinSegmentation().analyze(image,context:context)
        XCTAssertGreaterThan(result.faceCount,0)
        let tiny=result.mask.transformed(by:CGAffineTransform(scaleX:32/image.extent.width,y:32/image.extent.height));var bytes=[UInt8](repeating:0,count:1024)
        context.render(tiny,toBitmap:&bytes,rowBytes:32,bounds:CGRect(x:0,y:0,width:32,height:32),format:.L8,colorSpace:nil)
        XCTAssertGreaterThan(bytes.filter{$0>40}.count,3);XCTAssertLessThan(bytes.filter{$0>40}.count,512)
    }
    func testRealMetalPetalBeautyChangesSkinAndPreservesUnmaskedPixels() throws {
        guard let fixture=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Real portrait fixture optional") }
        let source=try XCTUnwrap(CIImage(contentsOf:URL(fileURLWithPath:fixture)))
        let scale=min(1,1600/max(source.extent.width,source.extent.height))
        let scaled=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale)),context=CIContext()
        // Match PhotoProcessor's materialized preview cache, avoiding a second affine resampling.
        let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(scaled,from:scaled.extent)))
        let engine=try BeautyProcessor()
        #if os(macOS)
        XCTAssertTrue(engine.metalPetalAvailable,"This Mac acceptance requires the actual GPU backend")
        #endif
        let analysis=try engine.segmentation.analyze(image,context:context)
        var settings=BeautySettings();settings.enabled=true;settings.strength=0.8
        let output=try engine.apply(image,settings:settings,analysis:analysis)
        XCTAssertTrue(engine.lastBackend.hasPrefix("MetalPetal"),engine.lastBackend)
        XCTAssertFalse(engine.lastBackend.contains("失败"))
        let w=Int(image.extent.width),h=Int(image.extent.height)
        var before=[UInt8](repeating:0,count:w*h*4),after=before,mask=[UInt8](repeating:0,count:w*h)
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        context.render(image,toBitmap:&before,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
        context.render(output,toBitmap:&after,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
        context.render(analysis.mask,toBitmap:&mask,rowBytes:w,bounds:image.extent,format:.L8,colorSpace:nil)
        let faceRequest=VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage:try XCTUnwrap(context.createCGImage(image,from:image.extent))).perform([faceRequest])
        let face=try XCTUnwrap(faceRequest.results?.first).boundingBox
        let allowed=face.insetBy(dx:-face.width*0.06,dy:-face.height*0.31)
        var changedSkin=0,unmaskedMax=0,skinSamples=0,alignedSkin=0
        for i in 0..<(w*h) {
            let delta=(0..<3).map{abs(Int(before[i*4+$0])-Int(after[i*4+$0]))}.max()!
            if mask[i]>80,delta>1 { changedSkin += 1 }
            if mask[i]>80 {
                skinSamples += 1
                if allowed.contains(CGPoint(x:Double(i%w)/Double(w),y:1-Double(i/w)/Double(h))) { alignedSkin += 1 }
            }
            if mask[i]==0 { unmaskedMax=max(unmaskedMax,delta) }
        }
        XCTAssertGreaterThan(changedSkin,100);XCTAssertLessThanOrEqual(unmaskedMax,1)
        XCTAssertGreaterThan(Double(alignedSkin)/Double(max(1,skinSamples)),0.95,"Skin mask must align with Vision face coordinates")
        if let evidence=ProcessInfo.processInfo.environment["LUMA_INTEGRATION_EVIDENCE"] {
            let dir=URL(fileURLWithPath:evidence);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try context.writePNGRepresentation(of:image,to:dir.appendingPathComponent("beauty-before.png"),format:.RGBA8,colorSpace:space)
            try context.writePNGRepresentation(of:output,to:dir.appendingPathComponent("beauty-after.png"),format:.RGBA8,colorSpace:space)
            try context.writePNGRepresentation(of:analysis.mask,to:dir.appendingPathComponent("beauty-mask.png"),format:.RGBA8,colorSpace:space)
            let report: [String:Any]=["backend":engine.lastBackend,"faces":analysis.faceCount,"changed_skin_pixels":changedSkin,"unmasked_max_delta_8bit":unmaskedMax,"width":w,"height":h,"scope":"one real portrait; algorithm execution and mask preservation, not broad aesthetic acceptance"]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("beauty-report.json"),options:.atomic)
        }
    }
}
