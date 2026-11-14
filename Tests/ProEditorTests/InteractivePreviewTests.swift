import XCTest
import CoreImage
import PhotoCore

final class InteractivePreviewTests: XCTestCase {
    func testDecoderInvalidatesSamePathWithinOneSecondAndSeparatesQuality() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("replace.png"),context=CIContext(),decoder=ImageDecoder()
        func write(_ color: CIColor,_ fraction: Double) throws {
            try context.writePNGRepresentation(of:CIImage(color:color).cropped(to:CGRect(x:0,y:0,width:2000,height:1200)),to:url,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1_700_000_000+fraction)],ofItemAtPath:url.path)
        }
        try write(CIColor(red:1,green:0,blue:0),0.1)
        let fine=try decoder.decode(url,tier:.preview),fast=try decoder.decode(url,tier:.interactive)
        XCTAssertEqual(Int(fine.extent.width),1600);XCTAssertEqual(Int(fast.extent.width),960)
        var before=[UInt8](repeating:0,count:4),after=before
        context.render(fast,toBitmap:&before,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        try write(CIColor(red:0,green:1,blue:0),0.2)
        let replaced=try decoder.decode(url,tier:.interactive)
        context.render(replaced,toBitmap:&after,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        XCTAssertGreaterThan(before[0],240);XCTAssertLessThan(before[1],10)
        XCTAssertLessThan(after[0],10);XCTAssertGreaterThan(after[1],240)
    }

    func testStrongPortraitRefinesToIdenticalFinePixelsAfterInteractiveAndCacheRelease() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else {throw XCTSkip("Real portrait fixture required")}
        let url=URL(fileURLWithPath:path),processor=try PhotoProcessor(),originalHash=try ContentDigest.sha256(url)
        var r=Recipe();r.beauty=BeautyStyle.reshape.settings
        r.document.global.exposure=0.15
        r.document.color.hsl=[HSLAdjustment(band:.orange,saturation:0.1)]
        let fine=try await processor.render(url:url,recipe:r)
        XCTAssertGreaterThan(fine.faceCount,0)
        let fast=try await processor.render(url:url,recipe:r,tier:.interactive)
        XCTAssertGreaterThan(fast.faceCount,0);XCTAssertLessThanOrEqual(max(fast.image.width,fast.image.height),961)
        XCTAssertEqual(fast.image.width,fast.original.width);XCTAssertEqual(fast.image.height,fast.original.height)
        XCTAssertEqual(fast.skinMask?.width,fast.image.width);XCTAssertEqual(fast.skinMask?.height,fast.image.height)
        XCTAssertGreaterThan(ProEditorTests.pixelDifference(fast.image,fast.original),0)
        let refined=try await processor.render(url:url,recipe:r)
        XCTAssertEqual(max(refined.image.width,refined.image.height),1600)
        XCTAssertEqual(ProEditorTests.pixelDifference(fine.image,refined.image),0,"The interactive cache must never replace the fine source")
        await processor.releaseCaches()
        let uncached=try await processor.render(url:url,recipe:r)
        XCTAssertEqual(ProEditorTests.pixelDifference(fine.image,uncached.image),0)
        XCTAssertEqual(try ContentDigest.sha256(url),originalHash)
    }

    func testInteractiveBrushCropAndFullResolutionExportKeepGeometry() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("neutral.png"),context=CIContext(),processor=try PhotoProcessor()
        try context.writePNGRepresentation(of:CIImage(color:CIColor(red:0.2,green:0.2,blue:0.2)).cropped(to:CGRect(x:0,y:0,width:2400,height:1600)),to:url,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        var r=Recipe();r.color.enabled=false
        r.document.geometry.cropAspect=1
        var mask=LocalMask(id:"center",kind:.brush);mask.feather=0;mask.adjustments.exposure=1
        mask.strokes=[BrushStroke(points:[BrushPoint(x:0.5,y:0.5)],size:0.25,flow:1)]
        r.document.masks=[mask]
        for tier in [RenderTier.interactive,.preview] {
            let result=try await processor.render(url:url,recipe:r,tier:tier,maskPreviewID:mask.id)
            XCTAssertEqual(result.image.width,result.image.height)
            let overlay=try XCTUnwrap(result.localMaskPreview)
            XCTAssertEqual(overlay.width,result.image.width);XCTAssertEqual(overlay.height,result.image.height)
            XCTAssertGreaterThan(pixel(overlay,x:overlay.width/2,y:overlay.height/2),220)
            XCTAssertLessThan(pixel(overlay,x:2,y:2),10)
            XCTAssertGreaterThan(pixel(result.image,x:result.image.width/2,y:result.image.height/2),pixel(result.image,x:2,y:2)+20)
        }
        let export=folder.appendingPathComponent("export.png");r.export.format = .png
        _=try await processor.export(url:url,recipe:r,destination:export)
        let full=try ImageDecoder().decode(export,tier:.fullResolution)
        XCTAssertEqual(Int(full.extent.width),1600);XCTAssertEqual(Int(full.extent.height),1600)
    }

    private func pixel(_ image: CGImage,x: Int,y: Int)->Int {
        let context=CIContext();var p=[UInt8](repeating:0,count:4)
        context.render(CIImage(cgImage:image),toBitmap:&p,rowBytes:4,bounds:CGRect(x:x,y:y,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB))
        return Int(p[0])
    }
}
