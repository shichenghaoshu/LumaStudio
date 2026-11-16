import XCTest
import CoreImage
import CryptoKit
import PhotoDomain
@testable import ColorEngine

final class CameraLookTests: XCTestCase {
    private let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private let space=CGColorSpace(name:CGColorSpace.sRGB)!
    private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!,.cacheIntermediates:false])

    private func image(_ samples:[[Float]]) -> CIImage {
        let components:[Float]=samples.flatMap{sample -> [Float] in sample+[Float(1)]}
        let data=components.withUnsafeBytes{Data($0)}
        return CIImage(bitmapData:data,bytesPerRow:samples.count*16,size:CGSize(width:samples.count,height:1),format:.RGBAf,colorSpace:space)
    }
    private func pixels(_ image:CIImage,space:CGColorSpace?=nil)->[Float] {
        var result=[Float](repeating:0,count:Int(image.extent.width)*4)
        context.render(image,toBitmap:&result,rowBytes:result.count*4,bounds:image.extent,format:.RGBAf,colorSpace:space ?? self.space)
        return result
    }
    func testPinnedSourcesAndAllLegacyBytesMatchManifest() throws {
        func verify(_ item:[String:Any]) throws {
            let path=try XCTUnwrap(item["path"] as? String),data=try Data(contentsOf:root.appendingPathComponent(path))
            XCTAssertEqual(data.count,item["bytes"] as? Int,path)
            XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),item["sha256"] as? String,path)
        }
        let directory=root.appendingPathComponent("Resources/ColorLooks")
        let upstream=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("Filmic/provenance.json"))) as? [String:Any])
        XCTAssertEqual(upstream["commit"] as? String,"219e30356cc80ae90e98d78be2af5da149d49116")
        for item in try XCTUnwrap(upstream["files"] as? [[String:Any]]) {try verify(item)}
        let baked=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("baked-manifest.json"))) as? [String:Any])
        let looks=try XCTUnwrap(baked["looks"] as? [[String:Any]])
        XCTAssertEqual(looks.count,11)
        for item in looks {try verify(item)}
        let legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("legacy-luts-v0.5.4.json"))) as? [String:String])
        XCTAssertEqual(legacy.count,30)
        for (id,sha) in legacy {
            let data=try Data(contentsOf:root.appendingPathComponent("Packages/ColorEngine/Sources/LUTs/"+id+".cube"))
            XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),sha,id)
        }
    }
    func testActualGPUOutputMatchesSRGBAnalyticProbes() throws {
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("Resources/ColorLooks/baked-manifest.json"))) as? [String:Any])
        var reports=[[String:Any]]()
        for look in try XCTUnwrap(manifest["looks"] as? [[String:Any]]) {
            let id=try XCTUnwrap(look["id"] as? String),preset=try XCTUnwrap(FilterPreset(rawValue:id))
            let probes=try XCTUnwrap(look["referenceSamples"] as? [[String:Any]])
            guard !probes.isEmpty else {continue}
            let inputs=try probes.map{try XCTUnwrap($0["input"] as? [Double]).map(Float.init)}
            let expected=try probes.map{try XCTUnwrap($0["output"] as? [Double])}
            let output=pixels(try preset.lut().apply(to:image(inputs)))
            var maximum=0.0
            for i in inputs.indices {for c in 0..<3 {
                maximum=max(maximum,abs(Double(output[i*4+c])-expected[i][c]))
                // Includes interpolation between 33^3 nodes and steep highlight shoulders.
                XCTAssertEqual(Double(output[i*4+c]),expected[i][c],accuracy:0.009,id+" probe \(i) channel \(c)")
            }}
            reports.append(["id":id,"maxAbsoluteSRGBError":maximum,"probeCount":inputs.count])
        }
        if let out=ProcessInfo.processInfo.environment["LUMA_COLOR_LOOK_OUTPUT"] {
            try JSONSerialization.data(withJSONObject:["scope":"GPU CIColorCubeWithColorSpace output vs independent sRGB analytic probes; not a vendor matching score","results":reports],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:out).appendingPathComponent("srgb-probes.json"))
        }
    }
    func testNeutralRampIsMonotoneAndBlackWhiteStylesRemoveChroma() throws {
        let input=image((0...255).map{let x=Float($0)/255;return [x,x,x]})
        for look in CameraColorLook.allCases {
            let lut=try XCTUnwrap(FilterPreset(rawValue:look.rawValue)).lut(),output=pixels(lut.apply(to:input))
            var previous:Float = -1
            for i in 0...255 {
                let y=output[i*4]*0.2126+output[i*4+1]*0.7152+output[i*4+2]*0.0722
                XCTAssertGreaterThanOrEqual(y+0.0001,previous,look.rawValue+" ramp \(i)")
                XCTAssertTrue(output[i*4].isFinite);previous=y
            }
            if look.monochrome {
                let colored=pixels(lut.apply(to:image([[0.8,0.4,0.2],[0.1,0.7,0.9]])))
                for i in 0..<2 {XCTAssertEqual(colored[i*4],colored[i*4+1],accuracy:0.001);XCTAssertEqual(colored[i*4+1],colored[i*4+2],accuracy:0.001)}
            }
        }
    }
    func testStyleApplicationKeepsPhotoStateAndRespectsLocks() throws {
        var original=EditRecipe();original.color.intensity=0.37;original.global.exposure=0.4
        original.color.referenceProfileID=UUID().uuidString;original.geometry.cropAspect=1.25
        original.beauty=BeautyStyle.chinese.settings(intensity:.strong)
        original.masks=[LocalMask(id:"own-brush",kind:.brush)]
        for look in CameraColorLook.allCases {
            let updated=try look.applying(to:original)
            XCTAssertEqual(updated.color.lut,look.rawValue);XCTAssertEqual(updated.color.intensity,original.color.intensity)
            XCTAssertEqual(updated.global,original.global);XCTAssertEqual(updated.geometry,original.geometry)
            XCTAssertEqual(updated.beauty,original.beauty);XCTAssertEqual(updated.masks,original.masks)
            XCTAssertEqual(updated.color.referenceProfileID,original.color.referenceProfileID)
            XCTAssertEqual(try EditRecipe.decodeValidated(updated.json()),updated)
            var locked=original;locked.color.lut="film";locked.lockedParameters=["color.lut","color.intensity"]
            XCTAssertEqual(try look.applying(to:locked).color,locked.color)
        }
        XCTAssertEqual(FilterPreset.inCategory("相机仿色").count,11)
        XCTAssertEqual(FilterPreset.inCategory("徕卡灵感").count,5)
        XCTAssertEqual(FilterPreset.inCategory("哈苏灵感").count,2)
        XCTAssertEqual(FilterPreset.inCategory("富士灵感").count,4)
    }
}
