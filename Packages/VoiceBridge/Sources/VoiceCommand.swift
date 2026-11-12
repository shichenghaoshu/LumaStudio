import Foundation
import DequeModule
import PhotoDomain

public struct VoiceCommand: Codable,Identifiable,Equatable,Sendable {
    public let id: UUID
    public let text: String
    public let source: String
    public let final: Bool
    public init(id: UUID=UUID(),text: String,source: String="external",final: Bool=true) throws {
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty,trimmed.count<=1000,source.count<=80 else { throw LumaError.unsupported("语音文本需要为 1–1000 字，来源最多 80 字") }
        self.id=id;self.text=trimmed;self.source=source;self.final=final
    }
    public static func decode(_ data: Data) throws -> VoiceCommand {
        guard data.count<=8192,let o=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(o.keys).isSubset(of:["id","text","source","final"]),let text=o["text"] as? String else { throw LumaError.corruptData("语音接口需要 text、source、final 和可选 UUID id") }
        let id: UUID
        if let raw=o["id"] { guard let s=raw as? String,let value=UUID(uuidString:s) else { throw LumaError.corruptData("语音请求 ID") };id=value } else { id=UUID() }
        if let value=o["final"] { guard let number=value as? NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID() else { throw LumaError.corruptData("final 应为布尔值") } }
        if let value=o["source"],!(value is String) { throw LumaError.corruptData("source 应为字符串") }
        return try VoiceCommand(id:id,text:text,source:o["source"] as? String ?? "external",final:o["final"] as? Bool ?? true)
    }
}
/// Bounded FIFO + deduplication. Real runtime use of swift-collections Deque.
public actor VoiceCommandQueue {
    private var recent=Deque<UUID>(),seen=Set<UUID>()
    private let limit: Int
    public init(limit: Int=128) { self.limit=max(1,limit) }
    public func accept(_ command: VoiceCommand)->Bool {
        guard command.final,!seen.contains(command.id) else { return false }
        seen.insert(command.id);recent.append(command.id)
        while recent.count>limit { seen.remove(recent.removeFirst()) }
        return true
    }
    public func forget(_ id: UUID) { seen.remove(id);recent.removeAll{$0==id} }
}
