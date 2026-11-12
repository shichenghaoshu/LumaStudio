import Foundation
import PhotoDomain

/// He et al. guided filter, one-channel guide; O(width*height) summed-area box means.
/// Used on the analysis mask only; full-size texture processing stays on the GPU.
public enum GuidedFilter {
    public static func apply(guide: [Float], input: [Float], width: Int, height: Int, radius: Int = 4, epsilon: Float = 0.003) throws -> [Float] {
        guard width>0,height>0,width*height==input.count,guide.count==input.count,radius>=0,epsilon>0 else { throw LumaError.corruptData("Guided filter 尺寸或参数") }
        let meanI=box(guide,width,height,radius), meanP=box(input,width,height,radius)
        let corrI=box(guide.map{$0*$0},width,height,radius)
        let corrIP=box(zip(guide,input).map(*),width,height,radius)
        var a=[Float](repeating:0,count:input.count), b=a
        for i in a.indices { a[i]=(corrIP[i]-meanI[i]*meanP[i])/(max(0,corrI[i]-meanI[i]*meanI[i])+epsilon); b[i]=meanP[i]-a[i]*meanI[i] }
        let ma=box(a,width,height,radius), mb=box(b,width,height,radius)
        return input.indices.map { min(1,max(0,ma[$0]*guide[$0]+mb[$0])) }
    }
    private static func box(_ p: [Float],_ w: Int,_ h: Int,_ r: Int) -> [Float] {
        let stride=w+1
        var integral=[Double](repeating:0,count:(w+1)*(h+1)), out=[Float](repeating:0,count:p.count)
        for y in 0..<h { var sum=0.0; for x in 0..<w { sum += Double(p[y*w+x]); integral[(y+1)*stride+x+1]=integral[y*stride+x+1]+sum } }
        for y in 0..<h { let y0=max(0,y-r),y1=min(h,y+r+1)
            for x in 0..<w { let x0=max(0,x-r),x1=min(w,x+r+1)
                out[y*w+x]=Float((integral[y1*stride+x1]-integral[y0*stride+x1]-integral[y1*stride+x0]+integral[y0*stride+x0])/Double((y1-y0)*(x1-x0)))
            }
        }
        return out
    }
}
