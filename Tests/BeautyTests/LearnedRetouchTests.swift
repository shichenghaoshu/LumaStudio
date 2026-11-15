import XCTest
import CoreImage
import PhotoDomain
import CryptoKit
@testable import BeautyEngine

final class LearnedRetouchTests: XCTestCase {
    private let space=CGColorSpace(name:CGColorSpace.sRGB)!
    private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!, .cacheIntermediates:false])
    private func pixels(_ image: CIImage) -> [UInt8] {
        let w=Int(image.extent.width),h=Int(image.extent.height)
        var p=[UInt8](repeating:0,count:w*h*4)
        context.render(image,toBitmap:&p,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
        return p
    }
    func testBundledModelsRunLocallyPreserveMaskAndReusePredictions() throws {
        let rect=CGRect(x:0,y:0,width:256,height:256)
        let flat=CIImage(color:CIColor(red:0.54,green:0.36,blue:0.26)).cropped(to:rect)
        let image=CIImage(color:CIColor(red:0.51,green:0.12,blue:0.1)).cropped(to:CGRect(x:111,y:125,width:4,height:4)).composited(over:flat)
        let engine=try BeautyProcessor()
        let faces=[FaceFeatures(bounds:CGRect(x:0.12,y:0.12,width:0.76,height:0.76))]
        let black=SkinAnalysis(mask:CIImage(color:.black).cropped(to:rect),faceCount:1,backend:"Known zero mask",faces:faces)
        let white=SkinAnalysis(mask:CIImage(color:.white).cropped(to:rect),faceCount:1,backend:"Known full mask",faces:faces)
        let before=pixels(image)
        let blocked=pixels(try engine.apply(image,settings:BeautyStyle.retouch.settings,analysis:black,context:context))
        XCTAssertLessThanOrEqual(zip(before,blocked).map{abs(Int($0)-Int($1))}.max()!,1,"A zero skin mask must protect every pixel")
        XCTAssertEqual(engine.retouchInferenceCount,1,"The bundled real models must have run")
        let first=pixels(try engine.apply(image,settings:BeautyStyle.retouch.settings(intensity:.gentle),analysis:white,context:context))
        let second=pixels(try engine.apply(image,settings:BeautyStyle.retouch.settings(intensity:.strong),analysis:white,context:context))
        XCTAssertEqual(engine.retouchInferenceCount,1,"Strength edits must reuse the source prediction")
        XCTAssertEqual(first.count,second.count)
        XCTAssertTrue(engine.lastBackend.contains("Core ML"))
        var disabled=BeautyStyle.retouch.settings;disabled.enabled=false
        XCTAssertEqual(pixels(try engine.apply(image,settings:disabled,analysis:white,context:context)),before)
        engine.releaseCaches()
        _=try engine.apply(image,settings:BeautyStyle.retouch.settings,analysis:white,context:context)
        XCTAssertEqual(engine.retouchInferenceCount,2,"Explicit cache release must not return stale predictions")
    }

    func testActualRetouchPortraitsAndIndependentControls() throws {
        let env=ProcessInfo.processInfo.environment
        guard let fixtures=env["LUMA_RETOUCH_FIXTURES"],let output=env["LUMA_RETOUCH_OUTPUT"] else {throw XCTSkip("Real public portrait acceptance requires explicit fixture/output paths")}
        let root=URL(fileURLWithPath:output);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let input=URL(fileURLWithPath:fixtures)
        let files=try FileManager.default.contentsOfDirectory(at:input,includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}
        XCTAssertGreaterThanOrEqual(files.count,2)
        let engine=try BeautyProcessor()
        var receipt=[[String:Any]]()
        for file in files {
            let start=Date()
            let source=try XCTUnwrap(CIImage(contentsOf:file,options:[.applyOrientationProperty:true]))
            let scale=min(1,1600/max(source.extent.width,source.extent.height))
            let small=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            // Match PhotoProcessor's bounded preview materialization. Expanding
            // a fractional extent would introduce an unrelated transparent rim.
            let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(small,from:small.extent,format:.RGBA8,colorSpace:space)))
            let analysis=try engine.segmentation.analyze(image,context:context)
            XCTAssertGreaterThan(analysis.faceCount,0,file.lastPathComponent)
            let name=file.deletingPathExtension().lastPathComponent
            try context.writePNGRepresentation(of:image,to:root.appendingPathComponent(name+"-original.png"),format:.RGBA8,colorSpace:space)
            try context.writePNGRepresentation(of:analysis.mask,to:root.appendingPathComponent(name+"-mask.png"),format:.RGBA8,colorSpace:space)
            var healing=BeautyStyle.retouch.settings;healing.retouchBlemishes=1;healing.retouchDodgeBurn=0
            var burn=BeautyStyle.retouch.settings;burn.retouchBlemishes=0;burn.retouchDodgeBurn=1
            let cases: [(String,BeautySettings)]=[("legacy-strong",BeautyStyle.intensive.settings(intensity:.strong)),("heal",healing),("dodge-burn",burn),("retouch-gentle",BeautyStyle.retouch.settings(intensity:.gentle)),("retouch-standard",BeautyStyle.retouch.settings),("retouch-strong",BeautyStyle.retouch.settings(intensity:.strong))]
            let before=pixels(image),mask=pixels(analysis.mask)
            var runs=[[String:Any]](),inferences=engine.retouchInferenceCount
            for (mode,settings) in cases {
                let started=Date(),result=try engine.apply(image,settings:settings,analysis:analysis,context:context)
                let after=pixels(result)
                var protected=0
                for p in 0..<(before.count/4) where mask[p*4]==0 {for c in 0..<3 {protected=max(protected,abs(Int(after[p*4+c])-Int(before[p*4+c])))}}
                XCTAssertLessThanOrEqual(protected,1,"\(name) \(mode): zero-mask pixels")
                if mode=="heal" {inferences=engine.retouchInferenceCount}
                else if mode != "legacy-strong" {XCTAssertEqual(engine.retouchInferenceCount,inferences,"\(name): no new model invocation when changing effect strength")}
                try context.writePNGRepresentation(of:result,to:root.appendingPathComponent(name+"-"+mode+".png"),format:.RGBA8,colorSpace:space)
                runs.append(["mode":mode,"renderMilliseconds":Date().timeIntervalSince(started)*1000,"modelMilliseconds":engine.retouchMilliseconds,"inferenceCount":engine.retouchInferenceCount,"backend":engine.lastBackend,"zeroMaskMaxChange8bit":protected])
            }
            receipt.append(["source":file.path,"sha256":SHA256.hash(data:try Data(contentsOf:file)).map{String(format:"%02x",$0)}.joined(),"name":name,"sourceWidth":source.extent.width,"sourceHeight":source.extent.height,"renderWidth":image.extent.width,"renderHeight":image.extent.height,"faceCount":analysis.faceCount,"runs":runs,"totalSeconds":Date().timeIntervalSince(start)])
        }
        try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("native-retouch.json"))
    }

    func testRepairBeforeGradingReusesSourcePredictionAndKeepsExposureEditable() throws {
        let engine=try BeautyProcessor(),rect=CGRect(x:0,y:0,width:256,height:256)
        let source=CIImage(color:CIColor(red:0.5,green:0.35,blue:0.25)).cropped(to:rect)
        let analysis=SkinAnalysis(mask:CIImage(color:.white).cropped(to:rect),faceCount:1,backend:"Known mask",faces:[FaceFeatures(bounds:CGRect(x:0.12,y:0.12,width:0.76,height:0.76))])
        let settings=BeautyStyle.retouch.settings
        var remaining=settings;remaining.retouchBlemishes=0;remaining.retouchDodgeBurn=0
        var frames=[[UInt8]]()
        for exposure in [0.0,0.5,-0.5] {
            let base=try engine.applyRetouchBase(source,settings:settings,analysis:analysis,context:context)
            let graded=base.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:exposure])
            let result=try engine.apply(graded,settings:remaining,analysis:analysis,context:context)
            XCTAssertLessThanOrEqual(zip(pixels(result),pixels(graded)).map{abs(Int($0)-Int($1))}.max()!,1)
            frames.append(pixels(result))
        }
        XCTAssertEqual(engine.retouchInferenceCount,1,"Exposure changes occur after repair and must not invalidate neural predictions")
        XCTAssertGreaterThan(frames[1][(128*256+128)*4],frames[0][(128*256+128)*4])
        XCTAssertLessThan(frames[2][(128*256+128)*4],frames[0][(128*256+128)*4])
    }
}
