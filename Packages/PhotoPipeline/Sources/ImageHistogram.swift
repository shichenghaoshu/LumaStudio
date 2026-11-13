import Foundation
import CoreGraphics

public struct ImageHistogram: Sendable {
    public var red=[Double](repeating:0,count:96),green=[Double](repeating:0,count:96),blue=[Double](repeating:0,count:96)
    public var shadows=0.0,highlights=0.0
    public init() {}
    public static func measure(_ image: CGImage)->Self {
        let width=160,height=min(200,max(1,Int(Double(image.height)*160/Double(image.width))))
        var result=Self()
        // Let CGContext own the bitmap. A pointer borrowed from a Swift Array may
        // not escape CGContext.init; drawing later must use storage that stays alive.
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),let storage=context.data else{return result}
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        let bytes=storage.assumingMemoryBound(to:UInt8.self)
        var shadows=0,highlights=0
        withExtendedLifetime(context) {
            for i in stride(from:0,to:width*height*4,by:4) {
                result.red[Int(bytes[i])*95/255] += 1;result.green[Int(bytes[i+1])*95/255] += 1;result.blue[Int(bytes[i+2])*95/255] += 1
                let y=0.2126*Double(bytes[i])+0.7152*Double(bytes[i+1])+0.0722*Double(bytes[i+2])
                if y<4{shadows += 1};if y>251{highlights += 1}
            }
        }
        let total=Double(width*height);result.shadows=Double(shadows)/total;result.highlights=Double(highlights)/total
        return result
    }
}
