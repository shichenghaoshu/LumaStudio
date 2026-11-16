import XCTest
import CoreImage
import PhotoCore

final class CameraLookPlanningTests: XCTestCase {
    func testNamedColorLooksPreserveBeautyGeometryMasksAndUnmentionedParameters() throws {
        let extent=CGRect(x:0,y:0,width:32,height:32),ci=CIImage(color:.gray).cropped(to:extent)
        let cg=try XCTUnwrap(CIContext().createCGImage(ci,from:extent))
        let analysis=ImageAnalysis(image:cg,faceCount:1,metrics:try PixelMetrics.measure(cg))
        var current=EditRecipe();current.beauty=BeautyStyle.chinese.settings(intensity:.strong)
        current.geometry.cropAspect=1;current.global.exposure=0.35;current.color.intensity=0.6
        current.color.hsl=[HSLAdjustment(band:.red,hue:0.1)];current.masks=[LocalMask(id:"own-brush",kind:.brush)]
        for (text,look) in [("小米徕卡经典",CameraColorLook.xiaomiLeicaClassic),("小米徕卡生动",.xiaomiLeicaVivid),("OPPO 哈苏自然色",.hasselbladNatural),("哈苏 XPan",.hasselbladXPan),("富士 Classic Chrome",.fujiClassicChrome),("富士鲜艳",.fujiVelvia),("富士柔和",.fujiAstia),("富士黑白",.fujiAcros),("徕卡微暖",.leicaStandard),("徕卡Chrome",.leicaChrome),("徕卡黑白",.leicaMonochrom)] {
            let context=PlanningContext(instruction:text,analysis:analysis,preferences:EditingPreferences(),currentRecipe:current)
            for result in [try LocalRulePlanner().plan(context),try IntentSafetyGate.enforce(EditRecipe(),context:context)] {
                XCTAssertEqual(result.color.lut,look.rawValue,text)
                XCTAssertEqual(result.beauty,current.beauty,text);XCTAssertEqual(result.geometry,current.geometry,text)
                XCTAssertEqual(result.global,current.global,text);XCTAssertEqual(result.masks,current.masks,text)
                XCTAssertEqual(result.color.hsl,current.color.hsl,text);XCTAssertEqual(result.color.intensity,current.color.intensity,text)
            }
        }
        current.color.lut="warm";current.lockedParameters=["color.lut"]
        let locked=PlanningContext(instruction:"哈苏自然色",analysis:analysis,preferences:EditingPreferences(),currentRecipe:current)
        XCTAssertEqual(try LocalRulePlanner().plan(locked).color.lut,"warm")
        let combined=PlanningContext(instruction:"哈苏自然色，曝光 +0.7 EV",analysis:analysis,preferences:EditingPreferences(),currentRecipe:current)
        XCTAssertEqual(try IntentSafetyGate.enforce(EditRecipe(),context:combined).global.exposure,0.7)
    }
    func testNegatedBrandAndGenericWordsDoNotSelectLooks() {
        for text in ["不要徕卡风格","不用哈苏","不使用富士","Do not apply Leica","without Hasselblad","自然一点","胶片感"] {XCTAssertNil(CameraColorLook.requested(in:text),text)}
        XCTAssertEqual(CameraColorLook.requested(in:"不要哈苏，换成徕卡生动"),.xiaomiLeicaVivid)
    }
}
