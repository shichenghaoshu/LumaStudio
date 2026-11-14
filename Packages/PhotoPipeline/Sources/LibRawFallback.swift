import Foundation
import CoreImage
import ImageIO
import CryptoKit
import PhotoDomain

/// Capability routing is per file, not per extension: compressed variants of one
/// camera can differ. Results include file size/date so replacing a file re-probes it.
enum RAWBackendRouter {
    private static let lock=NSLock()
    private static var native=[String:Bool]()
    static func stamp(_ url: URL)->String {
        let a=try? FileManager.default.attributesOfItem(atPath:url.path)
        let modified=(a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return url.standardizedFileURL.path+"|"+String(describing:a?[.size])+"|"+String(modified)+"|"+String(describing:a?[.systemFileNumber])
    }
    static func nativeAvailable(_ url: URL)->Bool {
        let key=stamp(url);lock.lock();let cached=native[key];lock.unlock()
        if let cached {return cached}
        let supported: Bool
        if let f=CIRAWFilter(imageURL:url) {f.scaleFactor=0.02;supported=f.outputImage != nil} else {supported=false}
        lock.lock();if native.count>256 {native.removeAll()};native[key]=supported;lock.unlock()
        return supported
    }
}

enum LibRawFallback {
    static var executable: URL? {
        #if os(macOS)
        if let resources=Bundle.main.resourceURL {
            let u=resources.appendingPathComponent("libraw-runtime/luma-raw-decode")
            if FileManager.default.isExecutableFile(atPath:u.path) {return u}
        }
        // SwiftPM diagnostics/tests use the same checked-in, relocatable runtime.
        var root=URL(fileURLWithPath:#filePath)
        for _ in 0..<4 {root.deleteLastPathComponent()}
        let u=root.appendingPathComponent("Vendor/libraw-runtime/luma-raw-decode")
        return FileManager.default.isExecutableFile(atPath:u.path) ? u : nil
        #else
        return nil
        #endif
    }
    static func canOpen(_ url: URL)->Bool {
        #if os(macOS)
        guard let executable else {return false}
        return (try? run(executable,args:["--identify",url.path],timeout:8)) != nil
        #else
        return false
        #endif
    }
    static func decode(_ url: URL,tier: RenderTier,raw: RAWSettings)throws->CIImage {
        #if os(macOS)
        guard let executable else {throw LumaError.unsupported("系统不能解码此 RAW，且 LibRaw 备用组件未安装")}
        var unsupported=raw;unsupported.exposure=0
        guard unsupported==RAWSettings() else {throw LumaError.unsupported("此文件使用 LibRaw 备用显影，仅支持 RAW 曝光与相机白平衡；请重置其余 RAW 参数，在基础影调中调色")}
        let fm=FileManager.default,cache=fm.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/LibRaw-0.22.3")
        try fm.createDirectory(at:cache,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stamp=RAWBackendRouter.stamp(url)+"|"+String(raw.exposure)
        let key=SHA256.hash(data:Data(stamp.utf8)).map{String(format:"%02x",$0)}.joined()
        let target=cache.appendingPathComponent(key+".tiff")
        if !fm.fileExists(atPath:target.path) {
            let stage=cache.appendingPathComponent(UUID().uuidString+".partial")
            defer{try? fm.removeItem(at:stage)}
            try run(executable,args:[url.path,stage.path,String(raw.exposure)],timeout:60)
            // Another worker may have decoded this file in parallel.
            do {try fm.moveItem(at:stage,to:target)} catch {if !fm.fileExists(atPath:target.path){throw error}}
            trim(cache,keeping:target)
        }
        guard let source=CGImageSourceCreateWithURL(target as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else {throw LumaError.invalidImage("LibRaw 16-bit TIFF")}
        let cg: CGImage?
        if let max=tier.maxDimension {cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max] as CFDictionary)}
        else {cg=CGImageSourceCreateImageAtIndex(source,0,nil)}
        guard let cg else {throw LumaError.invalidImage("LibRaw 备用显影输出")}
        return CIImage(cgImage:cg,options:[.colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!])
        #else
        throw LumaError.unsupported("此平台尚未包含 LibRaw 备用显影")
        #endif
    }
    #if os(macOS)
    private static func run(_ executable: URL,args: [String],timeout: TimeInterval)throws {
        let process=Process();process.executableURL=executable;process.arguments=args
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        let done=DispatchSemaphore(value:0);process.terminationHandler={_ in done.signal()}
        try process.run()
        if done.wait(timeout:.now()+timeout) == .timedOut {process.terminate();process.waitUntilExit();throw LumaError.unsupported("LibRaw 显影超时")}
        guard process.terminationStatus==0 else {throw LumaError.unsupported("LibRaw 无法解码该 RAW（状态 \(process.terminationStatus)）；原片已保留")}
    }
    private static func trim(_ cache: URL,keeping: URL) {
        let files=(try? FileManager.default.contentsOfDirectory(at:cache,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey])) ?? []
        let sorted=files.filter{$0.pathExtension=="tiff"}.sorted{((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
        var total=0
        for file in sorted {total += (try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;if total>512*1024*1024,file != keeping {try? FileManager.default.removeItem(at:file)}}
    }
    #endif
}
