import XCTest
import ImageIO
import PhotoCore

final class PluginPhotoTests: XCTestCase {
    func testFourKindsRenderRealPortraitsAndBatchKeepsOriginalsAndPerPhotoState() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let folder=env["LUMA_COLOR_LOOK_FIXTURES"],let destination=env["LUMA_PLUGIN_OUTPUT"] else {throw XCTSkip("Licensed portrait fixtures required")}
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out=URL(fileURLWithPath:destination);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let lutRoot=out.appendingPathComponent("TrialLUTs"),processor=try PhotoProcessor(userLUTDirectory:lutRoot)
        var records=[[String:Any]](),perPhoto=[UUID:Recipe](),assets=[PhotoAsset]()
        for (index,name) in ["pexels-1645822.jpg","pexels-26953099.jpg"].enumerated() {
            let file=URL(fileURLWithPath:folder).appendingPathComponent(name)
            // Provenance manifest uses original Pexels filenames; locate by ID if needed.
            let input=FileManager.default.fileExists(atPath:file.path) ? file : try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).first{$0.lastPathComponent.contains(index==0 ? "1645822" : "26953099")}!
            let hash=try ContentDigest.sha256(input)
            var base=EditRecipe();base.beauty.enabled=false;base.color.lut=nil;base.geometry.cropAspect=index==0 ? 1 : 1.25
            base.masks=[LocalMask(id:"user_mask",kind:.brush)];base.lockedParameters=["global.temperature"]
            let reference=try await processor.render(url:input,recipe:Recipe(document:base))
            let analysis=try VisionAnalyzer.analyze(reference.original)
            let before=try PixelMetrics.measure(reference.image)
            for slug in ["warm-light","clear-portrait","subject-light","portrait-assistant"] {
                let p=try PluginPackage.decode(Data(contentsOf:root.appendingPathComponent("Resources/Plugins/Examples/studio.luma.\(slug).lumaplugin")))
                let execution=try await PluginRuntime.execute(p,on:base,context:.batch,lutDirectory:lutRoot,planner:{ instruction,current in
                    let context=PlanningContext(instruction:instruction,analysis:analysis,preferences:EditingPreferences(),currentRecipe:current)
                    return try IntentSafetyGate.enforce(LocalRulePlanner().plan(context),context:context)
                })
                XCTAssertEqual(execution.recipe.geometry,base.geometry);XCTAssertEqual(execution.recipe.raw,base.raw)
                XCTAssertEqual(execution.recipe.lockedParameters,base.lockedParameters)
                XCTAssertEqual(execution.recipe.masks.first,base.masks.first)
                let result=try await processor.render(url:input,recipe:Recipe(document:execution.recipe))
                let after=try PixelMetrics.measure(result.image)
                let delta=abs(after.meanRed-before.meanRed)+abs(after.meanGreen-before.meanGreen)+abs(after.meanBlue-before.meanBlue)
                XCTAssertGreaterThan(delta,0.002,"Plugin must affect this actual portrait: "+slug)
                let data=NSMutableData(),image=out.appendingPathComponent("\(index)-\(slug).jpg")
                let encoder=try XCTUnwrap(CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil));CGImageDestinationAddImage(encoder,result.image,nil);XCTAssertTrue(CGImageDestinationFinalize(encoder));try (data as Data).write(to:image)
                records.append(["photo":input.lastPathComponent,"plugin":p.manifest.id,"context":"batch","meanRGBDelta":delta,"preview":image.path,"width":result.image.width,"height":result.image.height,"originalPreserved":try ContentDigest.sha256(input)==hash])
                if slug=="clear-portrait" {
                    let asset=PhotoAsset(name:input.lastPathComponent,originalURL:input,thumbnailURL:input);assets.append(asset);perPhoto[asset.id]=Recipe(document:execution.recipe)
                }
            }
            XCTAssertEqual(try ContentDigest.sha256(input),hash)
        }
        // Real existing batch engine consumes the unified plugin compiler's per-photo recipes.
        let queue=BatchProcessor(concurrency:1,journalURL:out.appendingPathComponent("batch.json"))
        try await queue.start(assets:assets,recipe:Recipe(),profile:nil,exportDirectory:out.appendingPathComponent("Exports"),libraryRoot:nil,perPhotoRecipes:perPhoto){_ in}
        await queue.waitUntilFinished();let current=await queue.current(),snapshot=try XCTUnwrap(current)
        XCTAssertEqual(snapshot.completed,2);XCTAssertEqual(snapshot.failures,0)
        for item in snapshot.items {let path=try XCTUnwrap(item.output);XCTAssertTrue(FileManager.default.fileExists(atPath:path.path))}
        try JSONSerialization.data(withJSONObject:["scope":"Eight real GPU previews and two full-resolution exports; output difference proves execution, not aesthetic quality or vendor parity","batchCompleted":snapshot.completed,"batchFailures":snapshot.failures,"previews":records],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("photo-report.json"))
    }
}
