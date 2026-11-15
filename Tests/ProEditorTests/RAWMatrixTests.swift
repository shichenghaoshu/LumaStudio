import XCTest
import ImageIO
import PhotoCore

final class RAWMatrixTests:XCTestCase {
    func testIndependentCameraRAWFilesRenderBrightenAndBatchExportFullResolution() async throws {
        guard let folder=ProcessInfo.processInfo.environment["LUMA_RAW_MATRIX"],let g9=ProcessInfo.processInfo.environment["LUMA_RAW_FIXTURE"] else {throw XCTSkip("The independent camera fixture set is optional in CI")}
        let rawRoot=URL(fileURLWithPath:folder),sources=[URL(fileURLWithPath:g9)]+(try FileManager.default.contentsOfDirectory(at:rawRoot,includingPropertiesForKeys:nil).filter{PhotoFileType.isRAW($0)}.sorted{$0.path<$1.path})
        XCTAssertEqual(sources.count,9)
        let output=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"].map{URL(fileURLWithPath:$0).appendingPathComponent("RAW")}
        let root=output ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{if output == nil {try? FileManager.default.removeItem(at:root)}}
        var records=[[String:Any]](),hashes=[URL:String](),sizes=[URL:CGSize]()
        for source in sources {
            let hash=try ContentDigest.sha256(source),worker=try PhotoProcessor()
            hashes[source]=hash
            var r=Recipe();r.color.enabled=false;r.document.evaluation.preserveSkin=false
            let a=try await worker.render(url:source,recipe:r)
            r.raw.exposure=0.5
            let b=try await worker.render(url:source,recipe:r)
            let before=try PixelMetrics.measure(a.image),after=try PixelMetrics.measure(b.image)
            XCTAssertGreaterThan(after.meanLuminance,before.meanLuminance,source.lastPathComponent)
            let full=try worker.decoder.decode(source,tier:.fullResolution).extent.size
            XCTAssertGreaterThan(full.width*full.height,8_000_000)
            sizes[source]=full
            let caps=RAWCapabilities.inspect(source)
            records.append(["input":source.lastPathComponent,"sha256":hash,"backend":caps.description,"controls":caps.supported.sorted(),"previewWidth":a.image.width,"previewHeight":a.image.height,"fullWidth":Int(full.width),"fullHeight":Int(full.height),"beforeLuminance":before.meanLuminance,"afterHalfEVLuminance":after.meanLuminance,"exposureDirectionPassed":true])
            await worker.releaseCaches()
        }
        var recipe=Recipe();recipe.color.enabled=false;recipe.color.exposure=0.25;recipe.document.evaluation.preserveSkin=false
        let queue=BatchProcessor(concurrency:1,journalURL:root.appendingPathComponent("queue.json"))
        let exports=root.appendingPathComponent(UUID().uuidString)
        try await queue.start(assets:sources.map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)},recipe:recipe,profile:nil,exportDirectory:exports,libraryRoot:nil){_ in}
        await queue.waitUntilFinished()
        let value=await queue.current(),snapshot=try XCTUnwrap(value)
        XCTAssertEqual(snapshot.completed,9);XCTAssertEqual(snapshot.failures,0)
        for (index,source) in sources.enumerated() {
            XCTAssertEqual(try ContentDigest.sha256(source),hashes[source])
            let item=try XCTUnwrap(snapshot.items.first{$0.source==source}),export=try XCTUnwrap(item.output),s=try XCTUnwrap(CGImageSourceCreateWithURL(export as CFURL,nil)),cg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(s,0,nil))
            XCTAssertEqual(cg.width,Int(sizes[source]!.width));XCTAssertEqual(cg.height,Int(sizes[source]!.height))
            records[index]["exportWidth"]=cg.width;records[index]["exportHeight"]=cg.height;records[index]["exportSHA256"]=try ContentDigest.sha256(export);records[index]["originalPreserved"]=true
        }
        if output != nil {try JSONSerialization.data(withJSONObject:["scope":"Nine independently sourced real camera files, nine RAW extensions. This is a tested camera set, not all RAW variants. Real batch, original-size JPEG exports, original hashes preserved.","files":records,"completed":snapshot.completed,"failures":snapshot.failures],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("raw-matrix.json"))}
    }
}
