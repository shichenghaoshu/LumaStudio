import Foundation
import CoreImage
import CoreGraphics
import PhotoDomain

/// Native operators used by both preview and export. Radii are referenced to a
/// 1600-pixel long edge, so a recipe retains its visual scale at full resolution.
enum ProOperators {
    private static let frequency=CIColorKernel(source:"""
    kernel vec4 frequency(__sample original,__sample low,float amount) {
        return vec4(original.rgb+(original.rgb-low.rgb)*amount,original.a);
    }
    """)!
    private static let haze=CIColorKernel(source:"""
    kernel vec4 haze(__sample original,__sample dark,float amount) {
        float t=clamp(1.0-max(amount,0.0)*0.45*(1.0-dark.r),0.45,1.0);
        vec3 c=(original.rgb-vec3(0.9))/t+vec3(0.9);
        if (amount<0.0) c=mix(original.rgb,vec3(0.9),-amount*0.32);
        return vec4(c,original.a);
    }
    """)!
    private static let denoise=CIColorKernel(source:"""
    kernel vec4 noise(__sample original,__sample low,float luminance,float lumDetail,float chroma,float chromaDetail) {
        vec3 weights=vec3(0.2126,0.7152,0.0722);
        float y=dot(original.rgb,weights),ly=dot(low.rgb,weights);
        float outY=mix(y,ly,luminance*(1.0-lumDetail*0.75)*0.85);
        vec3 color=mix(original.rgb-vec3(y),low.rgb-vec3(ly),chroma*(1.0-chromaDetail*0.75));
        return vec4(vec3(outY)+color,original.a);
    }
    """)!
    private static let sharpen=CIColorKernel(source:"""
    kernel vec4 sharpen(__sample original,__sample low,__sample edge,float amount,float detail,float masking) {
        vec3 weights=vec3(0.2126,0.7152,0.0722);
        float y=dot(original.rgb,weights),ly=dot(low.rgb,weights);
        float gate=mix(1.0,smoothstep(masking*0.12,masking*0.12+0.04,dot(edge.rgb,weights)),masking);
        return vec4(original.rgb+vec3((y-ly)*amount*(0.25+detail*0.75)*gate),original.a);
    }
    """)!
    private static let effectsKernel=CIColorKernel(source:"""
    kernel vec4 effects(__sample original,vec4 extent,float vignette,float midpoint,float roundness,float feather,float grain,float size,float roughness,float fade,vec3 tint,float tintAmount) {
        vec2 p=(destCoord()-extent.xy)/extent.zw-vec2(0.5);
        vec2 q=mix(p,p*extent.zw/min(extent.z,extent.w),roundness);
        float radial=length(q)*1.41421356;
        float mask=smoothstep(midpoint*0.8,midpoint*0.8+feather,radial);
        vec3 c=original.rgb*exp2(-vignette*mask*1.5);
        c=vec3(0.06*fade)+c*(1.0-fade*0.12);
        vec2 cell=floor(destCoord()/max(size,0.1));
        float n=fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453)-0.5;
        float fine=fract(sin(dot(floor(destCoord()/max(size*0.5,0.1)),vec2(39.346,11.135)))*24634.6345)-0.5;
        float y=max(0.0,dot(c,vec3(0.2126,0.7152,0.0722)));
        c+=vec3(mix(n,fine,roughness)*grain*0.12*sqrt(y+0.02));
        c+=(tint-vec3(0.5))*tintAmount*y*(1.0-clamp(y,0.0,1.0));
        return vec4(c,original.a);
    }
    """)!
    private static let highlight=CIColorKernel(source:"""
    kernel vec4 highlight(__sample original,float amount) {
        float y=dot(original.rgb,vec3(0.2126,0.7152,0.0722));
        return vec4(original.rgb*smoothstep(0.6,1.0,y)*amount,original.a);
    }
    """)!
    private static let radial=CIWarpKernel(source:"""
    kernel vec2 radial(vec2 center,vec2 size,float strength) {
        vec2 d=destCoord()-center,n=d/size;
        return center+d*(1.0+strength*dot(n,n)*2.0);
    }
    """)!
    private static let channels=CIColorKernel(source:"""
    kernel vec4 channels(__sample original,__sample red,__sample blue) { return vec4(red.r,original.g,blue.b,original.a); }
    """)!
    private static let lensLight=CIColorKernel(source:"""
    kernel vec4 lensLight(__sample original,vec2 center,vec2 size,float amount) {
        vec2 p=(destCoord()-center)/size;
        return vec4(original.rgb*(1.0+dot(p,p)*amount*2.0),original.a);
    }
    """)!
    static func presence(_ image: CIImage,_ g: GlobalAdjustments)->CIImage {
        var out=image;let scale=max(image.extent.width,image.extent.height)/1600
        for (amount,radius) in [(g.texture,1.2),(g.clarity,12.0)] where amount != 0 {
            let low=out.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.4,radius*scale)]).cropped(to:image.extent)
            out=frequency.apply(extent:image.extent,arguments:[out,low,amount*0.8])!
        }
        if g.dehaze != 0 {
            let dark=out.applyingFilter("CIMinimumComponent").clampedToExtent().applyingFilter("CIMorphologyMinimum",parameters:[kCIInputRadiusKey:max(1,8*scale)]).cropped(to:image.extent)
            out=haze.apply(extent:image.extent,arguments:[out,dark,g.dehaze])!
        }
        return out
    }
    static func detail(_ image: CIImage,_ s: DetailSettings)->CIImage {
        var out=image;let scale=max(image.extent.width,image.extent.height)/1600
        if s.luminanceNoise>0 || s.colorNoise>0 {
            let low=out.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.5,2.5*scale)]).cropped(to:image.extent)
            out=denoise.apply(extent:image.extent,arguments:[out,low,s.luminanceNoise,s.luminanceDetail,s.colorNoise,s.colorDetail])!
        }
        if s.sharpening>0 {
            let low=out.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(0.2,Double(s.radius)*scale)]).cropped(to:image.extent)
            let edges=out.applyingFilter("CIEdges",parameters:[kCIInputIntensityKey:1])
            out=sharpen.apply(extent:image.extent,arguments:[out,low,edges,s.sharpening,s.detail,s.masking])!
        }
        return out
    }
    static func effects(_ image: CIImage,_ s: EffectSettings)->CIImage {
        var out=image;let scale=max(image.extent.width,image.extent.height)/1600,e=image.extent
        if s.bloom>0 {
            let hi=highlight.apply(extent:e,arguments:[out,s.bloom*0.35])!
            let glow=hi.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:Double(s.bloomRadius)*scale]).cropped(to:e)
            out=glow.applyingFilter("CIAdditionCompositing",parameters:[kCIInputBackgroundImageKey:out]).cropped(to:e)
        }
        guard s.vignette != 0 || s.grain>0 || s.fade>0 || s.filmSaturation>0 else {return out}
        let hue=Double(s.filmHue)/60,c=1.0,x=1-abs(hue.truncatingRemainder(dividingBy:2)-1)
        let color: [Double]
        switch Int(hue)%6 {case 0:color=[c,x,0];case 1:color=[x,c,0];case 2:color=[0,c,x];case 3:color=[0,x,c];case 4:color=[x,0,c];default:color=[c,0,x]}
        return effectsKernel.apply(extent:e,arguments:[out,CIVector(cgRect:e),s.vignette,s.vignetteMidpoint,s.vignetteRoundness,s.vignetteFeather,s.grain,max(0.2,Double(s.grainSize)*scale),s.grainRoughness,s.fade,CIVector(values:color.map{CGFloat($0)},count:3),s.filmSaturation])!
    }
    private static func warp(_ image: CIImage,_ amount: Float)->CIImage {
        let e=image.extent
        return radial.apply(extent:e,roiCallback:{_,_ in e},image:image.clampedToExtent(),arguments:[CIVector(x:e.midX,y:e.midY),CIVector(x:e.width,y:e.height),amount])!.cropped(to:e)
    }
    static func geometry(_ image: CIImage,_ s: GeometrySettings)->CIImage {
        var out=image;let e=image.extent,w=e.width,h=e.height
        if s.distortion != 0 {out=warp(out,s.distortion)}
        if s.chromaticAberration != 0 {out=channels.apply(extent:e,arguments:[out,warp(out,s.chromaticAberration*0.012),warp(out,-s.chromaticAberration*0.012)])!}
        if s.lensVignette>0 {out=lensLight.apply(extent:e,arguments:[out,CIVector(x:e.midX,y:e.midY),CIVector(x:w,y:h),s.lensVignette])!}
        if s.horizontal != 0 || s.vertical != 0 {
            let ix=CGFloat(abs(s.vertical))*w*0.5,iy=CGFloat(abs(s.horizontal))*h*0.5
            let corrected=out.applyingFilter("CIPerspectiveCorrection",parameters:[
                "inputTopLeft":CIVector(x:s.vertical>0 ? ix : 0,y:h-(s.horizontal>0 ? iy : 0)),
                "inputTopRight":CIVector(x:w-(s.vertical>0 ? ix : 0),y:h-(s.horizontal<0 ? iy : 0)),
                "inputBottomLeft":CIVector(x:s.vertical<0 ? ix : 0,y:s.horizontal>0 ? iy : 0),
                "inputBottomRight":CIVector(x:w-(s.vertical<0 ? ix : 0),y:s.horizontal<0 ? iy : 0),"inputCrop":true])
            let r=corrected.extent
            out=corrected.transformed(by:CGAffineTransform(translationX:-r.minX,y:-r.minY)).transformed(by:CGAffineTransform(scaleX:w/r.width,y:h/r.height)).cropped(to:e)
        }
        if s.rotation != 0 {
            let angle=CGFloat(s.rotation) * .pi/180,c=abs(cos(angle)),v=abs(sin(angle)),fill=max((w*c+h*v)/w,(h*c+w*v)/h)
            out=out.transformed(by:CGAffineTransform(translationX:-e.midX,y:-e.midY)).transformed(by:CGAffineTransform(scaleX:fill,y:fill)).transformed(by:CGAffineTransform(rotationAngle:angle)).transformed(by:CGAffineTransform(translationX:e.midX,y:e.midY)).cropped(to:e)
        }
        var cw=w,ch=h
        if s.cropAspect>0 {let ratio=CGFloat(s.cropAspect);if w/h>ratio {cw=h*ratio}else{ch=w/ratio}}
        cw=max(1,floor(cw/CGFloat(s.scale)));ch=max(1,floor(ch/CGFloat(s.scale)))
        let cx=min(w-cw/2,max(cw/2,CGFloat(s.centerX)*w)),cy=min(h-ch/2,max(ch/2,(1-CGFloat(s.centerY))*h))
        let crop=CGRect(x:floor(cx-cw/2),y:floor(cy-ch/2),width:cw,height:ch)
        return out.cropped(to:crop).transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY))
    }
}

