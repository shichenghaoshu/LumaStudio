import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import PhotoDomain

enum ImageExport {
    static func write(_ input: CIImage,source: URL,to destination: URL,settings: ExportSettings,context: CIContext)throws {
        var image=input
        let maxDimension=max(image.extent.width,image.extent.height)
        if settings.longEdge>0,CGFloat(settings.longEdge)<maxDimension {
            let scale=CGFloat(settings.longEdge)/maxDimension
            image=image.applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:scale,kCIInputAspectRatioKey:1])
            image=image.cropped(to:CGRect(x:0,y:0,width:max(1,floor(image.extent.width)),height:max(1,floor(image.extent.height))))
        }
        let colorName: CFString
        switch settings.colorSpace {case .sRGB:colorName=CGColorSpace.sRGB;case .displayP3:colorName=CGColorSpace.displayP3;case .adobeRGB1998:colorName=CGColorSpace.adobeRGB1998}
        guard let space=CGColorSpace(name:colorName) else {throw LumaError.unsupported("输出色彩空间不可用")}
        let depth=settings.format == .jpeg ? 8 : settings.bitDepth
        guard let cg=context.createCGImage(image,from:image.extent,format:depth==16 ? .RGBA16 : .RGBA8,colorSpace:space) else {throw LumaError.invalidImage("输出像素")}
        let type: UTType=settings.format == .jpeg ? .jpeg : (settings.format == .png ? .png : .tiff)
        guard let dest=CGImageDestinationCreateWithURL(destination as CFURL,type.identifier as CFString,1,nil) else {throw LumaError.invalidImage("输出目标")}
        var properties=[CFString:Any]()
        if settings.preserveEXIF,let original=CGImageSourceCreateWithURL(source as CFURL,nil),let metadata=CGImageSourceCopyPropertiesAtIndex(original,0,nil) as? [CFString:Any] {
            // Intrinsic source properties (notably Depth=8) must not override the
            // newly rendered pixels. Preserve metadata families, not old headers.
            for key in [kCGImagePropertyExifDictionary,kCGImagePropertyExifAuxDictionary,kCGImagePropertyTIFFDictionary,kCGImagePropertyGPSDictionary,kCGImagePropertyIPTCDictionary] {if let value=metadata[key] {properties[key]=value}}
        }
        properties[kCGImagePropertyOrientation]=1;properties[kCGImagePropertyPixelWidth]=cg.width;properties[kCGImagePropertyPixelHeight]=cg.height
        properties[kCGImagePropertyDPIWidth]=settings.dpi;properties[kCGImagePropertyDPIHeight]=settings.dpi
        properties[kCGImagePropertyDepth]=depth
        if settings.format == .jpeg {properties[kCGImageDestinationLossyCompressionQuality]=settings.quality}
        properties[kCGImageDestinationEmbedThumbnail]=false
        var tiff=properties[kCGImagePropertyTIFFDictionary] as? [CFString:Any] ?? [:]
        tiff[kCGImagePropertyTIFFXResolution]=settings.dpi;tiff[kCGImagePropertyTIFFYResolution]=settings.dpi;tiff[kCGImagePropertyTIFFResolutionUnit]=2;tiff[kCGImagePropertyTIFFOrientation]=1
        tiff[kCGImagePropertyTIFFSoftware]="LumaStudio"
        if settings.format == .tiff {tiff[kCGImagePropertyTIFFCompression]=5}
        properties[kCGImagePropertyTIFFDictionary]=tiff
        if settings.preserveEXIF {
            var exif=properties[kCGImagePropertyExifDictionary] as? [CFString:Any] ?? [:]
            exif[kCGImagePropertyExifPixelXDimension]=cg.width;exif[kCGImagePropertyExifPixelYDimension]=cg.height
            exif[kCGImagePropertyExifColorSpace]=settings.colorSpace == .sRGB ? 1 : 65535
            properties[kCGImagePropertyExifDictionary]=exif
        }
        CGImageDestinationAddImage(dest,cg,properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {throw LumaError.invalidImage("输出写入未完成")}
    }
}
