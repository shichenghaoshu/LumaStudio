import XCTest
import CoreImage
import CryptoKit
import PhotoDomain
@testable import BeautyEngine

final class ChineseBeautyTests: XCTestCase {
    private let space=CGColorSpace(name:CGColorSpace.sRGB)!
    private let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!,.cacheIntermediates:false])
    private func pixels(_ image:CIImage)->[UInt8] {
        let w=Int(image.extent.width),h=Int(image.extent.height)
        var result=[UInt8](repeating:0,count:w*h*4)
        context.render(image,toBitmap:&result,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
        return result
    }
    func testSlopingBrowProtectionFollowsContourWithoutBlockingForehead() {
        let brow=SkinFeatureProtection(points:[CGPoint(x:20,y:30),CGPoint(x:35,y:40),CGPoint(x:50,y:44)],closed:false,coreRadius:1,featherRadius:3)
        XCTAssertEqual(brow.weight(at:CGPoint(x:35,y:40)),0)
        XCTAssertEqual(brow.weight(at:CGPoint(x:22,y:43)),1,"Empty corners of a sloping brow bounding box are skin, not eyebrow")
        XCTAssertEqual(brow.weight(at:CGPoint(x:50,y:30)),1)
        let eye=SkinFeatureProtection(points:[CGPoint(x:10,y:10),CGPoint(x:30,y:10),CGPoint(x:30,y:20),CGPoint(x:10,y:20)],closed:true,coreRadius:1,featherRadius:4)
        XCTAssertEqual(eye.weight(at:CGPoint(x:20,y:15)),0)
        XCTAssertEqual(eye.weight(at:CGPoint(x:20,y:9)),0)
        XCTAssertGreaterThan(eye.weight(at:CGPoint(x:20,y:7)),0)
        XCTAssertLessThan(eye.weight(at:CGPoint(x:20,y:7)),1)
        XCTAssertEqual(eye.weight(at:CGPoint(x:20,y:4)),1)
    }
    func testChinesePresetKeepsRepairAndVisibleFinishIndependentlyEditable() throws {
        var prior:BeautySettings?
        for level in BeautyIntensity.allCases {
            let recipe=try BeautyStyle.chinese.applying(to:EditRecipe(),intensity:level),b=recipe.beauty
            XCTAssertGreaterThan(b.retouchBlemishes,0);XCTAssertGreaterThan(b.retouchDodgeBurn,0)
            XCTAssertGreaterThan(b.skinWhitening,0);XCTAssertGreaterThan(b.intensiveSmoothing,0)
            XCTAssertGreaterThan(b.faceSlimming,0);XCTAssertGreaterThan(b.eyeEnlargement,0)
            if let prior {
                XCTAssertGreaterThan(b.skinWhitening,prior.skinWhitening)
                XCTAssertGreaterThan(b.faceSlimming,prior.faceSlimming)
                XCTAssertGreaterThan(b.intensiveSmoothing,prior.intensiveSmoothing)
            }
            prior=b
        }
        var original=EditRecipe();original.global.exposure=0.4;original.geometry.cropAspect=1.3
        original.masks=[LocalMask(id:"own-skin",kind:.brush)]
        original.lockedParameters=["beauty.skinWhitening","beauty.faceSlimming"]
        let result=try BeautyStyle.chinese.applying(to:original,intensity:.strong)
        XCTAssertEqual(result.beauty.skinWhitening,original.beauty.skinWhitening)
        XCTAssertEqual(result.beauty.faceSlimming,original.beauty.faceSlimming)
        XCTAssertEqual(result.global,original.global);XCTAssertEqual(result.geometry,original.geometry)
        XCTAssertEqual(result.masks,original.masks)
    }

    func testLicensedPortraitMatrixProducesVisibleBrighteningWithoutBackgroundLeak() throws {
        let env=ProcessInfo.processInfo.environment
        guard let folder=env["LUMA_CHINESE_FIXTURES"],let output=env["LUMA_CHINESE_OUTPUT"] else {throw XCTSkip("Explicit licensed portrait paths required")}
        let root=URL(fileURLWithPath:output)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let files=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}
        XCTAssertGreaterThanOrEqual(files.count,10)
        let engine=try BeautyProcessor()
        var records=[[String:Any]](),detected=0
        for file in files {
            try autoreleasepool {
                let data=try Data(contentsOf:file),hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
                let source=try XCTUnwrap(CIImage(contentsOf:file,options:[.applyOrientationProperty:true]))
                let scale=min(1,1600/max(source.extent.width,source.extent.height))
                let scaled=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
                let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(scaled,from:scaled.extent,format:.RGBA8,colorSpace:space)))
                let analysis=try engine.segmentation.analyze(image,context:context)
                if analysis.faceCount>0 {detected+=1}
                else {
                    let unsupported:Set<String>=["pexels-19377645.jpg","pexels-7479551.jpg"]
                    XCTAssertTrue(unsupported.contains(file.lastPathComponent),"Only the documented occluded face and near-profile with closed eyes are expected detection misses")
                }
                let name=file.deletingPathExtension().lastPathComponent
                let before=pixels(image),mask=pixels(analysis.mask)
                try context.writePNGRepresentation(of:image,to:root.appendingPathComponent(name+"-original.png"),format:.RGBA8,colorSpace:space)
                try context.writePNGRepresentation(of:analysis.mask,to:root.appendingPathComponent(name+"-mask.png"),format:.RGBA8,colorSpace:space)
                var cases=[("retouch",BeautyStyle.retouch.settings)]
                for level in BeautyIntensity.allCases {cases.append(("chinese-"+level.rawValue,BeautyStyle.chinese.settings(intensity:level)))}
                // A separate unwarped finish measures skin tone and exact mask
                // protection; reshaping deliberately moves pixels near the face.
                for level in BeautyIntensity.allCases {
                    var skin=BeautyStyle.chinese.settings(intensity:level);skin.faceSlimming=0;skin.eyeEnlargement=0
                    cases.append(("skin-"+level.rawValue,skin))
                }
                var runs=[[String:Any]](),lastSkin=0.0
                for (mode,settings) in cases {
                    let started=Date(),result=try engine.apply(image,settings:settings,analysis:analysis,context:context)
                    let after=pixels(result)
                    if analysis.faceCount==0 {
                        XCTAssertEqual(after,before,"An undetected face must leave the photo unchanged")
                        try context.writePNGRepresentation(of:result,to:root.appendingPathComponent(name+"-"+mode+".png"),format:.RGBA8,colorSpace:space)
                        runs.append(["mode":mode,"status":"not_processed_no_face","backend":engine.lastBackend])
                        continue
                    }
                    var weight=0.0,lift=0.0,changed=0,clipped=0,protected=0
                    for p in 0..<(before.count/4) {
                        let i=p*4,m=Double(mask[i])/255
                        if m>0.5 {
                            let dy=0.2126*Double(Int(after[i])-Int(before[i]))+0.7152*Double(Int(after[i+1])-Int(before[i+1]))+0.0722*Double(Int(after[i+2])-Int(before[i+2]))
                            lift+=dy*m;weight+=m
                            if abs(dy)>3 {changed+=1}
                            if after[i]>=254 && after[i+1]>=254 && after[i+2]>=254 {clipped+=1}
                        }
                        if mask[i]==0 {for c in 0..<3 {protected=max(protected,abs(Int(after[i+c])-Int(before[i+c])))}}
                    }
                    XCTAssertGreaterThan(weight,20,"Meaningful skin support: "+name)
                    let meanLift=lift/max(1,weight)
                    if mode.hasPrefix("skin-") {
                        XCTAssertLessThanOrEqual(protected,1,"Zero skin support protects background and features")
                        XCTAssertGreaterThan(meanLift,2,"Visible skin brightness change: "+name)
                        XCTAssertGreaterThan(meanLift,lastSkin,"Three levels must brighten skin progressively: "+name)
                        lastSkin=meanLift
                    }
                    try context.writePNGRepresentation(of:result,to:root.appendingPathComponent(name+"-"+mode+".png"),format:.RGBA8,colorSpace:space)
                    runs.append(["mode":mode,"meanSkinLumaLift8bit":meanLift,"changedSkinPixels":changed,"whiteSkinPixels":clipped,"zeroMaskMaxChange8bit":protected,"renderMilliseconds":Date().timeIntervalSince(started)*1000,"backend":engine.lastBackend])
                }
                records.append(["name":name,"sourceSHA256":hash,"sourceWidth":source.extent.width,"sourceHeight":source.extent.height,"renderWidth":image.extent.width,"renderHeight":image.extent.height,"faceCount":analysis.faceCount,"processingStatus":analysis.faceCount>0 ? "processed":"not_processed_no_face","faces":analysis.faces.map{["x":$0.bounds.minX,"y":$0.bounds.minY,"width":$0.bounds.width,"height":$0.bounds.height]},"runs":runs])
                XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:file)).map{String(format:"%02x",$0)}.joined(),hash,"Original photo remains unchanged")
            }
        }
        XCTAssertGreaterThanOrEqual(detected,8,"Eight distinct photos must have actual face support; detection misses are reported, never counted as retouched")
        try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("chinese-portraits.json"))
    }
}
