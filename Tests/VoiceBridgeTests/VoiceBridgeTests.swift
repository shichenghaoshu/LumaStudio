import XCTest
import VoiceBridge

private actor CommandSink {
    var commands=[VoiceCommand]()
    func receive(_ command: VoiceCommand)->VoiceReceipt { commands.append(command);return VoiceReceipt(id:command.id,status:"awaiting_review",message:"fixture") }
    func count()->Int { commands.count }
}
final class VoiceBridgeTests: XCTestCase {
    func testBoundedCommandsAndUnknownFields() throws {
        XCTAssertThrowsError(try VoiceCommand(text:" "))
        XCTAssertThrowsError(try VoiceCommand(text:String(repeating:"亮",count:1001)))
        XCTAssertThrowsError(try VoiceCommand.decode(Data("{\"text\":\"提亮\",\"shell\":\"bad\"}".utf8)))
        XCTAssertThrowsError(try VoiceCommand.decode(Data("{\"text\":\"提亮\",\"final\":1}".utf8)))
        XCTAssertThrowsError(try VoiceCommand.decode(Data("{\"text\":\"提亮\",\"source\":[]}".utf8)))
        XCTAssertEqual(try VoiceCommand.decode(Data("{\"text\":\" 提亮 \",\"final\":true}".utf8)).text,"提亮")
    }
    func testQueueDeduplicatesFinalsAndEvictsOldIds() async throws {
        let queue=VoiceCommandQueue(limit:2),a=try VoiceCommand(text:"A"),b=try VoiceCommand(text:"B"),c=try VoiceCommand(text:"C")
        let partial=try VoiceCommand(text:"partial",final:false)
        let p=await queue.accept(partial);XCTAssertFalse(p)
        let first=await queue.accept(a),duplicate=await queue.accept(a);XCTAssertTrue(first);XCTAssertFalse(duplicate)
        _=await queue.accept(b);_=await queue.accept(c)
        let evicted=await queue.accept(a);XCTAssertTrue(evicted)
    }
    func testMCPDiscoveryAndBoundedToolDispatch() async throws {
        let sink=CommandSink()
        let router=VoiceMCPRouter(onCommand:{ await sink.receive($0) },onStatus:{VoiceBridgeStatus(photo:"fixture.jpg",busy:false,pending:0,status:"ready")})
        let initRequest=Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}".utf8)
        let initialized=await router.handle(initRequest);XCTAssertTrue(String(decoding:initialized!,as:UTF8.self).contains("protocolVersion"))
        let tools=await router.handle(Data("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}".utf8));XCTAssertTrue(String(decoding:tools!,as:UTF8.self).contains("lumastudio.set_instruction"))
        let call=Data("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"lumastudio.set_instruction\",\"arguments\":{\"text\":\"自然提亮\"}}}".utf8)
        let result=await router.handle(call);XCTAssertTrue(String(decoding:result!,as:UTF8.self).contains("awaiting_review"))
        let invalid=Data("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"shell.exec\",\"arguments\":{}}}".utf8)
        _=await router.handle(invalid);let count=await sink.count();XCTAssertEqual(count,1)
        let notification=await router.handle(Data("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}".utf8));XCTAssertNil(notification)
    }
    func testRealLoopbackHTTPAuthAndCommand() async throws {
        let sink=CommandSink(),server=LocalVoiceServer(),token=String(repeating:"a",count:64)
        let port=try await server.start(token:token,onCommand:{await sink.receive($0)},onStatus:{VoiceBridgeStatus(photo:"fixture.jpg",busy:false,pending:0,status:"ready")})
        var request=URLRequest(url:URL(string:"http://127.0.0.1:\(port)/v1/voice/commands")!)
        request.httpMethod="POST";request.httpBody=Data("{\"text\":\"暖一点\",\"source\":\"fixture\",\"final\":true}".utf8)
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (_,unauthorized)=try await URLSession.shared.data(for:request);XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode,401)
        request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        let (data,accepted)=try await URLSession.shared.data(for:request)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode,200);XCTAssertTrue(String(decoding:data,as:UTF8.self).contains("awaiting_review"))
        request.setValue("https://untrusted.example",forHTTPHeaderField:"Origin")
        let (_,blocked)=try await URLSession.shared.data(for:request);XCTAssertEqual((blocked as? HTTPURLResponse)?.statusCode,400)
        let count=await sink.count();XCTAssertEqual(count,1)
        var statusRequest=URLRequest(url:URL(string:"http://127.0.0.1:\(port)/v1/status")!)
        statusRequest.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
        for _ in 0..<20 {
            let (_,status)=try await URLSession.shared.data(for:statusRequest)
            XCTAssertEqual((status as? HTTPURLResponse)?.statusCode,200)
        }
        await server.stop()
    }
}
