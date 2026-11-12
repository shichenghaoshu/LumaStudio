import Foundation
import CoreImage
import PhotoDomain
import ColorEngine

/// Global controls run on Core Image; HSL/curves/grading are compiled to one bounded 25³ LUT.
enum RecipeAdjustments {
    static func global(_ image: CIImage,_ g: GlobalAdjustments) -> CIImage {
        var r=image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:g.exposure])
            .applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:g.contrast,kCIInputSaturationKey:g.saturation])
        if g.highlights != 0 || g.shadows != 0 {
            r=r.applyingFilter("CIHighlightShadowAdjust",parameters:["inputHighlightAmount":1+g.highlights,"inputShadowAmount":g.shadows,"inputRadius":max(image.extent.width,image.extent.height)/80])
        }
        if g.whites != 0 || g.blacks != 0 {
            // Piecewise monotone-ish luminance curve: lift/compress endpoints without changing extent.
            r=r.applyingFilter("CIToneCurve",parameters:[
                "inputPoint0":CIVector(x:0,y:CGFloat(max(0,g.blacks))*0.12),
                "inputPoint1":CIVector(x:0.25,y:0.25+CGFloat(g.blacks)*0.1),
                "inputPoint2":CIVector(x:0.5,y:0.5),
                "inputPoint3":CIVector(x:0.75,y:0.75+CGFloat(g.whites)*0.1),
                "inputPoint4":CIVector(x:1,y:1+CGFloat(min(0,g.whites))*0.12)])
        }
        if g.temperature != 6500 || g.tint != 0 {
            r=r.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:CGFloat(g.temperature),y:CGFloat(g.tint)),"inputTargetNeutral":CIVector(x:6500,y:0)])
        }
        if g.vibrance != 0 { r=r.applyingFilter("CIVibrance",parameters:["inputAmount":g.vibrance]) }
        return r.cropped(to:image.extent)
    }
    static func advancedColor(_ image: CIImage,_ color: ColorAdjustments) throws -> CIImage {
        let curves=color.curve,grade=color.grading
        guard !color.hsl.isEmpty || ![curves.master,curves.red,curves.green,curves.blue].allSatisfy(\.isEmpty) || grade.shadowSaturation>0 || grade.highlightSaturation>0 else { return image }
        func interpolate(_ x: Double,_ p: [CurvePoint])->Double {
            guard !p.isEmpty else { return x }
            for (a,b) in zip(p,p.dropFirst()) where x<=Double(b.x) {
                return Double(a.y)+(Double(b.y-a.y))*(x-Double(a.x))/Double(b.x-a.x)
            };return Double(p.last!.y)
        }
        func hsv(_ c: RGB)->(Double,Double,Double) {
            let mx=max(c.r,max(c.g,c.b)),mn=min(c.r,min(c.g,c.b)),d=mx-mn
            var h=0.0
            if d>0 { if mx==c.r { h=(c.g-c.b)/d } else if mx==c.g { h=(c.b-c.r)/d+2 } else { h=(c.r-c.g)/d+4 };h=h/6;if h<0{h += 1} }
            return (h,mx>0 ? d/mx : 0,mx)
        }
        func rgb(_ h: Double,_ s: Double,_ v: Double)->RGB {
            let t=(h-floor(h))*6,i=Int(t),f=t-Double(i),p=v*(1-s),q=v*(1-f*s),u=v*(1-(1-f)*s)
            switch i%6 {case 0:return RGB(v,u,p);case 1:return RGB(q,v,p);case 2:return RGB(p,v,u);case 3:return RGB(p,q,v);case 4:return RGB(u,p,v);default:return RGB(v,p,q)}
        }
        let centers: [HueBand:Double]=[.red:0,.orange:1/12,.yellow:1/6,.green:1/3,.aqua:0.5,.blue:2/3,.purple:0.75,.magenta:5/6]
        let lut=try LUT3D(dimension:25) { input in
            var c=input;let (h,s,v)=hsv(c);var dh=0.0,ds=0.0,dv=0.0
            for a in color.hsl {
                let distance=abs(h-centers[a.band]!),circular=min(distance,1-distance),weight=max(0,1-circular/(1.0/6))
                dh += Double(a.hue)*weight;ds += Double(a.saturation)*weight;dv += Double(a.luminance)*weight
            }
            c=rgb(h+dh,min(1,max(0,s*(1+ds))),min(1,max(0,v+dv)))
            c=RGB(interpolate(interpolate(c.r,curves.master),curves.red),interpolate(interpolate(c.g,curves.master),curves.green),interpolate(interpolate(c.b,curves.master),curves.blue))
            let y=0.2126*c.r+0.7152*c.g+0.0722*c.b
            let shadow=pow(max(0,1-y),2)*(1-Double(grade.balance)*0.4)*Double(grade.shadowSaturation)
            let highlight=y*y*(1+Double(grade.balance)*0.4)*Double(grade.highlightSaturation)
            let sc=rgb(Double(grade.shadowHue)/360,1,1),hc=rgb(Double(grade.highlightHue)/360,1,1)
            return RGB(min(1,max(0,c.r+(sc.r-0.5)*shadow+(hc.r-0.5)*highlight)),min(1,max(0,c.g+(sc.g-0.5)*shadow+(hc.g-0.5)*highlight)),min(1,max(0,c.b+(sc.b-0.5)*shadow+(hc.b-0.5)*highlight)))
        }
        return lut.apply(to:image).cropped(to:image.extent)
    }
}
