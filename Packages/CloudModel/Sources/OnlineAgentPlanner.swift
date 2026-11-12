import Foundation
import PhotoDomain
import AgentCore
import ToolRegistry

public protocol ModelHTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data,HTTPURLResponse) }
private final class NoRedirectDelegate: NSObject,URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,newRequest request: URLRequest,completionHandler: @escaping (URLRequest?)->Void) { completionHandler(nil) }
}
public final class ModelURLTransport: ModelHTTPTransport,@unchecked Sendable {
    private let session: URLSession
    public init() {
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=45;config.timeoutIntervalForResource=60
        config.httpShouldSetCookies=false;config.urlCache=nil
        session=URLSession(configuration:config,delegate:NoRedirectDelegate(),delegateQueue:nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        do {
            let (stream,response)=try await session.bytes(for:request)
            guard let http=response as? HTTPURLResponse else { throw LumaError.unsupported("在线服务未返回 HTTP 响应") }
            var data=Data();data.reserveCapacity(4096)
            for try await byte in stream {
                guard data.count<2*1024*1024 else { throw LumaError.unsupported("在线服务返回内容超过限制") }
                data.append(byte)
            }
            return (data,http)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError { if error.code == .cancelled { throw CancellationError() };throw LumaError.unsupported("在线连接失败（\(error.code.rawValue)），请检查网络与服务地址") }
    }
}
public struct OnlineAgentPlanner: AgentPlanner {
    public let settings: CloudSettings
    private let key: String
    private let previewJPEG: Data?
    private let transport: any ModelHTTPTransport
    public init(settings: CloudSettings,key: String,previewJPEG: Data?=nil,transport: any ModelHTTPTransport=ModelURLTransport()) {
        self.settings=settings;self.key=key;self.previewJPEG=previewJPEG;self.transport=transport
    }
    public func plan(_ context: PlanningContext) async throws -> AgentPlan {
        let start=Date()
        let schema=String(decoding:try RecipeSchema.data,as:UTF8.self)
        let system="You are LumaStudio's bounded photo parameter planner. Return only one JSON EditRecipe matching this schema. Never output code, file paths, shell commands or unsupported tools. Use the user's instruction and image analysis. Preserve unrelated current parameters. No face: disable beauty. Never beautify if forbidden. Skin texture preservation at least 0.90. Supported masks: face,skin,subject,background; hair/sky unavailable. operations must be []. Schema: "+schema
        let current=context.currentRecipe.flatMap{try? $0.json()}.map{String(decoding:$0,as:UTF8.self)} ?? "null"
        let analysis=String(decoding:try JSONEncoder().encode(context.analysis),as:UTF8.self)
        let user="instruction: \(context.instruction)\nanalysis: \(analysis)\ncurrent_recipe: \(current)\nreference_profile_id: \(context.referenceProfileID ?? "none")\nPrevious instructions: \(context.previousInstructions.suffix(3).joined(separator:"; "))"
        let request=try makeRequest(system:system,user:user,image:settings.attachPreview ? previewJPEG : nil,maxTokens:2048)
        let data=try await perform(request)
        let output=try Self.outputText(data,style:settings.style)
        let decoded=try ToolRegistry().decode(Data(output.utf8))
        var recipe=try IntentSafetyGate.enforce(decoded,context:context)
        if context.analysis.faceCount==0 || InstructionParser.parse(context.instruction).beautyForbidden { recipe.beauty.enabled=false }
        recipe.beauty.texturePreservation=max(0.9,recipe.beauty.texturePreservation)
        recipe.operations=[];try ToolRegistry().validate(recipe)
        return AgentPlan(recipe:recipe,source:"在线 · \(settings.provider.title) / \(settings.model)",planningMilliseconds:Date().timeIntervalSince(start)*1000)
    }
    public func checkConnection() async throws {
        let request=try makeRequest(system:"Return JSON only.",user:"Return {\"ok\":true}.",image:nil,maxTokens:128)
        let output=try Self.outputText(await perform(request),style:settings.style)
        guard let object=try JSONSerialization.jsonObject(with:Data(output.utf8)) as? [String:Any],object["ok"] as? Bool==true else { throw LumaError.unsupported("服务可访问，但未通过 JSON 返回检查") }
    }
    private func makeRequest(system: String,user: String,image: Data?,maxTokens: Int) throws -> URLRequest {
        let base=try settings.validate()
        guard !key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,!key.contains("\n"),!key.contains("\r") else { throw LumaError.unsupported("请先在在线模型设置中保存 API 密钥") }
        var request=URLRequest(url:base.appendingPathComponent(settings.style == .responses ? "responses" : "chat/completions"))
        request.httpMethod="POST";request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var content: [[String:Any]]=[]
        let imageURL=image.map{"data:image/jpeg;base64,"+$0.base64EncodedString()}
        if let image,image.count>512*1024 { throw LumaError.unsupported("在线预览超过大小限制") }
        let body: [String:Any]
        if settings.style == .responses {
            content=[["type":"input_text","text":user]]
            if let imageURL { content.append(["type":"input_image","image_url":imageURL,"detail":"low"]) }
            body=["model":settings.model,"instructions":system,"input":[["role":"user","content":content]],"text":["format":["type":"json_object"]],"max_output_tokens":maxTokens,"store":false]
        } else {
            content=[["type":"text","text":user]]
            if let imageURL { content.append(["type":"image_url","image_url":["url":imageURL,"detail":"low"]]) }
            body=["model":settings.model,"messages":[["role":"system","content":system],["role":"user","content":content]],"response_format":["type":"json_object"],"max_tokens":maxTokens,"stream":false]
        }
        request.httpBody=try JSONSerialization.data(withJSONObject:body);return request
    }
    private func perform(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation();let (data,http)=try await transport.send(request);try Task.checkCancellation()
        switch http.statusCode {
        case 200..<300:return data
        case 401,403:throw LumaError.unsupported("在线服务拒绝认证，请检查密钥与模型权限（\(http.statusCode)）")
        case 429:throw LumaError.unsupported("在线服务限流或额度不足（429）")
        default:throw LumaError.unsupported("在线服务请求未成功（HTTP \(http.statusCode)）")
        }
    }
    public static func outputText(_ data: Data,style: CloudAPIStyle) throws -> String {
        guard data.count<=2*1024*1024,let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw LumaError.corruptData("在线模型返回格式") }
        if style == .chatCompletions,
           let choices=object["choices"] as? [[String:Any]],let choice=choices.first,
           choice["finish_reason"] as? String != "length",let message=choice["message"] as? [String:Any],message["refusal"] as? String == nil,
           let text=message["content"] as? String,!text.isEmpty { return text }
        if style == .responses,object["status"] as? String != "incomplete",let output=object["output"] as? [[String:Any]] {
            let texts=output.flatMap{$0["content"] as? [[String:Any]] ?? []}.filter{$0["type"] as? String=="output_text"}.compactMap{$0["text"] as? String}
            if !texts.isEmpty { return texts.joined() }
        }
        throw LumaError.corruptData("在线模型没有完整的 JSON 方案，或拒绝了请求")
    }
}
public struct OnlineWithLocalFallback: AgentPlanner {
    let online: any AgentPlanner
    let local: any AgentPlanner
    public init(online: any AgentPlanner,local: any AgentPlanner) { self.online=online;self.local=local }
    public func plan(_ context: PlanningContext) async throws -> AgentPlan {
        do { return try await online.plan(context) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation();let result=try await local.plan(context)
            return AgentPlan(recipe:result.recipe,source:result.source,fallbackReason:"在线方案未完成，已改用本地："+error.localizedDescription,planningMilliseconds:result.planningMilliseconds)
        }
    }
}
