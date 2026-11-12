import Foundation
import PhotoDomain

/// Compile this project's small, audited Schema into a token grammar.
/// Field names/enums/types are constrained while numeric bounds and cross-field rules
/// are independently checked before a single image tool is executed.
public enum EditRecipeGrammar {
    public static func make() throws -> String {
        let schema=try JSONSerialization.jsonObject(with:RecipeSchema.data) as! [String:Any]
        var rules=[String](),serial=0
        func literal(_ text: String)->String { String(decoding:try! JSONEncoder().encode(text),as:UTF8.self) }
        func jsonLiteral(_ value: Any)->String {
            let data=try! JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed,.sortedKeys])
            return literal(String(decoding:data,as:UTF8.self))+" ws"
        }
        func compile(_ s: [String:Any]) throws -> String {
            let name="s\(serial)";serial += 1
            let body: String
            if let enums=s["enum"] as? [Any] { body=enums.map(jsonLiteral).joined(separator:" | ") }
            else if let choices=s["anyOf"] as? [[String:Any]] { body=try choices.map(compile).joined(separator:" | ") }
            else {
                switch s["type"] as? String {
                case "object":
                    let properties=s["properties"] as? [String:[String:Any]] ?? [:]
                    let alternatives=try properties.keys.sorted().map { key in literal("\""+key+"\"")+" ws \":\" ws "+(try compile(properties[key]!)) }.joined(separator:" | ")
                    let pair="p\(serial)";serial += 1;rules.append(pair+" ::= "+alternatives)
                    body="\"{\" ws ("+pair+" (\",\" ws "+pair+"){0,\(max(0,properties.count-1))})? \"}\" ws"
                case "array":
                    let child=try compile(s["items"] as! [String:Any]),max=s["maxItems"] as? Int ?? 8
                    body="\"[\" ws ("+child+" (\",\" ws "+child+"){0,\(max-1)})? \"]\" ws"
                case "string":body="string"
                case "number":body="number"
                case "integer":body="integer"
                case "boolean":body="\"true\" ws | \"false\" ws"
                case "null":body="\"null\" ws"
                default:throw LumaError.corruptData("不支持的生成 Schema")
                }
            }
            rules.append(name+" ::= "+body);return name
        }
        let properties=schema["properties"] as! [String:[String:Any]]
        let order=["version","global","color","beauty","masks","operations","evaluation"]
        let fields=try order.map { key -> String in
            let value: String
            if key=="operations" { value="\"[]\" ws" }
            else if key=="global" {
                let values=properties[key]!["properties"] as! [String:[String:Any]]
                let pairs=try ["exposure","contrast","highlights","shadows","whites","blacks","temperature","tint","saturation","vibrance"].map { name in
                    literal("\""+name+"\"")+" ws \":\" ws "+(try compile(values[name]!))
                }
                rules.append("global-required ::= \"{\" ws "+pairs.joined(separator:" \",\" ws ")+" \"}\" ws")
                value="global-required"
            } else if key=="color" || key=="beauty" {
                // The untrained base model gets a compact deterministic shape. Advanced
                // HSL/curves/grading remain fully supported by the validated edit protocol
                // and renderer; specialist student grammar can widen this after training.
                let values=properties[key]!["properties"] as! [String:[String:Any]]
                let names=key=="color" ? ["lut","intensity","referenceProfileID"] : ["enabled","strength","skinTone","blemishRemoval","texturePreservation"]
                let pairs=try names.map { name in literal("\""+name+"\"")+" ws \":\" ws "+(try compile(values[name]!)) }
                let rule=key+"-required";rules.append(rule+" ::= \"{\" ws "+pairs.joined(separator:" \",\" ws ")+" \"}\" ws");value=rule
            } else if key=="evaluation" {
                value=literal("{\"automaticCorrection\":true,\"maxCorrections\":2,\"preserveSkin\":true}")+" ws"
            } else { value=try compile(properties[key]!) }
            return literal("\""+key+"\"")+" ws \":\" ws "+value
        }
        rules.insert("root ::= \"{\" ws "+fields.joined(separator:" \",\" ws ")+" \"}\" ws",at:0)
        rules.append(#"string ::= "\"" [a-zA-Z0-9_.-]{0,64} "\"" ws"#)
        rules.append(#"integer ::= "-"? ("0" | [1-9] [0-9]{0,3}) ws"#)
        rules.append(#"number ::= "-"? ("0" | [1-9] [0-9]{0,3}) ("." [0-9]{1,4})? ws"#)
        rules.append(#"ws ::= [ \t\n\r]{0,3}"#)
        return rules.joined(separator:"\n")+"\n"
    }
}
