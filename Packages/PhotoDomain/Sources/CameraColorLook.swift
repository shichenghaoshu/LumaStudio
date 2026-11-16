import Foundation

/// Independent color approximations. These identifiers never imply a vendor profile.
public enum CameraColorLook: String, CaseIterable, Codable, Sendable {
    case xiaomiLeicaClassic, xiaomiLeicaVivid
    case hasselbladNatural, hasselbladXPan
    case leicaStandard, leicaChrome, leicaMonochrom
    case fujiClassicChrome, fujiVelvia, fujiAstia, fujiAcros

    public var title: String {
        switch self {
        case .xiaomiLeicaClassic:return "徕卡 · 经典"
        case .xiaomiLeicaVivid:return "徕卡 · 生动"
        case .hasselbladNatural:return "哈苏 · 自然"
        case .hasselbladXPan:return "哈苏 · XPan 色彩"
        case .leicaStandard:return "徕卡 · 微暖"
        case .leicaChrome:return "徕卡 · Chrome"
        case .leicaMonochrom:return "徕卡 · 黑白"
        case .fujiClassicChrome:return "富士 · 经典灰调"
        case .fujiVelvia:return "富士 · 鲜艳"
        case .fujiAstia:return "富士 · 柔和"
        case .fujiAcros:return "富士 · 黑白"
        }
    }
    public var category: String {
        switch self {
        case .xiaomiLeicaClassic,.xiaomiLeicaVivid,.leicaStandard,.leicaChrome,.leicaMonochrom:return "徕卡灵感"
        case .hasselbladNatural,.hasselbladXPan:return "哈苏灵感"
        default:return "富士灵感"
        }
    }
    public var detail: String {
        switch self {
        case .xiaomiLeicaClassic:return "小米徕卡经典方向：克制饱和、较深中暗调、微暖肤色。LumaStudio 原创近似。"
        case .xiaomiLeicaVivid:return "小米徕卡生动方向：明快反差、鲜明红绿、保留肤色。LumaStudio 原创近似。"
        case .hasselbladNatural:return "OPPO 哈苏自然色方向：微暖、淡彩和柔和高光。基于 Filmic 开源仿色。"
        case .hasselbladXPan:return "冷影暖高光、褪色胶片。基于 Filmic 开源仿色；只改色彩，保留现有构图。"
        case .leicaStandard:return "微暖、适度反差、柔和高光。基于 Filmic 开源仿色。"
        case .leicaChrome:return "浓郁反差、暖中冷影、较深红色。基于 Filmic 开源仿色。"
        case .leicaMonochrom:return "深黑和较强反差的黑白色调。基于 Filmic 开源仿色。"
        case .fujiClassicChrome:return "灰调、低饱和、抬影。基于 Filmic Classic Chrome 开源仿色。"
        case .fujiVelvia:return "高饱和与强反差，适合风光。基于 Filmic 开源仿色。"
        case .fujiAstia:return "柔和淡彩、温润肤色。基于 Filmic 开源仿色。"
        case .fujiAcros:return "柔和高光的细腻黑白色调。基于 Filmic 开源仿色。"
        }
    }
    public var monochrome: Bool { self == .leicaMonochrom || self == .fujiAcros }

    /// Deterministic, explicit style names only; generic words do not choose a brand.
    public static func requested(in text: String) -> Self? {
        let t=text.lowercased()
        let clauses=t.components(separatedBy:CharacterSet(charactersIn:"，。；,;\n"))
        var selected:Self?
        for clause in clauses {
            if ["不要","不用","不使用","不加","不套","别用","不需要","关闭","移除","without","don't","do not"].contains(where:clause.contains) {continue}
            if clause.contains("徕卡") || clause.contains("leica") {
                if clause.contains("黑白") || clause.contains("mono") {selected = .leicaMonochrom}
                else if clause.contains("chrome") {selected = .leicaChrome}
                else if clause.contains("微暖") || clause.contains("standard") {selected = .leicaStandard}
                else if clause.contains("生动") || clause.contains("vivid") || clause.contains("vibrant") {selected = .xiaomiLeicaVivid}
                else {selected = .xiaomiLeicaClassic}
            } else if clause.contains("哈苏") || clause.contains("hasselblad") {
                selected = clause.contains("xpan") || clause.contains("x-pan") ? .hasselbladXPan : .hasselbladNatural
            } else if clause.contains("富士") || clause.contains("fuji") {
                if clause.contains("黑白") || clause.contains("acros") {selected = .fujiAcros}
                else if clause.contains("鲜艳") || clause.contains("velvia") {selected = .fujiVelvia}
                else if clause.contains("柔和") || clause.contains("astia") {selected = .fujiAstia}
                else {selected = .fujiClassicChrome}
            }
        }
        return selected
    }
    public func applying(to current: EditRecipe) throws -> EditRecipe {
        var result=current
        result.color.enabled=true;result.color.lut=rawValue
        result=ParameterLockPolicy.applying(result,preserving:current)
        try result.validateParameters()
        return result
    }
}
