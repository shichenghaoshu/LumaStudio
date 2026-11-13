import Foundation

/// Shape-preserving cubic interpolation, shared by the curve UI and image LUT.
public enum CurveSampler {
    public static func value(_ x: Float,points: [CurvePoint])->Float {
        guard points.count>=2 else {return x}
        if x<=points[0].x {return points[0].y}
        guard let i=(0..<(points.count-1)).first(where:{x<=points[$0+1].x}) else {return points.last!.y}
        let a=points[i],b=points[i+1],h=b.x-a.x,d=(b.y-a.y)/h
        func tangent(_ j: Int)->Float {
            if j==0 {return (points[1].y-points[0].y)/(points[1].x-points[0].x)}
            if j==points.count-1 {return (points[j].y-points[j-1].y)/(points[j].x-points[j-1].x)}
            let p=(points[j].y-points[j-1].y)/(points[j].x-points[j-1].x)
            let n=(points[j+1].y-points[j].y)/(points[j+1].x-points[j].x)
            return p*n<=0 ? 0 : 2*p*n/(p+n)
        }
        let m0=d==0 ? 0 : tangent(i),m1=d==0 ? 0 : tangent(i+1),t=(x-a.x)/h
        let result=(2*t*t*t-3*t*t+1)*a.y+(t*t*t-2*t*t+t)*h*m0+(-2*t*t*t+3*t*t)*b.y+(t*t*t-t*t)*h*m1
        return min(max(a.y,b.y),max(min(a.y,b.y),result))
    }
}

extension RGBCurve {
    public func points(_ channel: String)->[CurvePoint] {switch channel {case "red":return red;case "green":return green;case "blue":return blue;default:return master}}
    public mutating func setPoints(_ points: [CurvePoint],channel: String) {switch channel {case "red":red=points;case "green":green=points;case "blue":blue=points;default:master=points}}
}
