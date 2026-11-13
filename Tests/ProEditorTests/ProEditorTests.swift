import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PhotoCore

final class ProEditorTests: XCTestCase {
    func testHistogramCountsActualChannelsAndClipping() throws {
        let context=CIContext()
        func measure(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat)throws->ImageHistogram {
            let source=CIImage(color:CIColor(red:r,green:g,blue:b)).cropped(to:CGRect(x:0,y:0,width:64,height:64))
            return ImageHistogram.measure(try XCTUnwrap(context.createCGImage(source,from:source.extent)))
        }
        let color=try measure(0.25,0.5,0.75)
        XCTAssertEqual(color.red.reduce(0,+),25600);XCTAssertEqual(color.green.reduce(0,+),25600);XCTAssertEqual(color.blue.reduce(0,+),25600)
        let peak: ([Double])->Int = {values in values.indices.max{values[$0]<values[$1]}!}
        XCTAssertLessThan(peak(color.red),peak(color.green));XCTAssertLessThan(peak(color.green),peak(color.blue))
        XCTAssertEqual(try measure(0,0,0).shadows,1);XCTAssertEqual(try measure(1,1,1).highlights,1)
    }
    func testLegacyMigrationHasOneAuthoritativeDocument() throws {
        let data=Data(#"{"version":1,"color":{"exposure":0.4,"temperature":5800,"presetID":"film"},"beauty":{"enabled":true,"strength":0.2},"edit":{"version":1,"global":{"exposure":0.2,"shadows":0.3},"color":{"hsl":[{"band":"orange","hue":0.1,"saturation":0.2,"luminance":0.1}]}}}"#.utf8)
        var r=try Recipe.decodeValidated(data)
        XCTAssertEqual(r.document.version,2);XCTAssertEqual(r.document.global.exposure,0.4);XCTAssertEqual(r.document.global.shadows,0.3)
        r.color.exposure = -0.6;XCTAssertEqual(r.edit?.global.exposure,-0.6)
        r.document.global.exposure=1.2;XCTAssertEqual(r.color.exposure,1.2)
        let encoded=try XCTUnwrap(JSONSerialization.jsonObject(with:r.json()) as? [String:Any])
        XCTAssertNil(encoded["edit"]);XCTAssertNil((encoded["color"] as? [String:Any])?["exposure"])
        XCTAssertEqual(try Recipe.decodeValidated(r.json()),r)
    }
    func testPartialAIProposalPreservesUnmentionedManualParameters() throws {
        var r=EditRecipe();r.global.texture=0.31;r.color.curve.red=[CurvePoint(0,0.04),CurvePoint(1,0.92)]
        r.detail.sharpening=0.8;r.raw.temperature=5200;r.export.dpi=240;r.geometry.scale=1.5
        r.masks=[LocalMask(id:"manual",kind:.brush)]
        let patch=Data(#"{"version":2,"global":{"exposure":0.5}}"#.utf8)
        let out=try EditRecipe.proposal(patch,preserving:r)
        XCTAssertEqual(out.global.exposure,0.5);XCTAssertEqual(out.global.texture,r.global.texture)
        XCTAssertEqual(out.color,r.color);XCTAssertEqual(out.detail,r.detail);XCTAssertEqual(out.raw,r.raw)
        XCTAssertEqual(out.export,r.export);XCTAssertEqual(out.geometry,r.geometry);XCTAssertEqual(out.masks,r.masks)
        r.color.hsl=[HSLAdjustment(band:.blue,hue:0.1,saturation:0.2,luminance:0.1),HSLAdjustment(band:.red,hue:0.05,saturation:0.3,luminance:0)]
        let hsl=try EditRecipe.proposal(Data(#"{"version":2,"color":{"hsl":[{"band":"red","saturation":0.5}]}}"#.utf8),preserving:r)
        XCTAssertEqual(hsl.color.hsl.first{$0.band == .blue},r.color.hsl.first{$0.band == .blue})
        XCTAssertEqual(hsl.color.hsl.first{$0.band == .red}?.hue,0.05);XCTAssertEqual(hsl.color.hsl.first{$0.band == .red}?.saturation,0.5)
    }
    func testV2LimitsUnknownFieldsAndMalformedCurvesAreRejected() throws {
        XCTAssertNoThrow(try EditRecipe.decodeValidated(Data(#"{"version":2,"global":{"exposure":5,"temperature":12000,"tint":150}}"#.utf8)))
        for bad in [#"{"version":2,"global":{"exposure":5.01}}"#,#"{"version":2,"global":{"shell":0}}"#,#"{"version":3}"#,#"{"version":2,"color":{"curve":{"master":[{"x":0,"y":0},{"x":0,"y":1}]}}}"#] {XCTAssertThrowsError(try EditRecipe.decodeValidated(Data(bad.utf8)))}
        var r=EditRecipe();r.geometry.scale = .nan;XCTAssertThrowsError(try r.validateParameters())
        r=EditRecipe();r.export.nameTemplate="../original";XCTAssertThrowsError(try r.validateParameters())
    }
    func testLocksProtectParametersAcrossAWholeProposal() throws {
        var current=EditRecipe();current.global.exposure=0.7;current.beauty.skinTemperature=5700;current.raw.temperature=nil;current.export.dpi=240
        current.lockedParameters=["global.exposure","beauty.skinTemperature","raw","export"]
        var proposed=EditRecipe();proposed.global.exposure = -2;proposed.global.contrast=1.2;proposed.raw.temperature=8000
        let out=ParameterLockPolicy.applying(proposed,preserving:current)
        XCTAssertEqual(out.global.exposure,0.7);XCTAssertEqual(out.beauty.skinTemperature,5700);XCTAssertNil(out.raw.temperature)
        XCTAssertEqual(out.export.dpi,240);XCTAssertEqual(out.global.contrast,1.2);XCTAssertEqual(out.lockedParameters,current.lockedParameters)
    }
    func testCurveInterpolationPreservesBoundsAndControlPoints() {
        let points=[CurvePoint(0,0),CurvePoint(0.3,0.1),CurvePoint(0.6,0.9),CurvePoint(1,1)]
        for point in points {XCTAssertEqual(CurveSampler.value(point.x,points:points),point.y,accuracy:0.0001)}
        let samples=(0...100).map{CurveSampler.value(Float($0)/100,points:points)}
        XCTAssertTrue(samples.allSatisfy{(0...1).contains($0)})
        XCTAssertTrue(zip(samples,samples.dropFirst()).allSatisfy{$0<=$1})
    }
    func testAtLeastSixtyImageControlsActuallyAffectRenderedPixels() async throws {
        let root=try temporary(),url=root.appendingPathComponent("spectrum.png");defer{try? FileManager.default.removeItem(at:root)}
        try fixture(url);let processor=try PhotoProcessor()
        let controls=ParameterCatalog.all.filter{![ParameterSection.raw,.portrait,.output].contains($0.section)}
        XCTAssertGreaterThanOrEqual(controls.count,60);XCTAssertEqual(Set(ParameterCatalog.all.map(\.id)).count,ParameterCatalog.all.count)
        var evidence=[[String:Any]]()
        for p in controls {
            var r=EditRecipe();r.evaluation.preserveSkin=false
            if p.id=="color.intensity" {r.color.lut="warm"}
            if p.id.hasPrefix("color.grading") {r.color.grading.shadowSaturation=0.15;r.color.grading.midtoneSaturation=0.15;r.color.grading.highlightSaturation=0.15}
            if p.id.hasPrefix("color.range") {r.color.range.saturation=0.6;r.color.range.luminance=0.15;r.color.range.center=80;r.color.range.width=90}
            if p.id.contains("vignette") {r.effects.vignette=0.7}
            if p.id.contains("grain") {r.effects.grain=0.7}
            if p.id.contains("bloom") {r.effects.bloom=0.7}
            if p.id.contains("film") {r.effects.filmSaturation=0.2}
            if p.id.hasPrefix("detail.") {r.detail.sharpening=1;r.detail.luminanceNoise=0.7;r.detail.colorNoise=0.7}
            if p.id=="geometry.centerX" || p.id=="geometry.centerY" {r.geometry.scale=1.6}
            let a=try await processor.render(url:url,recipe:r.legacyRecipe())
            let old=p.read(r),target=abs(old-p.range.upperBound)>abs(old-p.range.lowerBound) ? p.range.upperBound : p.range.lowerBound
            p.write(&r,target)
            let b=try await processor.render(url:url,recipe:r.legacyRecipe())
            let difference=Self.pixelDifference(a.image,b.image)
            XCTAssertGreaterThan(difference,0,"Control has no rendered effect under its active preconditions: "+p.id)
            evidence.append(["id":p.id,"title":p.title,"pixel_difference":difference,"active_dependency_preconditions":true])
        }
        if let folder=ProcessInfo.processInfo.environment["LUMA_PRO_EVIDENCE"] {let out=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["scope":"synthetic spectrum, texture and tonal range; operator evidence, not aesthetic score","controls":evidence],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("scalar-effects.json"))}
    }
    func testExportUsesRequestedDimensionsDepthProfileDPIAndMetadata() async throws {
        let root=try temporary(),source=root.appendingPathComponent("metadata.tiff");defer{try? FileManager.default.removeItem(at:root)}
        try fixture(source,metadata:true);let processor=try PhotoProcessor()
        for format in ExportFormat.allCases {
            var r=Recipe();r.color.enabled=false;r.export.format=format;r.export.longEdge=96;r.export.dpi=240;r.export.colorSpace = .displayP3;r.export.bitDepth=16;r.export.preserveEXIF=true
            let out=root.appendingPathComponent("result."+format.rawValue)
            _=try await processor.export(url:source,recipe:r,destination:out)
            let imageSource=try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL,nil)),image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,0,nil))
            XCTAssertEqual(image.width,96);XCTAssertEqual(image.height,64);XCTAssertEqual(image.bitsPerComponent,format == .jpeg ? 8 : 16,format.rawValue)
            let props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource,0,nil) as? [CFString:Any])
            XCTAssertEqual((props[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue,240)
            XCTAssertTrue((image.colorSpace?.name as String? ?? "").contains("P3"))
            if format != .png {XCTAssertEqual((props[kCGImagePropertyExifDictionary] as? [CFString:Any])?[kCGImagePropertyExifUserComment] as? String,"fixture-exif-preserved")}
        }
        var clean=Recipe();clean.export.preserveEXIF=false;let out=root.appendingPathComponent("clean.jpg")
        _=try await processor.export(url:source,recipe:clean,destination:out)
        let src=try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL,nil)),props=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [CFString:Any])
        XCTAssertNil((props[kCGImagePropertyExifDictionary] as? [CFString:Any])?[kCGImagePropertyExifUserComment])
    }
    private func temporary()throws->URL {let u=FileManager.default.temporaryDirectory.appendingPathComponent("LumaPro-"+UUID().uuidString);try FileManager.default.createDirectory(at:u,withIntermediateDirectories:true);return u}
    private func fixture(_ url: URL,metadata: Bool=false)throws {
        let w=192,h=128;var bytes=[UInt8](repeating:255,count:w*h*4)
        for y in 0..<h {for x in 0..<w {
            let hue=Double(x)/Double(w)*6,sector=Int(hue),f=hue-Double(sector),p=0.12,q=1-f*0.88,t=0.12+f*0.88
            let rgb: [Double];switch sector%6 {case 0:rgb=[1,t,p];case 1:rgb=[q,1,p];case 2:rgb=[p,1,t];case 3:rgb=[p,q,1];case 4:rgb=[t,p,1];default:rgb=[1,p,q]}
            let level=0.08+Double(y)/Double(h)*0.9
            for c in 0..<3 {let noise=Double((x*37+y*29+c*11)%17-8)/180;bytes[(y*w+x)*4+c]=UInt8(max(0,min(255,(rgb[c]*level+noise)*255)))}
        }}
        let data=Data(bytes),provider=try XCTUnwrap(CGDataProvider(data:data as CFData)),image=try XCTUnwrap(CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let dest=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,(metadata ? UTType.tiff : .png).identifier as CFString,1,nil))
        let props: [CFString:Any]=metadata ? [kCGImagePropertyExifDictionary:[kCGImagePropertyExifUserComment:"fixture-exif-preserved"]] : [:]
        CGImageDestinationAddImage(dest,image,props as CFDictionary);XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
    static func pixelDifference(_ a: CGImage,_ b: CGImage)->Int {
        if a.width != b.width || a.height != b.height {return abs(a.width-b.width)+abs(a.height-b.height)+1}
        func bytes(_ image: CGImage)->[UInt8] {var data=[UInt8](repeating:0,count:image.width*image.height*4);let ctx=CGContext(data:&data,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return data}
        return zip(bytes(a),bytes(b)).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
    }
}
