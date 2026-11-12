import Foundation
import PhotoDomain

public enum VoiceConnectionState: String,Sendable { case disconnected,connecting,connected,failed }
private final class VoiceSocketDelegate: NSObject,URLSessionWebSocketDelegate {
    let status: @Sendable (VoiceConnectionState) async -> Void
    init(status: @escaping @Sendable (VoiceConnectionState) async -> Void) { self.status=status }
    func urlSession(_ session: URLSession,webSocketTask: URLSessionWebSocketTask,didOpenWithProtocol protocol: String?) { Task { await status(.connected) } }
    func urlSession(_ session: URLSession,webSocketTask: URLSessionWebSocketTask,didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,reason: Data?) { Task { await status(.disconnected) } }
    func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,newRequest request: URLRequest,completionHandler: @escaping (URLRequest?)->Void) { completionHandler(nil) }
}
/// Connects to XiaoZhi's MCP endpoint, which already handles ASR/LLM/TTS.
/// It is an MCP tool server over WebSocket, not an ESP32 Opus device emulator.
public actor XiaozhiMCPClient {
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var loop: Task<Void,Never>?
    public init() {}
    public func connect(endpoint: URL,router: VoiceMCPRouter,status: @escaping @Sendable (VoiceConnectionState) async -> Void) async throws {
        guard endpoint.scheme=="wss" || (endpoint.scheme=="ws" && ["localhost","127.0.0.1","::1"].contains(endpoint.host ?? "")),endpoint.user==nil,endpoint.password==nil,endpoint.fragment==nil else { throw LumaError.unsupported("小智 MCP 接入点需要 wss 地址") }
        disconnect()
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=15;config.urlCache=nil;config.httpShouldSetCookies=false
        let session=URLSession(configuration:config,delegate:VoiceSocketDelegate(status:status),delegateQueue:nil)
        self.session=session
        let socket=session.webSocketTask(with:endpoint);socket.maximumMessageSize=16384;self.socket=socket
        await status(.connecting);socket.resume()
        loop=Task {
            do {
                while !Task.isCancelled {
                    let message=try await socket.receive()
                    let input: Data
                    switch message {case .string(let text):input=Data(text.utf8);case .data(let data):input=data;@unknown default:continue}
                    if let output=await router.handle(input) { try await socket.send(.string(String(decoding:output,as:UTF8.self))) }
                }
            } catch { if !Task.isCancelled { await status(.failed) } }
        }
    }
    public func disconnect() {
        loop?.cancel();loop=nil;socket?.cancel(with:.goingAway,reason:nil);socket=nil
        session?.invalidateAndCancel();session=nil
    }
}
