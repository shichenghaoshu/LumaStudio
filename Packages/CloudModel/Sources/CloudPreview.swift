import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CloudPreview {
    /// New JPEG contains only the downscaled image, without original EXIF/location metadata.
    public static func jpeg(_ url: URL) throws -> Data? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:512] as CFDictionary) else { return nil }
        let bytes=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(bytes,UTType.jpeg.identifier as CFString,1,nil) else { return nil }
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination),bytes.length<=512*1024 else { return nil };return bytes as Data
    }
}
