import XCTest
import CoreImage
import PhotoCore

final class ImageTests: XCTestCase {
    func testExposureWarmthAndMetalPetalDoNotCreateGreenSkinSpots() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Real portrait fixture optional") }
        let processor=try PhotoProcessor(),url=URL(fileURLWithPath:path)
        var edit=EditRecipe();edit.global.exposure=0.35;edit.global.temperature=7200
        edit.color.lut=nil;edit.color.intensity=0
        let before=try await processor.render(url:url,recipe:edit.legacyRecipe())
        edit.beauty.enabled=true;edit.beauty.strength=0.45;edit.beauty.skinTone=0.2
        let after=try await processor.render(url:url,recipe:edit.legacyRecipe())
        XCTAssertTrue(after.beautyBackend.hasPrefix("MetalPetal"),after.beautyBackend)
        func pixels(_ image: CGImage)->[UInt8] {
            var result=[UInt8](repeating:0,count:image.width*image.height*4)
            let c=CGContext(data:&result,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return result
        }
        let a=pixels(before.image),b=pixels(after.image),mask=pixels(try XCTUnwrap(after.skinMask))
        var newGreen=0
        for i in stride(from:0,to:a.count,by:4) where mask[i]>80 {
            if Int(a[i])-Int(a[i+1])>10,Int(b[i+1])-Int(b[i])>5 { newGreen += 1 }
        }
        XCTAssertEqual(newGreen,0,"Beauty must not turn warm skin into green spots")
        if let directory=ProcessInfo.processInfo.environment["LUMA_INTEGRATION_EVIDENCE"] {
            let out=URL(fileURLWithPath:directory),context=processor.context,space=CGColorSpace(name:CGColorSpace.sRGB)!
            try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            try context.writePNGRepresentation(of:CIImage(cgImage:before.image),to:out.appendingPathComponent("pipeline-before.png"),format:.RGBA8,colorSpace:space)
            try context.writePNGRepresentation(of:CIImage(cgImage:after.image),to:out.appendingPathComponent("pipeline-after.png"),format:.RGBA8,colorSpace:space)
            try JSONSerialization.data(withJSONObject:["new_green_skin_pixels":newGreen,"backend":after.beautyBackend],options:.prettyPrinted).write(to:out.appendingPathComponent("pipeline-report.json"),options:.atomic)
        }
    }
    func testGlobalToneHSLAndCurveActuallyChangePixels() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let path=root.appendingPathComponent("test-color.jpg"),ci=CIContext()
        try ci.writeJPEGRepresentation(of:CIImage(color:CIColor(red:0.4,green:0.3,blue:0.2)).cropped(to:CGRect(x:0,y:0,width:64,height:64)),to:path,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        let p=try PhotoProcessor();var r=EditRecipe();r.evaluation.preserveSkin=false
        let neutral=try await p.render(url:path,recipe:r.legacyRecipe())
        r.global.exposure=0.5;r.global.temperature=7200;r.global.shadows=0.1
        let global=try await p.render(url:path,recipe:r.legacyRecipe())
        let a=try PixelMetrics.measure(neutral.image),b=try PixelMetrics.measure(global.image)
        XCTAssertGreaterThan(b.meanLuminance,a.meanLuminance);XCTAssertGreaterThan(b.meanRed-b.meanBlue,a.meanRed-a.meanBlue)
        r=EditRecipe();r.evaluation.preserveSkin=false;r.color.hsl=[HSLAdjustment(band:.orange,saturation:-0.8)];r.color.curve.master=[CurvePoint(0,0),CurvePoint(0.5,0.65),CurvePoint(1,1)]
        let color=try await p.render(url:path,recipe:r.legacyRecipe()),c=try PixelMetrics.measure(color.image)
        XCTAssertLessThan(c.meanSaturation,a.meanSaturation);XCTAssertNotEqual(c.meanLuminance,a.meanLuminance)
    }
    func testRealPersonBackgroundMaskChangesBackgroundAndProtectsSubject() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Real portrait fixture not provided") }
        let p=try PhotoProcessor(),url=URL(fileURLWithPath:path);var r=EditRecipe()
        var local=GlobalAdjustments();local.exposure = -1;r.masks=[LocalMask(id:"background",kind:.background,adjustments:local)]
        let result=try await p.render(url:url,recipe:r.legacyRecipe())
        let maskEngine=SemanticMaskEngine(),source=CIImage(cgImage:result.original)
        let masks=try maskEngine.masks(for:source,kinds:[.subject,.background],skin:nil,context:p.context)
        let subject=p.context.createCGImage(masks[.subject]!,from:source.extent)!,background=p.context.createCGImage(masks[.background]!,from:source.extent)!
        let sb=try PixelMetrics.measure(result.original,mask:subject),sa=try PixelMetrics.measure(result.image,mask:subject)
        let bb=try PixelMetrics.measure(result.original,mask:background),ba=try PixelMetrics.measure(result.image,mask:background)
        XCTAssertLessThan(ba.meanLuminance,bb.meanLuminance)
        XCTAssertLessThan(abs(sa.meanLuminance-sb.meanLuminance),abs(ba.meanLuminance-bb.meanLuminance))
    }
    func testQualityEvaluatorDetectsWrongDirectionAndOverexposure() async throws {
        let ctx=CIContext(),extent=CGRect(x:0,y:0,width:32,height:32)
        let a=ctx.createCGImage(CIImage(color:CIColor(red:0.4,green:0.4,blue:0.4)).cropped(to:extent),from:extent)!
        let b=ctx.createCGImage(CIImage(color:.white).cropped(to:extent),from:extent)!
        let report=try QualityEvaluator().evaluate(original:a,result:b,recipe:EditRecipe(),intent:InstructionParser.parse("压暗一点"))
        XCTAssertFalse(report.accepted);XCTAssertTrue(report.issues.contains{$0.kind == .highlights});XCTAssertTrue(report.issues.contains{$0.kind == .brightnessAlignment})
    }
}
