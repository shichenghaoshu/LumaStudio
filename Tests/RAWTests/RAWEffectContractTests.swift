import XCTest
import CoreImage
import PhotoPipeline
import PhotoDomain

final class RAWEffectContractTests:XCTestCase {
    func testDeclaredSharpnessIsMeasuredAtPreviewAndFullResolution() async throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_RAW_FIXTURE"] else {throw XCTSkip("A real camera RAW is required")}
        let url=URL(fileURLWithPath:path),caps=RAWCapabilities.inspect(url)
        guard caps.supported.contains("raw.sharpness") else {throw XCTSkip("This decoder does not declare native sharpening")}
        let worker=try PhotoProcessor(),context=CIContext()
        var r=Recipe();r.color.enabled=false;r.document.evaluation.preserveSkin=false;r.raw.detail=1;r.raw.sharpness=0
        var records=[[String:Any]]()
        for tier in [RenderTier.preview,.fullResolution] {
            r.raw.sharpness=0;let a=try await worker.render(url:url,recipe:r,tier:tier)
            r.raw.sharpness=1;let b=try await worker.render(url:url,recipe:r,tier:tier)
            let w=a.image.width,h=a.image.height
            var x=[UInt8](repeating:0,count:w*h*4),y=x
            context.render(CIImage(cgImage:a.image),toBitmap:&x,rowBytes:w*4,bounds:CGRect(x:0,y:0,width:w,height:h),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
            context.render(CIImage(cgImage:b.image),toBitmap:&y,rowBytes:w*4,bounds:CGRect(x:0,y:0,width:w,height:h),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
            let difference=zip(x,y).reduce(0){$0+abs(Int($1.0)-Int($1.1))}
            records.append(["tier":tier == .preview ? "preview" : "fullResolution","width":w,"height":h,"absoluteByteDifference":difference])
            if tier == .fullResolution {XCTAssertGreaterThan(difference,0,"A declared RAW sharpness control must affect the full-resolution output")}
            await worker.releaseCaches()
        }
        if let folder=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"] {
            try JSONSerialization.data(withJSONObject:["scope":"Real G9 RAW, explicitly enabled decoder detail, sharpness 0 vs 1","measurements":records],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:folder).appendingPathComponent("raw-sharpness-contract.json"))
        }
    }
}
