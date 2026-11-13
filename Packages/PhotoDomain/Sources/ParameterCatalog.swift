import Foundation

public enum ParameterSection: String, CaseIterable, Codable, Sendable, Identifiable {
    case raw,tone,levels,curves,hsl,range,grading,selective,calibration,portrait,masks,detail,style,geometry,output
    public var id: String { rawValue }
    public var title: String { switch self {
    case .raw:return "RAW 显影";case .tone:return "基础影调";case .hsl:return "HSL 色彩混合"
    case .curves:return "曲线";case .portrait:return "人像精修";case .masks:return "局部蒙版"
    case .levels:return "色阶";case .range:return "色彩编辑器";case .grading:return "颜色分级"
    case .selective:return "可选颜色";case .calibration:return "相机校准"
    case .detail:return "细节与画质";case .style:return "LUT 与胶片";case .geometry:return "镜头与构图";case .output:return "输出与批量"
    } }
    public var symbol: String { switch self {
    case .raw:return "camera.aperture";case .tone:return "slider.horizontal.3";case .hsl:return "circle.hexagongrid"
    case .curves:return "point.topleft.down.curvedto.point.bottomright.up";case .portrait:return "person.crop.rectangle"
    case .masks:return "circle.dashed";case .detail:return "triangle";case .style:return "camera.filters"
    case .geometry:return "crop.rotate";case .output:return "square.and.arrow.up"
    case .levels:return "chart.bar.xaxis";case .range:return "scope";case .grading:return "circle.lefthalf.filled"
    case .selective:return "slider.horizontal.below.square.filled.and.square";case .calibration:return "camera.filters"
    } }
}

/// Scalar accessors point into the single EditRecipe document. UI, locks and
/// parameter diffs share these exact accessors, units and ranges.
public struct ParameterDescriptor: Identifiable, @unchecked Sendable {
    public let id: String,title: String,section: ParameterSection
    public let range: ClosedRange<Float>,defaultValue: Float,step: Float,scale: Float,offset: Float,unit: String
    public let read: (EditRecipe)->Float
    public let write: (inout EditRecipe,Float)->Void
    public let reset: (inout EditRecipe)->Void
    public let copy: (inout EditRecipe,EditRecipe)->Void
    public let isAutomatic: (EditRecipe)->Bool
    public var displayRange: ClosedRange<Float> { (range.lowerBound*scale+offset)...(range.upperBound*scale+offset) }
    public func display(_ value: Float)->String {
        let n=value*scale+offset
        return String(format:step*scale>=0.99 ? "%.0f" : (step*scale>=0.09 ? "%.1f" : "%.2f"),n)+unit
    }
    public func bounded(_ value: Float)->Float { value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : defaultValue }
    public static func scalar(_ id: String,_ title: String,_ section: ParameterSection,_ path: WritableKeyPath<EditRecipe,Float>,_ range: ClosedRange<Float>,defaultValue: Float,step: Float,scale: Float,offset: Float,unit: String)->Self {
        Self(id:id,title:title,section:section,range:range,defaultValue:defaultValue,step:step,scale:scale,offset:offset,unit:unit,read:{$0[keyPath:path]},write:{$0[keyPath:path]=$1},reset:{$0[keyPath:path]=defaultValue},copy:{$0[keyPath:path]=$1[keyPath:path]},isAutomatic:{_ in false})
    }
    public static func optional(_ id: String,_ title: String,_ section: ParameterSection,_ path: WritableKeyPath<EditRecipe,Float?>,_ range: ClosedRange<Float>,defaultValue: Float,step: Float,scale: Float,offset: Float,unit: String)->Self {
        Self(id:id,title:title,section:section,range:range,defaultValue:defaultValue,step:step,scale:scale,offset:offset,unit:unit,read:{$0[keyPath:path] ?? defaultValue},write:{$0[keyPath:path]=$1},reset:{$0[keyPath:path]=nil},copy:{$0[keyPath:path]=$1[keyPath:path]},isAutomatic:{$0[keyPath:path]==nil})
    }
    public static func integer(_ id: String,_ title: String,_ section: ParameterSection,_ path: WritableKeyPath<EditRecipe,Int>,_ range: ClosedRange<Float>,defaultValue: Float,step: Float,scale: Float,offset: Float,unit: String)->Self {
        Self(id:id,title:title,section:section,range:range,defaultValue:defaultValue,step:step,scale:scale,offset:offset,unit:unit,read:{Float($0[keyPath:path])},write:{$0[keyPath:path]=Int($1.rounded())},reset:{$0[keyPath:path]=Int(defaultValue)},copy:{$0[keyPath:path]=$1[keyPath:path]},isAutomatic:{_ in false})
    }
    public static func hsl(_ band: HueBand,_ title: String,_ path: WritableKeyPath<HSLAdjustment,Float>,_ range: ClosedRange<Float>,scale: Float)->Self {
        let field=path == \.hue ? "hue" : (path == \.saturation ? "saturation" : "luminance")
        func value(_ r: EditRecipe)->Float { r.color.hsl.first{$0.band==band}?[keyPath:path] ?? 0 }
        func put(_ r: inout EditRecipe,_ v: Float) {
            if let i=r.color.hsl.firstIndex(where:{$0.band==band}) { r.color.hsl[i][keyPath:path]=v }
            else if v != 0 { var h=HSLAdjustment(band:band);h[keyPath:path]=v;r.color.hsl.append(h) }
            r.color.hsl.removeAll{$0.hue==0 && $0.saturation==0 && $0.luminance==0}
        }
        return Self(id:"color.hsl.\(band.rawValue).\(field)",title:title,section:.hsl,range:range,defaultValue:0,step:1/scale,scale:scale,offset:0,unit:"",read:value,write:put,reset:{put(&$0,0)},copy:{put(&$0,value($1))},isAutomatic:{_ in false})
    }
}

