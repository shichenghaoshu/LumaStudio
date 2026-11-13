import XCTest
import PhotoCore

final class PhotoColorLabelTests: XCTestCase {
    func testLegacyReviewsKeepRatingAndFlagWhileNewLabelsRoundTrip() throws {
        let data=Data(#"{"rating":4,"flag":"picked"}"#.utf8)
        let legacy=try JSONDecoder().decode(PhotoReview.self,from:data).validated()
        XCTAssertEqual(legacy,PhotoReview(rating:4,flag:.picked,colorLabel:.none))
        for label in PhotoColorLabel.allCases {
            var review=legacy;review.colorLabel=label
            let restored=try JSONDecoder().decode(PhotoReview.self,from:JSONEncoder().encode(review)).validated()
            XCTAssertEqual(restored,review)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(PhotoReview.self,from:Data(#"{"rating":4,"flag":"picked","colorLabel":"unknown"}"#.utf8)))
    }
    func testColorFilterCombinesWithExistingFiltersAndDistinguishesUnlabeledFromAll() {
        func photo(_ name: String)->PhotoAsset {
            let url=URL(fileURLWithPath:"/test/"+name)
            return PhotoAsset(name:name,originalURL:url,thumbnailURL:url,importedAt:Date(timeIntervalSince1970:1))
        }
        let redRAW=photo("A2.NEF"),blueRAW=photo("A10.NEF"),redJPEG=photo("B1.jpg"),unlabeled=photo("C1.jpg")
        let assets=[unlabeled,blueRAW,redJPEG,redRAW]
        let reviews=[redRAW.id:PhotoReview(rating:5,flag:.picked,colorLabel:.red),blueRAW.id:PhotoReview(rating:4,flag:.picked,colorLabel:.blue),redJPEG.id:PhotoReview(rating:2,flag:.rejected,colorLabel:.red)]
        var filter=PhotoFilter();filter.colorLabel = .red;filter.minimumRating=3;filter.rawOnly=true;filter.flag = .picked;filter.query="a"
        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(filter.apply(to:assets,reviews:reviews).map(\.id),[redRAW.id])
        filter=PhotoFilter();filter.colorLabel = .some(.none)
        XCTAssertTrue(filter.isActive,"Only unlabeled is an active filter")
        XCTAssertEqual(filter.apply(to:assets,reviews:reviews).map(\.id),[unlabeled.id])
        filter.colorLabel=nil;filter.sort = .name
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to:assets,reviews:reviews).map(\.id),[redRAW.id,blueRAW.id,redJPEG.id,unlabeled.id])
    }
}
