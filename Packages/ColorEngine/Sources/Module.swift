import Foundation
import CoreImage
import PhotoDomain

public struct LUT3D: Sendable {
    public let dimension: Int
    public let values: [Float] // R fastest, then G, then B; RGBA as required by Core Image.
    public init(dimension: Int, transform: (RGB)->RGB) throws {
        guard (2...65).contains(dimension) else { throw LumaError.corruptData("LUT 维度") }
        self.dimension=dimension
        var values=[Float](); values.reserveCapacity(dimension*dimension*dimension*4)
        for b in 0..<dimension { for g in 0..<dimension { for r in 0..<dimension {
            let c=transform(RGB(Double(r)/Double(dimension-1),Double(g)/Double(dimension-1),Double(b)/Double(dimension-1)))
            values += [Float(c.r),Float(c.g),Float(c.b),1]
        } } }
        guard values.allSatisfy(\.isFinite) else { throw LumaError.corruptData("LUT 非有限数值") }; self.values=values
    }
    public init(cube: String) throws {
        var dimension=0; var values=[Float]()
        for raw in cube.components(separatedBy: .newlines) {
            let l=raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("TITLE") { continue }
            let tokens=l.split(whereSeparator: \.isWhitespace)
            if l.hasPrefix("LUT_3D_SIZE") { dimension=tokens.last.flatMap{Int($0)} ?? 0; guard (2...65).contains(dimension) else { throw LumaError.corruptData("LUT 超过安全维度") }; continue }
            if l.hasPrefix("DOMAIN_MIN") { guard tokens.dropFirst().compactMap({Float($0)}) == [0,0,0] else { throw LumaError.unsupported("LUT DOMAIN_MIN 必须为 0") }; continue }
            if l.hasPrefix("DOMAIN_MAX") { guard tokens.dropFirst().compactMap({Float($0)}) == [1,1,1] else { throw LumaError.unsupported("LUT DOMAIN_MAX 必须为 1") }; continue }
            let rgb=tokens.compactMap{Float($0)}
            guard dimension>0, rgb.count==3, rgb.allSatisfy({$0.isFinite && $0>=0 && $0<=1}), values.count<65*65*65*4 else { throw LumaError.corruptData("LUT 格式") }
            values += rgb+[1]
        }
        guard (2...65).contains(dimension), values.count == dimension*dimension*dimension*4 else { throw LumaError.corruptData("LUT 数据长度") }
        self.dimension=dimension; self.values=values
    }
    public func cube(title: String) -> String {
        var out="TITLE \"\(title.replacingOccurrences(of: "\"", with: ""))\"\nLUT_3D_SIZE \(dimension)\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n"
        for i in stride(from: 0,to: values.count,by: 4) { out += String(format:"%.6f %.6f %.6f\n",values[i],values[i+1],values[i+2]) }
        return out
    }
    public func apply(to image: CIImage) -> CIImage {
        let data=values.withUnsafeBytes { Data($0) }
        return image.applyingFilter("CIColorCubeWithColorSpace", parameters: ["inputCubeDimension":dimension,"inputCubeData":data,"inputColorSpace":CGColorSpace(name: CGColorSpace.sRGB)!])
    }
}
public enum FilterPreset: String, CaseIterable, Identifiable, Sendable {
    case natural, portrait, film, warm, cool, clean, ivory, rose, peach, softPortrait, amber, golden, copper, sunset, silver, mono, matteMono, noir, forest, jade, ocean, alpine, faded, vintage, instant, cinema, tealOrange, night, pastel, airy
    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
    public var title: String {
        ["natural":"自然","portrait":"自然人像","film":"经典胶片","warm":"暖调","cool":"冷调","clean":"清透","ivory":"象牙白","rose":"玫瑰","peach":"蜜桃","softPortrait":"柔光人像","amber":"琥珀","golden":"金色时刻","copper":"铜色","sunset":"落日","silver":"银盐","mono":"经典黑白","matteMono":"哑光黑白","noir":"黑色电影","forest":"森林","jade":"青玉","ocean":"海岸","alpine":"山野","faded":"褪色胶片","vintage":"复古","instant":"即影","cinema":"电影","tealOrange":"青橙","night":"夜色","pastel":"粉彩","airy":"空气感"][id] ?? name
    }
    public var category: String {
        switch self {
        case .natural,.warm,.cool,.clean:return "基础"
        case .portrait,.ivory,.rose,.peach,.softPortrait:return "人像"
        case .amber,.golden,.copper,.sunset:return "暖光"
        case .silver,.mono,.matteMono,.noir:return "黑白"
        case .forest,.jade,.ocean,.alpine:return "风光"
        case .film,.faded,.vintage,.instant:return "胶片"
        case .cinema,.tealOrange,.night:return "电影"
        case .pastel,.airy:return "清新"
        }
    }
    public func lut() throws -> LUT3D {
        guard let url=Bundle.module.url(forResource: rawValue, withExtension: "cube") else { throw LumaError.corruptData("内置 LUT 缺失") }
        return try LUT3D(cube: String(contentsOf: url))
    }
}
public final class ColorProcessor: @unchecked Sendable {
    private let luts: [String: LUT3D]
    public init() throws { luts = try Dictionary(uniqueKeysWithValues: FilterPreset.allCases.map{($0.rawValue,try $0.lut())}) }
    public func analyze(_ image: CIImage, context: CIContext) throws -> ColorStatistics {
        let scale=min(1,160/max(image.extent.width,image.extent.height)); let small=image.transformed(by: CGAffineTransform(scaleX: scale,y: scale))
        let w=max(1,Int(small.extent.width)), h=max(1,Int(small.extent.height))
        var pixels=[UInt8](repeating: 0,count: w*h*4)
        context.render(small, toBitmap: &pixels, rowBytes: w*4, bounds: CGRect(x:0,y:0,width:w,height:h), format:.RGBA8, colorSpace: CGColorSpace(name:CGColorSpace.sRGB))
        let samples=stride(from:0,to:pixels.count,by:4).map { RGB(Double(pixels[$0])/255,Double(pixels[$0+1])/255,Double(pixels[$0+2])/255) }
        return try ColorStatistics(samples:samples)
    }
    public func matchingLUT(source: ColorStatistics, profile: ColorProfile, dimension: Int = 25) throws -> LUT3D {
        try source.validate(); try profile.validate()
        let ref=profile.reference
        func ratio(_ a: Double,_ b: Double)->Double { min(1.65,max(0.65,a/max(3,b))) }
        return try LUT3D(dimension:dimension) { rgb in
            let lab=Lab.from(rgb)
            let reinhardL=(lab.l-source.mean.l)*ratio(ref.deviation.l,source.deviation.l)+ref.mean.l
            let hist=HistogramMatching.map(value:lab.l/100,source:source.luminanceHistogram,reference:ref.luminanceHistogram)*100
            // Bound luminance/chroma shifts to avoid clipping or turning a portrait orange.
            let l=lab.l+min(20,max(-20,(reinhardL*0.75+hist*0.25)-lab.l))
            let a=lab.a+min(13,max(-13,(lab.a-source.mean.a)*ratio(ref.deviation.a,source.deviation.a)+ref.mean.a-lab.a))
            let b=lab.b+min(13,max(-13,(lab.b-source.mean.b)*ratio(ref.deviation.b,source.deviation.b)+ref.mean.b-lab.b))
            return Lab(l,a,b).rgb()
        }
    }
    public func apply(_ image: CIImage, settings: ColorSettings, profile: ColorProfile?, skinMask: CIImage?, context: CIContext) throws -> CIImage {
        guard settings.enabled else { return image }
        var result=image
        if let id=settings.presetID {
            let lut: LUT3D
            if let builtin=luts[id] {lut=builtin} else {lut=try UserFilterLibrary.load(id:id)}
            result=lut.apply(to:result)
        }
        if let profile {
            let source=try analyze(image,context:context)
            let matched=try matchingLUT(source:source,profile:profile).apply(to:result)
            if let skinMask {
                // Restore 80% of the face skin before global intensity blending.
                let protection=skinMask.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:0.8,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.8,z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:0.8,w:0)])
                result=result.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:matched,kCIInputMaskImageKey:protection])
            } else { result=matched }
        }
        result=result.applyingFilter("CIDissolveTransition",parameters:[kCIInputTargetImageKey:image,kCIInputTimeKey:1-min(1,max(0,settings.intensity))])
        result=result.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:settings.exposure])
            .applyingFilter("CIColorControls",parameters:[kCIInputContrastKey:settings.contrast,kCIInputSaturationKey:settings.saturation])
        if settings.temperature != 6500 { result=result.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:CGFloat(settings.temperature),y:0),"inputTargetNeutral":CIVector(x:6500,y:0)]) }
        return result.cropped(to:image.extent)
    }
}
