import XCTest
import ImageIO
import PhotoCore

final class ChineseBeautyBatchTests:XCTestCase {
    func testChineseBeautyExportsTenPublicPhotographsAtOriginalDimensions() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let folder=env["LUMA_CHINESE_FIXTURES"],let evidence=env["LUMA_CHINESE_OUTPUT"] else {throw XCTSkip("Explicit public Chinese beauty fixture set required")}
        let files=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}
        XCTAssertGreaterThanOrEqual(files.count,10)
        let hashes=try files.map{try ContentDigest.sha256($0)}
        XCTAssertEqual(Set(hashes).count,files.count,"Count independent source photos, not repeated copies")
        let output=URL(fileURLWithPath:evidence).appendingPathComponent("Batch-"+UUID().uuidString)
        let queue=BatchProcessor(concurrency:1,journalURL:output.appendingPathComponent("queue.json"))
        var recipe=Recipe(document:try BeautyStyle.chinese.applying(to:EditRecipe(),intensity:.standard))
        recipe.color.enabled=false;recipe.document.evaluation.preserveSkin=false
        let started=Date()
        try await queue.start(assets:files.map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)},recipe:recipe,profile:nil,exportDirectory:output.appendingPathComponent("exports"),libraryRoot:nil){_ in}
        await queue.waitUntilFinished()
        let current=await queue.current(),snapshot=try XCTUnwrap(current)
        XCTAssertEqual(snapshot.completed,files.count);XCTAssertEqual(snapshot.failures,0)
        var records=[[String:Any]]()
        for (index,source) in files.enumerated() {
            let item=try XCTUnwrap(snapshot.items.first{$0.source==source}),destination=try XCTUnwrap(item.output)
            func size(_ url:URL)throws->[Int] {
                let input=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil)),cg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(input,0,nil))
                return [cg.width,cg.height]
            }
            let dimensions=try size(source)
            XCTAssertEqual(try size(destination),dimensions)
            XCTAssertEqual(try ContentDigest.sha256(source),hashes[index])
            records.append(["source":source.lastPathComponent,"sourceSHA256":hashes[index],"dimensions":dimensions,"output":destination.path,"outputSHA256":try ContentDigest.sha256(destination),"originalPreserved":true])
        }
        try JSONSerialization.data(withJSONObject:["scope":"Actual batch processor with standard Chinese beauty, original-size JPEG output. Export success does not imply every face was detected; consult the separate portrait qualification matrix.","completed":snapshot.completed,"failures":snapshot.failures,"seconds":Date().timeIntervalSince(started),"recipe":try JSONSerialization.jsonObject(with:JSONEncoder().encode(recipe)),"files":records],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:evidence).appendingPathComponent("chinese-batch.json"))
    }
}
