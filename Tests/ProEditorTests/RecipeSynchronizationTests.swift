import XCTest
import PhotoCore

final class RecipeSynchronizationTests: XCTestCase {
    func testRecommendedSyncPreservesPhotoSpecificEditsAndLocks() throws {
        var source=Recipe();source.document.global.exposure=1.1;source.document.global.temperature=4900
        source.document.color.lut="film";source.document.color.curve.red=[CurvePoint(0,0.1),CurvePoint(1,1)]
        source.document.geometry.cropAspect=1;source.document.beauty.enabled=true
        source.document.masks=[LocalMask(id:"source",kind:.brush)];source.export.longEdge=400
        var target=Recipe();target.document.global.temperature=6100;target.document.geometry.cropAspect=1.5
        target.document.masks=[LocalMask(id:"target",kind:.subject)];target.export.longEdge=1200
        target.document.lockedParameters=["global.temperature","color.lut"]
        let result=try RecipeSynchronization.applying(source,to:target,groups:.init(RecipeSyncGroup.recommended),targetIsRAW:false)
        XCTAssertEqual(result.document.global.exposure,1.1);XCTAssertEqual(result.document.global.temperature,6100)
        XCTAssertEqual(result.document.color.lut,target.document.color.lut);XCTAssertEqual(result.document.color.curve,source.document.color.curve)
        XCTAssertEqual(result.document.geometry,target.document.geometry);XCTAssertEqual(result.document.masks,target.document.masks)
        XCTAssertEqual(result.beauty,target.beauty);XCTAssertEqual(result.export,target.export)
        XCTAssertEqual(result.document.lockedParameters,target.document.lockedParameters)
    }
    func testToneDoesNotCopyWhiteBalanceSaturationOrStyle() throws {
        var source=Recipe();source.document.global.exposure=0.8;source.document.global.temperature=4200
        source.document.global.saturation=1.4;source.document.global.texture=0.3;source.document.color.lut="warm"
        let target=Recipe(),result=try RecipeSynchronization.applying(source,to:target,groups:[.tone],targetIsRAW:false)
        XCTAssertEqual(result.color.exposure,0.8);XCTAssertEqual(result.document.global.texture,0.3)
        XCTAssertEqual(result.document.global.temperature,target.document.global.temperature)
        XCTAssertEqual(result.document.global.saturation,target.document.global.saturation);XCTAssertEqual(result.document.color,target.document.color)
    }
    func testAllGroupsCanBeExplicitlyCopiedWithoutCopyingSourceLocksOrEvaluation() throws {
        var source=Recipe();source.document.global.exposure=0.5;source.document.color.lut="warm"
        source.document.color.hsl=[HSLAdjustment(band:.orange,saturation:0.2)]
        source.document.color.curve.master=[CurvePoint(0,0.03),CurvePoint(1,0.95)]
        source.document.color.grading.shadowSaturation=0.2;source.document.effects.vignette=0.3
        source.document.detail.sharpening=0.7;source.document.raw.exposure=0.4;source.document.geometry.scale=1.3
        source.document.beauty.enabled=true;source.document.masks=[LocalMask(id:"brush",kind:.brush)]
        source.export.longEdge=1000;source.document.lockedParameters=["global"]
        source.document.evaluation.automaticCorrection=false
        let target=Recipe(),result=try RecipeSynchronization.applying(source,to:target,groups:Set(RecipeSyncGroup.allCases),targetIsRAW:true)
        var expected=source;expected.document.lockedParameters=target.document.lockedParameters;expected.document.evaluation=target.document.evaluation
        XCTAssertEqual(result,expected)
        let jpeg=try RecipeSynchronization.applying(source,to:target,groups:[.raw],targetIsRAW:false)
        XCTAssertEqual(jpeg,target)
        var invalid=source;invalid.document.global.exposure = .nan
        XCTAssertThrowsError(try RecipeSynchronization.applying(invalid,to:target,groups:[.tone],targetIsRAW:true))
    }
}

final class PhotoReviewTests: XCTestCase {
    func testCombinedFiltersAndStableSorting() {
        let date=Date(timeIntervalSince1970:100)
        func asset(_ name: String)->PhotoAsset {let url=URL(fileURLWithPath:"/test/"+name);return PhotoAsset(name:name,originalURL:url,thumbnailURL:url,importedAt:date)}
        let a=asset("A2.NEF"),b=asset("A10.NEF"),c=asset("A1.jpg")
        let assets=[b,c,a],reviews=[a.id:PhotoReview(rating:4,flag:.picked),b.id:PhotoReview(rating:2,flag:.picked),c.id:PhotoReview(rating:5,flag:.rejected)]
        var filter=PhotoFilter();filter.rawOnly=true;filter.flag = .picked;filter.minimumRating=3;filter.query="a"
        XCTAssertEqual(filter.apply(to:assets,reviews:reviews).map(\.id),[a.id])
        filter=PhotoFilter();filter.sort = .name
        XCTAssertEqual(filter.apply(to:assets,reviews:reviews).map(\.id),[c.id,a.id,b.id])
        filter.sort = .rating
        XCTAssertEqual(filter.apply(to:assets,reviews:reviews).map(\.id),[c.id,a.id,b.id])
        filter.flag = .unflagged;XCTAssertTrue(filter.apply(to:assets,reviews:reviews).isEmpty)
        XCTAssertEqual(PhotoFilter().apply(to:assets,reviews:reviews).count,3,"Reject is a reversible marker, never a deletion")
    }
    func testInvalidRatingsAreRejectedAndReviewRoundTrips() throws {
        XCTAssertThrowsError(try PhotoReview(rating:6).validated());XCTAssertThrowsError(try PhotoReview(rating:-1).validated())
        let review=PhotoReview(rating:5,flag:.picked)
        XCTAssertEqual(try JSONDecoder().decode(PhotoReview.self,from:JSONEncoder().encode(review)),review)
    }
}
