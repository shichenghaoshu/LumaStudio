import Foundation
import PhotoCore
import CoreImage
import ImageIO
import Metal
import Darwin

@main struct Diagnostics {
    static func main() async {
        do {
            let a=Array(CommandLine.arguments.dropFirst())
            guard a.count>=3 else { print("Usage: LumaDiagnostics inspect <photo> <output-folder> | benchmark <photo> <output-folder> [count=100] | import <photo> <library-folder>");return }
            let source=URL(fileURLWithPath:a[1]),out=URL(fileURLWithPath:a[2],isDirectory:true)
            try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            switch a[0] {
            case "inspect":try await inspect(source,out)
            case "benchmark":try await benchmark(source,out,count:a.count>3 ? Int(a[3]) ?? 100 : 100)
            case "preview-benchmark":try await previewBenchmark(source,out)
            case "import":let library=try PhotoLibrary(root:out);let result=try await library.importPhoto(source);print("Imported \(result.asset.name), RAW=\(result.asset.isRAW), duplicate=\(result.duplicate)")
            default:throw LumaError.unsupported("Unknown command")
            }
        } catch { fputs("ERROR: \(error.localizedDescription)\n",stderr);exit(1) }
    }
    static func save(_ cg: CGImage,_ url: URL) throws {
        guard let d=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else { throw LumaError.invalidImage("PNG destination") };CGImageDestinationAddImage(d,cg,nil)
        guard CGImageDestinationFinalize(d) else { throw LumaError.invalidImage("PNG write") }
    }
    /// Reproducible preview workload: the same HSL/curves while exposure changes.
    /// This measures the image engine, independently of UI automation overhead.
    static func previewBenchmark(_ source: URL,_ out: URL) async throws {
        let processor=try PhotoProcessor(),hash=try ContentDigest.sha256(source)
        var reports=[[String:Any]]()
        for advanced in [false,true] {
            var r=Recipe();r.beauty.enabled=false
            if advanced {
                r.document.color.hsl=[HSLAdjustment(band:.orange,saturation:0.2,luminance:0.1),HSLAdjustment(band:.blue,hue:0.02,saturation:0.15)]
                r.document.color.curve.master=[CurvePoint(0,0),CurvePoint(0.3,0.26),CurvePoint(0.7,0.76),CurvePoint(1,1)]
            }
            var samples=[Double]()
            for i in 0..<25 {
                r.document.global.exposure=Float(i%9)*0.04
                let result=try await processor.render(url:source,recipe:r)
                samples.append(result.milliseconds)
                if i==24 {try save(result.image,out.appendingPathComponent(advanced ? "advanced.png" : "tone.png"))}
            }
            let warm=Array(samples.dropFirst()).sorted()
            reports.append(["workload":advanced ? "tone_with_hsl_curve" : "tone","cold_ms":samples[0],"warm_median_ms":warm[warm.count/2],"warm_p95_ms":warm[Int(Double(warm.count-1)*0.95)],"samples_ms":samples])
        }
        guard try ContentDigest.sha256(source)==hash else {throw LumaError.corruptData("Original changed")}
        let report:[String:Any] = ["input":source.lastPathComponent,"sha256":hash,"device":MTLCreateSystemDefaultDevice()?.name ?? "software","build":"Release","scope":"engine preview; not end-to-end UI latency","workloads":reports]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("report.json"))
        print("PREVIEW BENCHMARK SUCCESS")
    }
    static func inspect(_ source: URL,_ out: URL) async throws {
        let processor=try PhotoProcessor();var recipe=Recipe();recipe.beauty.enabled=true
        let beforeHash=try ContentDigest.sha256(source)
        let r=try await processor.render(url:source,recipe:recipe)
        try save(r.original,out.appendingPathComponent("original.png"));try save(r.image,out.appendingPathComponent("beauty.png"))
        let decoder=ImageDecoder();let thumb=try decoder.decode(source,tier:.thumbnail)
        print("Thumbnail \(Int(thumb.extent.width))x\(Int(thumb.extent.height))")
        var ms=[Double]()
        for _ in 0..<8 { let sample=try await processor.render(url:source,recipe:recipe);ms.append(sample.milliseconds) }
        let export=out.appendingPathComponent("full-resolution.jpg")
        _=try await processor.export(url:source,recipe:recipe,destination:export)
        let decoded=try decoder.decode(export,tier:.fullResolution)
        let fullExtent=try decoder.decode(source,tier:.fullResolution).extent
        guard fullExtent.size==decoded.extent.size else { throw LumaError.corruptData("Full-resolution dimensions changed") }
        let native: String
        if PhotoFileType.isRAW(source), let raw=CIRAWFilter(imageURL:source) { native="\(Int(raw.nativeSize.width))x\(Int(raw.nativeSize.height))" } else { native="not-RAW" }
        var adjustments=[String:Double]()
        if PhotoFileType.isRAW(source) {
            for (name,value) in [("exposure",Float(0.7)),("whitebalance",Float(5200)),("shadows",Float(0.25))] {
                var changed=recipe
                if name=="exposure" { changed.raw.exposure=value }
                if name=="whitebalance" { changed.raw.temperature=value }
                if name=="shadows" { changed.raw.shadows=value }
                let sample=try await processor.render(url:source,recipe:changed);try save(sample.image,out.appendingPathComponent("raw-\(name).png"));adjustments[name]=sample.milliseconds
            }
        }
        let profile=try await processor.referenceProfile(url:source,name:"Self reference validation")
        try await processor.exportLUT(source:source,profile:profile,destination:out.appendingPathComponent("self-reference.cube"))
        var matched=recipe;matched.color.referenceProfileID=profile.id
        let match=try await processor.render(url:source,recipe:matched,profile:profile);try save(match.image,out.appendingPathComponent("self-reference.png"))
        let afterHash=try ContentDigest.sha256(source)
        guard beforeHash==afterHash else { throw LumaError.corruptData("Original changed") }
        let tiff=(CGImageSourceCreateWithURL(source as CFURL,nil).flatMap{CGImageSourceCopyPropertiesAtIndex($0,0,nil)} as? [CFString:Any])?[kCGImagePropertyTIFFDictionary] as? [CFString:Any]
        let report: [String:Any] = ["cameraModel":tiff?[kCGImagePropertyTIFFModel] as? String ?? "unknown","cameraMake":tiff?[kCGImagePropertyTIFFMake] as? String ?? "unknown","input":source.lastPathComponent,"sha256":beforeHash,"metalDevice":MTLCreateSystemDefaultDevice()?.name ?? "software","rawNativeSize":native,"previewWidth":r.image.width,"previewHeight":r.image.height,"faces":r.faceCount,"beautyBackend":r.beautyBackend,"coldPreviewMS":r.milliseconds,"warmPreviewMS":ms,"warmMedianMS":ms.sorted()[ms.count/2],"exportWidth":Int(decoded.extent.width),"exportHeight":Int(decoded.extent.height),"rawAdjustmentMS":adjustments,"originalUnchanged":beforeHash==afterHash]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("report.json"))
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted),encoding:.utf8)!)
    }
    static func benchmark(_ source: URL,_ out: URL,count: Int) async throws {
        guard (1...1000).contains(count) else { throw LumaError.corruptData("benchmark count") }
        let fm=FileManager.default, inputs=out.appendingPathComponent("inputs"),outputs=out.appendingPathComponent("exports")
        try fm.createDirectory(at:inputs,withIntermediateDirectories:true);try fm.createDirectory(at:outputs,withIntermediateDirectories:true)
        var assets=[PhotoAsset]()
        for i in 0..<count {
            let u=inputs.appendingPathComponent("workload-\(i).\(source.pathExtension)")
            if !fm.fileExists(atPath:u.path) { try fm.linkItem(at:source,to:u) }
            assets.append(PhotoAsset(name:u.lastPathComponent,originalURL:u,thumbnailURL:u))
        }
        var recipe=Recipe();recipe.beauty.enabled=true;recipe.color.presetID="portrait"
        let engine=BatchProcessor(concurrency:2,journalURL:out.appendingPathComponent("queue.json"))
        let start=Date()
        try await engine.start(assets:assets,recipe:recipe,profile:nil,exportDirectory:outputs,libraryRoot:nil) { s in
            if !s.active || s.completed%10==0 { print("completed=\(s.completed) failed=\(s.failures) progress=\(s.progress)");fflush(stdout) }
        }
        await engine.waitUntilFinished()
        guard let final=await engine.current(),final.completed==count,final.failures==0 else { throw LumaError.corruptData("Benchmark did not finish successfully") }
        let report: [String:Any] = ["count":count,"completed":final.completed,"failures":final.failures,"elapsedSeconds":Date().timeIntervalSince(start),"concurrency":2,"input":source.lastPathComponent,"workload":"same real source hard-linked under distinct paths; not 100 different scenes","outputDimensions":"original dimensions; full-resolution pipeline"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("report.json"));print("BENCHMARK SUCCESS")
    }
}
