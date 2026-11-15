import XCTest
import PhotoCore

final class BeautyPresetWorkflowTests: XCTestCase {
    func testEveryPresetIntensityIsValidAndRoundTripsAsOrdinaryV2Parameters() throws {
        for style in BeautyStyle.allCases {
            XCTAssertEqual(style.settings(intensity:.standard),style.settings,"Keep existing preset recipes unchanged")
            for intensity in BeautyIntensity.allCases {
                let document=try style.applying(to:EditRecipe(),intensity:intensity)
                try document.validateParameters()
                let restored=try Recipe.decodeValidated(JSONEncoder().encode(Recipe(document:document)))
                XCTAssertEqual(restored.document,document)
            }
        }
    }
    func testStrongerPresetRetainsPhotoSpecificSettingsAndGranularLocks() throws {
        var original=EditRecipe();original.global.exposure=0.65
        original.geometry.cropAspect=1.5;original.geometry.rotation=4
        original.masks=[LocalMask(id:"own-brush",kind:.brush)]
        original.export.longEdge=1600;original.color.referenceProfileID=UUID().uuidString
        original.beauty.skinWhitening=0.2;original.beauty.faceSlimming=0.15
        original.lockedParameters=["beauty.skinWhitening","beauty.faceSlimming"]
        let result=try BeautyStyle.reshape.applying(to:original,intensity:.strong)
        var expected=original;expected.beauty=BeautyStyle.reshape.settings(intensity:.strong)
        expected.beauty.skinWhitening=0.2;expected.beauty.faceSlimming=0.15
        XCTAssertEqual(result,expected)
    }
    func testWholeBeautyAndEnabledLocksPreventPresetOverwrites() throws {
        var original=EditRecipe();original.beauty=BeautyStyle.studio.settings
        original.lockedParameters=["beauty"]
        XCTAssertEqual(try BeautyStyle.intensive.applying(to:original,intensity:.strong),original)
        original.lockedParameters=["beauty.enabled"];original.beauty.enabled=false
        let result=try BeautyStyle.intensive.applying(to:original,intensity:.strong)
        XCTAssertFalse(result.beauty.enabled)
        XCTAssertGreaterThan(result.beauty.skinWhitening,original.beauty.skinWhitening)
    }
    func testBeautyOnlySynchronizationPreservesEachTargetAndItsLocks() throws {
        let source=Recipe(document:try BeautyStyle.intensive.applying(to:EditRecipe(),intensity:.strong))
        for index in 0..<3 {
            var target=Recipe();target.document.global.exposure=Float(index)*0.4
            target.document.geometry.cropAspect=Float(index+1)
            target.document.masks=[LocalMask(id:"target-\(index)",kind:.brush)]
            target.export.longEdge=800+index*200
            target.document.beauty.skinWhitening=0.1*Float(index)
            target.document.lockedParameters=["beauty.skinWhitening"]
            let result=try RecipeSynchronization.applying(source,to:target,groups:[.beauty],targetIsRAW:false)
            var expected=target;expected.beauty=source.beauty
            expected.beauty.skinWhitening=target.beauty.skinWhitening
            XCTAssertEqual(result,expected)
        }
    }
}