enum LocalMaskRasterizer {
    static func resolve(_ m: LocalMask,semantic: CIImage?,extent: CGRect)throws->CIImage {
        var mask: CIImage
        if m.kind == .brush {
            let scale=min(1,1600/max(extent.width,extent.height)),w=max(1,Int(extent.width*scale)),h=max(1,Int(extent.height*scale))
            guard let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else {throw LumaError.invalidImage("画笔蒙版")}
            c.setFillColor(gray:0,alpha:1);c.fill(CGRect(x:0,y:0,width:w,height:h));c.setLineCap(.round);c.setLineJoin(.round)
            for stroke in m.strokes {
                c.setStrokeColor(gray:1,alpha:CGFloat(stroke.flow));c.setFillColor(gray:1,alpha:CGFloat(stroke.flow));c.setLineWidth(CGFloat(stroke.size)*CGFloat(min(w,h)))
                let points=stroke.points.map{CGPoint(x:CGFloat($0.x)*CGFloat(w),y:(1-CGFloat($0.y))*CGFloat(h))}
                if points.count==1 {let r=CGFloat(stroke.size)*CGFloat(min(w,h))/2;c.fillEllipse(in:CGRect(x:points[0].x-r,y:points[0].y-r,width:r*2,height:r*2))}
                else {c.beginPath();c.addLines(between:points);c.strokePath()}
            }
            guard let cg=c.makeImage() else {throw LumaError.invalidImage("画笔像素")}
            mask=CIImage(cgImage:cg).transformed(by:CGAffineTransform(scaleX:extent.width/CGFloat(w),y:extent.height/CGFloat(h)))
        } else {guard let semantic else {throw LumaError.unsupported("当前照片未取得所选区域")};mask=semantic}
        if m.feather>0 {mask=mask.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:CGFloat(m.feather)*min(extent.width,extent.height)]).cropped(to:extent)}
        if m.inverted {mask=mask.applyingFilter("CIColorInvert")}
        let a=CGFloat(m.amount)
        return mask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:a,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:a,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:a,w:0)]).cropped(to:extent)
    }
}
