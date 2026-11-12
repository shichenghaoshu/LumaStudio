import Foundation

public struct GlobalAdjustments: Codable, Equatable, Sendable {
    public var exposure: Float=0, contrast: Float=1, highlights: Float=0, shadows: Float=0
    public var whites: Float=0, blacks: Float=0, temperature: Float=6500, tint: Float=0
    public var saturation: Float=1, vibrance: Float=0
    public init() {}
    enum CodingKeys: String,CodingKey { case exposure,contrast,highlights,shadows,whites,blacks,temperature,tint,saturation,vibrance }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        exposure=try c.decodeIfPresent(Float.self,forKey:.exposure) ?? exposure
        contrast=try c.decodeIfPresent(Float.self,forKey:.contrast) ?? contrast
        highlights=try c.decodeIfPresent(Float.self,forKey:.highlights) ?? highlights
        shadows=try c.decodeIfPresent(Float.self,forKey:.shadows) ?? shadows
        whites=try c.decodeIfPresent(Float.self,forKey:.whites) ?? whites
        blacks=try c.decodeIfPresent(Float.self,forKey:.blacks) ?? blacks
        temperature=try c.decodeIfPresent(Float.self,forKey:.temperature) ?? temperature
        tint=try c.decodeIfPresent(Float.self,forKey:.tint) ?? tint
        saturation=try c.decodeIfPresent(Float.self,forKey:.saturation) ?? saturation
        vibrance=try c.decodeIfPresent(Float.self,forKey:.vibrance) ?? vibrance
    }
}
public enum HueBand: String,Codable,CaseIterable,Sendable { case red,orange,yellow,green,aqua,blue,purple,magenta }
public struct HSLAdjustment: Codable,Equatable,Sendable {
    public var band: HueBand
    public var hue: Float, saturation: Float, luminance: Float
    public init(band: HueBand,hue: Float=0,saturation: Float=0,luminance: Float=0) { self.band=band;self.hue=hue;self.saturation=saturation;self.luminance=luminance }
}
public struct CurvePoint: Codable,Equatable,Sendable {
    public var x: Float,y: Float
    public init(_ x: Float,_ y: Float) { self.x=x;self.y=y }
}
public struct RGBCurve: Codable,Equatable,Sendable {
    public var master: [CurvePoint]=[],red: [CurvePoint]=[],green: [CurvePoint]=[],blue: [CurvePoint]=[]
    public init() {}
    enum CodingKeys: String,CodingKey { case master,red,green,blue }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        master=try c.decodeIfPresent([CurvePoint].self,forKey:.master) ?? [];red=try c.decodeIfPresent([CurvePoint].self,forKey:.red) ?? []
        green=try c.decodeIfPresent([CurvePoint].self,forKey:.green) ?? [];blue=try c.decodeIfPresent([CurvePoint].self,forKey:.blue) ?? []
    }
}
public struct ColorGrade: Codable,Equatable,Sendable {
    public var shadowHue: Float=220,shadowSaturation: Float=0,highlightHue: Float=40,highlightSaturation: Float=0,balance: Float=0
    public init() {}
    enum CodingKeys: String,CodingKey { case shadowHue,shadowSaturation,highlightHue,highlightSaturation,balance }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        shadowHue=try c.decodeIfPresent(Float.self,forKey:.shadowHue) ?? shadowHue
        shadowSaturation=try c.decodeIfPresent(Float.self,forKey:.shadowSaturation) ?? shadowSaturation
        highlightHue=try c.decodeIfPresent(Float.self,forKey:.highlightHue) ?? highlightHue
        highlightSaturation=try c.decodeIfPresent(Float.self,forKey:.highlightSaturation) ?? highlightSaturation
        balance=try c.decodeIfPresent(Float.self,forKey:.balance) ?? balance
    }
}
public struct ColorAdjustments: Codable,Equatable,Sendable {
    public var hsl: [HSLAdjustment]=[]
    public var curve=RGBCurve(),grading=ColorGrade()
    public var lut: String?=nil
    public var intensity: Float=0.8
    public var referenceProfileID: String?
    public init() {}
    enum CodingKeys: String,CodingKey { case hsl,curve,grading,lut,intensity,referenceProfileID }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        hsl=try c.decodeIfPresent([HSLAdjustment].self,forKey:.hsl) ?? []
        curve=try c.decodeIfPresent(RGBCurve.self,forKey:.curve) ?? curve;grading=try c.decodeIfPresent(ColorGrade.self,forKey:.grading) ?? grading
        lut=try c.decodeIfPresent(String.self,forKey:.lut);intensity=try c.decodeIfPresent(Float.self,forKey:.intensity) ?? intensity
        referenceProfileID=try c.decodeIfPresent(String.self,forKey:.referenceProfileID)
    }
}
public enum MaskKind: String,Codable,CaseIterable,Sendable { case face,skin,hair,sky,background,subject }
public struct LocalMask: Codable,Equatable,Identifiable,Sendable {
    public var id: String
    public var kind: MaskKind
    public var amount: Float
    public var adjustments: GlobalAdjustments
    public init(id: String,kind: MaskKind,amount: Float=1,adjustments: GlobalAdjustments=GlobalAdjustments()) { self.id=id;self.kind=kind;self.amount=amount;self.adjustments=adjustments }
}
public enum ToolID: String,Codable,CaseIterable,Sendable { case global="global.adjust", beauty="beauty.skin", color="color.adjust", local="local.adjust" }
public struct EditOperation: Codable,Equatable,Sendable {
    public var tool: ToolID
    public var maskID: String?
    public init(_ tool: ToolID,maskID: String?=nil) { self.tool=tool;self.maskID=maskID }
}
public struct EvaluationSettings: Codable,Equatable,Sendable {
    public var automaticCorrection=true
    public var maxCorrections=2
    public var preserveSkin=true
    public init() {}
    enum CodingKeys: String,CodingKey { case automaticCorrection,maxCorrections,preserveSkin }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        automaticCorrection=try c.decodeIfPresent(Bool.self,forKey:.automaticCorrection) ?? true
        maxCorrections=try c.decodeIfPresent(Int.self,forKey:.maxCorrections) ?? 2
        preserveSkin=try c.decodeIfPresent(Bool.self,forKey:.preserveSkin) ?? true
    }
}
public struct EditRecipe: Codable,Equatable,Sendable {
    public var version=1
    public var global=GlobalAdjustments()
    public var color=ColorAdjustments()
    public var beauty=BeautySettings()
    public var masks: [LocalMask]=[]
    public var operations: [EditOperation]=[]
    public var evaluation=EvaluationSettings()
    public init() {}
    public var resolvedOperations: [EditOperation] {
        [.init(.global)] + (beauty.enabled ? [.init(.beauty)] : []) + [.init(.color)] + masks.map{.init(.local,maskID:$0.id)}
    }
    public func validateParameters() throws {
        guard version==1 else { throw LumaError.unsupported("EditRecipe 版本 \(version)") }
        func range(_ value: Float,_ lo: Float,_ hi: Float,_ name: String) throws {
            guard value.isFinite,value>=lo,value<=hi else { throw LumaError.corruptData("\(name) 超出 \(lo)…\(hi)") }
        }
        func check(_ g: GlobalAdjustments) throws {
            try range(g.exposure,-3,3,"曝光");try range(g.contrast,0.5,1.5,"对比度")
            for v in [g.highlights,g.shadows,g.whites,g.blacks,g.vibrance] { try range(v,-1,1,"影调") }
            try range(g.temperature,2500,10000,"色温");try range(g.tint,-100,100,"色调");try range(g.saturation,0,2,"饱和度")
        }
        try check(global)
        for (v,n) in [(beauty.strength,"磨皮"),(beauty.skinTone,"肤色"),(beauty.blemishRemoval,"瑕疵"),(color.intensity,"滤镜")] { try range(v,0,1,n) }
        try range(beauty.texturePreservation,0.6,1,"纹理保留")
        guard color.lut==nil || ["natural","portrait","film","warm","cool","clean"].contains(color.lut!) else { throw LumaError.unsupported("未注册的 LUT") }
        if let id=color.referenceProfileID,UUID(uuidString:id)==nil { throw LumaError.corruptData("参考档案 ID") }
        guard color.hsl.count<=8,Set(color.hsl.map(\.band)).count==color.hsl.count else { throw LumaError.corruptData("HSL 重复或过多") }
        for h in color.hsl { try range(h.hue,-0.2,0.2,"HSL 色相");try range(h.saturation,-1,1,"HSL 饱和");try range(h.luminance,-0.5,0.5,"HSL 明度") }
        for points in [color.curve.master,color.curve.red,color.curve.green,color.curve.blue] {
            guard points.isEmpty || ((2...8).contains(points.count) && points.first?.x==0 && points.last?.x==1 && zip(points,points.dropFirst()).allSatisfy{$0.x<$1.x}) else { throw LumaError.corruptData("曲线必须从 0 到 1，且横坐标严格递增") }
            for p in points { try range(p.x,0,1,"曲线 x");try range(p.y,0,1,"曲线 y") }
        }
        try range(color.grading.shadowHue,0,360,"阴影色相");try range(color.grading.highlightHue,0,360,"高光色相")
        try range(color.grading.shadowSaturation,0,0.3,"阴影着色");try range(color.grading.highlightSaturation,0,0.3,"高光着色");try range(color.grading.balance,-1,1,"分离色调平衡")
        guard masks.count<=6,Set(masks.map(\.id)).count==masks.count else { throw LumaError.corruptData("局部区域重复或超过 6 个") }
        for m in masks {
            guard m.id.range(of:"^[A-Za-z0-9_-]{1,32}$",options:.regularExpression) != nil else { throw LumaError.corruptData("区域 ID") }
            try range(m.amount,0,1,"局部强度");try check(m.adjustments)
        }
        guard (0...2).contains(evaluation.maxCorrections) else { throw LumaError.corruptData("最多两轮自动修正") }
        guard operations.isEmpty || operations==resolvedOperations else { throw LumaError.corruptData("工具调用必须与已声明的编辑步骤一致") }
    }
    public func legacyRecipe(export: ExportSettings=ExportSettings(),raw: RAWSettings=RAWSettings()) throws -> Recipe {
        try validateParameters();var r=Recipe();r.edit=self;r.export=export;r.raw=raw;r.beauty=beauty
        r.color.presetID=color.lut;r.color.intensity=color.intensity;r.color.referenceProfileID=color.referenceProfileID
        r.color.exposure=global.exposure;r.color.contrast=global.contrast;r.color.saturation=global.saturation;r.color.temperature=global.temperature
        return r
    }
    public func json() throws -> Data { try validateParameters();let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];return try e.encode(self) }
    public static func decodeValidated(_ data: Data) throws -> EditRecipe {
        try RecipeSchema.validate(data)
        let r=try JSONDecoder().decode(Self.self,from:data);try r.validateParameters();return r
    }
}
