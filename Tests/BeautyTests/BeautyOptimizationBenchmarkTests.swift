import XCTest
import CoreImage
import PhotoDomain
import BeautyEngine
import Metal

/// Opt-in same-machine benchmark. Timings deliberately have no CI threshold;
/// rendering is forced, analysis/PNG encoding are outside the measured interval.
final class BeautyOptimizationBenchmarkTests: XCTestCase {
    func testPortraitRenderingBenchmark() throws {
        guard let root=ProcessInfo.processInfo.environment["LUMA_BEAUTY_BENCHMARK"],
              let fixture=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else {
            throw XCTSkip("Run explicitly for before/after engine measurements")
        }
        let folder=URL(fileURLWithPath:root)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let context=CIContext(),engine=try BeautyProcessor(),source=try XCTUnwrap(CIImage(contentsOf:URL(fileURLWithPath:fixture)))
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        var rows=[[String:Any]]()
        var neutral=BeautySettings();neutral.enabled=true;neutral.strength=0;neutral.blemishRemoval=0;neutral.detailRecovery=0;neutral.skinTone=0
        var white=neutral;white.skinWhitening=0.55
        var repair=neutral;repair.blemishRemoval=1;repair.radius=32
        var detail=neutral;detail.detailRecovery=0.15
        let settings:[(String,BeautySettings)]=[("whitening_only",white),("blemish_only",repair),("detail_only",detail),("natural",BeautyStyle.natural.settings),("intensive",BeautyStyle.intensive.settings)]
        for side in [960,1600] {
            let scale=min(1,CGFloat(side)/max(source.extent.width,source.extent.height))
            let small=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(small,from:small.extent)))
            let analysisStart=ProcessInfo.processInfo.systemUptime
            let analysis=try engine.segmentation.analyze(image,context:context)
            let analysisMS=(ProcessInfo.processInfo.systemUptime-analysisStart)*1000
            XCTAssertGreaterThan(analysis.faceCount,0)
            for (name,setting) in settings {
                var times=[Double]()
                for iteration in 0..<9 {
                    // Model the preceding exposure edit, preventing stale graph reuse.
                    let input=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:Double(iteration%5)*0.03])
                    let start=ProcessInfo.processInfo.systemUptime
                    let output=try engine.apply(input,settings:setting,analysis:analysis,context:context)
                    let rendered=try XCTUnwrap(context.createCGImage(output,from:image.extent,format:.RGBA8,colorSpace:space))
                    XCTAssertEqual(rendered.width,Int(image.extent.width))
                    times.append((ProcessInfo.processInfo.systemUptime-start)*1000)
                }
                let warm=Array(times.dropFirst(2)).sorted()
                rows.append(["workload":name,"longEdge":side,"width":Int(image.extent.width),"height":Int(image.extent.height),"faces":analysis.faceCount,"analysis_ms":analysisMS,"median_ms":warm[warm.count/2],"p95_ms":warm[Int(ceil(Double(warm.count)*0.95))-1],"samples_ms":times,"backend":engine.lastBackend])
            }
        }
        try JSONSerialization.data(withJSONObject:["scope":"Actual Release beauty engine, same public portrait, exposure varies each frame; cached analysis, no UI/encoding latency","device":MTLCreateSystemDefaultDevice()?.name ?? "software","warmup":2,"measured":7,"workloads":rows],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("benchmark.json"))
    }
}
