import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PhotoCore

final class FormatAndMaskTests: XCTestCase {
    func testNativeRasterFormatsImportAndDecodeRealPhotograph() throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else {throw XCTSkip("Set a licensed photograph fixture")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil))
        let image=try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:384] as CFDictionary))
        let writers=CGImageDestinationCopyTypeIdentifiers() as! [String]
        var verified=[String]()
        for ext in ["jpg","png","tiff","heic","bmp","gif","jp2"] {
            guard let type=UTType(filenameExtension:ext),writers.contains(type.identifier) else {continue}
            let url=root.appendingPathComponent("derived."+ext),dest=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,type.identifier as CFString,1,nil))
            CGImageDestinationAddImage(dest,image,nil);XCTAssertTrue(CGImageDestinationFinalize(dest),ext)
            XCTAssertTrue(PhotoFileType.accepts(url),ext);XCTAssertFalse(PhotoFileType.isRAW(url),ext)
            let decoded=try ImageDecoder().decode(url,tier:.fullResolution)
            XCTAssertEqual(Int(decoded.extent.width),image.width);XCTAssertEqual(Int(decoded.extent.height),image.height);verified.append(ext)
        }
        XCTAssertGreaterThanOrEqual(verified.count,5)
        XCTAssertFalse(PhotoFileType.accepts(root.appendingPathComponent("document.pdf")))
        XCTAssertFalse(PhotoFileType.accepts(root.appendingPathComponent("drawing.svg")))
        try evidence(["scope":"Formats derived from one licensed real photograph, not additional independent scenes","verified":verified],name:"raster-formats.json")
    }
    func testBrushLocationFeatherInversionAndStackingAffectIntendedRegion() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let url=root.appendingPathComponent("neutral.png"),context=CIContext()
        try context.writePNGRepresentation(of:CIImage(color:CIColor(red:0.2,green:0.2,blue:0.2)).cropped(to:CGRect(x:0,y:0,width:160,height:120)),to:url,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        let worker=try PhotoProcessor();var r=Recipe();r.color.enabled=false
        var mask=LocalMask(id:"top_left",kind:.brush);mask.feather=0;mask.adjustments.exposure=1
        mask.strokes=[BrushStroke(points:[BrushPoint(x:0.25,y:0.25)],size:0.3,flow:1)]
        r.document.masks=[mask]
        let applied=try await worker.render(url:url,recipe:r,maskPreviewID:mask.id)
        let top=try sample(applied.image,x:40,y:30),bottom=try sample(applied.image,x:40,y:90)
        XCTAssertGreaterThan(top,bottom+20,"UI brush origin must map to the same top-left region in the image")
        let normal=try XCTUnwrap(applied.localMaskPreview)
        XCTAssertGreaterThan(try sample(normal,x:40,y:30),200);XCTAssertLessThan(try sample(normal,x:40,y:90),10)
        r.document.masks[0].inverted=true
        let inverted=try await worker.render(url:url,recipe:r)
        XCTAssertGreaterThan(try sample(inverted.image,x:40,y:90),try sample(inverted.image,x:40,y:30)+20)
        r.document.masks[0].inverted=false;r.document.masks[0].feather=0.1
        let feathered=try await worker.render(url:url,recipe:r,maskPreviewID:mask.id)
        XCTAssertNotEqual(try sample(XCTUnwrap(feathered.localMaskPreview),x:58,y:30),try sample(normal,x:58,y:30))
        r.document.masks[0].feather=0;r.document.masks.append(mask);r.document.masks[1].id="second"
        let stacked=try await worker.render(url:url,recipe:r)
        XCTAssertGreaterThan(try sample(stacked.image,x:40,y:30),top+10)
    }
    func testRealRAWDecoderControlsAreMeasuredOnSupportedCamera() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_RAW_FIXTURE"] else {throw XCTSkip("Set a real RAW fixture")}
        let url=URL(fileURLWithPath:path),caps=RAWCapabilities.inspect(url),worker=try PhotoProcessor()
        XCTAssertGreaterThan(caps.supported.count,6)
        var records=[[String:Any]]()
        for p in ParameterCatalog.all where p.section == .raw && caps.supported.contains(p.id) {
            var recipe=EditRecipe();recipe.color.enabled=false
            if p.id=="raw.sharpness" {recipe.raw.detail=1}
            let a=try await worker.render(url:url,recipe:recipe.legacyRecipe())
            let baseline=caps.defaults[p.id] ?? p.defaultValue
            let target=abs(baseline-p.range.upperBound)>abs(baseline-p.range.lowerBound) ? p.range.upperBound : p.range.lowerBound
            p.write(&recipe,target)
            let b=try await worker.render(url:url,recipe:recipe.legacyRecipe())
            let difference=ProEditorTests.pixelDifference(a.image,b.image)
            records.append(["id":p.id,"pixelDifference":difference,"cameraDefault":baseline,"target":target])
            if ["raw.exposure","raw.temperature","raw.tint","raw.shadows"].contains(p.id) {XCTAssertGreaterThan(difference,0,p.id)}
        }
        XCTAssertGreaterThanOrEqual(records.filter{($0["pixelDifference"] as? Int ?? 0)>0}.count,7)
        try evidence(["scope":"Real G9 RAW decoder controls. A scene without noise/moire can yield zero change for a supported filter.","controls":records],name:"raw-control-effects.json")
        var r=Recipe();r.color.enabled=false
        let baseline=try await worker.render(url:url,recipe:r);r.raw.shadows=0.7
        let lifted=try await worker.render(url:url,recipe:r);r.raw.shadows = -0.7
        let darkened=try await worker.render(url:url,recipe:r)
        XCTAssertGreaterThan(try PixelMetrics.measure(lifted.image).meanLuminance,try PixelMetrics.measure(baseline.image).meanLuminance)
        XCTAssertLessThan(try PixelMetrics.measure(darkened.image).meanLuminance,try PixelMetrics.measure(baseline.image).meanLuminance)
    }
    func testAllPortraitControlsHaveMeasuredEffectsWithinRealSkinRegion() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else {throw XCTSkip("Set a licensed real portrait fixture")}
        let url=URL(fileURLWithPath:path),worker=try PhotoProcessor()
        var records=[[String:Any]]()
        for p in ParameterCatalog.section(.portrait) {
            var r=EditRecipe();r.color.enabled=false;r.beauty.enabled=true;r.beauty.strength=0.7;r.beauty.skinTone=0.5;r.beauty.blemishRemoval=0.7
            let before=try await worker.render(url:url,recipe:r.legacyRecipe());XCTAssertGreaterThan(before.faceCount,0)
            let old=p.read(r),target=abs(old-p.range.upperBound)>abs(old-p.range.lowerBound) ? p.range.upperBound : p.range.lowerBound
            p.write(&r,target)
            let after=try await worker.render(url:url,recipe:r.legacyRecipe()),difference=ProEditorTests.pixelDifference(before.image,after.image)
            XCTAssertGreaterThan(difference,0,p.id)
            records.append(["id":p.id,"pixelDifference":difference,"activeDependencyPreconditions":true])
        }
        try evidence(["scope":"Real licensed NASA portrait, skin mask and active beauty pipeline. Pixel differences are operator checks, not cosmetic-quality scores.","controls":records],name:"portrait-control-effects.json")
    }
    private func sample(_ image: CGImage,x: Int,y: Int)throws->Int {
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let context=try XCTUnwrap(CGContext(data:&bytes,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return Int(bytes[(y*image.width+x)*4])
    }
    private func evidence(_ object: Any,name: String)throws {
        if let path=ProcessInfo.processInfo.environment["LUMA_PRO_EVIDENCE"] {let root=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(name))}
    }
}
