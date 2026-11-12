import Foundation

public struct VoiceReceipt: Codable,Sendable {
    public let id: UUID
    public let status: String
    public let message: String
    public init(id: UUID,status: String,message: String) { self.id=id;self.status=status;self.message=message }
}
public struct VoiceBridgeStatus: Codable,Sendable {
    public let photo: String?
    public let busy: Bool
    public let pending: Int
    public let status: String
    public init(photo: String?,busy: Bool,pending: Int,status: String) { self.photo=photo;self.busy=busy;self.pending=pending;self.status=status }
}
public typealias VoiceCommandHandler = @Sendable (VoiceCommand) async throws -> VoiceReceipt
public typealias VoiceStatusHandler = @Sendable () async -> VoiceBridgeStatus

/// MCP JSON-RPC 2.0 tools used by XiaoZhi's remote MCP endpoint and stdio clients.
/// No arbitrary code, file selection, export, or photo-upload tools are exposed.
public struct VoiceMCPRouter: Sendable {
    public let onCommand: VoiceCommandHandler
    public let onStatus: VoiceStatusHandler
    public init(onCommand: @escaping VoiceCommandHandler,onStatus: @escaping VoiceStatusHandler) { self.onCommand=onCommand;self.onStatus=onStatus }
    public func handle(_ data: Data) async -> Data? {
        var id: Any=NSNull()
        func response(_ value: Any,error: Bool=false)->Data? {
            try? JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":id,error ? "error" : "result":value],options:.sortedKeys)
        }
        guard data.count<=16384,let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],object["jsonrpc"] as? String=="2.0",let method=object["method"] as? String else { return response(["code":-32600,"message":"Invalid bounded JSON-RPC request"],error:true) }
        if let value=object["id"] { guard value is String || value is NSNumber || value is NSNull else { return response(["code":-32600,"message":"Invalid request id"],error:true) };id=value }
        else { return nil }
        switch method {
        case "initialize":
            let requested=(object["params"] as? [String:Any])?["protocolVersion"] as? String ?? "2024-11-05"
            let version=["2024-11-05","2025-03-26","2025-06-18"].contains(requested) ? requested : "2024-11-05"
            return response(["protocolVersion":version,"capabilities":["tools":["listChanged":false]],"serverInfo":["name":"LumaStudio","version":"0.3.0"]])
        case "ping":return response([String:String]())
        case "tools/list":
            return response(["tools":[
                ["name":"lumastudio.get_status","description":"Get the selected photo name, processing state and pending voice command count; no image is returned.","inputSchema":["type":"object","properties":[:],"additionalProperties":false],"annotations":["readOnlyHint":true,"openWorldHint":false]],
                ["name":"lumastudio.set_instruction","description":"Send a 1-1000 character photo-editing instruction. By default it awaits review in LumaStudio. If the user enabled automatic voice execution, start the existing bounded edit pipeline.","inputSchema":["type":"object","properties":["text":["type":"string","minLength":1,"maxLength":1000],"id":["type":"string","description":"Optional UUID for retry deduplication"]],"required":["text"],"additionalProperties":false],"annotations":["readOnlyHint":false,"destructiveHint":false,"openWorldHint":false]]
            ]])
        case "tools/call":
            guard let params=object["params"] as? [String:Any],let name=params["name"] as? String else { return response(["code":-32602,"message":"Missing tool name"],error:true) }
            let arguments=params["arguments"] as? [String:Any] ?? [:]
            do {
                let output: Data
                if name=="lumastudio.get_status" {
                    guard arguments.isEmpty else { return response(["code":-32602,"message":"Status tool takes no arguments"],error:true) }
                    output=try JSONEncoder().encode(await onStatus())
                } else if name=="lumastudio.set_instruction" {
                    guard Set(arguments.keys).isSubset(of:["text","id"]) else { return response(["code":-32602,"message":"Unknown arguments"],error:true) }
                    var body=arguments;body["source"]="xiaozhi-mcp";body["final"]=true
                    let command=try VoiceCommand.decode(JSONSerialization.data(withJSONObject:body))
                    output=try JSONEncoder().encode(await onCommand(command))
                } else { return response(["code":-32602,"message":"Unknown tool"],error:true) }
                return response(["content":[["type":"text","text":String(decoding:output,as:UTF8.self)]],"isError":false])
            } catch {
                return response(["content":[["type":"text","text":"语音请求未被接受，请检查文字长度、队列和应用状态。"]],"isError":true])
            }
        default:return response(["code":-32601,"message":"Method not found"],error:true)
        }
    }
}
