import Foundation

extension EditRecipe {
    /// An AI response is a validated field patch. Omitted fields retain the user's
    /// current values instead of being reset by Codable's default constructors.
    public static func proposal(_ data: Data,preserving current: EditRecipe?) throws -> EditRecipe {
        try RecipeSchema.validate(data)
        guard let patch=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw LumaError.corruptData("方案不是对象")}
        let baseline=try JSONSerialization.jsonObject(with:JSONEncoder().encode(current ?? EditRecipe())) as! [String:Any]
        func merge(_ base: [String:Any],_ patch: [String:Any])->[String:Any] {
            var out=base
            for (key,value) in patch {
                if key=="hsl",let bands=value as? [[String:Any]],let old=base[key] as? [[String:Any]],!bands.isEmpty {
                    var result=old
                    for band in bands {
                        if let index=result.firstIndex(where:{($0["band"] as? String)==(band["band"] as? String)}) {result[index]=merge(result[index],band)}
                        else {result.append(band)}
                    }
                    out[key]=result
                }
                else if let nested=value as? [String:Any],let old=base[key] as? [String:Any] {out[key]=merge(old,nested)}
                else {out[key]=value}
            }
            return out
        }
        var object=merge(baseline,patch);object["version"]=2;object["operations"]=[]
        let r=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:object))
        try r.validateParameters();return r
    }
}
