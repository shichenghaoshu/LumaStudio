import XCTest
import ImageIO
import PhotoCore

final class BrandSampleTests: XCTestCase {
    func testOfficialBrandSamplesAndUserLandscapeThroughPlanningPreviewAndExport() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let folder=env["LUMA_BRAND_FIXTURES"],let output=env["LUMA_BRAND_OUTPUT"] else {throw XCTSkip("Explicit local-only official gallery samples required")}
        let root=URL(fileURLWithPath:output);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let files=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).filter{["jpg","png"].contains($0.pathExtension.lowercased())}.sorted{$0.path<$1.path}
        XCTAssertGreaterThanOrEqual(files.count,12)
        let processor=try PhotoProcessor();var records=[[String:Any]]()
        for input in files {
            let hash=try ContentDigest.sha256(input),start=Date()
            var base=EditRecipe();base.beauty.enabled=false;base.color.lut=nil
            base.lockedParameters=["global.temperature"]
            let neutral=try await processor.render(url:input,recipe:Recipe(document:base))
            let analysis=try VisionAnalyzer.analyze(neutral.original)
            let instruction=analysis.faceCount>0 ? "中式人像美颜，提亮肤色，保留皮肤纹理，不要瘦脸，不要大眼，保留其他参数" : "自动校正曝光和白平衡，适度提亮暗部，恢复高光，不要美颜，保留其他参数"
            let planning=PlanningContext(instruction:instruction,analysis:analysis,preferences:EditingPreferences(),currentRecipe:base)
            let edit=try IntentSafetyGate.enforce(LocalRulePlanner().plan(planning),context:planning)
            XCTAssertEqual(edit.geometry,base.geometry);XCTAssertEqual(edit.masks,base.masks);XCTAssertEqual(edit.lockedParameters,base.lockedParameters)
            XCTAssertEqual(edit.global.temperature,base.global.temperature)
            XCTAssertEqual(edit.beauty.faceSlimming,base.beauty.faceSlimming);XCTAssertEqual(edit.beauty.eyeEnlargement,base.beauty.eyeEnlargement)
            let rendered=try await processor.render(url:input,recipe:Recipe(document:edit))
            func jpeg(_ image:CGImage,_ name:String) throws {
                let url=root.appendingPathComponent(name),d=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,"public.jpeg" as CFString,1,nil))
                CGImageDestinationAddImage(d,image,nil);XCTAssertTrue(CGImageDestinationFinalize(d))
            }
            let name=input.deletingPathExtension().lastPathComponent
            try jpeg(neutral.image,name+"-before.jpg");try jpeg(rendered.image,name+"-after.jpg")
            let destination=root.appendingPathComponent(name+"-export.jpg")
            _=try await processor.export(url:input,recipe:Recipe(document:edit),destination:destination)
            let source=try XCTUnwrap(CGImageSourceCreateWithURL(input as CFURL,nil)),result=try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL,nil))
            let a=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any]),b=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result,0,nil) as? [String:Any])
            XCTAssertEqual(a[kCGImagePropertyPixelWidth as String] as? Int,b[kCGImagePropertyPixelWidth as String] as? Int)
            XCTAssertEqual(a[kCGImagePropertyPixelHeight as String] as? Int,b[kCGImagePropertyPixelHeight as String] as? Int)
            XCTAssertEqual(try ContentDigest.sha256(input),hash)
            let before=try PixelMetrics.measure(neutral.image),after=try PixelMetrics.measure(rendered.image)
            let delta=abs(before.meanRed-after.meanRed)+abs(before.meanGreen-after.meanGreen)+abs(before.meanBlue-after.meanBlue)
            records.append(["file":input.lastPathComponent,"faces":analysis.faceCount,"instruction":instruction,"meanRGBChange":delta,"width":b[kCGImagePropertyPixelWidth as String] ?? 0,"height":b[kCGImagePropertyPixelHeight as String] ?? 0,"exported":true,"sourceUnchanged":true,"seconds":Date().timeIntervalSince(start)])
            try edit.json().write(to:root.appendingPathComponent(name+"-recipe.json"))
        }
        try JSONSerialization.data(withJSONObject:["scope":"Official web JPEG samples and user PNG; local rules, real preview/full-size export, state preservation. Not a RAW calibration or aesthetic score.","count":records.count,"results":records],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("sample-report.json"))
    }
}
