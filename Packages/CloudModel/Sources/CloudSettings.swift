import Foundation
import Security
import PhotoDomain

public enum PlannerMode: String,Codable,CaseIterable,Sendable { case local,online }
public enum CloudAPIStyle: String,Codable,CaseIterable,Sendable { case chatCompletions,responses }
public enum CloudProvider: String,Codable,CaseIterable,Sendable {
    case dashscope,deepseek,openAI,custom
    public var title: String { switch self {case .dashscope:return "阿里云百炼 / 通义";case .deepseek:return "DeepSeek";case .openAI:return "OpenAI";case .custom:return "自定义兼容服务"} }
    public var baseURL: String { switch self {case .dashscope:return "https://dashscope.aliyuncs.com/compatible-mode/v1";case .deepseek:return "https://api.deepseek.com";case .openAI:return "https://api.openai.com/v1";case .custom:return "https://your-service.example/v1"} }
    public var model: String { switch self {case .dashscope:return "qwen-plus";case .deepseek:return "deepseek-flash";case .openAI:return "";case .custom:return ""} }
}
public struct CloudSettings: Codable,Equatable,Sendable {
    public var mode: PlannerMode = .local
    public var provider: CloudProvider = .dashscope
    public var baseURL=CloudProvider.dashscope.baseURL
    public var model=CloudProvider.dashscope.model
    public var style: CloudAPIStyle = .chatCompletions
    public var attachPreview=false
    public var fallbackToLocal=true
    public init() {}
    public var credentialAccount: String { "cloud."+baseURL.trimmingCharacters(in:.whitespacesAndNewlines) }
    public func validate() throws -> URL {
        guard !model.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,model.count<=150,!model.contains("\n") else { throw LumaError.unsupported("请输入服务端提供的模型 ID") }
        return try ServiceEndpoint.validate(baseURL,webSocket:false)
    }
}
public enum ServiceEndpoint {
    public static func validate(_ value: String,webSocket: Bool) throws -> URL {
        guard let u=URL(string:value.trimmingCharacters(in:.whitespacesAndNewlines)),let host=u.host,!host.isEmpty,u.user==nil,u.password==nil,u.fragment==nil else { throw LumaError.unsupported("服务地址无效") }
        let loopback=["localhost","127.0.0.1","::1"].contains(host.lowercased())
        let secure=webSocket ? "wss" : "https",plain=webSocket ? "ws" : "http"
        guard u.scheme==secure || (loopback && u.scheme==plain),webSocket || u.query==nil else { throw LumaError.unsupported("远程服务需使用加密连接；本机调试可使用 localhost") }
        return u
    }
}
/// Secrets are never Codable, logged, or written to project files.
public enum IntegrationCredentials {
    private static let service="studio.luma.integrations"
    public static func read(_ account: String) throws -> String? {
        let q: [String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess,let data=result as? Data else { throw LumaError.unsupported("无法读取系统钥匙串（\(status)）") }
        return String(data:data,encoding:.utf8)
    }
    public static func save(_ value: String,account: String) throws {
        guard !value.isEmpty,value.count<=8192,!value.contains("\n"),!value.contains("\r") else { throw LumaError.unsupported("密钥或连接地址格式无效") }
        let q: [String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let data=Data(value.utf8),status=SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status==errSecItemNotFound {
            var add=q;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { throw LumaError.unsupported("无法保存到系统钥匙串") }
        } else if status != errSecSuccess { throw LumaError.unsupported("无法更新系统钥匙串（\(status)）") }
    }
    public static func remove(_ account: String) throws {
        let q: [String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        let status=SecItemDelete(q as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else { throw LumaError.unsupported("无法移除保存的凭据") }
    }
}
