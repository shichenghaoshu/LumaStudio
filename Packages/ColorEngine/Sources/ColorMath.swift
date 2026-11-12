import Foundation
import CoreImage
import PhotoDomain

public struct RGB: Codable, Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r=r; self.g=g; self.b=b }
}
public struct Lab: Codable, Equatable, Sendable {
    public var l: Double, a: Double, b: Double
    public init(_ l: Double, _ a: Double, _ b: Double) { self.l=l; self.a=a; self.b=b }
    public static func from(_ rgb: RGB) -> Lab {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055)/1.055, 2.4) }
        let r=linear(rgb.r), g=linear(rgb.g), b=linear(rgb.b)
        func f(_ t: Double) -> Double { t > 0.00885645168 ? cbrt(t) : 7.787037*t + 16/116 }
        let x=f((0.4124564*r+0.3575761*g+0.1804375*b)/0.95047)
        let y=f(0.2126729*r+0.7151522*g+0.072175*b)
        let z=f((0.0193339*r+0.119192*g+0.9503041*b)/1.08883)
        return Lab(116*y-16,500*(x-y),200*(y-z))
    }
    public func rgb() -> RGB {
        let y=(l+16)/116, x=a/500+y, z=y-b/200
        func inv(_ t: Double) -> Double { t*t*t > 0.00885645168 ? t*t*t : (t-16/116)/7.787037 }
        let xx=0.95047*inv(x), yy=inv(y), zz=1.08883*inv(z)
        func gamma(_ t: Double) -> Double { min(1, max(0, t <= 0.0031308 ? 12.92*t : 1.055*pow(t,1/2.4)-0.055)) }
        return RGB(gamma(3.2404542*xx-1.5371385*yy-0.4985314*zz), gamma(-0.969266*xx+1.8760108*yy+0.041556*zz),gamma(0.0556434*xx-0.2040259*yy+1.0572252*zz))
    }
}
public struct ColorStatistics: Codable, Sendable {
    public let mean: Lab
    public let deviation: Lab
    public let luminanceHistogram: [Double]
    public let saturation: Double
    public let shadows: Double
    public let highlights: Double
    public let estimatedTemperature: Double
    public let estimatedTint: Double
    public let exposureEV: Double
    public let contrast: Double
    public init(samples: [RGB]) throws {
        guard !samples.isEmpty else { throw LumaError.corruptData("没有色彩样本") }
        let labs=samples.map(Lab.from); let n=Double(labs.count)
        let ml=labs.reduce(0){$0+$1.l}/n, ma=labs.reduce(0){$0+$1.a}/n, mb=labs.reduce(0){$0+$1.b}/n
        mean=Lab(ml,ma,mb)
        deviation=Lab(sqrt(labs.reduce(0){$0+pow($1.l-ml,2)}/n),sqrt(labs.reduce(0){$0+pow($1.a-ma,2)}/n),sqrt(labs.reduce(0){$0+pow($1.b-mb,2)}/n))
        var bins=[Double](repeating: 0,count: 64)
        for v in labs { bins[min(63,max(0,Int(v.l*0.63)))] += 1/n }
        luminanceHistogram=bins
        saturation=samples.reduce(0) { v,c in let hi=max(c.r,c.g,c.b), lo=min(c.r,c.g,c.b); return v+(hi > 0.001 ? (hi-lo)/hi : 0) }/n
        shadows=Double(labs.filter{$0.l<20}.count)/n; highlights=Double(labs.filter{$0.l>90}.count)/n
        estimatedTemperature=min(12000,max(2000,6500-mb*70)); estimatedTint=ma
        exposureEV=log2(max(0.01,ml/50)); contrast=deviation.l
    }
    public func validate() throws {
        let values=[mean.l,mean.a,mean.b,deviation.l,deviation.a,deviation.b,saturation,shadows,highlights,estimatedTemperature,estimatedTint,exposureEV,contrast]+luminanceHistogram
        guard luminanceHistogram.count == 64, values.allSatisfy(\.isFinite), luminanceHistogram.allSatisfy({$0>=0}), abs(luminanceHistogram.reduce(0,+)-1)<0.02, deviation.l>=0, deviation.a>=0, deviation.b>=0 else { throw LumaError.corruptData("色彩统计数据") }
    }
}
public struct ColorProfile: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let reference: ColorStatistics
    public init(name: String, reference: ColorStatistics) { id=UUID().uuidString; self.name=name; self.reference=reference }
    public func validate() throws { guard UUID(uuidString:id) != nil,name.count<=256 else { throw LumaError.corruptData("色彩档案标识") };try reference.validate() }
}
public enum HistogramMatching {
    public static func map(value: Double, source: [Double], reference: [Double]) -> Double {
        guard source.count == reference.count, source.count>1 else { return value }
        let index=min(source.count-1,max(0,Int(value*Double(source.count-1))))
        let q=source.prefix(index+1).reduce(0,+)
        var sum=0.0
        for (i,v) in reference.enumerated() { sum += v; if sum >= q { return Double(i)/Double(reference.count-1) } }
        return 1
    }
}
