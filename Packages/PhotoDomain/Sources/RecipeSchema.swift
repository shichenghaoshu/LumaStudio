import Foundation

/// A bounded validator for the JSON Schema keywords used by the shipped recipe schema.
/// Unsupported schema keywords are a development error, never a silent model escape.
public enum RecipeSchema {
    public static var data: Data { get throws {
        guard let u=Bundle.module.url(forResource:"edit-recipe.schema",withExtension:"json") else { throw LumaError.corruptData("缺少编辑协议 Schema") }
        return try Data(contentsOf:u)
    } }
    public static func validate(_ data: Data) throws {
        guard data.count<=512*1024 else { throw LumaError.corruptData("编辑计划超过 512KB") }
        let value=try JSONSerialization.jsonObject(with:data,options:.fragmentsAllowed)
        let schemaData: Data
        if let object=value as? [String:Any],object["version"] as? Int==1,
           let legacy=Bundle.module.url(forResource:"edit-recipe-v1.schema",withExtension:"json") { schemaData=try Data(contentsOf:legacy) }
        else { schemaData=try Self.data }
        let schema=try JSONSerialization.jsonObject(with:schemaData) as! [String:Any]
        try check(value,schema:schema,path:"recipe",depth:0)
    }
    private static func check(_ v: Any,schema s: [String:Any],path: String,depth: Int) throws {
        guard depth<=14 else { throw LumaError.corruptData("计划嵌套过深") }
        func fail(_ reason: String) throws -> Never { throw LumaError.corruptData("\(path)：\(reason)") }
        if let choices=s["enum"] as? [Any],!choices.contains(where:{($0 as? NSObject)?.isEqual(v)==true}) { try fail("不在允许值中") }
        if let alternatives=s["anyOf"] as? [[String:Any]] {
            for a in alternatives { if (try? check(v,schema:a,path:path,depth:depth+1)) != nil { return } }
            try fail("类型不匹配")
        }
        switch s["type"] as? String {
        case "object":
            guard let o=v as? [String:Any] else { try fail("应为对象") }
            let properties=s["properties"] as? [String:[String:Any]] ?? [:]
            for key in s["required"] as? [String] ?? [] where o[key]==nil { try fail("缺少 \(key)") }
            for (key,item) in o {
                guard let sub=properties[key] else { if s["additionalProperties"] as? Bool==false { try fail("未知字段 \(key)") };continue }
                try check(item,schema:sub,path:path+"."+key,depth:depth+1)
            }
        case "array":
            guard let a=v as? [Any] else { try fail("应为数组") }
            if let max=s["maxItems"] as? Int,a.count>max { try fail("数组过长") }
            if let min=s["minItems"] as? Int,a.count<min { try fail("数组过短") }
            if let sub=s["items"] as? [String:Any] { for (i,item) in a.enumerated() { try check(item,schema:sub,path:path+"[\(i)]",depth:depth+1) } }
        case "number","integer":
            guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else { try fail("应为有限数值") }
            let d=n.doubleValue
            if s["type"] as? String=="integer",d.rounded() != d { try fail("应为整数") }
            if let min=s["minimum"] as? Double,d<min { try fail("低于下限") }
            if let max=s["maximum"] as? Double,d>max { try fail("高于上限") }
        case "boolean":guard let n=v as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else { try fail("应为布尔值") }
        case "string":
            guard let t=v as? String else { try fail("应为字符串") }
            if let max=s["maxLength"] as? Int,t.count>max { try fail("文本过长") }
            if let p=s["pattern"] as? String,t.range(of:p,options:.regularExpression)==nil { try fail("格式错误") }
        case "null":guard v is NSNull else { try fail("应为空值") }
        default:try fail("Schema 缺少类型")
        }
    }
}
