import XCTest
import ImageIO
import CoreGraphics
import PhotoDomain
@testable import BatchEngine
final class BatchTests: XCTestCase {
    func fixture(_ url: URL) throws {
        let ctx=CGContext(data:nil,width:256,height:192,bitsPerComponent:8,bytesPerRow:1024,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:0.3,green:0.5,blue:0.6,alpha:1));ctx.fill(CGRect(x:0,y:0,width:256,height:192))
        let d=CGImageDestinationCreateWithURL(url as CFURL,"public.jpeg" as CFString,1,nil)!;CGImageDestinationAddImage(d,ctx.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(d))
    }
    func testFailureRetryAndDuplicateSource() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("photo.jpg"),missing=root.appendingPathComponent("missing.jpg");try fixture(source)
        let p=PhotoAsset(name:"photo.jpg",originalURL:source,thumbnailURL:source),bad=PhotoAsset(name:"missing.jpg",originalURL:missing,thumbnailURL:missing)
        let engine=BatchProcessor(concurrency:1,journalURL:root.appendingPathComponent("queue.json"))
        try await engine.start(assets:[p,p,bad],recipe:Recipe(),profile:nil,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:nil){_ in}
        await engine.waitUntilFinished();let firstState=await engine.current();let first=try XCTUnwrap(firstState)
        XCTAssertEqual(first.items.count,2);XCTAssertEqual(first.completed,1);XCTAssertEqual(first.failures,1)
        try fixture(missing);try await engine.retryFailures{_ in};await engine.waitUntilFinished()
        let retryState=await engine.current();let retried=try XCTUnwrap(retryState);XCTAssertEqual(retried.completed,2);XCTAssertEqual(retried.failures,0)
        XCTAssertEqual(retried.items.first{$0.source==missing}?.attempts,2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("exports"),includingPropertiesForKeys:nil).count,2)
    }
    func testPauseResumeCancelAndRecovery() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("photo.jpg");try fixture(source)
        let item=BatchItem(source:source,name:"photo.jpg")
        let snapshot=BatchSnapshot(items:[item],paused:false,active:true,cancelled:false,recipe:Recipe(),profile:nil,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:nil)
        try FileManager.default.createDirectory(at:snapshot.exportDirectory,withIntermediateDirectories:true)
        let journal=root.appendingPathComponent("queue.json");try JSONEncoder().encode(snapshot).write(to:journal)
        let engine=BatchProcessor(concurrency:1,journalURL:journal)
        let recovered=try await engine.recover{_ in};XCTAssertTrue(recovered)
        try await Task.sleep(for:.milliseconds(250));let paused=await engine.current();XCTAssertEqual(paused?.completed,0);XCTAssertTrue(paused?.paused==true)
        await engine.resume();await engine.waitUntilFinished();let finished=await engine.current();XCTAssertEqual(finished?.completed,1)
        // A recovered queue can be cancelled while paused, without creating an output.
        try JSONEncoder().encode(snapshot).write(to:journal);let second=BatchProcessor(journalURL:journal);_ = try await second.recover{_ in};await second.cancel();await second.waitUntilFinished()
        let cancelled=await second.current();XCTAssertTrue(cancelled?.cancelled==true);XCTAssertEqual(cancelled?.items.first?.state,.cancelled)
    }
}
