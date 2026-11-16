import XCTest
import CoreImage
import PhotoDomain
@testable import ColorEngine

final class CameraLookPhotoTests:XCTestCase {
    func testAllCameraLooksOnSixPublicScenesWithRealIntensity() throws {
        let env=ProcessInfo.processInfo.environment
        guard let folder=env["LUMA_COLOR_LOOK_FIXTURES"],let output=env["LUMA_COLOR_LOOK_OUTPUT"] else {throw XCTSkip("Explicit licensed color-look fixtures required")}
        let root=URL(fileURLWithPath:output).appendingPathComponent("Photos")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let files=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil).filter{$0.pathExtension.lowercased()=="jpg"}.sorted{$0.path<$1.path}
        XCTAssertEqual(files.count,6)
        let context=CIContext(options:[.workingColorSpace:CGColorSpace(name:CGColorSpace.extendedLinearSRGB)!,.cacheIntermediates:false])
        let space=CGColorSpace(name:CGColorSpace.sRGB)!,processor=try ColorProcessor()
        func pixels(_ image:CIImage)->[UInt8] {
            let w=Int(image.extent.width),h=Int(image.extent.height)
            var data=[UInt8](repeating:0,count:w*h*4)
            context.render(image,toBitmap:&data,rowBytes:w*4,bounds:image.extent,format:.RGBA8,colorSpace:space)
            return data
        }
        func difference(_ a:[UInt8],_ b:[UInt8])->Double {zip(a,b).enumerated().reduce(0.0){$0+($1.offset%4==3 ? 0 : Double(abs(Int($1.element.0)-Int($1.element.1))))}/Double(a.count/4*3)}
        var reports=[[String:Any]]()
        for file in files {
            try autoreleasepool {
                let source=try XCTUnwrap(CIImage(contentsOf:file,options:[.applyOrientationProperty:true]))
                let scale=min(1,1280/max(source.extent.width,source.extent.height)),scaled=source.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
                let image=CIImage(cgImage:try XCTUnwrap(context.createCGImage(scaled,from:scaled.extent.integral,format:.RGBA8,colorSpace:space)))
                let original=pixels(image),name=file.deletingPathExtension().lastPathComponent
                try context.writePNGRepresentation(of:image,to:root.appendingPathComponent(name+"-original.png"),format:.RGBA8,colorSpace:space)
                for look in CameraColorLook.allCases {
                    var settings=ColorSettings();settings.presetID=look.rawValue;settings.intensity=0
                    let zero=try processor.apply(image,settings:settings,profile:nil,skinMask:nil,context:context)
                    XCTAssertLessThanOrEqual(difference(original,pixels(zero)),0.1,look.rawValue+" off")
                    settings.intensity=1
                    let started=Date(),full=try processor.apply(image,settings:settings,profile:nil,skinMask:nil,context:context),colored=pixels(full)
                    let seconds=Date().timeIntervalSince(started),change=difference(original,colored)
                    XCTAssertGreaterThan(change,0.4,name+" "+look.rawValue)
                    settings.intensity=0.5
                    let half=pixels(try processor.apply(image,settings:settings,profile:nil,skinMask:nil,context:context))
                    let halfChange=difference(original,half)
                    XCTAssertGreaterThan(halfChange,0);XCTAssertLessThan(halfChange,change)
                    let destination=root.appendingPathComponent(name+"-"+look.rawValue+".png")
                    try context.writePNGRepresentation(of:full,to:destination,format:.RGBA8,colorSpace:space)
                    reports.append(["source":file.lastPathComponent,"look":look.rawValue,"meanAbsoluteRGBChange8bit":change,"halfIntensityChange":halfChange,"renderSeconds":seconds,"output":destination.lastPathComponent])
                }
            }
        }
        try JSONSerialization.data(withJSONObject:["scope":"Six independently sourced photos, 11 looks, actual GPU color processing at 1280px; intensity checks are engineering evidence, not vendor similarity or aesthetic scores","results":reports],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output).appendingPathComponent("photo-matrix.json"))
    }
}
