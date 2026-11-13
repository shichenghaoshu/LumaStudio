import XCTest
import ImageIO
import CoreGraphics
import PhotoDomain
import LocalLibrary

final class PhotoWorkflowTests: XCTestCase {
    private func temporary() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("PhotoWorkflow-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
    }
    private func importPhotos(_ library: PhotoLibrary,at root: URL) async throws -> [PhotoAsset] {
        var assets=[PhotoAsset]()
        for i in 0..<3 {
            let url=root.appendingPathComponent("photo\(i).jpg")
            let context=CGContext(data:nil,width:64,height:32,bitsPerComponent:8,bytesPerRow:256,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red:CGFloat(i+1)*0.2,green:0.3,blue:0.5,alpha:1));context.fill(CGRect(x:0,y:0,width:64,height:32))
            let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.jpeg" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,context.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
            assets.append(try await library.importPhoto(url).asset)
        }
        return assets
    }
    func testReviewPersistenceAndInvalidUpdatesAreAtomic() async throws {
        let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
        let location=root.appendingPathComponent("library"),library=try PhotoLibrary(root:location)
        let photos=try await importPhotos(library,at:root),ids=Set(photos.map(\.id))
        try await library.updateReviews(for:ids,rating:4,flag:.picked)
        let reopened=try PhotoLibrary(root:location),reviews=try await reopened.reviews()
        XCTAssertEqual(reviews.count,3);XCTAssertTrue(reviews.values.allSatisfy{$0==PhotoReview(rating:4,flag:.picked)})
        do {try await library.updateReviews(for:ids,rating:6);XCTFail("Must reject invalid rating")}catch{}
        do {try await library.updateReviews(for:[photos[0].id,UUID()],flag:.rejected);XCTFail("Must reject stale selection")}catch{}
        let unchanged=try await library.reviews();XCTAssertEqual(unchanged,reviews)
        try await library.updateReviews(for:[photos[0].id],rating:0,flag:PhotoFlag.none)
        let cleared=try await library.reviews();XCTAssertEqual(cleared[photos[0].id],PhotoReview())
    }
    func testColorLabelsPersistAndPartialMetadataUpdatesPreserveOtherFieldsAndRecipes() async throws {
        let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
        let location=root.appendingPathComponent("library"),library=try PhotoLibrary(root:location)
        let photos=try await importPhotos(library,at:root),ids=Set(photos.map(\.id))
        let hashes=try photos.map{try ContentDigest.sha256($0.originalURL)}
        var recipe=Recipe();recipe.color.exposure=0.25;try await library.saveRecipe(recipe,for:photos[0].id)
        try await library.updateReviews(for:ids,rating:4,flag:.picked)
        try await library.updateReviews(for:[photos[0].id,photos[1].id],colorLabel:.red)
        try await library.updateReviews(for:[photos[0].id],rating:2,flag:.rejected)
        let before=try await library.reviews()
        do {
            try await library.updateReviews(for:[photos[0].id,UUID()],colorLabel:.blue)
            XCTFail("Stale targets must reject the complete color-label update")
        } catch {}
        let unchanged=try await library.reviews();XCTAssertEqual(unchanged,before)
        let reopened=try PhotoLibrary(root:location),restored=try await reopened.reviews()
        XCTAssertEqual(restored[photos[0].id],PhotoReview(rating:2,flag:.rejected,colorLabel:.red))
        XCTAssertEqual(restored[photos[1].id],PhotoReview(rating:4,flag:.picked,colorLabel:.red))
        XCTAssertEqual(restored[photos[2].id],PhotoReview(rating:4,flag:.picked,colorLabel:.none))
        try await reopened.updateReviews(for:[photos[0].id],colorLabel:PhotoColorLabel.none)
        let cleared=try await reopened.reviews(),savedRecipe=try await reopened.recipe(for:photos[0].id)
        XCTAssertEqual(cleared[photos[0].id],PhotoReview(rating:2,flag:.rejected,colorLabel:.none))
        XCTAssertEqual(savedRecipe,recipe)
        XCTAssertEqual(try photos.map{try ContentDigest.sha256($0.originalURL)},hashes)
    }
    func testSynchronizationAndUndoPreserveOriginalsAndSourceRecipe() async throws {
        let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
        let library=try PhotoLibrary(root:root.appendingPathComponent("library")),photos=try await importPhotos(library,at:root)
        let hashes=try photos.map{try ContentDigest.sha256($0.originalURL)}
        var source=Recipe();source.color.exposure=1.2;source.document.global.temperature=4800
        try await library.saveRecipe(source,for:photos[0].id)
        var target=Recipe();target.document.geometry.scale=1.5;target.document.masks=[LocalMask(id:"local",kind:.brush)]
        target.document.lockedParameters=["global.exposure"]
        try await library.saveRecipe(target,for:photos[1].id)
        let transaction=try await library.synchronizeRecipe(source,from:photos[0].id,to:Set(photos.map(\.id)),groups:RecipeSyncGroup.recommended)
        XCTAssertEqual(transaction.changes.count,2)
        let first=try await library.recipe(for:photos[1].id),second=try await library.recipe(for:photos[2].id)
        XCTAssertEqual(first.color.exposure,0);XCTAssertEqual(first.document.geometry,target.document.geometry);XCTAssertEqual(first.document.masks,target.document.masks)
        XCTAssertEqual(second.color.exposure,1.2)
        try await library.undoSynchronization(transaction)
        let restored=try await library.recipe(for:photos[1].id),defaultRecipe=try await library.recipe(for:photos[2].id),unchangedSource=try await library.recipe(for:photos[0].id)
        XCTAssertEqual(restored,target);XCTAssertEqual(defaultRecipe,Recipe());XCTAssertEqual(unchangedSource,source)
        XCTAssertEqual(try photos.map{try ContentDigest.sha256($0.originalURL)},hashes)
    }
    func testMissingTargetAndUndoConflictLeaveWholeGroupUnchanged() async throws {
        let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
        let library=try PhotoLibrary(root:root.appendingPathComponent("library")),photos=try await importPhotos(library,at:root)
        var source=Recipe();source.color.exposure=0.8
        do { _=try await library.synchronizeRecipe(source,from:photos[0].id,to:[photos[1].id,UUID()],groups:[.tone]);XCTFail("Must reject stale target") }catch{}
        let untouched=try await library.recipe(for:photos[1].id);XCTAssertEqual(untouched,Recipe())
        let transaction=try await library.synchronizeRecipe(source,from:photos[0].id,to:[photos[1].id,photos[2].id],groups:[.tone])
        var changed=source;changed.document.global.texture=0.2;try await library.saveRecipe(changed,for:photos[2].id)
        do {try await library.undoSynchronization(transaction);XCTFail("Must preserve subsequent edits")}catch{}
        let a=try await library.recipe(for:photos[1].id),b=try await library.recipe(for:photos[2].id)
        XCTAssertEqual(a,source);XCTAssertEqual(b,changed)
    }
    func testPreReviewDatabaseMigratesWithoutLosingPhotoOrRecipe() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_LEGACY_FIXTURE"] else {throw XCTSkip("Pre-change database fixture required")}
        let root=try temporary();defer{try? FileManager.default.removeItem(at:root)}
        let copy=root.appendingPathComponent("library");try FileManager.default.copyItem(at:URL(fileURLWithPath:path),to:copy)
        let id=try XCTUnwrap(UUID(uuidString:String(contentsOf:copy.appendingPathComponent("fixture-id.txt"),encoding:.utf8)))
        let library=try PhotoLibrary(root:copy),photos=try await library.list(),recipe=try await library.recipe(for:id),initial=try await library.reviews()
        XCTAssertEqual(photos.count,1);XCTAssertEqual(photos[0].id,id);XCTAssertEqual(recipe.color.exposure,0.42);XCTAssertTrue(initial.isEmpty)
        try await library.updateReviews(for:[id],rating:5,flag:.picked)
        let reviews=try await library.reviews(),after=try await library.recipe(for:id)
        XCTAssertEqual(reviews[id],PhotoReview(rating:5,flag:.picked));XCTAssertEqual(after,recipe)
    }
}
