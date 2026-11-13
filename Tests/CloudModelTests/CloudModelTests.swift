import XCTest
import CoreImage
import ImageIO
import CloudModel
import PhotoDomain
import AgentCore
import VisionEngine
import LocalMemory

private actor FixtureTransport: ModelHTTPTransport {
    let body: Data
    let status: Int
    var requests=[URLRequest]()
    init(body: Data,status: Int=200) { self.body=body;self.status=status }
    func send(_ request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        requests.append(request)
        return (body,HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil)!)
    }
    func last()->URLRequest? { requests.last }
}
final class CloudModelTests: XCTestCase {
    func testDeepSeekDisablesThinkingForBoundedJSONButOtherProvidersAreUnchanged() async throws {
        for deepseek in [false,true] {
            var settings=configuration();if deepseek{settings.provider = .deepseek;settings.baseURL="https://api.deepseek.com";settings.model="deepseek-flash"}
            let fixture=FixtureTransport(body:try JSONSerialization.data(withJSONObject:["choices":[["message":["content":"{\"ok\":true}"],"finish_reason":"stop"]]]))
            try await OnlineAgentPlanner(settings:settings,key:"unit-test-key",transport:fixture).checkConnection()
            let request=await fixture.last(),object=try XCTUnwrap(try JSONSerialization.jsonObject(with:request!.httpBody!) as? [String:Any])
            if deepseek{XCTAssertEqual((object["thinking"] as? [String:String])?["type"],"disabled")}else{XCTAssertNil(object["thinking"])}
        }
        XCTAssertThrowsError(try OnlineAgentPlanner.outputText(JSONSerialization.data(withJSONObject:["choices":[["message":["content":"   "],"finish_reason":"stop"]]]),style:.chatCompletions))
    }
    private func context() throws -> PlanningContext {
        let ci=CIImage(color:CIColor(red:0.4,green:0.3,blue:0.2)).cropped(to:CGRect(x:0,y:0,width:64,height:64))
        let cg=CIContext().createCGImage(ci,from:ci.extent)!
        return PlanningContext(instruction:"保持自然，不要美颜",analysis:ImageAnalysis(image:cg,faceCount:1,metrics:try PixelMetrics.measure(cg)),preferences:EditingPreferences())
    }
    private func configuration(_ style: CloudAPIStyle = .chatCompletions)->CloudSettings {
        var settings=CloudSettings();settings.provider = .custom;settings.baseURL="https://fixture.example/v1";settings.model="fixture-model";settings.style=style
        return settings
    }
    func testChatRecipeIsValidatedAndImageRequiresExplicitOptIn() async throws {
        var recipe=EditRecipe();recipe.beauty.enabled=true
        let text=String(decoding:try recipe.json(),as:UTF8.self)
        let fixture=FixtureTransport(body:try JSONSerialization.data(withJSONObject:["choices":[["message":["content":text],"finish_reason":"stop"]]]))
        let plan=try await OnlineAgentPlanner(settings:configuration(),key:"unit-test-key",previewJPEG:Data([1,2,3]),transport:fixture).plan(context())
        XCTAssertFalse(plan.recipe.beauty.enabled);XCTAssertTrue(plan.source.hasPrefix("在线"))
        let captured=await fixture.last();let request=try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString,"https://fixture.example/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer unit-test-key")
        let object=try XCTUnwrap(try JSONSerialization.jsonObject(with:request.httpBody!) as? [String:Any])
        XCTAssertFalse(String(decoding:request.httpBody!,as:UTF8.self).contains("data:image"))
        XCTAssertEqual((object["response_format"] as? [String:String])?["type"],"json_object")
    }
    func testResponsesRequestAndConnectionProbe() async throws {
        let fixture=FixtureTransport(body:try JSONSerialization.data(withJSONObject:["status":"completed","output":[["type":"message","content":[["type":"output_text","text":"{\"ok\":true}"]]]]]))
        try await OnlineAgentPlanner(settings:configuration(.responses),key:"unit-test-key",transport:fixture).checkConnection()
        let captured=await fixture.last();let request=try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.path,"/v1/responses")
        let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        XCTAssertEqual(body["store"] as? Bool,false)
        XCTAssertFalse(String(decoding:request.httpBody!,as:UTF8.self).contains("photo"))
    }
    func testUnauthorizedErrorNeverEchoesCredentialOrProviderBody() async throws {
        let secret="unit-test-private-value"
        let fixture=FixtureTransport(body:Data("provider echoed \(secret)".utf8),status:401)
        do { try await OnlineAgentPlanner(settings:configuration(),key:secret,transport:fixture).checkConnection();XCTFail("Expected 401") }
        catch { XCTAssertTrue(error.localizedDescription.contains("401"));XCTAssertFalse(error.localizedDescription.contains(secret)) }
    }
    func testInvalidModelPlanAndIncompleteOutputAreRejected() async throws {
        let fixture=FixtureTransport(body:try JSONSerialization.data(withJSONObject:["choices":[["message":["content":"{\"shell\":\"touch /tmp/not-allowed\"}"],"finish_reason":"stop"]]]))
        do { _=try await OnlineAgentPlanner(settings:configuration(),key:"unit-test",transport:fixture).plan(context());XCTFail("Unknown fields must fail") } catch {}
        let incomplete=Data("{\"status\":\"incomplete\",\"output\":[]}".utf8)
        XCTAssertThrowsError(try OnlineAgentPlanner.outputText(incomplete,style:.responses))
    }
    func testEndpointPoliciesRejectInsecureRemoteAndCredentials() throws {
        XCTAssertThrowsError(try ServiceEndpoint.validate("http://remote.example/v1",webSocket:false))
        XCTAssertThrowsError(try ServiceEndpoint.validate("https://user:secret@service.example/v1",webSocket:false))
        XCTAssertThrowsError(try ServiceEndpoint.validate("https://service.example/v1?api_key=secret",webSocket:false))
        XCTAssertNoThrow(try ServiceEndpoint.validate("http://127.0.0.1:8990/v1",webSocket:false))
        XCTAssertNoThrow(try ServiceEndpoint.validate("wss://service.example/mcp?token=example",webSocket:true))
    }
    func testCancellationIsNeverConvertedIntoLocalFallback() async throws {
        struct CancelledPlanner: AgentPlanner { func plan(_ context: PlanningContext) async throws -> AgentPlan { throw CancellationError() } }
        do { _=try await OnlineWithLocalFallback(online:CancelledPlanner(),local:RulesAgentPlanner()).plan(context());XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }
    func testFailedOnlinePlanHasVisibleLocalFallbackReason() async throws {
        struct FailedPlanner: AgentPlanner { func plan(_ context: PlanningContext) async throws -> AgentPlan { throw LumaError.unsupported("fixture connection failure") } }
        let result=try await OnlineWithLocalFallback(online:FailedPlanner(),local:RulesAgentPlanner()).plan(context())
        XCTAssertEqual(result.source,"本地规则 + Vision");XCTAssertTrue(result.fallbackReason?.contains("在线方案未完成")==true)
    }
    func testCloudPreviewContainsNoOriginalGPSAndHasBoundedSize() throws {
        guard let path=ProcessInfo.processInfo.environment["LUMA_PORTRAIT_FIXTURE"] else { throw XCTSkip("Real portrait fixture optional") }
        let data=try XCTUnwrap(try CloudPreview.jpeg(URL(fileURLWithPath:path)))
        let source=CGImageSourceCreateWithData(data as CFData,nil)!
        let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as! [CFString:Any]
        XCTAssertNil(props[kCGImagePropertyGPSDictionary]);XCTAssertLessThanOrEqual(props[kCGImagePropertyPixelWidth] as! Int,512);XCTAssertLessThanOrEqual(props[kCGImagePropertyPixelHeight] as! Int,512)
    }
}
