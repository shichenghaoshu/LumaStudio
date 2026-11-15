import XCTest
import PhotoCore

final class BeautyPresetWorkflowTests: XCTestCase {
    func testAIRetouchSeparatesRepairFromWhiteningAndHonorsTargetLocks() throws {
        let old=try JSONDecoder().decode(BeautySettings.self,from:Data("{\"enabled\":true,\"strength\":0.35}".utf8))
        XCTAssertEqual(old.retouchBlemishes,0);XCTAssertEqual(old.retouchDodgeBurn,0)
        for intensity in BeautyIntensity.allCases {
            let b=BeautyStyle.retouch.settings(intensity:intensity)
            XCTAssertEqual(b.strength,0);XCTAssertEqual(b.intensiveSmoothing,0)
            XCTAssertEqual(b.skinWhitening,0);XCTAssertEqual(b.skinBrightness,0)
            XCTAssertEqual(b.faceSlimming,0);XCTAssertEqual(b.eyeEnlargement,0)
            XCTAssertGreaterThan(b.retouchBlemishes,0);XCTAssertGreaterThan(b.retouchDodgeBurn,0)
        }
        var original=EditRecipe();original.beauty.retouchBlemishes=0.15
        original.geometry.cropAspect=1.4;original.masks=[LocalMask(id:"preserve",kind:.brush)]
        original.lockedParameters=["beauty.retouchBlemishes"]
        let result=try BeautyStyle.retouch.applying(to:original,intensity:.strong)
        XCTAssertEqual(result.beauty.retouchBlemishes,0.15)
        XCTAssertEqual(result.beauty.retouchDodgeBurn,1)
        XCTAssertEqual(result.geometry,original.geometry);XCTAssertEqual(result.masks,original.masks)
        var target=Recipe(document:original)
        target.document.lockedParameters=["beauty.retouchDodgeBurn"]
        let copied=try RecipeSynchronization.applying(Recipe(document:result),to:target,groups:[.beauty],targetIsRAW:false)
        XCTAssertEqual(copied.beauty.retouchDodgeBurn,0)
        XCTAssertEqual(copied.beauty.retouchBlemishes,0.15)
        XCTAssertEqual(copied.document.geometry,original.geometry)
    }
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
