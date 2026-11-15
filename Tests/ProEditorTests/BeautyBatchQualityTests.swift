import XCTest
import ImageIO
import PhotoCore

final class BeautyBatchQualityTests:XCTestCase {
    func testRealPortraitsExportWithStrongBeautyAtOriginalDimensions() async throws {
        guard let fixture=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"],
              let folder=ProcessInfo.processInfo.environment["LUMA_AUDIT_PORTRAITS"] else {throw XCTSkip("Public portrait set optional outside local acceptance")}
        func photos(_ path:String)throws->[URL] {try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:path),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}}
        var inputs=[URL(fileURLWithPath:fixture)]+(try photos(folder))
        if let expanded=ProcessInfo.processInfo.environment["LUMA_BEAUTY_EXPANDED"] {inputs += try photos(expanded)}
        XCTAssertGreaterThanOrEqual(inputs.count,5)
        let evidence=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"].map{URL(fileURLWithPath:$0).appendingPathComponent("BeautyBatch")}
        let root=(evidence ?? FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {if evidence==nil {try? FileManager.default.removeItem(at:root)}}
        let hashes=try inputs.map{try ContentDigest.sha256($0)}
        var recipe=Recipe();recipe.beauty=BeautyStyle.intensive.settings(intensity:.strong);recipe.color.enabled=false;recipe.document.evaluation.preserveSkin=false
        let queue=BatchProcessor(concurrency:1,journalURL:root.appendingPathComponent("queue.json"))
        let start=ProcessInfo.processInfo.systemUptime
        try await queue.start(assets:inputs.map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)},recipe:recipe,profile:nil,exportDirectory:root.appendingPathComponent("exports"),libraryRoot:nil){_ in}
        await queue.waitUntilFinished()
        let seconds=ProcessInfo.processInfo.systemUptime-start,value=await queue.current(),snapshot=try XCTUnwrap(value)
        XCTAssertEqual(snapshot.completed,inputs.count);XCTAssertEqual(snapshot.failures,0)
        var rows=[[String:Any]]()
        for (index,source) in inputs.enumerated() {
            let item=try XCTUnwrap(snapshot.items.first{$0.source==source}),destination=try XCTUnwrap(item.output)
            func cg(_ url:URL)throws->CGImage {let input=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil));return try XCTUnwrap(CGImageSourceCreateImageAtIndex(input,0,nil))}
            let original=try cg(source),output=try cg(destination)
            XCTAssertEqual(output.width,original.width);XCTAssertEqual(output.height,original.height)
            XCTAssertEqual(try ContentDigest.sha256(source),hashes[index])
            rows.append(["input":source.lastPathComponent,"sourceSHA256":hashes[index],"width":output.width,"height":output.height,"output":root.lastPathComponent+"/exports/"+destination.lastPathComponent,"outputSHA256":try ContentDigest.sha256(destination),"originalPreserved":true])
        }
        if let evidence {
            try JSONSerialization.data(withJSONObject:["scope":"Real batch processor, public portraits, strong intensive beauty and original-size JPEG exports; no GUI or large-scale aesthetic claim","completed":snapshot.completed,"failures":snapshot.failures,"seconds":seconds,"files":rows],options:[.prettyPrinted,.sortedKeys]).write(to:evidence.appendingPathComponent("batch-report.json"))
        }
    }
}