public enum ParameterCatalog {
    public static func lockTargets(in recipe: EditRecipe)->[String] {
        var ids=all.map(\.id)+["beauty.enabled","color.lut","color.enabled","color.selective.absolute","color.referenceProfileID","color.curve.master","color.curve.red","color.curve.green","color.curve.blue","raw.draft","raw.lensCorrection","geometry.cropAspect","export.format","export.colorSpace","export.bitDepth","export.preserveEXIF","export.nameTemplate"]
        for m in recipe.masks {
            ids += ["amount","feather","brushSize","flow","inverted","strokes"].map{"masks.\(m.id)."+$0}
            ids += section(.tone).map{"masks.\(m.id).adjustments."+$0.id.dropFirst("global.".count)}
            ids += section(.detail).map{"masks.\(m.id)."+$0.id}
        }
        return ids
    }
    public static func find(_ id: String)->ParameterDescriptor? { all.first{$0.id==id} }
    public static func section(_ section: ParameterSection)->[ParameterDescriptor] { all.filter{$0.section==section} }
    public static func reset(_ section: ParameterSection,in recipe: inout EditRecipe) {
        for p in self.section(section) { p.reset(&recipe) }
        switch section {
        case .raw:recipe.raw=RAWSettings()
        case .curves:recipe.color.curve=RGBCurve()
        case .selective:recipe.color.selective=SelectiveColorSettings()
        case .portrait:recipe.beauty.enabled=false
        case .style:recipe.color.lut=nil;recipe.color.referenceProfileID=nil
        case .geometry:recipe.geometry=GeometrySettings()
        case .output:recipe.export=ExportSettings()
        case .masks:recipe.masks=[]
        default:break
        }
    }
    public static func changed(from before: EditRecipe,to after: EditRecipe)->[ParameterChange] {
        var changes=all.compactMap { p -> ParameterChange? in
            let a=p.read(before),b=p.read(after)
            guard abs(a-b)>0.00001 || p.isAutomatic(before) != p.isAutomatic(after) else { return nil }
            return ParameterChange(id:p.id,title:p.title,before:p.isAutomatic(before) ? "相机默认" : p.display(a),after:p.isAutomatic(after) ? "相机默认" : p.display(b))
        }
        if before.beauty.enabled != after.beauty.enabled {changes.append(.init(id:"beauty.enabled",title:"启用美颜",before:before.beauty.enabled ? "开" : "关",after:after.beauty.enabled ? "开" : "关"))}
        if before.color.lut != after.color.lut {changes.append(.init(id:"color.lut",title:"LUT",before:before.color.lut ?? "无",after:after.color.lut ?? "无"))}
        for (key,title) in [("master","RGB 总曲线"),("red","红通道曲线"),("green","绿通道曲线"),("blue","蓝通道曲线")] {
            let a=before.color.curve.points(key),b=after.color.curve.points(key)
            if a != b {changes.append(.init(id:"color.curve."+key,title:title,before:"\(a.isEmpty ? 2 : a.count) 点",after:"\(b.isEmpty ? 2 : b.count) 点已修改"))}
        }
        if before.masks != after.masks {changes.append(.init(id:"masks",title:"局部蒙版",before:"\(before.masks.count) 个",after:"\(after.masks.count) 个 · 参数已修改"))}
        return changes
    }
}
public struct ParameterChange: Identifiable,Sendable { public let id: String,title: String,before: String,after: String }

