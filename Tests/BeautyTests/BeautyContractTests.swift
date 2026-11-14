import XCTest
import CoreImage
import BeautyEngine
import PhotoDomain

final class BeautyContractTests: XCTestCase {
    private let context=CIContext()
    private let extent=CGRect(x:0,y:0,width:400,height:400)
    private func data(_ image:CIImage)->[UInt8] {
        var bytes=[UInt8](repeating:0,count:400*400*4)
        context.render(image,toBitmap:&bytes,rowBytes:1600,bounds:extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        return bytes
    }
    private func persist(_ rows:[[String:Any]],_ name:String)throws {
        if let path=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"] {try JSONSerialization.data(withJSONObject:["scope":"Known synthetic mask, independently measured directional contracts; not semantic skin accuracy","checks":rows],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent(name))}
    }
    private func neutral()->BeautySettings {
        var b=BeautySettings();b.enabled=true;b.strength=0;b.skinTone=0;b.blemishRemoval=0;b.detailRecovery=0;return b
    }
    private func analysis()->SkinAnalysis {
        SkinAnalysis(mask:CIImage(color:.white).cropped(to:extent),faceCount:1,backend:"Known synthetic mask; not a segmentation-quality claim",faces:[FaceFeatures(bounds:CGRect(x:0.25,y:0.2,width:0.5,height:0.6),leftEye:CGPoint(x:0.4,y:0.65),rightEye:CGPoint(x:0.6,y:0.65))])
    }
    func testWhiteningToneAndGeometryRemainIndependentOfSmoothingStrength() throws {
        let engine=try BeautyProcessor(),flat=CIImage(color:CIColor(red:0.35,green:0.25,blue:0.2)).cropped(to:extent)
        let baseline=data(flat)
        var b=neutral();b.skinWhitening=1
        let white=data(try engine.apply(flat,settings:b,analysis:analysis(),context:context))
        XCTAssertGreaterThan(white[0],baseline[0]+10,"Whitening must remain usable when smoothing strength is zero")
        b=neutral();b.skinTone=1
        // Tone optimization intentionally protects deep shadows. Use a known
        // midtone here, rather than asserting a lift outside its tonal region.
        let mid=CIImage(color:CIColor(red:0.65,green:0.5,blue:0.4)).cropped(to:extent)
        let tone=data(try engine.apply(mid,settings:b,analysis:analysis(),context:context))
        XCTAssertGreaterThan(tone[0],data(mid)[0],"Skin tone is independent of smoothing")
        let black=CIImage(color:.black).cropped(to:extent)
        var eyes=black
        for x in [152,232] {eyes=CIImage(color:.white).cropped(to:CGRect(x:x,y:252,width:16,height:16)).composited(over:eyes)}
        b=neutral();b.eyeEnlargement=1
        let enlarged=data(try engine.apply(eyes,settings:b,analysis:analysis(),context:context))
        func bright(_ bytes:[UInt8])->Int {stride(from:0,to:bytes.count,by:4).filter{bytes[$0]>128}.count}
        XCTAssertGreaterThan(bright(enlarged),bright(data(eyes))+100,"Inverse eye warp must increase visible eye marker area")
        let face=CIImage(color:.white).cropped(to:CGRect(x:140,y:110,width:120,height:100)).composited(over:black)
        b=neutral();b.faceSlimming=1
        let slim=data(try engine.apply(face,settings:b,analysis:analysis(),context:context))
        XCTAssertLessThan(bright(slim),bright(data(face))-100,"Slimming must narrow the known face silhouette")
        let zero=data(try engine.apply(flat,settings:neutral(),analysis:analysis(),context:context))
        XCTAssertEqual(zero,baseline,"All effects disabled must be an identity")
        try persist([
            ["id":"beauty.skinWhitening","rule":"whitening lifts skin with smoothing disabled","before":baseline[0],"after":white[0],"passed":white[0]>baseline[0]+10],
            ["id":"beauty.skinTone","rule":"tone lifts protected midtones independently","before":data(mid)[0],"after":tone[0],"passed":tone[0]>data(mid)[0]],
            ["id":"beauty.eyeEnlargement","rule":"eye warp increases known marker area","before":bright(data(eyes)),"after":bright(enlarged),"passed":bright(enlarged)>bright(data(eyes))+100],
            ["id":"beauty.faceSlimming","rule":"face warp narrows known silhouette","before":bright(data(face)),"after":bright(slim),"passed":bright(slim)<bright(data(face))-100]
        ],"beauty-independent-contracts.json")
    }
    func testWhiteningRosinessShadowRepairAndSaturationMoveExpectedChannels() throws {
        let engine=try BeautyProcessor(),flat=CIImage(color:CIColor(red:0.25,green:0.17,blue:0.12)).cropped(to:extent),base=data(flat)
        var rows=[[String:Any]]()
        for (id,key,expected) in [
            ("skinWhitening",\BeautySettings.skinWhitening,"brightness"),
            ("skinRosiness",\.skinRosiness,"redness"),
            ("shadowRepair",\.shadowRepair,"brightness"),
            ("skinBrightness",\.skinBrightness,"brightness"),
            ("skinSaturation",\.skinSaturation,"saturation")
        ] {
            var b=neutral();b.strength=0.3;b[keyPath:key]=id=="skinSaturation" ? 1.7 : 0.8
            let result=data(try engine.apply(flat,settings:b,analysis:analysis(),context:context))
            func metric(_ bytes:[UInt8])->Double {
                let r=Double(bytes[0]),g=Double(bytes[1]),bb=Double(bytes[2])
                if expected=="redness" {return r-(g+bb)/2}
                if expected=="saturation" {return (max(r,g,bb)-min(r,g,bb))/max(r,g,bb)}
                return 0.2126*r+0.7152*g+0.0722*bb
            }
            XCTAssertGreaterThan(metric(result),metric(base),id)
            rows.append(["id":"beauty."+id,"rule":"increasing control raises "+expected,"before":metric(base),"after":metric(result),"passed":metric(result)>metric(base)])
        }
        try persist(rows,"beauty-tonal-contracts.json")
    }
    func testSmoothingTextureDetailAndBlemishControlsAgainstKnownSkinSignals() throws {
        let engine=try BeautyProcessor()
        var bytes=[UInt8](repeating:255,count:400*400*4)
        for y in 0..<400 {for x in 0..<400 {
            let noise=Double((x*37+y*43)%31-15)/250
            let wave=sin(Double(x)*2 * .pi/18)*0.025
            for (c,v) in [0.65,0.5,0.4].enumerated(){bytes[(y*400+x)*4+c]=UInt8(((v+noise+wave)*255).rounded())}
        }}
        let source=CIImage(bitmapData:Data(bytes),bytesPerRow:1600,size:extent.size,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        func edge(_ b:[UInt8])->Double {var sum=0.0,n=0.0;for y in 20..<380 {for x in 21..<380 {let i=(y*400+x)*4;sum+=Double(abs(Int(b[i])-Int(b[i-4])));n+=255}};return sum/n}
        var b=neutral();b.strength=1;b.texturePreservation=0
        var records=[[String:Any]]()
        for (id,key,low,high,sign) in [
            ("beauty.strength",\BeautySettings.strength,Float(0),Float(1),-1.0),
            ("beauty.smoothing",\.smoothing,0,1,-1),
            ("beauty.texturePreservation",\.texturePreservation,0,1,1),
            ("beauty.detailRecovery",\.detailRecovery,0,0.3,1),
            ("beauty.sharpness",\.sharpness,0,1,1),
            ("beauty.intensiveSmoothing",\.intensiveSmoothing,0,1,-1)
        ] {
            var a=b,z=b
            if id=="beauty.detailRecovery" {a.texturePreservation=1;z.texturePreservation=1}
            a[keyPath:key]=low;z[keyPath:key]=high
            let x=edge(data(try engine.apply(source,settings:a,analysis:analysis(),context:context)))
            let y=edge(data(try engine.apply(source,settings:z,analysis:analysis(),context:context)))
            let pass=(y-x)*sign>0.00001
            records.append(["id":id,"lowValue":low,"highValue":high,"lowEdge":x,"highEdge":y,"passed":pass])
            XCTAssertTrue(pass,"\(id) must \(sign<0 ? "reduce" : "retain/increase") known skin texture; \(x) -> \(y)")
        }
        let skin=CIImage(color:CIColor(red:0.65,green:0.5,blue:0.4)).cropped(to:extent)
        // Keep red constant while lowering green/blue: this remains redder than
        // the surrounding skin in both encoded and linear working RGB.
        let spot=CIImage(color:CIColor(red:0.65,green:0.25,blue:0.2)).cropped(to:CGRect(x:199,y:199,width:2,height:2)).composited(over:skin)
        func spotLuma(_ b:[UInt8])->Double {var n=0.0;for y in 199..<201 {for x in 199..<201 {let i=(y*400+x)*4;n+=(Double(b[i])*0.2126+Double(b[i+1])*0.7152+Double(b[i+2])*0.0722)/255}};return n/4}
        // Radius selects a spatial frequency scale. Measure a known step edge
        // under the explicit smoothing pass, avoiding a sub-8-bit impulse tail.
        let step=CIImage(color:CIColor(red:0.35,green:0.3,blue:0.25)).cropped(to:CGRect(x:0,y:0,width:200,height:400)).composited(over:skin)
        func slope(_ a:[UInt8])->Double {
            (185..<215).map{x in Double(abs(Int(a[(200*400+x)*4+1])-Int(a[(200*400+x-1)*4+1])))/255}.max()!
        }
        var rad=neutral();rad.intensiveSmoothing=1
        rad.radius=2
        let tight=slope(data(try engine.apply(step,settings:rad,analysis:analysis(),context:context)))
        rad.radius=32
        let wide=slope(data(try engine.apply(step,settings:rad,analysis:analysis(),context:context)))
        records.append(["id":"beauty.radius","rule":"larger smoothing radius spreads a known step over more pixels and reduces peak slope","smallRadiusSlope":tight,"largeRadiusSlope":wide,"passed":wide<tight])
        XCTAssertLessThan(wide,tight,"A larger radius must broaden the known edge")
        var repair=neutral();repair.strength=0.3;repair.blemishThreshold=0.005;repair.radius=32
        let off=spotLuma(data(try engine.apply(spot,settings:repair,analysis:analysis(),context:context)))
        repair.blemishRemoval=1
        let on=spotLuma(data(try engine.apply(spot,settings:repair,analysis:analysis(),context:context)))
        records.append(["id":"beauty.blemishRemoval","before":off,"after":on,"passed":on>off])
        XCTAssertGreaterThan(on,off,"A known red/dark anomaly must be attenuated")
        repair.blemishThreshold=0.1
        let selective=spotLuma(data(try engine.apply(spot,settings:repair,analysis:analysis(),context:context)))
        records.append(["id":"beauty.blemishThreshold","lowThreshold":on,"highThreshold":selective,"passed":selective<on])
        XCTAssertLessThan(selective,on,"A higher anomaly threshold must suppress fewer marks")
        if let path=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"] {
            let object:[String:Any]=["scope":"Known artificial skin noise and a red/dark anomaly, known full mask. Not a trained semantic skin/blemish claim.","backend":engine.lastBackend,"checks":records]
            try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent("beauty-texture-contracts.json"))
        }
    }
    func testSkinTemperatureTintAndUniformityHaveIndependentColorMeaning() throws {
        let engine=try BeautyProcessor(),flat=CIImage(color:CIColor(red:0.6,green:0.45,blue:0.35)).cropped(to:extent)
        var records=[[String:Any]]()
        for (id,key,low,high) in [("beauty.skinTemperature",\BeautySettings.skinTemperature,Float(4500),Float(8500)),("beauty.skinTint",\.skinTint,-60,60)] {
            var a=neutral(),b=neutral();a[keyPath:key]=low;b[keyPath:key]=high
            let x=data(try engine.apply(flat,settings:a,analysis:analysis(),context:context)),y=data(try engine.apply(flat,settings:b,analysis:analysis(),context:context))
            func metric(_ p:[UInt8])->Double {id=="beauty.skinTemperature" ? Double(Int(p[0])-Int(p[2])):Double(Int(p[0])+Int(p[2])-2*Int(p[1]))}
            let before=metric(x),after=metric(y)
            XCTAssertGreaterThan(after,before,id)
            records.append(["id":id,"before":before,"after":after,"passed":after>before])
        }
        var bytes=[UInt8](repeating:255,count:400*400*4)
        for y in 0..<400 {for x in 0..<400 {
            let n=sin(Double(x)*2 * .pi/6)*0.045
            for (c,v) in [0.6+n,0.45-n*0.2126/0.7152,0.35].enumerated(){bytes[(y*400+x)*4+c]=UInt8((v*255).rounded())}
        }}
        let texture=CIImage(bitmapData:Data(bytes),bytesPerRow:1600,size:extent.size,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        func colorEdge(_ p:[UInt8])->Double {var total=0.0;for x in 21..<380 {let k=(200*400+x)*4,j=k-4;total+=Double(abs((Int(p[k])-Int(p[k+1]))-(Int(p[j])-Int(p[j+1]))))};return total/359}
        var b=neutral();b.skinTone=1;b.toneUniformity=0
        let before=colorEdge(data(try engine.apply(texture,settings:b,analysis:analysis(),context:context)))
        b.toneUniformity=1
        let after=colorEdge(data(try engine.apply(texture,settings:b,analysis:analysis(),context:context)))
        XCTAssertLessThan(after,before,"Uniformity must reduce known chroma variation at fixed tone amount")
        records.append(["id":"beauty.toneUniformity","before":before,"after":after,"passed":after<before])
        if let path=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"] {try JSONSerialization.data(withJSONObject:["checks":records],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent("beauty-color-contracts.json"))}
    }
    func testFrequencyFallbackKeepsBlemishAndRecoveryIndependentOfSmoothing() throws {
        let engine=try BeautyProcessor(useMetalPetal:false)
        let flat=CIImage(color:CIColor(red:0.65,green:0.5,blue:0.4)).cropped(to:extent)
        let spot=CIImage(color:CIColor(red:0.65,green:0.25,blue:0.2)).cropped(to:CGRect(x:199,y:199,width:2,height:2)).composited(over:flat)
        var b=neutral();b.radius=32;b.blemishThreshold=0.005
        let original=data(spot),off=data(try engine.apply(spot,settings:b,analysis:analysis(),context:context))
        XCTAssertEqual(original,off)
        b.blemishRemoval=1
        let repaired=data(try engine.apply(spot,settings:b,analysis:analysis(),context:context)),k=(200*400+200)*4
        XCTAssertGreaterThan(repaired[k+1],off[k+1],"Fallback blemish removal must work with smoothing at zero")
        b=neutral();b.radius=32;b.detailRecovery=0.3
        let recovered=data(try engine.apply(spot,settings:b,analysis:analysis(),context:context))
        XCTAssertLessThan(recovered[k+1],off[k+1],"Fallback recovery must strengthen the known negative green detail")
        XCTAssertTrue(engine.lastBackend.hasPrefix("传统频率分离"))
    }
}
