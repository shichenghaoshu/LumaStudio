import XCTest
import ImageIO
import CoreGraphics
import PhotoDomain
@testable import LocalLibrary
final class LibraryTests: XCTestCase {
    func fixture(_ url: URL,red: CGFloat = 0.5) throws {
        let context=CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:red,green:0.3,blue:0.2,alpha:1));context.fill(CGRect(x:0,y:0,width:64,height:64))
        let dest=CGImageDestinationCreateWithURL(url as CFURL,"public.jpeg" as CFString,1,nil)!;CGImageDestinationAddImage(dest,context.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
    func testContentDedupAndCollisionSafeOriginals() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let library=try PhotoLibrary(root:dir.appendingPathComponent("library")),src=dir.appendingPathComponent("P100001.jpg")
        try fixture(src);let hash=try ContentDigest.sha256(src);let first=try await library.importPhoto(src);let duplicate=try await library.importPhoto(src)
        XCTAssertFalse(first.duplicate);XCTAssertTrue(duplicate.duplicate);XCTAssertEqual(first.asset.id,duplicate.asset.id)
        try fixture(src,red:0.9);let collision=try await library.importPhoto(src)
        XCTAssertNotEqual(collision.asset.id,first.asset.id);XCTAssertEqual(try ContentDigest.sha256(first.asset.originalURL),hash)
        let list=try await library.list();XCTAssertEqual(list.count,2)
        var recipe=Recipe();recipe.beauty.enabled=true;try await library.saveRecipe(recipe,for:first.asset.id)
        let loaded=try await library.recipe(for:first.asset.id);XCTAssertEqual(loaded,recipe)
    }
    func testRAWJPEGPairing() async throws {
        guard let fixture=ProcessInfo.processInfo.environment["LUMA_RAW_FIXTURE"] else {throw XCTSkip("Real RW2 required")}
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
        let raw=dir.appendingPathComponent("G9.RW2"),jpeg=dir.appendingPathComponent("G9.JPG")
        try FileManager.default.copyItem(at:URL(fileURLWithPath:fixture),to:raw);try self.fixture(jpeg)
        let date=Date();try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:raw.path);try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:jpeg.path)
        let library=try PhotoLibrary(root:dir.appendingPathComponent("library"));let j=try await library.importPhoto(jpeg);let r=try await library.importPhoto(raw)
        XCTAssertEqual(j.asset.id,r.asset.id);XCTAssertTrue(r.asset.isRAW);XCTAssertNotNil(r.asset.companionURL)
        let list=try await library.list();XCTAssertEqual(list.count,1)
    }
}
