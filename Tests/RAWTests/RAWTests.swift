import XCTest
import CoreImage
import ImageIO
import PhotoDomain
@testable import PhotoPipeline
final class RAWTests: XCTestCase {
    func testInvalidRAWDoesNotClaimSupport() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let u=dir.appendingPathComponent("broken.RW2");try Data("invalid".utf8).write(to:u)
        XCTAssertThrowsError(try ImageDecoder().decode(u,tier:.preview))
    }
    func testOriginalAndSymlinkExportProtection() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder.appendingPathComponent("Originals"),withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let source=folder.appendingPathComponent("Originals/original.jpg");try Data().write(to:source)
        let link=folder.appendingPathComponent("linked");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:folder.appendingPathComponent("Originals"))
        XCTAssertThrowsError(try SafeExport.validate(destination:source,originals:[source],libraryRoot:folder))
        XCTAssertThrowsError(try SafeExport.validate(destination:link.appendingPathComponent("export.jpg"),originals:[source],libraryRoot:folder))
    }
    func testRealG9RAWThreeTiersAndExport() async throws {
        guard let fixture=ProcessInfo.processInfo.environment["LUMA_RAW_FIXTURE"] else {throw XCTSkip("Set LUMA_RAW_FIXTURE to a real first-generation G9 RW2")}
        let source=URL(fileURLWithPath:fixture),decoder=ImageDecoder()
        let thumbnail=try decoder.decode(source,tier:.thumbnail),preview=try decoder.decode(source,tier:.preview),full=try decoder.decode(source,tier:.fullResolution)
        XCTAssertLessThanOrEqual(max(thumbnail.extent.width,thumbnail.extent.height),360)
        XCTAssertLessThanOrEqual(max(preview.extent.width,preview.extent.height),1601)
        XCTAssertGreaterThan(full.extent.width,5000);XCTAssertGreaterThan(full.extent.height,3000)
        let processor=try PhotoProcessor();let dest=FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg");defer{try? FileManager.default.removeItem(at:dest)}
        _=try await processor.export(url:source,recipe:Recipe(),destination:dest)
        let exported=try decoder.decode(dest,tier:.fullResolution)
        XCTAssertEqual(exported.extent.size,full.extent.size)
    }
}
extension RAWTests {
    func testRasterFormatsRespectOrientationAndNeverOverwrite() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let source=folder.appendingPathComponent("rotated.jpg")
        let ctx=CGContext(data:nil,width:48,height:32,bitsPerComponent:8,bytesPerRow:192,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:0.7,green:0.5,blue:0.4,alpha:1));ctx.fill(CGRect(x:0,y:0,width:48,height:32))
        let d=CGImageDestinationCreateWithURL(source as CFURL,"public.jpeg" as CFString,1,nil)!;CGImageDestinationAddImage(d,ctx.makeImage()!,[kCGImagePropertyOrientation:6] as CFDictionary);XCTAssertTrue(CGImageDestinationFinalize(d))
        let decoder=ImageDecoder(),processor=try PhotoProcessor()
        let preview=try decoder.decode(source,tier:.preview);XCTAssertEqual(preview.extent.size,CGSize(width:32,height:48))
        for format in ExportFormat.allCases {
            var r=Recipe();r.export.format=format
            let target=folder.appendingPathComponent("output.\(format.rawValue)")
            _=try await processor.export(url:source,recipe:r,destination:target)
            let result=try decoder.decode(target,tier:.fullResolution);XCTAssertEqual(result.extent.size,CGSize(width:32,height:48))
            do {_=try await processor.export(url:source,recipe:r,destination:target);XCTFail("Must not overwrite any existing file")}catch{}
        }
    }
}
