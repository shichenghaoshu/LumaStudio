import XCTest
import ImageIO
import CoreGraphics
import PhotoDomain
import ColorEngine
import PhotoPipeline
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
    func testPerPhotoPlansArePersistedAndFailedExportsDoNotPlanAgain() async throws {
        actor Counter {var count=0;func increment(){count += 1};func value()->Int{count}}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let first=root.appendingPathComponent("first.jpg"),second=root.appendingPathComponent("second.jpg");try fixture(first)
        let count=Counter(),journal=root.appendingPathComponent("queue.json"),queue=BatchProcessor(concurrency:1,journalURL:journal)
        try await queue.start(assets:[first,second].map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)},recipe:Recipe(),profile:nil,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:nil,aiInstruction:"逐张调整",planner:{asset,base in
            await count.increment();var recipe=base;recipe.color.exposure=asset.name=="first.jpg" ? 0.2 : 0.7
            return BatchPlan(recipe:recipe,source:"unit-test per-photo planner")
        }){_ in}
        await queue.waitUntilFinished()
        let state=await queue.current();let initial=try XCTUnwrap(state)
        XCTAssertEqual(initial.completed,1);XCTAssertEqual(initial.failures,1)
        XCTAssertEqual(initial.items[0].plan?.recipe.color.exposure,0.2);XCTAssertEqual(initial.items[1].plan?.recipe.color.exposure,0.7)
        let calls=await count.value();XCTAssertEqual(calls,2)
        try fixture(second)
        try await queue.retryFailures{_ in};await queue.waitUntilFinished()
        let retried=await queue.current();XCTAssertEqual(retried?.completed,2)
        let retryCalls=await count.value();XCTAssertEqual(retryCalls,2,"Retry must reuse the saved paid plan")
        // Simulate an interruption after planning and before export, then recover without a planner.
        var recovered=initial;recovered.items=[initial.items[1]];recovered.items[0].state = .running
        recovered.exportDirectory=root.appendingPathComponent("recovered");try FileManager.default.createDirectory(at:recovered.exportDirectory,withIntermediateDirectories:true)
        try JSONEncoder().encode(recovered).write(to:journal)
        let resumed=BatchProcessor(journalURL:journal);let loaded=try await resumed.recover{_ in};XCTAssertTrue(loaded)
        await resumed.resume();await resumed.waitUntilFinished()
        let final=await resumed.current();XCTAssertEqual(final?.completed,1);XCTAssertEqual(final?.items.first?.plan?.recipe.color.exposure,0.7)
    }
    func testSavedPhotoRecipesExportWithDistinctSettingsAndSurviveRecovery() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let first=root.appendingPathComponent("first.jpg"),second=root.appendingPathComponent("second.jpg");try fixture(first);try fixture(second)
        let assets=[first,second].map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)}
        var a=Recipe();a.export.longEdge=80;a.document.geometry.cropAspect=1
        var b=Recipe();b.export.longEdge=128;b.color.exposure=0.6
        let queue=BatchProcessor(journalURL:root.appendingPathComponent("queue.json"))
        try await queue.start(assets:assets,recipe:Recipe(),profile:nil,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:nil,perPhotoRecipes:[assets[0].id:a,assets[1].id:b]){_ in}
        await queue.waitUntilFinished();let finalState=await queue.current();let state=try XCTUnwrap(finalState)
        XCTAssertEqual(state.completed,2);XCTAssertEqual(state.failures,0)
        for (i,item) in state.items.enumerated() {
            let source=try XCTUnwrap(CGImageSourceCreateWithURL(try XCTUnwrap(item.output) as CFURL,nil))
            let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
            XCTAssertEqual(image.width,i==0 ? 80 : 128);XCTAssertEqual(image.height,i==0 ? 80 : 96)
        }
        var snapshot=state;snapshot.items[0].state = .running;snapshot.items[0].output=nil
        snapshot.items=[snapshot.items[0]];snapshot.exportDirectory=root.appendingPathComponent("recovered")
        try FileManager.default.createDirectory(at:snapshot.exportDirectory,withIntermediateDirectories:true)
        let journal=root.appendingPathComponent("recover.json");try JSONEncoder().encode(snapshot).write(to:journal)
        let recovered=BatchProcessor(journalURL:journal);let loaded=try await recovered.recover{_ in};XCTAssertTrue(loaded)
        await recovered.resume();await recovered.waitUntilFinished();let result=await recovered.current()
        XCTAssertEqual(result?.completed,1);XCTAssertEqual(result?.items[0].startingRecipe,a)
    }
    func testSavedRecipesResolveTheirOwnReferenceProfiles() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let first=root.appendingPathComponent("first.jpg"),second=root.appendingPathComponent("second.jpg");try fixture(first);try fixture(second)
        let assets=[first,second].map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)}
        let profile=ColorProfile(name:"personal",reference:try ColorStatistics(samples:[RGB(0.7,0.5,0.3),RGB(0.2,0.4,0.6)]))
        let unrelated=ColorProfile(name:"unrelated",reference:try ColorStatistics(samples:[RGB(0.8,0.1,0.1),RGB(0.4,0.2,0.1)]))
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Profiles"),withIntermediateDirectories:true)
        try JSONEncoder().encode(profile).write(to:root.appendingPathComponent("Profiles/\(profile.id).json"))
        var a=Recipe();a.document.color.referenceProfileID=profile.id
        let b=Recipe(),queue=BatchProcessor()
        try await queue.start(assets:assets,recipe:Recipe(),profile:unrelated,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:root,perPhotoRecipes:[assets[0].id:a,assets[1].id:b]){_ in}
        await queue.waitUntilFinished();let final=await queue.current();XCTAssertEqual(final?.completed,2);XCTAssertEqual(final?.failures,0)
        let output=try XCTUnwrap(final?.items[1].output),expected=root.appendingPathComponent("expected.jpg")
        _=try await PhotoProcessor().export(url:second,recipe:b,destination:expected,profile:nil)
        XCTAssertEqual(try Data(contentsOf:output),try Data(contentsOf:expected),"A photo without a reference must not inherit another photo's reference")
    }
    func testAIBatchPreservesEachPhotosLockedValuesAlongsideTemplateLocks() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("photo.jpg");try fixture(source)
        let asset=PhotoAsset(name:"photo.jpg",originalURL:source,thumbnailURL:source)
        var personal=Recipe();personal.color.exposure=0.42;personal.document.lockedParameters=["global.exposure"]
        var template=Recipe();template.color.exposure = -1;template.document.global.texture=0.25;template.export.longEdge=100;template.document.lockedParameters=["export"]
        let queue=BatchProcessor()
        try await queue.start(assets:[asset],recipe:template,profile:nil,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:nil,aiInstruction:"自动调整",perPhotoRecipes:[asset.id:personal],planner:{_,base in
            XCTAssertEqual(base.color.exposure,0.42);XCTAssertEqual(base.document.global.texture,0.25);XCTAssertEqual(base.export.longEdge,100)
            XCTAssertEqual(Set(base.document.lockedParameters),["global.exposure","export"])
            return BatchPlan(recipe:base,source:"unit-test input preservation")
        }){_ in}
        await queue.waitUntilFinished();let state=await queue.current();XCTAssertEqual(state?.completed,1)
        XCTAssertEqual(state?.items.first?.startingRecipe?.color.exposure,0.42)
    }
}
