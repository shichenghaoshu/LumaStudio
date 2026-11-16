import XCTest
import ImageIO
import PhotoCore

final class CameraLookBatchTests:XCTestCase {
    func testPerPhotoColorLooksExportOriginalSizesAndKeepOriginals() async throws {
        let env=ProcessInfo.processInfo.environment
        guard let folder=env["LUMA_COLOR_LOOK_FIXTURES"],let evidence=env["LUMA_COLOR_LOOK_OUTPUT"] else {throw XCTSkip("Explicit licensed color-look fixtures required")}
        let files=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}
        XCTAssertEqual(files.count,6)
        let assets=files.map{PhotoAsset(name:$0.lastPathComponent,originalURL:$0,thumbnailURL:$0)}
        let before=try files.map{try ContentDigest.sha256($0)}
        let looks:[CameraColorLook]=[.xiaomiLeicaClassic,.hasselbladNatural,.hasselbladXPan,.xiaomiLeicaVivid,.fujiAstia,.fujiVelvia]
        var perPhoto=[UUID:Recipe]()
        for (i,asset) in assets.enumerated() {
            var document=try looks[i].applying(to:EditRecipe());document.color.intensity=0.8
            if asset.name.contains("26953099") {document=try BeautyStyle.chinese.applying(to:document,intensity:.standard)}
            let recipe=Recipe(document:document)
            XCTAssertEqual(try Recipe.decodeValidated(JSONEncoder().encode(recipe)).document,document)
            perPhoto[asset.id]=recipe
        }
        let output=URL(fileURLWithPath:evidence).appendingPathComponent("Batch-"+UUID().uuidString)
        let queue=BatchProcessor(concurrency:1,journalURL:output.appendingPathComponent("queue.json"))
        let started=Date()
        try await queue.start(assets:assets,recipe:Recipe(),profile:nil,exportDirectory:output.appendingPathComponent("exports"),libraryRoot:nil,perPhotoRecipes:perPhoto){_ in}
        await queue.waitUntilFinished()
        let current=await queue.current(),snapshot=try XCTUnwrap(current)
        XCTAssertEqual(snapshot.completed,6);XCTAssertEqual(snapshot.failures,0)
        var records=[[String:Any]]()
        for (i,asset) in assets.enumerated() {
            let item=try XCTUnwrap(snapshot.items.first{$0.source==asset.originalURL}),destination=try XCTUnwrap(item.output)
            func size(_ url:URL)throws->[Int] {
                let src=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil)),cg=try XCTUnwrap(CGImageSourceCreateImageAtIndex(src,0,nil))
                return [cg.width,cg.height]
            }
            XCTAssertEqual(try size(destination),try size(asset.originalURL))
            XCTAssertEqual(try ContentDigest.sha256(asset.originalURL),before[i])
            records.append(["source":asset.name,"look":looks[i].rawValue,"beautyEnabled":perPhoto[asset.id]!.beauty.enabled,"dimensions":try size(destination),"output":destination.path,"sourceSHA256":before[i],"outputSHA256":try ContentDigest.sha256(destination)])
        }
        try JSONSerialization.data(withJSONObject:["scope":"Actual per-photo batch queue, original-size JPEG; one portrait combines standard Chinese beauty and a camera look","completed":snapshot.completed,"failures":snapshot.failures,"seconds":Date().timeIntervalSince(started),"files":records],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:evidence).appendingPathComponent("batch.json"))
    }
}
