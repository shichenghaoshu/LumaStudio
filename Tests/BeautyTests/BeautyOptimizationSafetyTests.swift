import XCTest
import CoreImage
import PhotoDomain
@testable import BeautyEngine

final class BeautyOptimizationSafetyTests: XCTestCase {
    func testMaskRefinementSoftensColorCutsAndKeepsFeatureSupportExactlyZero() throws {
        let w=64,h=32
        var support=[Float](repeating:0,count:w*h),probability=support
        for y in 0..<h {for x in 0..<w {
            let i=y*w+x
            if x>=8,x<56,y>=4,y<28 {support[i]=1}
            if (24..<28).contains(x),(12..<20).contains(y) {support[i]=0} // protected eye
            probability[i]=x<32 ? 0.8*support[i]:0 // known color-probability cut
        }}
        let guide=[Float](repeating:0.5,count:w*h)
        let filtered=try GuidedFilter.apply(guide:guide,input:probability,width:w,height:h,radius:3)
        let old=filtered.indices.map{probability[$0]==0 ? 0:filtered[$0]}
        let result=try SkinMaskRefinement.apply(guide:guide,probability:probability,support:support,width:w,height:h)
        for i in result.indices {
            XCTAssertGreaterThanOrEqual(result[i],0);XCTAssertLessThanOrEqual(result[i],support[i])
            if support[i]==0 {XCTAssertEqual(result[i],0,"Never leak into a protected eye or background")}
        }
        XCTAssertGreaterThan(result[8*w+32],0,"Do not reintroduce a binary color cut after refinement")
        func jump(_ a:[Float])->Float {(30...35).map{abs(a[8*w+$0]-a[8*w+$0-1])}.max()!}
        XCTAssertLessThan(jump(result),jump(old)*0.5)
    }
    func testFaceRegionRenderingMatchesWholeFrameWithBlurSupportAndCoordinates() throws {
        guard let fixture=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else {throw XCTSkip("Public real portrait optional outside acceptance")}
        let context=CIContext(),engine=try BeautyProcessor(),source=try XCTUnwrap(CIImage(contentsOf:URL(fileURLWithPath:fixture)))
        let scale=1600/max(source.extent.width,source.extent.height),small=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(small,from:small.extent)))
        let local=try engine.segmentation.analyze(image,context:context),bounds=try XCTUnwrap(local.processingBounds)
        XCTAssertLessThan(bounds.width*bounds.height,image.extent.width*image.extent.height*0.5)
        let full=SkinAnalysis(mask:local.mask,faceCount:local.faceCount,backend:local.backend,faces:local.faces)
        let input=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.35]).applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:7200,y:0),"inputTargetNeutral":CIVector(x:6500,y:0)])
        let w=Int(image.extent.width),h=Int(image.extent.height)
        func data(_ ci:CIImage)->[UInt8] {var bytes=[UInt8](repeating:0,count:w*h*4);context.render(ci,toBitmap:&bytes,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!);return bytes}
        var records=[[String:Any]]()
        for style in [BeautyStyle.natural,.intensive,.reshape] {
            let a=data(try engine.apply(input,settings:style.settings,analysis:local,context:context))
            let b=data(try engine.apply(input,settings:style.settings,analysis:full,context:context))
            let delta=zip(a,b).map{abs(Int($0)-Int($1))}.max()!
            XCTAssertLessThanOrEqual(delta,2,"Cropping must preserve color, blur scale, orientation and placement: \(style)")
            records.append(["style":style.rawValue,"maxChannelDifference8bit":delta])
        }
        if let root=ProcessInfo.processInfo.environment["LUMA_BEAUTY_QUALITY"] {
            try JSONSerialization.data(withJSONObject:["scope":"Cropped GPU transfer vs complete frame, real portrait at 1600px with exposure and white balance","checks":records],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent("region-parity.json"))
        }
    }
    func testStrongSmoothingKeepsConstantExtendedRangeAndDarkValuesFinite() throws {
        let context=CIContext(),engine=try BeautyProcessor(useMetalPetal:false),rect=CGRect(x:0,y:0,width:128,height:128)
        var settings=BeautySettings();settings.enabled=true;settings.strength=0;settings.skinTone=0;settings.blemishRemoval=0;settings.detailRecovery=0;settings.intensiveSmoothing=1
        let mask=SkinAnalysis(mask:CIImage(color:.white).cropped(to:rect),faceCount:1,backend:"Known full mask")
        for color in [CIColor(red:1.8,green:1.2,blue:0.8),CIColor(red:0.001,green:0.002,blue:0.003)] {
            let original=CIImage(color:color).cropped(to:rect)
            let output=try engine.apply(original,settings:settings,analysis:mask,context:context)
            func values(_ ci:CIImage)->[Float] {
                var result=[Float](repeating:0,count:128*128*4)
                context.render(ci,toBitmap:&result,rowBytes:128*16,bounds:rect,format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!)
                return result
            }
            let a=values(original),b=values(output)
            XCTAssertTrue(b.allSatisfy{$0.isFinite})
            XCTAssertLessThan(zip(a,b).map{abs($0-$1)}.max()!,0.002,"Flat extended highlights and dark skin must not be clipped or shifted")
        }
    }
    func testIndependentRepairAndRecoveryDoNotCallTheSmoothingBackend() throws {
        let context=CIContext(),engine=try BeautyProcessor(),rect=CGRect(x:0,y:0,width:64,height:64)
        let image=CIImage(color:CIColor(red:0.6,green:0.4,blue:0.3)).cropped(to:rect)
        let mask=SkinAnalysis(mask:CIImage(color:.white).cropped(to:rect),faceCount:1,backend:"Known full mask")
        var b=BeautySettings();b.enabled=true;b.strength=1;b.smoothing=0;b.skinTone=0;b.blemishRemoval=1
        _=try engine.apply(image,settings:b,analysis:mask,context:context)
        XCTAssertTrue(engine.lastBackend.contains("独立祛瑕／细节"))
        b.blemishRemoval=0;b.detailRecovery=0.2
        _=try engine.apply(image,settings:b,analysis:mask,context:context)
        XCTAssertTrue(engine.lastBackend.contains("独立祛瑕／细节"))
    }
}
