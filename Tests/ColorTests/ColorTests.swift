import XCTest
import CoreImage
import PhotoDomain
@testable import ColorEngine
final class ColorTests: XCTestCase {
    func testLabRoundTrip() {
        for c in [RGB(0,0,0),RGB(1,1,1),RGB(0.2,0.4,0.7),RGB(0.7,0.4,0.3),RGB(0.03,0.02,0.01)] {
            let back=Lab.from(c).rgb();XCTAssertEqual(c.r,back.r,accuracy:0.0001);XCTAssertEqual(c.g,back.g,accuracy:0.0001);XCTAssertEqual(c.b,back.b,accuracy:0.0001)
        }
    }
    func testLUTRoundTripAndSixPresets() throws {
        XCTAssertEqual(FilterPreset.allCases.count,6)
        for p in FilterPreset.allCases {let l=try p.lut();let decoded=try LUT3D(cube:l.cube(title:p.name));XCTAssertEqual(l.dimension,17);XCTAssertEqual(l.values,decoded.values)}
    }
    func testMalformedLUTRejected() {
        for s in ["LUT_3D_SIZE 100000", "LUT_3D_SIZE 2\n1 2 3", "LUT_3D_SIZE 2\nNaN 0 0"] {XCTAssertThrowsError(try LUT3D(cube:s))}
    }
    func testHistogramMappingMovesDistribution() {
        XCTAssertGreaterThan(HistogramMatching.map(value:0.3,source:[0.5,0.5,0,0],reference:[0,0,0.5,0.5]),0.5)
    }
    func testNaturalLUTIsIdentity() throws {
        let lut=try FilterPreset.natural.lut();let n=lut.dimension
        for b in 0..<n {for g in 0..<n {for r in 0..<n {let i=((b*n+g)*n+r)*4;XCTAssertEqual(lut.values[i],Float(r)/Float(n-1),accuracy:0.00001)}}}
    }
    func testMatchingRespondsToReferenceColor() throws {
        let c=try ColorProcessor(),source=try ColorStatistics(samples:[RGB(0.2,0.3,0.4),RGB(0.6,0.6,0.6),RGB(0.8,0.7,0.5)])
        let warm=ColorProfile(name:"warm",reference:try ColorStatistics(samples:[RGB(0.8,0.6,0.3),RGB(0.6,0.4,0.2)]))
        let cool=ColorProfile(name:"cool",reference:try ColorStatistics(samples:[RGB(0.3,0.6,0.8),RGB(0.2,0.4,0.6)]))
        XCTAssertNotEqual(try c.matchingLUT(source:source,profile:warm,dimension:5).values,try c.matchingLUT(source:source,profile:cool,dimension:5).values)
    }
    func testRecipeMinimalJSONAndClamping() throws {
        let json="""
        {"version":1,"beauty":{"enabled":true,"strength":0.35,"skinTone":0.25,"blemishRemoval":0.2},"color":{"enabled":true,"presetID":"portrait","intensity":0.8,"referenceProfileID":null},"export":{"format":"jpeg","quality":0.95}}
        """
        var recipe=try JSONDecoder().decode(Recipe.self,from:Data(json.utf8));XCTAssertEqual(recipe.color.contrast,1);recipe.beauty.strength=5
        XCTAssertEqual(try recipe.validated().beauty.strength,1);recipe.version=2;XCTAssertThrowsError(try recipe.validated())
    }
}
extension ColorTests {
    func testSkinProtectionReducesColorShift() throws {
        let context=CIContext(),processor=try ColorProcessor()
        let image=CIImage(color:CIColor(red:0.6,green:0.4,blue:0.3)).cropped(to:CGRect(x:0,y:0,width:16,height:16))
        let profile=ColorProfile(name:"blue",reference:try ColorStatistics(samples:[RGB(0.2,0.4,0.8),RGB(0.3,0.5,0.9)]))
        var settings=ColorSettings();settings.intensity=1
        let raw=try processor.apply(image,settings:settings,profile:profile,skinMask:nil,context:context)
        let mask=CIImage(color:.white).cropped(to:image.extent)
        let protected=try processor.apply(image,settings:settings,profile:profile,skinMask:mask,context:context)
        func rgb(_ img: CIImage)->[Double] {var data=[UInt8](repeating:0,count:16*16*4);context.render(img,toBitmap:&data,rowBytes:64,bounds:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB));return data.prefix(3).map(Double.init)}
        let original=rgb(image),a=rgb(raw),b=rgb(protected)
        let da=zip(a,original).reduce(0){$0+abs($1.0-$1.1)},db=zip(b,original).reduce(0){$0+abs($1.0-$1.1)}
        XCTAssertGreaterThan(da,5);XCTAssertLessThan(db,da*0.35)
    }
}
