import XCTest
import CoreImage
import CryptoKit
import PhotoDomain
import BeautyEngine

final class BeautyStressMatrixTests: XCTestCase {
    func testExpandedRealPhotographsAtEveryPresetIntensityAndDifficultLighting() throws {
        let env=ProcessInfo.processInfo.environment
        guard let expanded=env["LUMA_BEAUTY_EXPANDED"],let legacy=env["LUMA_AUDIT_PORTRAITS"],let first=env["LUMA_PORTRAIT_FIXTURE"] else {
            throw XCTSkip("Expanded public photograph set is opt-in outside local acceptance")
        }
        func photos(_ path:String)throws->[URL] {
            try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:path),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}
        }
        let inputs=[URL(fileURLWithPath:first)]+(try photos(legacy))+(try photos(expanded))
        func digest(_ url:URL)throws->String {SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()}
        let hashes=try inputs.map{try digest($0)}
        XCTAssertGreaterThanOrEqual(Set(hashes).count,12,"Count distinct source photographs, not lighting variants")
        let root=env["LUMA_BEAUTY_STRESS_OUTPUT"].map{URL(fileURLWithPath:$0)}
        if let root {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
        let context=CIContext(),engine=try BeautyProcessor(),space=CGColorSpace(name:CGColorSpace.sRGB)!
        var records=[[String:Any]]()
        for (index,url) in inputs.enumerated() {
            let source=try XCTUnwrap(CIImage(contentsOf:url)),scale=min(1,960/max(source.extent.width,source.extent.height))
            let scaled=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(scaled,from:scaled.extent)))
            let w=Int(image.extent.width),h=Int(image.extent.height),name=url.deletingPathExtension().lastPathComponent
            func pixels(_ ci:CIImage)->[UInt8] {
                var result=[UInt8](repeating:0,count:w*h*4)
                context.render(ci,toBitmap:&result,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
                return result
            }
            let variants:[(String,CIImage)]=[
                ("original",image),
                ("underexposed",image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:-1.5])),
                ("bright",image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:1.0])),
                ("warm",image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:8500,y:30),"inputTargetNeutral":CIVector(x:6500,y:0)]))
            ]
            var variantsReport=[[String:Any]](),originalFaces=0
            for (variant,input) in variants {
                // Lighting transformations are derived cases of this source,
                // not additional independent photographs.
                let analysis=try engine.segmentation.analyze(input,context:context)
                if variant=="original" {
                    originalFaces=analysis.faceCount;XCTAssertGreaterThan(originalFaces,0,name)
                    if let expected=["KSC-2009-5366":6,"iss061e025918":4][name] {XCTAssertEqual(originalFaces,expected,"Known visible group faces")}
                } else {XCTAssertEqual(analysis.faceCount,originalFaces,"\(name) \(variant): lighting must not silently disable beauty on a detected face")}
                let before=pixels(input),mask=pixels(analysis.mask)
                let expandedMask=pixels(analysis.mask.applyingFilter("CIMorphologyMaximum",parameters:[kCIInputRadiusKey:3]))
                let skin=(0..<(w*h)).filter{mask[$0*4]>80}
                if variant=="original" {XCTAssertGreaterThan(skin.count,100,name)}
                var checks=[[String:Any]](),standardDelta=0.0,strongDelta=0.0
                let styles: [BeautyStyle] = variant=="original" ? BeautyStyle.allCases : [.intensive]
                let levels: [BeautyIntensity] = variant=="original" ? BeautyIntensity.allCases : [.standard,.strong]
                for style in styles {for level in levels {
                    let settings=style.settings(intensity:level)
                    let output=try engine.apply(input,settings:settings,analysis:analysis,context:context),after=pixels(output)
                    var delta=0.0,brightness=0.0,background=0
                    for p in skin {for c in 0..<3 {
                        let d=Double(Int(after[p*4+c])-Int(before[p*4+c]));delta+=abs(d);brightness+=d
                    }}
                    delta/=Double(max(1,skin.count*3));brightness/=Double(max(1,skin.count*3))
                    if settings.faceSlimming==0 && settings.eyeEnlargement==0 {
                        for p in 0..<(w*h) where expandedMask[p*4]==0 {for c in 0..<3 {background=max(background,abs(Int(after[p*4+c])-Int(before[p*4+c])))}}
                        XCTAssertLessThanOrEqual(background,1,"\(name) \(variant) \(style) \(level): protected pixels")
                    }
                    if analysis.faceCount==0 {XCTAssertEqual(after,before,"No detected face must leave the input unchanged")}
                    if style == .intensive,level == .standard {standardDelta=delta}
                    if style == .intensive,level == .strong {strongDelta=delta}
                    checks.append(["style":style.rawValue,"intensity":level.rawValue,"skinMeanAbsoluteChange8bit":delta,"skinMeanBrightnessChange8bit":brightness,"zeroMaskMaxChange8bit":background])
                    if let root,variant=="original",(style == .natural && level == .standard) || (style == .intensive && level != .gentle) {
                        try context.writePNGRepresentation(of:output,to:root.appendingPathComponent(name+"-"+style.rawValue+"-"+level.rawValue+".png"),format:.RGBA8,colorSpace:space)
                    }
                }}
                if variant=="original" {
                    XCTAssertGreaterThan(strongDelta,standardDelta*1.03,"\(name): stronger preset must visibly exceed standard intensive beauty")
                    let full=SkinAnalysis(mask:analysis.mask,faceCount:analysis.faceCount,backend:analysis.backend,faces:analysis.faces)
                    let regional=pixels(try engine.apply(input,settings:BeautyStyle.intensive.settings(intensity:.strong),analysis:analysis,context:context))
                    let complete=pixels(try engine.apply(input,settings:BeautyStyle.intensive.settings(intensity:.strong),analysis:full,context:context))
                    let difference=zip(regional,complete).map{abs(Int($0)-Int($1))}.max()!
                    XCTAssertLessThanOrEqual(difference,2,"\(name): face-region optimization must not change placement or boundaries")
                    if let root {
                        try context.writePNGRepresentation(of:input,to:root.appendingPathComponent(name+"-original.png"),format:.RGBA8,colorSpace:space)
                        try context.writePNGRepresentation(of:analysis.mask,to:root.appendingPathComponent(name+"-mask.png"),format:.RGBA8,colorSpace:space)
                    }
                    variantsReport.append(["variant":variant,"faces":analysis.faceCount,"skinPixels":skin.count,"regionMaxChannelDifference8bit":difference,"checks":checks])
                } else {variantsReport.append(["variant":variant,"faces":analysis.faceCount,"skinPixels":skin.count,"checks":checks])}
            }
            XCTAssertEqual(try digest(url),hashes[index])
            records.append(["source":url.lastPathComponent,"sourceSHA256":hashes[index],"width":w,"height":h,"faces":originalFaces,"originalPreserved":true,"variants":variantsReport])
        }
        if let root {
            try JSONSerialization.data(withJSONObject:["scope":"Twelve distinct public NASA photographs; four derived lighting cases each; real Vision/GPU, 15 preset/intensity combinations on originals. No aesthetic or demographic generalization and no native GUI claim.","photos":records],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("stress-matrix.json"))
        }
    }
}
