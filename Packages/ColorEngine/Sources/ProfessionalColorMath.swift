import Foundation
import PhotoDomain

/// Original, deterministic color operators used by both preview and full-size export.
/// These are manual color controls, not learned camera profiles or segmentation models.
public enum ProfessionalColorMath {
    private static func clamp(_ x: Double)->Double {min(1,max(0,x))}
    public static func hsv(_ c: RGB)->(Double,Double,Double) {
        let mx=max(c.r,max(c.g,c.b)),mn=min(c.r,min(c.g,c.b)),d=mx-mn
        var h=0.0
        if d>0 {if mx==c.r {h=(c.g-c.b)/d} else if mx==c.g {h=(c.b-c.r)/d+2} else {h=(c.r-c.g)/d+4};h /= 6;if h<0 {h += 1}}
        return (h,mx>0 ? d/mx : 0,mx)
    }
    public static func rgb(_ h: Double,_ s: Double,_ v: Double)->RGB {
        let t=(h-floor(h))*6,i=Int(t),f=t-Double(i),p=v*(1-s),q=v*(1-f*s),u=v*(1-(1-f)*s)
        switch i%6 {case 0:return RGB(v,u,p);case 1:return RGB(q,v,p);case 2:return RGB(p,v,u);case 3:return RGB(p,q,v);case 4:return RGB(u,p,v);default:return RGB(v,p,q)}
    }
    private static func level(_ x: Double,_ p: LevelsChannel)->Double {
        let normalized=clamp((x-Double(p.inputBlack))/Double(p.inputWhite-p.inputBlack))
        return Double(p.outputBlack)+pow(normalized,1/Double(p.gamma))*Double(p.outputWhite-p.outputBlack)
    }
    public static func levels(_ c: RGB,_ p: LevelsSettings)->RGB {
        RGB(level(level(c.r,p.master),p.red),level(level(c.g,p.master),p.green),level(level(c.b,p.master),p.blue))
    }
    public static func calibration(_ c: RGB,_ p: CalibrationSettings)->RGB {
        // Shift each RGB primary's basis vector, then rebuild the original color.
        func basis(_ h: Double,_ hue: Float,_ saturation: Float)->RGB {
            rgb(h+Double(hue),clamp(1+Double(min(0,saturation))),1+Double(max(0,saturation))*0.35)
        }
        let r=basis(0,p.redHue,p.redSaturation),g=basis(1/3,p.greenHue,p.greenSaturation),b=basis(2/3,p.blueHue,p.blueSaturation)
        let y=0.2126*c.r+0.7152*c.g+0.0722*c.b,t=Double(p.shadowTint)*0.12*pow(1-y,2)
        return RGB(clamp(c.r*r.r+c.g*g.r+c.b*b.r+t*0.5),clamp(c.r*r.g+c.g*g.g+c.b*b.g-t),clamp(c.r*r.b+c.g*g.b+c.b*b.b+t*0.5))
    }
    public static func colorRange(_ c: RGB,_ p: ColorRangeSettings)->RGB {
        let (h,s,v)=hsv(c),d=abs(h-Double(p.center)/360),distance=min(d,1-d)*360
        let radius=Double(p.width)/2,edge=max(0.25,radius*Double(p.softness))
        let t=clamp((radius-distance)/edge),weight=t*t*(3-2*t)*min(1,s*4)
        return rgb(h+Double(p.hue)*weight,clamp(s*(1+Double(p.saturation)*weight)),clamp(v+Double(p.luminance)*weight))
    }
    public static func selective(_ c: RGB,_ p: SelectiveColorSettings)->RGB {
        let (h,s,_)=hsv(c),y=0.2126*c.r+0.7152*c.g+0.0722*c.b
        func hueWeight(_ center: Double)->Double {let d=abs(h-center),t=max(0,1-min(d,1-d)*6);return t*t*(3-2*t)*s}
        let zones: [(Double,Float,Float,Float,Float)]=[
            (hueWeight(0),p.redCyan,p.redMagenta,p.redYellow,p.redBlack),
            (hueWeight(1/6),p.yellowCyan,p.yellowMagenta,p.yellowYellow,p.yellowBlack),
            (hueWeight(1/3),p.greenCyan,p.greenMagenta,p.greenYellow,p.greenBlack),
            (hueWeight(0.5),p.cyanCyan,p.cyanMagenta,p.cyanYellow,p.cyanBlack),
            (hueWeight(2/3),p.blueCyan,p.blueMagenta,p.blueYellow,p.blueBlack),
            (hueWeight(5/6),p.magentaCyan,p.magentaMagenta,p.magentaYellow,p.magentaBlack),
            (clamp((y-0.6)/0.4)*(1-s),p.whiteCyan,p.whiteMagenta,p.whiteYellow,p.whiteBlack),
            ((1-abs(2*y-1))*(1-s*0.8),p.neutralCyan,p.neutralMagenta,p.neutralYellow,p.neutralBlack),
            (clamp((0.4-y)/0.4),p.blackCyan,p.blackMagenta,p.blackYellow,p.blackBlack)]
        var r=c.r,g=c.g,b=c.b
        func delta(_ value: Double,_ amount: Float,_ weight: Double)->Double {
            let a=Double(amount)
            return -a*weight*(p.absolute ? 0.35 : (a>=0 ? max(0.04,value) : max(0.04,1-value)))*0.6
        }
        for (w,cyan,magenta,yellow,black) in zones where w>0 {
            r += delta(c.r,cyan,w)+delta(c.r,black,w)
            g += delta(c.g,magenta,w)+delta(c.g,black,w)
            b += delta(c.b,yellow,w)+delta(c.b,black,w)
        }
        return RGB(clamp(r),clamp(g),clamp(b))
    }
}
