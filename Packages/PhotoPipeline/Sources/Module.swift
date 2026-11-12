import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Metal
import UniformTypeIdentifiers
import PhotoDomain
import BeautyEngine
import ColorEngine
import ToolRegistry
import VisionEngine

public struct RenderResult {
    public let image: CGImage
    public let original: CGImage
    public let faceCount: Int
    public let beautyBackend: String
    public let milliseconds: Double
    public let skinMask: CGImage?
}
public final class ImageDecoder: @unchecked Sendable {
    private let cache=NSCache<NSURL,CIImage>()
    public init() { cache.countLimit=3; cache.totalCostLimit=48*1024*1024 }
    public func decode(_ url: URL,tier: RenderTier,raw: RAWSettings = RAWSettings()) throws -> CIImage {
        if case .preview=tier, raw.exposure == 0,raw.temperature == nil,raw.tint == nil,raw.shadows == 0,raw.highlights == 0.7, let cached=cache.object(forKey:url as NSURL) { return cached }
        let image: CIImage
        if PhotoFileType.isRAW(url), tier != .thumbnail {
            guard let filter=CIRAWFilter(imageURL:url) else { throw LumaError.unsupported("当前系统 CIRAWFilter 无法解码 \(url.lastPathComponent)，可使用配对 JPEG；原 RAW 保留。") }
            filter.exposure=raw.exposure
            if let t=raw.temperature { filter.neutralTemperature=t }
            if let tint=raw.tint { filter.neutralTint=tint }
            filter.boostShadowAmount=1+raw.shadows
            filter.boostAmount=1
            if filter.isLocalToneMapSupported { filter.localToneMapAmount=raw.highlights }
            if let max=tier.maxDimension { filter.scaleFactor=min(1,Float(max)/Float(maximum(filter.nativeSize))) }
            guard let result=filter.outputImage else { throw LumaError.invalidImage(url.lastPathComponent) }; image=normalize(result)
        } else {
            guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else { throw LumaError.invalidImage(url.lastPathComponent) }
            let cg: CGImage?
            if let max=tier.maxDimension { cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max] as CFDictionary) }
            else { cg=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) }
            guard let cg else { throw LumaError.invalidImage(url.lastPathComponent) }
            if tier == .fullResolution {
                let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
                let orientation=(props?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
                image=normalize(CIImage(cgImage:cg).oriented(forExifOrientation:orientation))
            } else { image=CIImage(cgImage:cg) }
        }
        guard image.extent.width>0,image.extent.height>0,image.extent.width.isFinite,image.extent.height.isFinite else { throw LumaError.invalidImage(url.lastPathComponent) }
        if tier == .preview,raw.exposure == 0,raw.temperature == nil,raw.tint == nil,raw.shadows == 0,raw.highlights == 0.7 { cache.setObject(image,forKey:url as NSURL,cost:Int(image.extent.width*image.extent.height)*8) }
        return image
    }
    private func maximum(_ size: CGSize)->CGFloat { max(size.width,size.height) }
    private func normalize(_ image: CIImage)->CIImage { image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY)) }
    public func clearCache() { cache.removeAllObjects() }
}
public enum SafeExport {
    /// Resolve the closest existing ancestor, since Foundation does not resolve a
    /// symlink parent when the final export file has not been created yet.
    public static func canonical(_ url: URL) -> URL {
        var ancestor=url.standardizedFileURL, suffix=[String]()
        while !FileManager.default.fileExists(atPath:ancestor.path),ancestor.path != "/" {
            suffix.insert(ancestor.lastPathComponent,at:0);ancestor=ancestor.deletingLastPathComponent()
        }
        var result=ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in suffix { result.appendPathComponent(component) }
        return result.standardizedFileURL
    }

