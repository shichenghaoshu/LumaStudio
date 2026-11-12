import Foundation
import ImageIO
let folder=URL(fileURLWithPath:CommandLine.arguments[1])
let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}
var failures=[String]()
for url in files {
    guard let source=CGImageSourceCreateWithURL(url as CFURL,nil), let p=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let w=p[kCGImagePropertyPixelWidth] as? Int,let h=p[kCGImagePropertyPixelHeight] as? Int,w==5184,h==3888 else {failures.append(url.lastPathComponent);continue}
}
print("JPEG count=\(files.count), dimensions=5184x3888, invalid=\(failures.count)")
if files.count != 100 || !failures.isEmpty {exit(1)}
