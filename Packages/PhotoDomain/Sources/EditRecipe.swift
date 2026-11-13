import Foundation

public enum HueBand: String,Codable,CaseIterable,Sendable { case red,orange,yellow,green,aqua,blue,purple,magenta }
public struct HSLAdjustment: Codable,Equatable,Sendable {
    public var band: HueBand
    public var hue: Float, saturation: Float, luminance: Float
    public init(band: HueBand,hue: Float=0,saturation: Float=0,luminance: Float=0) { self.band=band;self.hue=hue;self.saturation=saturation;self.luminance=luminance }
    private enum CodingKeys: String,CodingKey {case band,hue,saturation,luminance}
    public init(from decoder: Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        band=try c.decode(HueBand.self,forKey:.band);hue=try c.decodeIfPresent(Float.self,forKey:.hue) ?? 0
        saturation=try c.decodeIfPresent(Float.self,forKey:.saturation) ?? 0;luminance=try c.decodeIfPresent(Float.self,forKey:.luminance) ?? 0
    }
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
public struct ColorAdjustments: Codable,Equatable,Sendable {
    public var enabled=true
    public var hsl: [HSLAdjustment]=[]
    public var curve=RGBCurve(),grading=ColorGrade()
    public var levels=LevelsSettings(),calibration=CalibrationSettings(),range=ColorRangeSettings(),selective=SelectiveColorSettings()
    public var lut: String?=nil
    public var intensity: Float=0.8
    public var referenceProfileID: String?
    public init() {}
    enum CodingKeys: String,CodingKey { case enabled,hsl,curve,grading,levels,calibration,range,selective,lut,intensity,referenceProfileID }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        enabled=try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? true
        hsl=try c.decodeIfPresent([HSLAdjustment].self,forKey:.hsl) ?? []
        curve=try c.decodeIfPresent(RGBCurve.self,forKey:.curve) ?? curve;grading=try c.decodeIfPresent(ColorGrade.self,forKey:.grading) ?? grading
        levels=try c.decodeIfPresent(LevelsSettings.self,forKey:.levels) ?? levels
        calibration=try c.decodeIfPresent(CalibrationSettings.self,forKey:.calibration) ?? calibration
        range=try c.decodeIfPresent(ColorRangeSettings.self,forKey:.range) ?? range
        selective=try c.decodeIfPresent(SelectiveColorSettings.self,forKey:.selective) ?? selective
        lut=try c.decodeIfPresent(String.self,forKey:.lut);intensity=try c.decodeIfPresent(Float.self,forKey:.intensity) ?? intensity
        referenceProfileID=try c.decodeIfPresent(String.self,forKey:.referenceProfileID)
    }
}
public enum MaskKind: String,Codable,CaseIterable,Sendable { case face,skin,hair,sky,background,subject,brush }
public struct BrushPoint: Codable,Equatable,Sendable { public var x: Float,y: Float;public init(x: Float,y: Float) {self.x=x;self.y=y} }
public struct BrushStroke: Codable,Equatable,Sendable {
    public var points: [BrushPoint],size: Float,flow: Float
    public init(points: [BrushPoint],size: Float,flow: Float) {self.points=points;self.size=size;self.flow=flow}
}
public struct LocalMask: Codable,Equatable,Identifiable,Sendable {
    public var id: String,kind: MaskKind,amount: Float
    public var adjustments: GlobalAdjustments
    public var detail=DetailSettings(),inverted=false,feather: Float=0.01,brushSize: Float=0.06,flow: Float=1
    public var strokes: [BrushStroke]=[]
    public init(id: String,kind: MaskKind,amount: Float=1,adjustments: GlobalAdjustments=GlobalAdjustments()) {self.id=id;self.kind=kind;self.amount=amount;self.adjustments=adjustments}
    enum CodingKeys: String,CodingKey { case id,kind,amount,adjustments,detail,inverted,feather,brushSize,flow,strokes }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        self.init(id:try c.decode(String.self,forKey:.id),kind:try c.decode(MaskKind.self,forKey:.kind),amount:try c.decodeIfPresent(Float.self,forKey:.amount) ?? 1,adjustments:try c.decodeIfPresent(GlobalAdjustments.self,forKey:.adjustments) ?? GlobalAdjustments())
        detail=try c.decodeIfPresent(DetailSettings.self,forKey:.detail) ?? detail;inverted=try c.decodeIfPresent(Bool.self,forKey:.inverted) ?? false
        feather=try c.decodeIfPresent(Float.self,forKey:.feather) ?? feather;brushSize=try c.decodeIfPresent(Float.self,forKey:.brushSize) ?? brushSize;flow=try c.decodeIfPresent(Float.self,forKey:.flow) ?? flow
        strokes=try c.decodeIfPresent([BrushStroke].self,forKey:.strokes) ?? []
    }
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
    public var version=2
    public var global=GlobalAdjustments(),color=ColorAdjustments(),beauty=BeautySettings()
    public var raw=RAWSettings(),detail=DetailSettings(),effects=EffectSettings(),geometry=GeometrySettings(),export=ExportSettings()
    public var masks: [LocalMask]=[],operations: [EditOperation]=[]
    public var lockedParameters: [String]=[]
    public var evaluation=EvaluationSettings()
    public init() {}
    enum CodingKeys: String,CodingKey { case version,global,color,beauty,raw,detail,effects,geometry,export,masks,operations,lockedParameters,evaluation }
    public init(from decoder: Decoder) throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        let incoming=try c.decodeIfPresent(Int.self,forKey:.version) ?? 1
        guard incoming==1 || incoming==2 else { throw LumaError.unsupported("EditRecipe 版本 \(incoming)") }
        version=2
        global=try c.decodeIfPresent(GlobalAdjustments.self,forKey:.global) ?? global;color=try c.decodeIfPresent(ColorAdjustments.self,forKey:.color) ?? color
        beauty=try c.decodeIfPresent(BeautySettings.self,forKey:.beauty) ?? beauty;raw=try c.decodeIfPresent(RAWSettings.self,forKey:.raw) ?? raw
        detail=try c.decodeIfPresent(DetailSettings.self,forKey:.detail) ?? detail;effects=try c.decodeIfPresent(EffectSettings.self,forKey:.effects) ?? effects
        geometry=try c.decodeIfPresent(GeometrySettings.self,forKey:.geometry) ?? geometry;export=try c.decodeIfPresent(ExportSettings.self,forKey:.export) ?? export
        masks=try c.decodeIfPresent([LocalMask].self,forKey:.masks) ?? [];operations=try c.decodeIfPresent([EditOperation].self,forKey:.operations) ?? []
        lockedParameters=try c.decodeIfPresent([String].self,forKey:.lockedParameters) ?? [];evaluation=try c.decodeIfPresent(EvaluationSettings.self,forKey:.evaluation) ?? evaluation
    }
    public var resolvedOperations: [EditOperation] { [.init(.global)] + (beauty.enabled ? [.init(.beauty)] : []) + [.init(.color)] + masks.map{.init(.local,maskID:$0.id)} }
    public func validateParameters() throws {
        guard version==2 else { throw LumaError.unsupported("EditRecipe 版本 \(version)") }
        func range(_ v: Float,_ lo: Float,_ hi: Float,_ name: String) throws { guard v.isFinite,v>=lo,v<=hi else { throw LumaError.corruptData("\(name) 超出 \(lo)…\(hi)") } }
        for p in ParameterCatalog.all where !p.isAutomatic(self) {try range(p.read(self),p.range.lowerBound,p.range.upperBound,p.title)}
        guard color.lut==nil || FilterIdentifiers.isValid(color.lut!) else {throw LumaError.unsupported("未注册的 LUT")}
        if let id=color.referenceProfileID,UUID(uuidString:id)==nil {throw LumaError.corruptData("参考档案 ID")}
        guard color.hsl.count<=8,Set(color.hsl.map(\.band)).count==color.hsl.count else {throw LumaError.corruptData("HSL 重复或过多")}
        for points in [color.curve.master,color.curve.red,color.curve.green,color.curve.blue] {
            guard points.isEmpty || ((2...16).contains(points.count) && points.first?.x==0 && points.last?.x==1 && zip(points,points.dropFirst()).allSatisfy{$0.x<$1.x}) else {throw LumaError.corruptData("曲线需有 2–16 点，端点横坐标为 0/1，且严格递增")}
            for p in points {try range(p.x,0,1,"曲线 x");try range(p.y,0,1,"曲线 y")}
        }
        try range(geometry.cropAspect,0,3,"裁切比例")
        guard [8,16].contains(export.bitDepth),export.nameTemplate.count<=128,!export.nameTemplate.isEmpty,!export.nameTemplate.contains("/"),!export.nameTemplate.contains("\\"),!export.nameTemplate.contains(".."),!export.nameTemplate.contains(where:{$0.isNewline || $0.asciiValue.map{$0<32}==true}) else {throw LumaError.corruptData("输出位深或命名规则")}
        let names=export.nameTemplate.replacingOccurrences(of:"{name}",with:"").replacingOccurrences(of:"{id}",with:"").replacingOccurrences(of:"{index}",with:"").replacingOccurrences(of:"{date}",with:"")
        guard !names.contains("{"),!names.contains("}") else {throw LumaError.corruptData("命名仅支持 {name}/{id}/{index}/{date}")}
        guard masks.count<=16,Set(masks.map(\.id)).count==masks.count else {throw LumaError.corruptData("局部区域重复或超过 16 个")}
        for m in masks {
            guard m.id.range(of:"^[A-Za-z0-9_-]{1,32}$",options:.regularExpression) != nil else {throw LumaError.corruptData("区域 ID")}
            try range(m.amount,0,1,"局部强度");try range(m.feather,0,0.1,"羽化");try range(m.brushSize,0.002,0.3,"画笔大小");try range(m.flow,0.01,1,"流量")
            var local=EditRecipe();local.global=m.adjustments;local.detail=m.detail
            for p in ParameterCatalog.all where p.section == .tone || p.section == .detail {try range(p.read(local),p.range.lowerBound,p.range.upperBound,p.title)}
            guard m.strokes.count<=128,m.strokes.reduce(0,{$0+$1.points.count})<=16384 else {throw LumaError.corruptData("画笔笔触过多")}
            for stroke in m.strokes {
                guard (1...2048).contains(stroke.points.count) else {throw LumaError.corruptData("画笔点数量")}
                try range(stroke.size,0.002,0.3,"笔触大小");try range(stroke.flow,0.01,1,"笔触流量")
                for p in stroke.points {try range(p.x,0,1,"笔触 x");try range(p.y,0,1,"笔触 y")}
            }
        }
        guard lockedParameters.count<=256,Set(lockedParameters).count==lockedParameters.count,lockedParameters.allSatisfy({!$0.isEmpty && $0.count<=100 && $0.range(of:"^[A-Za-z0-9_.-]+$",options:.regularExpression) != nil}) else {throw LumaError.corruptData("参数锁定列表")}
        guard (0...2).contains(evaluation.maxCorrections) else {throw LumaError.corruptData("最多两轮自动修正")}
        guard operations.isEmpty || operations==resolvedOperations else {throw LumaError.corruptData("工具调用必须与已声明的编辑步骤一致")}
    }
    public func legacyRecipe(export: ExportSettings?=nil,raw: RAWSettings?=nil) throws -> Recipe {
        var document=self;if let export {document.export=export};if let raw {document.raw=raw}
        try document.validateParameters();return Recipe(document:document)
    }
    public func json() throws -> Data {try validateParameters();let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];return try e.encode(self)}
    public static func decodeValidated(_ data: Data) throws -> EditRecipe {try RecipeSchema.validate(data);let r=try JSONDecoder().decode(Self.self,from:data);try r.validateParameters();return r}
}
