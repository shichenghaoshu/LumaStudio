import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let size=1024
let image=NSImage(size:NSSize(width:size,height:size))
image.lockFocus()
let bounds=NSRect(x:0,y:0,width:size,height:size)
let bg=NSBezierPath(roundedRect:bounds,xRadius:220,yRadius:220)
NSGradient(starting:NSColor(calibratedRed:0.15,green:0.16,blue:0.17,alpha:1),ending:NSColor(calibratedRed:0.025,green:0.035,blue:0.04,alpha:1))!.draw(in:bg,angle:-90)
NSColor(calibratedRed:0.9,green:0.71,blue:0.44,alpha:1).setStroke()
let ring=NSBezierPath(ovalIn:NSRect(x:222,y:222,width:580,height:580));ring.lineWidth=26;ring.stroke()
let center=NSPoint(x:512,y:512)
for k in 0..<6 {
    let angle=Double(k)*Double.pi/3
    func p(_ x:Double,_ y:Double)->NSPoint { NSPoint(x:center.x+x*cos(angle)-y*sin(angle),y:center.y+x*sin(angle)+y*cos(angle)) }
    let blade=NSBezierPath();blade.move(to:p(-98,164));blade.line(to:p(94,164));blade.line(to:p(251,-20));blade.line(to:p(158,-180));blade.close()
    NSColor(calibratedRed:0.9,green:0.71,blue:0.44,alpha:0.60+Double(k)*0.06).setFill();blade.fill()
}
image.unlockFocus()
let tiff=image.tiffRepresentation!,rep=NSBitmapImageRep(data:tiff)!
try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("Resources/Icons/LumaStudio-1024.png"))
