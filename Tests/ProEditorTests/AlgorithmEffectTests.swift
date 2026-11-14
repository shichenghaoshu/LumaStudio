import XCTest
import CoreImage
import ImageIO
import PhotoCore

/// Acceptance contracts use known image content and independently measured
/// direction, channel isolation and error against a clean source. A nonzero
/// pixel difference alone is deliberately not a correctness assertion.
final class AlgorithmEffectTests: XCTestCase {
    private let context=CIContext()
    private var evidence=[[String:Any]]()
    private var root=FileManager.default.temporaryDirectory.appendingPathComponent("LumaAlgorithms-"+UUID().uuidString)
    override func setUpWithError() throws {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    override func tearDownWithError() throws {try? FileManager.default.removeItem(at:root)}
    private func persist(_ name: String) {
        guard let path=ProcessInfo.processInfo.environment["LUMA_AUDIT_OUTPUT"] else {return}
        let folder=URL(fileURLWithPath:path)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let report: [String:Any]=["scope":"Actual PhotoProcessor output; independent image-effect contracts, not aesthetic quality or hardware certification","checks":evidence]
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(name+".json"))
    }
    private func check(_ id: String,_ rule: String,_ before: Double,_ after: Double,_ passed: Bool,file: StaticString=#filePath,line: UInt=#line) {
        evidence.append(["id":id,"rule":rule,"before":before,"after":after,"passed":passed])
        XCTAssertTrue(passed,"\(id): \(rule); before=\(before), after=\(after)",file:file,line:line)
    }
    private func neutral()->EditRecipe {var r=EditRecipe();r.beauty.enabled=false;r.color.lut=nil;r.evaluation.preserveSkin=false;return r}
    private func setting(_ id: String,_ value: Float,base: EditRecipe?=nil)->EditRecipe {
        var r=base ?? neutral();ParameterCatalog.find(id)!.write(&r,value);return r
    }
    private func write(_ name: String,width: Int=384,height: Int=256,pixel:(Int,Int)->RGB)throws->URL {
        var bytes=[UInt8](repeating:255,count:width*height*4)
        for y in 0..<height {for x in 0..<width {
            let c=pixel(x,y)
            for (k,v) in [c.r,c.g,c.b].enumerated() {bytes[(y*width+x)*4+k]=UInt8(max(0,min(255,(v*255).rounded())))}
        }}
        let data=Data(bytes),provider=try XCTUnwrap(CGDataProvider(data:data as CFData))
        let image=try XCTUnwrap(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let url=root.appendingPathComponent(name+".png"),d=try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil))
        CGImageDestinationAddImage(d,image,nil);XCTAssertTrue(CGImageDestinationFinalize(d));return url
    }
    private func pixels(_ image: CGImage)throws->AuditPixels {
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let c=try XCTUnwrap(CGContext(data:&bytes,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return AuditPixels(width:image.width,height:image.height,bytes:bytes)
    }
    private func render(_ url: URL,_ r: EditRecipe,_ worker: PhotoProcessor) async throws -> AuditPixels {
        try await pixels(worker.render(url:url,recipe:r.legacyRecipe()).image)
    }
    func testToneDirectionsOnKnownNeutralAndColorCharts() async throws {
        defer{persist("tone-contracts")}
        let gray=try write("gray"){x,_ in let v=0.08+Double(x)/383*0.84;return RGB(v,v,v)}
        let color=try write("color"){x,y in
            let n=Double((x*31+y*17)%19-9)/200
            return ProfessionalColorMath.rgb(Double(x)/384,0.58,0.45+Double(y)/256*0.35+n)
        }
        let worker=try PhotoProcessor(),baseline=try await render(gray,neutral(),worker)
        let colorBase=try await render(color,neutral(),worker)
        for (id,delta) in [("global.exposure",Float(0.6)),("global.brightness",0.12),("global.highlights",0.6),("global.shadows",0.6),("global.whites",0.6),("global.blacks",0.6)] {
            let low=try await render(gray,setting(id,-delta),worker),high=try await render(gray,setting(id,delta),worker)
            let area: CGRect?=id=="global.highlights" || id=="global.whites" ? CGRect(x:280,y:32,width:80,height:192) : (id=="global.shadows" || id=="global.blacks" ? CGRect(x:16,y:32,width:80,height:192) : nil)
            let a=low.mean(area).y,b=baseline.mean(area).y,c=high.mean(area).y
            check(id,"negative lowers the intended tonal region",b,a,a<b-0.001)
            check(id,"positive raises the intended tonal region",b,c,c>b+0.001)
        }
        let soft=try await render(gray,setting("global.contrast",0.6),worker),hard=try await render(gray,setting("global.contrast",1.4),worker)
        check("global.contrast","higher contrast increases tonal spread",soft.spread,hard.spread,hard.spread>soft.spread+0.02)
        for (id,low,high,key) in [("global.temperature",Float(4500),Float(8500),"warmth"),("global.tint",-60,60,"magenta"),("global.saturation",0.5,1.5,"saturation"),("global.vibrance",-0.6,0.6,"saturation")] {
            let a=try await render(color,setting(id,low),worker),b=try await render(color,setting(id,high),worker)
            let x=a.metric(key),y=b.metric(key)
            check(id,"increasing control raises "+key,x,y,y>x+0.001)
        }
        for id in ["global.texture","global.clarity"] {
            let low=try await render(color,setting(id,-0.7),worker),high=try await render(color,setting(id,0.7),worker)
            check(id,"positive increases local edge contrast; negative softens",low.edge,high.edge,high.edge>low.edge+0.0001)
        }
        let haze=try await render(color,setting("global.dehaze",-0.7),worker),clear=try await render(color,setting("global.dehaze",0.7),worker)
        check("global.dehaze","dehaze restores contrast relative to adding haze",haze.spread,clear.spread,clear.spread>haze.spread)
        check("global.saturation","zero saturation produces neutral RGB",0,try await render(color,setting("global.saturation",0),worker).chroma,try await render(color,setting("global.saturation",0),worker).chroma<0.005)
        XCTAssertGreaterThan(colorBase.chroma,0.1)
    }
    func testLevelsAndCurvesHaveExpectedChannelDirection() async throws {
        defer{persist("levels-curves-contracts")}
        let source=try write("neutral"){_,_ in RGB(0.42,0.42,0.42)},worker=try PhotoProcessor()
        let baseline=try await render(source,neutral(),worker)
        for channel in ["master","red","green","blue"] {
            for (field,target,sign) in [("inputBlack",Float(0.15),-1.0),("inputWhite",0.8,1),("gamma",1.6,1),("outputBlack",0.15,1),("outputWhite",0.8,-1)] {
                let id="color.levels."+channel+"."+field,result=try await render(source,setting(id,target),worker)
                let a=baseline.mean().channel(channel),b=result.mean().channel(channel)
                check(id,"level endpoint/gamma moves selected channel in the defined direction",a,b,(b-a)*sign>0.005)
                if channel != "master" {for other in ["red","green","blue"] where other != channel {
                    let a=baseline.mean().channel(other),b=result.mean().channel(other)
                    check(id,"unselected "+other+" channel remains unchanged",a,b,abs(a-b)<0.005)
                }}
            }
            var r=neutral();r.color.curve.setPoints([CurvePoint(0,0),CurvePoint(0.5,0.7),CurvePoint(1,1)],channel:channel)
            let raised=try await render(source,r,worker),a=baseline.mean().channel(channel),b=raised.mean().channel(channel)
            check("color.curve."+channel,"raised midpoint brightens selected channel",a,b,b>a+0.01)
            r.color.curve.setPoints([CurvePoint(0,0),CurvePoint(1,1)],channel:channel)
            let identity=try await render(source,r,worker)
            check("color.curve."+channel,"identity curve preserves pixels",0,identity.difference(baseline),identity.difference(baseline)<1.1/255)
        }
    }
    func testEveryHSLBandAndSelectiveColorChannelDirection() async throws {
        defer{persist("hsl-selective-contracts")}
        let bands:[(String,Double)]=[("red",0),("orange",1/12),("yellow",1/6),("green",1/3),("aqua",0.5),("blue",2/3),("purple",0.75),("magenta",5/6)]
        let worker=try PhotoProcessor()
        for (band,hue) in bands {
            let source=try write(band){_,_ in ProfessionalColorMath.rgb(hue,0.65,0.7)}
            let baseline=try await render(source,neutral(),worker),a=baseline.mean()
            for (field,target) in [("hue",Float(0.07)),("saturation",0.4),("luminance",0.15)] {
                let id="color.hsl."+band+"."+field,result=try await render(source,setting(id,target),worker),b=result.mean()
                if field=="hue" {
                    let delta=(b.hue-a.hue+1.5).truncatingRemainder(dividingBy:1)-0.5
                    check(id,"positive hue rotates forward on the color circle",0,delta,delta>0.001 && delta<0.25)
                } else if field=="saturation" {check(id,"positive saturation increases colorfulness",a.saturation,b.saturation,b.saturation>a.saturation+0.005)}
                else {check(id,"positive luminance brightens the selected band",a.y,b.y,b.y>a.y+0.005)}
            }
        }
        for zone in ["red","yellow","green","cyan","blue","magenta","white","neutral","black"] {
            let centers:[String:Double]=["red":0,"yellow":1/6,"green":1/3,"cyan":0.5,"blue":2/3,"magenta":5/6]
            let hue=centers[zone]
            let v=zone=="white" ? 0.9 : (zone=="black" ? 0.18 : 0.55)
            let rgb=hue.map{ProfessionalColorMath.rgb($0,0.65,0.7)} ?? RGB(v,v,v)
            let source=try write(zone+"-selective"){_,_ in rgb}
            for (field,channel) in [("Cyan","red"),("Magenta","green"),("Yellow","blue"),("Black","master")] {
                let id="color.selective."+zone+field
                let less=try await render(source,setting(id,-0.4),worker),more=try await render(source,setting(id,0.4),worker)
                let a=less.mean().channel(channel),b=more.mean().channel(channel)
                check(id,"adding subtractive ink lowers its complementary RGB channel",a,b,b<a-0.001)
            }
        }
    }
    func testDenoisingReducesKnownErrorAndSharpeningStrengthensEdges() async throws {
        defer{persist("detail-contracts")}
        let clean=try write("clean",width:1600,height:240){x,_ in let v=x<800 ? 0.3 : 0.65;return RGB(v,v,v)}
        let noisy=try write("noise",width:1600,height:240){x,y in let v=x<800 ? 0.3 : 0.65,n=Double((x*37+y*43)%31-15)/220;return RGB(v+n,v+n,v+n)}
        let colorNoise=try write("chroma",width:1600,height:240){x,y in let n=Double((x*37+y*43)%31-15)/220;return RGB(0.45+n,0.45-n,0.45+n)}
        let worker=try PhotoProcessor(),truth=try await render(clean,neutral(),worker),input=try await render(noisy,neutral(),worker)
        let region=CGRect(x:100,y:20,width:500,height:180)
        let denoised=try await render(noisy,setting("detail.luminanceNoise",1),worker)
        let a=input.difference(truth,region),b=denoised.difference(truth,region)
        check("detail.luminanceNoise","denoising reduces error against the known clean image",a,b,b<a*0.8)
        check("detail.luminanceNoise","large-scale step contrast is retained",truth.stepContrast,denoised.stepContrast,denoised.stepContrast>truth.stepContrast*0.9)
        let colorInput=try await render(colorNoise,neutral(),worker),colorOutput=try await render(colorNoise,setting("detail.colorNoise",1),worker)
        check("detail.colorNoise","chroma noise moves closer to neutral",colorInput.chroma,colorOutput.chroma,colorOutput.chroma<colorInput.chroma*0.8)
        for (noise,detail,url) in [("detail.luminanceNoise","detail.luminanceDetail",noisy),("detail.colorNoise","detail.colorDetail",colorNoise)] {
            let base=setting(noise,1),low=try await render(url,setting(detail,0,base:base),worker),high=try await render(url,setting(detail,1,base:base),worker)
            check(detail,"more detail retention preserves more high-frequency signal",low.edge,high.edge,high.edge>low.edge)
        }
        var blurred=neutral();blurred.global.texture = -1
        let baseline=try await render(clean,blurred,worker)
        for (id,low,high) in [("detail.sharpening",Float(0),Float(1.5)),("detail.detail",0,1)] {
            var base=blurred;base.detail.sharpening=1.5;base.detail.radius=2
            let a=try await render(clean,setting(id,low,base:base),worker),b=try await render(clean,setting(id,high,base:base),worker)
            check(id,"sharpening increases edge slope",a.maxSlope,b.maxSlope,b.maxSlope>a.maxSlope+0.001)
        }
        var sharp=neutral();sharp.detail.sharpening=1.5;sharp.detail.masking=0
        let unmasked=try await render(noisy,sharp,worker);sharp.detail.masking=1
        let masked=try await render(noisy,sharp,worker)
        check("detail.masking","edge masking reduces sharpening changes on flat noisy areas",unmasked.difference(input,region),masked.difference(input,region),masked.difference(input,region)<unmasked.difference(input,region))
        var radius=neutral();radius.detail.sharpening=1.5;radius.detail.masking=0;radius.detail.radius=0.5
        let narrow=try await render(clean,radius,worker);radius.detail.radius=3
        let broad=try await render(clean,radius,worker)
        let shoulder=CGRect(x:795,y:20,width:4,height:180)
        check("detail.radius","larger sharpening radius broadens the edge halo beyond the narrow kernel",narrow.difference(truth,shoulder),broad.difference(truth,shoulder),broad.difference(truth,shoulder)>narrow.difference(truth,shoulder)+0.001)
        XCTAssertGreaterThan(baseline.width,0)
    }
    func testSelectiveAbsoluteAndRelativeModesScaleWithChannelContent() async throws {
        defer{persist("selective-mode-contracts")}
        let worker=try PhotoProcessor()
        for (name,value) in [("dark",0.2),("light",0.6)] {
            let source=try write(name+"-neutral"){_,_ in RGB(value,value,value)},plain=try await render(source,neutral(),worker)
            var r=neutral();r.color.selective.neutralCyan=0.4
            let relative=try await render(source,r,worker);r.color.selective.absolute=true
            let absolute=try await render(source,r,worker)
            check("color.selective.absolute","both modes reduce red when adding cyan",plain.mean().r,absolute.mean().r,absolute.mean().r<plain.mean().r && relative.mean().r<plain.mean().r)
            check("color.selective.absolute","relative strength follows channel content; absolute uses a fixed increment",relative.mean().r,absolute.mean().r,value<0.35 ? absolute.mean().r<relative.mean().r:relative.mean().r<absolute.mean().r)
            check("color.selective.absolute","other channels stay unchanged",plain.mean().g,absolute.mean().g,abs(plain.mean().g-absolute.mean().g)<1.1/255)
        }
    }
    func testGradingBalanceRangeSelectionAndCalibrationDirection() async throws {
        defer{persist("grading-range-calibration-contracts")}
        let worker=try PhotoProcessor()
        for (zone,level) in [("shadow",0.24),("midtone",0.72),("highlight",0.96)] {
            let source=try write(zone+"-gray"){_,_ in RGB(level,level,level)}
            var base=neutral()
            for suffix in ["Hue","Saturation","Luminance"] {
                let id="color.grading."+zone+suffix
                var a=base,b=base
                if suffix=="Hue" {
                    ParameterCatalog.find("color.grading."+zone+"Saturation")!.write(&a,0.15);b=a
                    ParameterCatalog.find(id)!.write(&a,0);ParameterCatalog.find(id)!.write(&b,240)
                } else if suffix=="Saturation" {
                    ParameterCatalog.find("color.grading."+zone+"Hue")!.write(&a,0);b=a
                    ParameterCatalog.find(id)!.write(&a,0);ParameterCatalog.find(id)!.write(&b,0.2)
                } else {ParameterCatalog.find(id)!.write(&a,-0.08);ParameterCatalog.find(id)!.write(&b,0.08)}
                let x=try await render(source,a,worker).mean(),y=try await render(source,b,worker).mean()
                let before=suffix=="Luminance" ? x.y : x.r-x.b,after=suffix=="Luminance" ? y.y : y.r-y.b
                check(id,suffix=="Hue" ? "blue hue moves the selected tonal range toward blue" : "increased amount affects the selected tonal range in its defined direction",before,after,suffix=="Hue" ? after<before-0.001 : after>before+0.001)
            }
            base.color.grading.shadowSaturation=0.15;base.color.grading.midtoneSaturation=0.15;base.color.grading.highlightSaturation=0.15
            let off=try await render(source,setting("color.grading.intensity",0,base:base),worker),on=try await render(source,setting("color.grading.intensity",1,base:base),worker)
            let identity=try await render(source,neutral(),worker)
            check("color.grading.intensity","zero grading intensity restores the ungraded image",0,off.difference(identity),off.difference(identity)<1.1/255)
            check("color.grading.intensity","nonzero intensity adds selected colors",0,on.chroma,on.chroma>0.005)
        }
        let mid=try write("balance-gray"){_,_ in RGB(0.7,0.7,0.7)}
        var grade=neutral();grade.color.grading.shadowHue=240;grade.color.grading.shadowSaturation=0.2;grade.color.grading.highlightHue=0;grade.color.grading.highlightSaturation=0.2
        let shadows=try await render(mid,setting("color.grading.balance",-0.8,base:grade),worker),highlights=try await render(mid,setting("color.grading.balance",0.8,base:grade),worker)
        check("color.grading.balance","positive balance favors highlight color, negative favors shadow color",shadows.mean().r-shadows.mean().b,highlights.mean().r-highlights.mean().b,highlights.mean().r-highlights.mean().b>shadows.mean().r-shadows.mean().b+0.005)
        let transition=try write("blend-center"){_,_ in RGB(0.5,0.5,0.5)}
        let blend0=try await render(transition,setting("color.grading.blending",0,base:grade),worker),blend1=try await render(transition,setting("color.grading.blending",1,base:grade),worker)
        check("color.grading.blending","more blending extends tonal colors into the transition",blend0.chroma,blend1.chroma,blend1.chroma>blend0.chroma+0.001)
        let swatches:[RGB]=[RGB(0.7,0.245,0.245),RGB(0.7,0.7,0.245),RGB(0.245,0.7,0.245),RGB(0.245,0.7,0.7),RGB(0.245,0.245,0.7),RGB(0.7,0.245,0.7)]
        let chart=try write("range"){x,_ in swatches[min(5,x/64)]},plain=try await render(chart,neutral(),worker)
        var range=neutral();range.color.range.center=120;range.color.range.width=80
        let green=CGRect(x:140,y:40,width:40,height:160),red=CGRect(x:10,y:40,width:40,height:160)
        for (field,value) in [("hue",Float(0.06)),("saturation",0.4),("luminance",0.15)] {
            let id="color.range."+field,result=try await render(chart,setting(id,value,base:range),worker),a=plain.mean(green),b=result.mean(green)
            let first=field=="hue" ? a.hue : (field=="saturation" ? a.saturation : a.y)
            let second=field=="hue" ? b.hue : (field=="saturation" ? b.saturation : b.y)
            check(id,"selected green range moves in requested direction",first,second,second>first+0.001)
            check(id,"unselected red range stays unchanged",0,result.difference(plain,red),result.difference(plain,red)<1.1/255)
        }
        range.color.range.luminance=0.15
        let selectGreen=try await render(chart,range,worker);range.color.range.center=240
        let selectBlue=try await render(chart,range,worker)
        check("color.range.center","moving center away releases the old color range",selectGreen.difference(plain,green),selectBlue.difference(plain,green),selectBlue.difference(plain,green)<selectGreen.difference(plain,green)*0.1)
        range.color.range.center=120
        let narrow=try await render(chart,setting("color.range.width",20,base:range),worker),wide=try await render(chart,setting("color.range.width",180,base:range),worker)
        check("color.range.width","a wider range affects more neighboring colors",narrow.difference(plain),wide.difference(plain),wide.difference(plain)>narrow.difference(plain)+0.001)
        range.color.range.center=90;range.color.range.width=120
        let firm=try await render(chart,setting("color.range.softness",0.05,base:range),worker),soft=try await render(chart,setting("color.range.softness",1,base:range),worker)
        check("color.range.softness","softer boundary reduces adjustment near the selection edge",firm.difference(plain),soft.difference(plain),soft.difference(plain)<firm.difference(plain))
        for (channel,index) in [("red",0),("green",2),("blue",4)] {
            let source=try write(channel+"-calibration"){_,_ in swatches[index]}
            for (field,low,high) in [("Hue",Float(-0.07),Float(0.07)),("Saturation",-0.6,0.6)] {
                let id="color.calibration."+channel+field,a=try await render(source,setting(id,low),worker).mean(),b=try await render(source,setting(id,high),worker).mean()
                let delta=(b.hue-a.hue+1.5).truncatingRemainder(dividingBy:1)-0.5
                check(id,field=="Hue" ? "primary hue rotates forward" : "primary saturation increases colorfulness",field=="Hue" ? 0 : a.saturation,field=="Hue" ? delta : b.saturation,field=="Hue" ? delta>0.001 : b.saturation>a.saturation+0.001)
            }
        }
        let tintLow=try await render(mid,setting("color.calibration.shadowTint",-0.8),worker),tintHigh=try await render(mid,setting("color.calibration.shadowTint",0.8),worker)
        check("color.calibration.shadowTint","positive shadow tint moves from green toward magenta",tintLow.metric("magenta"),tintHigh.metric("magenta"),tintHigh.metric("magenta")>tintLow.metric("magenta"))
    }
    func testAllThirtyFiltersHaveRealIntensityAndMonochromeBehavior() async throws {
        defer{persist("filter-contracts")}
        let source=try write("filter-chart"){x,y in RGB(0.15+Double(x)/384*0.6,0.2+Double(y)/256*0.6,0.4)},worker=try PhotoProcessor()
        let base=try await render(source,neutral(),worker)
        XCTAssertEqual(FilterPreset.allCases.count,30)
        for preset in FilterPreset.allCases {
            var r=neutral();r.color.lut=preset.rawValue;r.color.intensity=0
            let zero=try await render(source,r,worker);r.color.intensity=1
            let full=try await render(source,r,worker);r.color.intensity=0.5
            let half=try await render(source,r,worker)
            check("filter."+preset.rawValue,"zero intensity is identity",0,zero.difference(base),zero.difference(base)<1.1/255)
            if preset == .natural {
                // The supplied natural CUBE is an identity, deliberately not a look.
                check("filter.natural","natural preset preserves the source",0,full.difference(base),full.difference(base)<1.1/255)
            } else {check("filter."+preset.rawValue,"full intensity has a visible effect",0,full.difference(base),full.difference(base)>0.001)}
            check("color.intensity","half intensity lies between off and full for "+preset.rawValue,half.difference(base),full.difference(base),preset == .natural ? half.difference(base)<1.1/255 : (half.difference(base)<full.difference(base) && half.difference(base)>0))
            if ["mono","matteMono","noir"].contains(preset.rawValue) {check("filter."+preset.rawValue,"monochrome preset removes chroma",base.chroma,full.chroma,full.chroma<0.015)}
            if preset == .silver {check("filter.silver","silver toning suppresses source chroma while retaining its declared cool cast",base.chroma,full.chroma,full.chroma<base.chroma*0.15)}
        }
    }
    func testVignetteGrainBloomAndFilmEffectsHaveSpatialMeaning() async throws {
        defer{persist("effects-contracts")}
        let worker=try PhotoProcessor(),flat=try write("effect-flat"){_,_ in RGB(0.45,0.45,0.45)}
        let base=try await render(flat,neutral(),worker)
        var vignette=neutral();vignette.effects.vignette=0.8
        let dark=try await render(flat,vignette,worker)
        let center=CGRect(x:180,y:116,width:24,height:24),edge=CGRect(x:8,y:8,width:24,height:24)
        check("effects.vignette","positive vignette darkens edges more than center",base.mean(edge).y-dark.mean(edge).y,base.mean(center).y-dark.mean(center).y,base.mean(edge).y-dark.mean(edge).y>base.mean(center).y-dark.mean(center).y+0.03)
        let bright=try await render(flat,setting("effects.vignette",-0.8),worker)
        check("effects.vignette","negative vignette lifts the edges",base.mean(edge).y,bright.mean(edge).y,bright.mean(edge).y>base.mean(edge).y)
        let midSmall=try await render(flat,setting("effects.vignetteMidpoint",0.2,base:vignette),worker),midLarge=try await render(flat,setting("effects.vignetteMidpoint",0.9,base:vignette),worker)
        check("effects.vignetteMidpoint","larger midpoint protects a larger central area",midSmall.mean().y,midLarge.mean().y,midLarge.mean().y>midSmall.mean().y)
        let hard=try await render(flat,setting("effects.vignetteFeather",0.1,base:vignette),worker),soft=try await render(flat,setting("effects.vignetteFeather",1,base:vignette),worker)
        check("effects.vignetteFeather","larger feather softens edge attenuation",hard.mean().y,soft.mean().y,soft.mean().y>hard.mean().y)
        let roundLow=try await render(flat,setting("effects.vignetteRoundness",0.2,base:vignette),worker),roundHigh=try await render(flat,setting("effects.vignetteRoundness",1,base:vignette),worker)
        func circleError(_ p:AuditPixels)->Double {abs(p.mean(CGRect(x:282,y:124,width:8,height:8)).y-p.mean(CGRect(x:188,y:218,width:8,height:8)).y)}
        check("effects.vignetteRoundness","circular setting treats equal physical radii equally",circleError(roundLow),circleError(roundHigh),circleError(roundHigh)<circleError(roundLow))
        let large=try write("grain-flat",width:1600,height:240){_,_ in RGB(0.5,0.5,0.5)},plain=try await render(large,neutral(),worker)
        var grain=neutral();grain.effects.grain=0.9
        let noisy=try await render(large,grain,worker),repeated=try await render(large,grain,worker)
        check("effects.grain","grain adds measurable local variation",plain.edge,noisy.edge,noisy.edge>plain.edge+0.001)
        check("effects.grain","the same grain recipe renders deterministically",0,noisy.difference(repeated),noisy.difference(repeated)==0)
        grain.effects.grainRoughness=0
        let small=try await render(large,setting("effects.grainSize",0.5,base:grain),worker),big=try await render(large,setting("effects.grainSize",4,base:grain),worker)
        check("effects.grainSize","larger grains have fewer neighboring-pixel transitions",small.edge,big.edge,big.edge<small.edge)
        grain.effects.grainSize=4
        let coarse=try await render(large,setting("effects.grainRoughness",0,base:grain),worker),fine=try await render(large,setting("effects.grainRoughness",1,base:grain),worker)
        check("effects.grainRoughness","roughness introduces finer grain structure",coarse.edge,fine.edge,fine.edge>coarse.edge)
        let ramp=try write("fade-ramp"){x,_ in let v=Double(x)/383;return RGB(v,v,v)},rampBase=try await render(ramp,neutral(),worker)
        let faded=try await render(ramp,setting("effects.fade",1),worker)
        check("effects.fade","fade raises blacks",rampBase.mean(edge).y,faded.mean(edge).y,faded.mean(edge).y>rampBase.mean(edge).y)
        let white=CGRect(x:350,y:8,width:24,height:24)
        check("effects.fade","fade compresses the bright endpoint",rampBase.mean(white).y,faded.mean(white).y,faded.mean(white).y<rampBase.mean(white).y)
        let lamp=try write("bloom-lamp"){x,y in let v=abs(x-192)<8 && abs(y-128)<8 ? 1.0 : 0.15;return RGB(v,v,v)},lampBase=try await render(lamp,neutral(),worker)
        var bloom=neutral();bloom.effects.bloom=1
        let glow=try await render(lamp,bloom,worker)
        check("effects.bloom","bloom adds light around a bright source",lampBase.mean().y,glow.mean().y,glow.mean().y>lampBase.mean().y)
        let tight=try await render(lamp,setting("effects.bloomRadius",2,base:bloom),worker),wide=try await render(lamp,setting("effects.bloomRadius",50,base:bloom),worker),halo=CGRect(x:208,y:124,width:6,height:8)
        check("effects.bloomRadius","larger radius spreads light farther from its source",tight.mean(halo).y,wide.mean(halo).y,wide.mean(halo).y>tight.mean(halo).y)
        var film=neutral();film.effects.filmSaturation=0.3
        let red=try await render(flat,setting("effects.filmHue",0,base:film),worker),blue=try await render(flat,setting("effects.filmHue",240,base:film),worker)
        check("effects.filmHue","red vs blue tint follows the selected hue",red.metric("warmth"),blue.metric("warmth"),red.metric("warmth")>blue.metric("warmth"))
        let tintOff=try await render(flat,setting("effects.filmSaturation",0,base:film),worker),tintOn=try await render(flat,film,worker)
        check("effects.filmSaturation","zero tint is neutral; nonzero tint adds chroma",tintOff.chroma,tintOn.chroma,tintOff.chroma<0.005 && tintOn.chroma>0.005)
    }
    func testGeometryMovesKnownFeaturesAndCropSelectsCorrectRegions() async throws {
        defer{persist("geometry-contracts")}
        let worker=try PhotoProcessor(),stripe=try write("geometry-stripe"){x,_ in let v=abs(x-288)<4 ? 1.0 : 0;return RGB(v,v,v)}
        let baseline=try await render(stripe,neutral(),worker)
        func centroid(_ p:AuditPixels,_ channel:Int)->CGPoint {
            var sx=0.0,sy=0.0,n=0.0
            for y in 0..<p.height {for x in 0..<p.width {let v=Double(p.bytes[(y*p.width+x)*4+channel]);sx+=Double(x)*v;sy+=Double(y)*v;n+=v}}
            return CGPoint(x:sx/max(1,n),y:sy/max(1,n))
        }
        let inward=try await render(stripe,setting("geometry.distortion",0.3),worker),outward=try await render(stripe,setting("geometry.distortion",-0.3),worker)
        let originalX=centroid(baseline,0).x,innerX=centroid(inward,0).x,outerX=centroid(outward,0).x
        check("geometry.distortion","opposite radial correction signs move an off-center feature inward/outward",Double(innerX),Double(outerX),innerX<originalX && outerX>originalX)
        let ca=try await render(stripe,setting("geometry.chromaticAberration",1),worker)
        check("geometry.chromaticAberration","red and blue correction move channels in opposite radial directions",Double(centroid(ca,0).x),Double(centroid(ca,2).x),centroid(ca,0).x<centroid(ca,2).x-0.05)
        let flat=try write("lens-flat"){_,_ in RGB(0.3,0.3,0.3)},plain=try await render(flat,neutral(),worker),lens=try await render(flat,setting("geometry.lensVignette",1),worker)
        let corner=CGRect(x:4,y:4,width:12,height:12),center=CGRect(x:186,y:122,width:12,height:12)
        check("geometry.lensVignette","lens falloff compensation lifts the corner more than the center",lens.mean(center).y-plain.mean(center).y,lens.mean(corner).y-plain.mean(corner).y,lens.mean(corner).y-plain.mean(corner).y>lens.mean(center).y-plain.mean(center).y+0.02)
        let marker=try write("rotation-marker"){x,y in let v=abs(x-280)<10 && abs(y-128)<10 ? 1.0 : 0;return RGB(v,0,0)}
        let zero=try await render(marker,neutral(),worker),positive=try await render(marker,setting("geometry.rotation",15),worker),negative=try await render(marker,setting("geometry.rotation",-15),worker)
        let cy=centroid(zero,0).y,a=centroid(positive,0).y,b=centroid(negative,0).y
        check("geometry.rotation","opposite rotation signs move the marker to opposite sides of center",Double(a),Double(b),(a-cy)*(b-cy)<0 && abs(a-b)>20)
        XCTAssertEqual(positive.width,384);XCTAssertEqual(positive.height,256)
        let chart=try write("crop-chart"){x,y in RGB(Double(x)/383,0.25,Double(y)/255)}
        var crop=neutral();crop.geometry.scale=2
        let left=try await render(chart,setting("geometry.centerX",0.25,base:crop),worker),right=try await render(chart,setting("geometry.centerX",0.75,base:crop),worker)
        check("geometry.centerX","moving crop right selects the right-side red gradient",left.mean().r,right.mean().r,right.mean().r>left.mean().r+0.2)
        let top=try await render(chart,setting("geometry.centerY",0.25,base:crop),worker),bottom=try await render(chart,setting("geometry.centerY",0.75,base:crop),worker)
        check("geometry.centerY","top-origin crop coordinates select the expected lower region",top.mean().b,bottom.mean().b,bottom.mean().b>top.mean().b+0.2)
        check("geometry.scale","2x zoom crops to half width and height",384*256,Double(left.width*left.height),left.width==192 && left.height==128)
        crop.geometry.cropAspect=1
        let square=try await render(chart,crop,worker)
        check("geometry.cropAspect","square framing has square output",Double(square.width),Double(square.height),square.width==square.height)
        let grid=try write("perspective-grid"){x,y in let v=abs(x-192)%32<4 || abs(y-128)%32<4 ? 0.9 : 0.1;return RGB(v,v,v)},gridBase=try await render(grid,neutral(),worker)
        for id in ["geometry.horizontal","geometry.vertical"] {
            let a=try await render(grid,setting(id,-0.25),worker),b=try await render(grid,setting(id,0.25),worker)
            check(id,"both perspective directions produce distinct bounded corrections",a.difference(gridBase),b.difference(gridBase),a.width==384 && a.height==256 && b.width==384 && b.height==256 && a.difference(gridBase)>0.01 && b.difference(gridBase)>0.01 && a.difference(b)>0.01)
        }
    }
    func testPerspectiveCorrectionStraightensKnownConvergingLines() async throws {
        defer{persist("perspective-contracts")}
        let worker=try PhotoProcessor()
        for vertical in [true,false] {for sign in [-1.0,1.0] {
            let id=vertical ? "geometry.vertical":"geometry.horizontal"
            // A photographed rectangular board is a known trapezoid. Lines at
            // fixed board coordinates converge in the input; rectification
            // must make them parallel. No CI perspective filter builds input.
            let source=try write("trapezoid-\(vertical)-\(sign)"){x,y in
                let t=vertical ? Double(y)/255:Double(x)/383
                let inset=(sign>0 ? 1-t:t)*(vertical ? 48:32)
                let full=vertical ? 384.0:256.0
                let a=vertical ? Double(x):Double(y)
                let marker=inset+(full-2*inset)*0.25
                if abs(a-marker)<2 {return RGB(0.9,0.1,0.1)}
                let v=a>=inset && a<=full-inset ? 0.15:0.02
                return RGB(v,v,v)
            }
            let before=try await render(source,neutral(),worker)
            let after=try await render(source,setting(id,Float(sign*0.25)),worker)
            func drift(_ p:AuditPixels)->Double {
                func position(_ coordinate:Int)->Double {
                    var sum=0.0,n=0.0
                    let length=vertical ? p.width:p.height
                    for a in 0..<length {
                        let x=vertical ? a:coordinate,y=vertical ? coordinate:a,k=(y*p.width+x)*4
                        let weight=max(0,Double(p.bytes[k])-Double(p.bytes[k+1])-30)
                        sum+=Double(a)*weight;n+=weight
                    }
                    XCTAssertGreaterThan(n,0,"The known marker must remain visible")
                    return sum/max(1,n)
                }
                let length=vertical ? p.height:p.width
                return abs(position(length/4)-position(length*3/4))
            }
            let a=drift(before),b=drift(after)
            check(id,"matching perspective correction makes known converging lines parallel",a,b,a>5 && b<1.5 && b<a*0.2)
            XCTAssertEqual(after.width,384);XCTAssertEqual(after.height,256)
        }}
    }
}

private struct AuditPixels {
    let width:Int,height:Int,bytes:[UInt8]
    func mean(_ area:CGRect?=nil)->AuditColor {
        let r=area ?? CGRect(x:0,y:0,width:width,height:height)
        var a=0.0,b=0.0,c=0.0,n=0.0
        for y in max(0,Int(r.minY))..<min(height,Int(r.maxY)) {for x in max(0,Int(r.minX))..<min(width,Int(r.maxX)) {let i=(y*width+x)*4;a+=Double(bytes[i]);b+=Double(bytes[i+1]);c+=Double(bytes[i+2]);n+=255}}
        return AuditColor(r:a/n,g:b/n,b:c/n)
    }
    func difference(_ other:AuditPixels,_ area:CGRect?=nil)->Double {
        guard width==other.width,height==other.height else {return .infinity}
        let r=area ?? CGRect(x:0,y:0,width:width,height:height);var sum=0.0,n=0.0
        for y in max(0,Int(r.minY))..<min(height,Int(r.maxY)) {for x in max(0,Int(r.minX))..<min(width,Int(r.maxX)) {for c in 0..<3 {let i=(y*width+x)*4+c;sum+=Double(abs(Int(bytes[i])-Int(other.bytes[i])));n+=255}}}
        return sum/n
    }
    var chroma:Double {var v=0.0;for i in stride(from:0,to:bytes.count,by:4){v+=Double(max(bytes[i],bytes[i+1],bytes[i+2])-min(bytes[i],bytes[i+1],bytes[i+2]))/255};return v/Double(width*height)}
    var spread:Double {let m=mean().y;var s=0.0;for i in stride(from:0,to:bytes.count,by:4){let y=(Double(bytes[i])*0.2126+Double(bytes[i+1])*0.7152+Double(bytes[i+2])*0.0722)/255;s+=(y-m)*(y-m)};return sqrt(s/Double(width*height))}
    var edge:Double {var s=0.0,n=0.0;for y in 1..<height {for x in 1..<width {let i=(y*width+x)*4;s+=Double(abs(Int(bytes[i])-Int(bytes[i-4]))+abs(Int(bytes[i])-Int(bytes[i-width*4])));n+=510}};return s/n}
    var maxSlope:Double {var m=0.0;let y=height/2;for x in 1..<width {let i=(y*width+x)*4;m=max(m,Double(abs(Int(bytes[i])-Int(bytes[i-4])))/255)};return m}
    var stepContrast:Double {mean(CGRect(x:width*3/4,y:20,width:10,height:height-40)).y-mean(CGRect(x:width/4,y:20,width:10,height:height-40)).y}
    func metric(_ key:String)->Double {let c=mean();if key=="warmth" {return c.r-c.b};if key=="magenta" {return (c.r+c.b)/2-c.g};var s=0.0;for i in stride(from:0,to:bytes.count,by:4){let mx=Double(max(bytes[i],bytes[i+1],bytes[i+2])),mn=Double(min(bytes[i],bytes[i+1],bytes[i+2]));s+=mx>0 ? (mx-mn)/mx : 0};return s/Double(width*height)}
}
private struct AuditColor {
    let r:Double,g:Double,b:Double
    var y:Double {0.2126*r+0.7152*g+0.0722*b}
    var hue:Double {let h=atan2(sqrt(3)*(g-b),2*r-g-b)/(2 * Double.pi);return h<0 ? h+1 : h}
    var saturation:Double {let mx=max(r,g,b);return mx>0 ? (mx-min(r,g,b))/mx : 0}
    func channel(_ c:String)->Double {c=="red" ? r : (c=="green" ? g : (c=="blue" ? b : y))}
}
