import AppKit

// Compose standard macOS icon slots from the user's unmodified artwork.
// This is asset sizing/layout; the trademark itself is never redrawn.
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let source=root.appendingPathComponent("Resources/Assets.xcassets/ShiguangMark.imageset/shiguang-mark.png")
guard let mark=NSImage(contentsOf:source) else {fatalError("Missing supplied trademark")}
let folder=root.appendingPathComponent("Resources/Assets.xcassets/ShiguangAppIcon.appiconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
func render(_ pixels: Int)->Data {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let n=CGFloat(pixels),inset=n*0.055
    let rect=NSRect(x:inset,y:inset,width:n-2*inset,height:n-2*inset)
    let tile=NSBezierPath(roundedRect:rect,xRadius:n*0.19,yRadius:n*0.19)
    NSColor.white.setFill();tile.fill();tile.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    mark.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using:.png,properties:[:])!
}
var slots=[[String:String]]()
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let name="mac-\(size)-\(scale).png"
        try render(size*scale).write(to:folder.appendingPathComponent(name))
        slots.append(["idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x","filename":name])
    }
}
let contents:[String:Any]=["images":slots,"info":["author":"xcode","version":1]]
try JSONSerialization.data(withJSONObject:contents,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("Contents.json"))
try render(1024).write(to:root.appendingPathComponent("Resources/Icons/Shiguang-1024.png"))
print("Created 10 Mac icon slots from the supplied trademark")