    public static func validate(destination: URL, originals: [URL], libraryRoot: URL?) throws {
        let target=canonical(destination).path.lowercased()
        for original in originals { if target == canonical(original).path.lowercased() { throw LumaError.unsafeDestination } }
        if let root=libraryRoot {
            let protected=canonical(root.appendingPathComponent("Originals")).path.lowercased()
            if target == protected || target.hasPrefix(protected+"/") { throw LumaError.unsafeDestination }
        }
    }
    public static func uniqueURL(folder: URL,baseName: String,format: ExportFormat)->URL {
        let base=URL(fileURLWithPath:baseName).deletingPathExtension().lastPathComponent
        return folder.appendingPathComponent("\(base)_Luma_\(UUID().uuidString.prefix(8)).\(format == .jpeg ? "jpg" : format.rawValue)")
    }
}
public actor PhotoProcessor {
    public nonisolated let context: CIContext
    public nonisolated let decoder=ImageDecoder()
    private let beauty: BeautyProcessor
    private let color: ColorProcessor
    private let previewCache=NSCache<NSString,CIImage>()
    private var skinCache: (String,SkinAnalysis)?
    private let semanticMasks=SemanticMaskEngine()
    private var maskCache: (String,Set<MaskKind>,[MaskKind:CIImage])?
    public init(modelURL: URL? = nil) throws {
        if let device=MTLCreateSystemDefaultDevice() { context=CIContext(mtlDevice:device,options:[.cacheIntermediates:false,.workingColorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!]) }
        else { context=CIContext(options:[.useSoftwareRenderer:true,.cacheIntermediates:false]) }
        beauty=try BeautyProcessor(modelURL:modelURL); color=try ColorProcessor();previewCache.countLimit=2;previewCache.totalCostLimit=40*1024*1024
    }
    private func prepared(url: URL,recipe: Recipe,tier: RenderTier,profile: ColorProfile?,raw: RAWSettings) throws -> (CIImage,CIImage,SkinAnalysis?) {
        let r=try recipe.validated()
        if let edit=r.edit { try ToolRegistry().validate(edit) }
        if r.color.referenceProfileID != nil && profile?.id != r.color.referenceProfileID { throw LumaError.unsupported("配方引用的色彩档案未找到，请先导入对应档案。") }
        let attributes=try? FileManager.default.attributesOfItem(atPath:url.path)
        let stamp=(attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let rawKey=(try? JSONEncoder().encode(raw).base64EncodedString()) ?? ""
        let key=url.path+"|"+String(stamp)+"|"+rawKey
        let original: CIImage
        if tier == .preview,let cached=previewCache.object(forKey:key as NSString) { original=cached }
        else {
            let decoded=try decoder.decode(url,tier:tier,raw:raw)
            if tier == .preview {
                guard let cg=context.createCGImage(decoded,from:decoded.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) else { throw LumaError.invalidImage("预览缓存") }
                original=CIImage(cgImage:cg)
                previewCache.setObject(original,forKey:key as NSString,cost:cg.width*cg.height*4)
            } else { original=decoded }
        }
        let analysis: SkinAnalysis?
        if r.beauty.enabled || profile != nil || r.edit?.evaluation.preserveSkin==true || r.edit?.masks.contains(where:{$0.kind == .skin})==true {
            if tier == .preview,let cached=skinCache,cached.0==key { analysis=cached.1 }
            else { let result=try beauty.segmentation.analyze(original,context:context);analysis=result;if tier == .preview { skinCache=(key,result) } }
        } else { analysis=nil }
        var image=original
        if let edit=r.edit { image=RecipeAdjustments.global(image,edit.global) }
        if let analysis { image=try beauty.apply(image,settings:r.beauty,analysis:analysis,context:context) }
        var colorSettings=r.color
        if r.edit != nil { colorSettings.exposure=0;colorSettings.contrast=1;colorSettings.saturation=1;colorSettings.temperature=6500 }
        image=try color.apply(image,settings:colorSettings,profile:profile,skinMask:analysis?.mask,context:context)
        if let edit=r.edit {
            image=try RecipeAdjustments.advancedColor(image,edit.color)
            let kinds=Set(edit.masks.map(\.kind))
            let maskKey=key+"|\(Int(original.extent.width))x\(Int(original.extent.height))"
            let masks: [MaskKind:CIImage]
            if tier == .preview,let cached=maskCache,cached.0==maskKey,cached.1==kinds { masks=cached.2 }
            else {
                masks=try semanticMasks.masks(for:original,kinds:kinds,skin:analysis?.mask,context:context)
                if tier == .preview { maskCache=(maskKey,kinds,masks) }
            }
            for local in edit.masks {
                try Task.checkCancellation()
                if local.kind == .skin,analysis?.faceCount == 0 { throw LumaError.unsupported("未检测到人脸皮肤；局部调整未执行") }
                guard let mask=masks[local.kind] else { throw LumaError.unsupported("局部区域 \(local.kind.rawValue) 不可用") }
                let adjusted=RecipeAdjustments.global(image,local.adjustments)
                let opacity=CGFloat(local.amount)
                let weighted=mask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:opacity,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:opacity,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:opacity,w:0)])
                image=adjusted.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:image,kCIInputMaskImageKey:weighted]).cropped(to:original.extent)
            }
        }
        return (original,image,analysis)
    }
    public func render(url: URL,recipe: Recipe,tier: RenderTier = .preview,profile: ColorProfile? = nil,raw: RAWSettings? = nil) throws -> RenderResult {
        let start=Date(); let (original,image,analysis)=try prepared(url:url,recipe:recipe,tier:tier,profile:profile,raw:raw ?? recipe.raw)
        guard let cg=context.createCGImage(image,from:image.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!),let source=context.createCGImage(original,from:original.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) else { throw LumaError.invalidImage("渲染") }
        let mask: CGImage?
        if tier == .preview,let analysis,analysis.faceCount>0 { mask=context.createCGImage(analysis.mask,from:analysis.mask.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) } else { mask=nil }
        let backend=recipe.beauty.enabled ? beauty.lastBackend+" · "+(analysis?.backend ?? "") : (analysis?.backend ?? "美颜未开启")
        return RenderResult(image:cg,original:source,faceCount:analysis?.faceCount ?? 0,beautyBackend:backend,milliseconds:Date().timeIntervalSince(start)*1000,skinMask:mask)
    }
    public func referenceProfile(url: URL,name: String) throws -> ColorProfile {
        let image=try decoder.decode(url,tier:.preview)
        return ColorProfile(name:name,reference:try color.analyze(image,context:context))
    }
    public func exportLUT(source: URL,profile: ColorProfile,destination: URL) throws {
        let image=try decoder.decode(source,tier:.preview)
        let lut=try color.matchingLUT(source:color.analyze(image,context:context),profile:profile,dimension:33)
        try lut.cube(title:profile.name).write(to:destination,atomically:true,encoding:.utf8)
    }
    public func export(url: URL,recipe: Recipe,destination: URL,libraryRoot: URL? = nil,profile: ColorProfile? = nil,raw: RAWSettings? = nil) throws -> URL {
        try SafeExport.validate(destination:destination,originals:[url],libraryRoot:libraryRoot)
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw LumaError.unsafeDestination }
        try Task.checkCancellation()
        let r=try recipe.validated(); let (_,image,_)=try prepared(url:url,recipe:r,tier:.fullResolution,profile:profile,raw:raw ?? r.raw)
        let stage=destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at:stage) }
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        switch r.export.format {
        case .jpeg: try context.writeJPEGRepresentation(of:image,to:stage,colorSpace:space,options:[kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:r.export.quality])
        case .png: try context.writePNGRepresentation(of:image,to:stage,format:.RGBA8,colorSpace:space)
        case .tiff: try context.writeTIFFRepresentation(of:image,to:stage,format:.RGBA16,colorSpace:space)
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at:stage,to:destination) // fails instead of overwriting, including races.
        context.clearCaches(); return destination
    }
    public func releaseCaches() { decoder.clearCache();previewCache.removeAllObjects();skinCache=nil;maskCache=nil;context.clearCaches() }
}