public enum ParameterLockPolicy {
    public static func isLocked(_ id: String,in recipe: EditRecipe)->Bool { recipe.lockedParameters.contains{id==$0 || id.hasPrefix($0+".")} }
    public static func applying(_ proposed: EditRecipe,preserving original: EditRecipe?)->EditRecipe {
        guard let original else { return proposed }
        var result=proposed;result.lockedParameters=original.lockedParameters
        for p in ParameterCatalog.all where isLocked(p.id,in:original) { p.copy(&result,original) }
        if isLocked("beauty.enabled",in:original) || original.lockedParameters.contains("beauty") { result.beauty.enabled=original.beauty.enabled }
        if isLocked("color.lut",in:original) { result.color.lut=original.color.lut }
        if isLocked("color.referenceProfileID",in:original) { result.color.referenceProfileID=original.color.referenceProfileID }
        if isLocked("color.enabled",in:original) {result.color.enabled=original.color.enabled}
        if isLocked("color.selective.absolute",in:original) {result.color.selective.absolute=original.color.selective.absolute}
        if isLocked("color.curve.master",in:original) { result.color.curve.master=original.color.curve.master }
        if isLocked("color.curve.red",in:original) { result.color.curve.red=original.color.curve.red }
        if isLocked("color.curve.green",in:original) { result.color.curve.green=original.color.curve.green }
        if isLocked("color.curve.blue",in:original) { result.color.curve.blue=original.color.curve.blue }
        if original.lockedParameters.contains("raw") { result.raw=original.raw }
        if original.lockedParameters.contains("export") { result.export=original.export }
        if original.lockedParameters.contains("geometry") { result.geometry=original.geometry }
        if original.lockedParameters.contains("masks") { result.masks=original.masks }
        if isLocked("raw.draft",in:original) {result.raw.draft=original.raw.draft}
        if isLocked("raw.lensCorrection",in:original) {result.raw.lensCorrection=original.raw.lensCorrection}
        if isLocked("geometry.cropAspect",in:original) {result.geometry.cropAspect=original.geometry.cropAspect}
        if isLocked("export.format",in:original) {result.export.format=original.export.format}
        if isLocked("export.colorSpace",in:original) {result.export.colorSpace=original.export.colorSpace}
        if isLocked("export.bitDepth",in:original) {result.export.bitDepth=original.export.bitDepth}
        if isLocked("export.preserveEXIF",in:original) {result.export.preserveEXIF=original.export.preserveEXIF}
        if isLocked("export.nameTemplate",in:original) {result.export.nameTemplate=original.export.nameTemplate}
        for mask in original.masks {
            let prefix="masks."+mask.id
            guard original.lockedParameters.contains(where:{$0==prefix || $0.hasPrefix(prefix+".")}) else {continue}
            if !result.masks.contains(where:{$0.id==mask.id}) {result.masks.append(mask)}
            let i=result.masks.firstIndex(where:{$0.id==mask.id})!
            if original.lockedParameters.contains(prefix) {result.masks[i]=mask;continue}
            var a=EditRecipe(),b=EditRecipe();a.global=mask.adjustments;a.detail=mask.detail;b.global=result.masks[i].adjustments;b.detail=result.masks[i].detail
            for p in ParameterCatalog.all where p.section == .tone || p.section == .detail {
                let suffix=p.section == .tone ? "adjustments."+p.id.dropFirst("global.".count) : p.id
                if isLocked(prefix+"."+suffix,in:original) {p.copy(&b,a)}
            }
            result.masks[i].adjustments=b.global;result.masks[i].detail=b.detail
            if isLocked(prefix+".amount",in:original) {result.masks[i].amount=mask.amount}
            if isLocked(prefix+".feather",in:original) {result.masks[i].feather=mask.feather}
            if isLocked(prefix+".brushSize",in:original) {result.masks[i].brushSize=mask.brushSize}
            if isLocked(prefix+".flow",in:original) {result.masks[i].flow=mask.flow}
            if isLocked(prefix+".inverted",in:original) {result.masks[i].inverted=mask.inverted}
            if isLocked(prefix+".strokes",in:original) {result.masks[i].strokes=mask.strokes}
        }
        result.operations=[];return result
    }
}
