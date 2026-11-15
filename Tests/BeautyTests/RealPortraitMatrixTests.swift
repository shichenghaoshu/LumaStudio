import XCTest
import CoreImage
import PhotoDomain
import BeautyEngine

final class RealPortraitMatrixTests: XCTestCase {
    func testIndependentRealPortraitsAndEveryBeautyStylePreserveUnmaskedBackground() throws {
        guard let directory=ProcessInfo.processInfo.environment["LUMA_AUDIT_PORTRAITS"],let original=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else {throw XCTSkip("Independent licensed portrait set is optional outside local acceptance")}
        let inputs=[URL(fileURLWithPath:original)]+(try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:directory),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path})
        XCTAssertEqual(inputs.count,5)
        let context=CIContext(),engine=try BeautyProcessor(),space=CGColorSpace(name:CGColorSpace.sRGB)!
        let output=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"].map{URL(fileURLWithPath:$0).appendingPathComponent("Portraits")}
        if let output {try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)}
        var reports=[[String:Any]]()
        for input in inputs {
            let source=try XCTUnwrap(CIImage(contentsOf:input)),s=min(1,960/max(source.extent.width,source.extent.height))
            let scaled=source.transformed(by:CGAffineTransform(scaleX:s,y:s))
            let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(scaled,from:scaled.extent)))
            let w=Int(image.extent.width),h=Int(image.extent.height)
            func pixels(_ ci:CIImage)->[UInt8] {var b=[UInt8](repeating:0,count:w*h*4);context.render(ci,toBitmap:&b,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space);return b}
            let analysis=try engine.segmentation.analyze(image,context:context),before=pixels(image)
            XCTAssertGreaterThan(analysis.faceCount,0,input.lastPathComponent)
            // Use the same aligned RGBA representation as the saved mask. A
            // tightly packed L8 stride can be rejected at non-aligned widths.
            let maskRGBA=pixels(analysis.mask)
            let mask=(0..<(w*h)).map{maskRGBA[$0*4]}
            let expanded=pixels(analysis.mask.applyingFilter("CIMorphologyMaximum",parameters:[kCIInputRadiusKey:3]))
            let active=mask.filter{$0>80}.count
            XCTAssertGreaterThan(active,100,input.lastPathComponent)
            XCTAssertLessThan(Double(active)/Double(w*h),0.55,"Skin mask must not cover most of the photo")
            var styles=[[String:Any]](),natural=0.0,intensive=0.0
            for style in BeautyStyle.allCases {
                let result=try engine.apply(image,settings:style.settings,analysis:analysis,context:context),after=pixels(result)
                var delta=0.0,light=0.0,redness=0.0,unmasked=0,changed=0
                for i in 0..<(w*h) {
                    let k=i*4,d=(0..<3).map{abs(Int(after[k+$0])-Int(before[k+$0]))}.max()!
                    if mask[i]>80 {delta+=Double(d);light+=(0..<3).reduce(0.0){$0+Double(Int(after[k+$1])-Int(before[k+$1]))}/3;redness+=Double(Int(after[k])-Int(before[k]))-Double(Int(after[k+1])-Int(before[k+1]))}
                    // Exclude the quantized soft boundary from a zero-mask
                    // assertion; sample pixels with a full 3px zero surround.
                    if expanded[i*4]==0 {unmasked=max(unmasked,d)}
                    if d>3 {changed+=1}
                }
                delta/=Double(max(1,active));light/=Double(max(1,active));redness/=Double(max(1,active))
                XCTAssertGreaterThan(changed,style == .natural ? 0:100,"\(input.lastPathComponent) \(style.rawValue)")
                if style != .reshape {XCTAssertLessThanOrEqual(unmasked,1,"Known zero-mask pixels must be preserved")}
                if style == .porcelain {XCTAssertGreaterThan(light,3,"Whitening must actually lift skin in this photograph")}
                if style == .natural {natural=delta};if style == .intensive {intensive=delta}
                styles.append(["style":style.rawValue,"skinMeanMaxChannelDelta8bit":delta,"skinMeanBrightnessChange8bit":light,"redMinusGreenChange8bit":redness,"zeroMaskMaxChange8bit":unmasked,"changedPixelsOver3":changed,"backend":engine.lastBackend])
                if let output {try context.writePNGRepresentation(of:result,to:output.appendingPathComponent(input.deletingPathExtension().lastPathComponent+"-"+style.rawValue+".png"),format:.RGBA8,colorSpace:space)}
            }
            XCTAssertGreaterThan(intensive,natural,"Strong smoothing must visibly exceed the natural preset on each fixture")
            if let output {
                try context.writePNGRepresentation(of:image,to:output.appendingPathComponent(input.deletingPathExtension().lastPathComponent+"-original.png"),format:.RGBA8,colorSpace:space)
                try context.writePNGRepresentation(of:analysis.mask,to:output.appendingPathComponent(input.deletingPathExtension().lastPathComponent+"-mask.png"),format:.RGBA8,colorSpace:space)
            }
            reports.append(["source":input.lastPathComponent,"faces":analysis.faceCount,"eyesLocated":analysis.faces.filter{$0.leftEye != nil && $0.rightEye != nil}.count,"skinPixelsOver80":active,"width":w,"height":h,"styles":styles])
        }
        if let output {try JSONSerialization.data(withJSONObject:["scope":"Five independent public NASA photographs including one group portrait; real GPU and Vision, not a demographic or aesthetic benchmark","photographs":reports],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("portrait-matrix.json"))}
    }
}
