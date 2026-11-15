import XCTest
import CoreImage
import ImageIO
import PhotoDomain
import PhotoPipeline

final class ExportContractTests:XCTestCase {
    private let space=CGColorSpace(name:CGColorSpace.sRGB)!
    private func fixture(_ url:URL,orientation:Int=1)throws {
        let w=120,h=80;var bytes=[UInt8](repeating:255,count:w*h*4)
        let colors:[[UInt8]]=[[220,35,25],[25,210,40],[30,45,220],[220,210,25]]
        for y in 0..<h {for x in 0..<w {let c=colors[(y>=h/2 ? 2:0)+(x>=w/2 ? 1:0)];for k in 0..<3{bytes[(y*w+x)*4+k]=c[k]}}}
        let image=try XCTUnwrap(CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let d=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,"public.tiff" as CFString,1,nil))
        let p:[CFString:Any]=[kCGImagePropertyOrientation:orientation,kCGImagePropertyTIFFDictionary:[kCGImagePropertyTIFFMake:"Luma-QA-Camera"],kCGImagePropertyExifDictionary:[kCGImagePropertyExifFNumber:2.8],kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:37.0,kCGImagePropertyGPSLatitudeRef:"N"]]
        CGImageDestinationAddImage(d,image,p as CFDictionary);XCTAssertTrue(CGImageDestinationFinalize(d))
    }
    private func neutral()->Recipe {var r=Recipe();r.color.enabled=false;r.document.evaluation.preserveSkin=false;return r}
    private func save(_ object:Any,_ name:String)throws {if let root=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"] {try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:root).appendingPathComponent(name))}}
    private func colors(_ image:CIImage,context:CIContext)->[Int] {
        let w=Int(image.extent.width),h=Int(image.extent.height);var b=[UInt8](repeating:0,count:w*h*4)
        context.render(image,toBitmap:&b,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
        return [(w/4,h/4),(3*w/4,h/4),(w/4,3*h/4),(3*w/4,3*h/4)].map{x,y in
            let i=(y*w+x)*4,r=b[i],g=b[i+1],bb=b[i+2]
            return r>150 && g>150 ? 3 : (r>g && r>bb ? 0 : (g>r && g>bb ? 1 : 2))
        }
    }
    func testEveryEXIFOrientationHasCorrectCornersInPreviewFullAndExport() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let decoder=ImageDecoder(),processor=try PhotoProcessor(),context=CIContext()
        let expected=[[0,1,2,3],[1,0,3,2],[3,2,1,0],[2,3,0,1],[0,2,1,3],[2,0,3,1],[3,1,2,0],[1,3,0,2]]
        var rows=[[String:Any]]()
        for orientation in 1...8 {
            let input=root.appendingPathComponent("orientation-\(orientation).tiff");try fixture(input,orientation:orientation)
            for tier in [RenderTier.preview,.fullResolution] {
                let image=try decoder.decode(input,tier:tier),corners=colors(image,context:context)
                XCTAssertEqual(corners,expected[orientation-1],"EXIF \(orientation), \(tier)")
                XCTAssertEqual(Int(image.extent.width),orientation>=5 ? 80:120);XCTAssertEqual(Int(image.extent.height),orientation>=5 ? 120:80)
                rows.append(["orientation":orientation,"stage":tier == .preview ? "preview":"full","corners":corners,"expected":expected[orientation-1]])
            }
            let out=root.appendingPathComponent("oriented-\(orientation).png");var recipe=neutral();recipe.export.format = .png;recipe.export.preserveEXIF=true
            _=try await processor.export(url:input,recipe:recipe,destination:out)
            let exported=try decoder.decode(out,tier:.fullResolution)
            XCTAssertEqual(colors(exported,context:context),expected[orientation-1],"Orientation must be baked once")
            let properties=CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(out as CFURL,nil)!,0,nil) as! [CFString:Any]
            XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1,1)
            rows.append(["orientation":orientation,"stage":"export","corners":colors(exported,context:context),"expected":expected[orientation-1]])
        }
        try save(["checks":rows,"passed":true],"orientation-contracts.json")
    }
    func testFormatDepthICCMetadataSizeDPINamingAndNoOverwrite() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("original.tiff");try fixture(source)
        let sourceBefore=try Data(contentsOf:source),processor=try PhotoProcessor();var rows=[[String:Any]]()
        for format in ExportFormat.allCases {for color in ExportColorSpace.allCases {for depth in (format == .jpeg ? [16] : [8,16]) {for preserve in [false,true] {
            var r=neutral();r.export.format=format;r.export.colorSpace=color;r.export.bitDepth=depth;r.export.preserveEXIF=preserve;r.export.longEdge=60;r.export.dpi=240;r.export.nameTemplate="{name}_{index}"
            let target=SafeExport.uniqueURL(folder:root,baseName:source.lastPathComponent,format:format,settings:r.export,index:7)
            XCTAssertTrue(target.lastPathComponent.hasPrefix("original_0007"))
            _=try await processor.export(url:source,recipe:r,destination:target)
            let s=try XCTUnwrap(CGImageSourceCreateWithURL(target as CFURL,nil)),image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(s,0,nil)),p=CGImageSourceCopyPropertiesAtIndex(s,0,nil) as! [CFString:Any]
            XCTAssertEqual(image.width,60);XCTAssertEqual(image.height,40)
            XCTAssertEqual(image.bitsPerComponent,format == .jpeg ? 8:depth)
            let expected:CFString=color == .sRGB ? CGColorSpace.sRGB : (color == .displayP3 ? CGColorSpace.displayP3:CGColorSpace.adobeRGB1998)
            XCTAssertEqual(image.colorSpace?.name,expected)
            XCTAssertEqual((p[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0,240,accuracy:0.1)
            let exif=p[kCGImagePropertyExifDictionary] as? [CFString:Any] ?? [:],gps=p[kCGImagePropertyGPSDictionary] as? [CFString:Any] ?? [:]
            if preserve {XCTAssertEqual((exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue ?? 0,2.8,accuracy:0.001)}
            else {XCTAssertNil(exif[kCGImagePropertyExifFNumber]);XCTAssertNil(gps[kCGImagePropertyGPSLatitude])}
            let saved=try Data(contentsOf:target)
            do {_=try await processor.export(url:source,recipe:r,destination:target);XCTFail("Existing export must remain untouched")}catch{}
            XCTAssertEqual(try Data(contentsOf:target),saved)
            rows.append(["format":format.rawValue,"colorSpace":color.rawValue,"requestedDepth":depth,"actualDepth":image.bitsPerComponent,"preserveEXIF":preserve,"width":image.width,"height":image.height,"dpi":(p[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue ?? 0,"retainedFNumber":(exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue ?? 0,"retainedGPS":gps[kCGImagePropertyGPSLatitude] != nil,"originalAndPriorExportUnchanged":true])
        }}}}
        XCTAssertEqual(try Data(contentsOf:source),sourceBefore)
        XCTAssertEqual(rows.count,30)
        try save(["checks":rows,"passed":true],"export-contracts.json")
    }
    func testJPEGQualityImprovesErrorAndUsesMoreBytes() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("quality.tiff");try fixture(source)
        let processor=try PhotoProcessor(),context=CIContext(),decoder=ImageDecoder()
        func pixels(_ image:CIImage)->[UInt8] {var p=[UInt8](repeating:0,count:120*80*4);context.render(image,toBitmap:&p,rowBytes:480,bounds:CGRect(x:0,y:0,width:120,height:80),format:.RGBA8,colorSpace:space);return p}
        let expected=pixels(try decoder.decode(source,tier:.fullResolution))
        var errors=[Double](),sizes=[Int](),rows=[[String:Any]]()
        for quality in [Float(0.1),Float(1)] {
            var r=neutral();r.export.quality=quality
            let out=root.appendingPathComponent("q-\(quality).jpg");_=try await processor.export(url:source,recipe:r,destination:out)
            let p=pixels(try decoder.decode(out,tier:.fullResolution)),error=zip(expected,p).enumerated().filter{$0.offset%4 != 3}.reduce(0.0){$0+pow(Double(Int($1.element.0)-Int($1.element.1)),2)}/Double(120*80*3)
            let size=try Data(contentsOf:out).count;errors.append(error);sizes.append(size)
            rows.append(["quality":quality,"meanSquareRGBError8bit":error,"bytes":size])
        }
        XCTAssertLessThan(errors[1],errors[0]);XCTAssertGreaterThan(sizes[1],sizes[0])
        try save(["checks":rows,"passed":true],"jpeg-quality-contract.json")
    }
}
