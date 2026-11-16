import Foundation
import PhotoDomain

public struct InstalledPlugin: Codable, Identifiable, Sendable {
    public var id: String {manifest.id}
    public let manifest: PluginManifest
    public let sha256: String
    public let installedAt: Date
}
/// Immutable per-version packages and an atomic active-version index.
public actor PluginStore {
    public static var defaultRoot: URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/Plugins")}
    private let root: URL
    private var index: [String:InstalledPlugin]
    public init(root: URL=PluginStore.defaultRoot) throws {
        self.root=root;try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("installed.json")
        if FileManager.default.fileExists(atPath:url.path) {index=try JSONDecoder().decode([String:InstalledPlugin].self,from:Data(contentsOf:url))} else {index=[:]}
        for (id,item) in index {try validatePath(id,item.manifest.version)}
    }
    public func all() -> [InstalledPlugin] {index.values.sorted{$0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending}}
    @discardableResult public func install(_ data: Data, commercialAuthorized: Bool=false) throws -> InstalledPlugin {
        let package=try PluginPackage.decode(data),m=package.manifest
        guard m.license.type != "commercial" || commercialAuthorized else {throw LumaError.unsupported("商业插件需要作者或有效授权；当前服务尚未接入购买")}
        let folder=root.appendingPathComponent(m.id),url=folder.appendingPathComponent(m.version+".lumaplugin")
        let hash=PluginPackage.digest(data)
        if FileManager.default.fileExists(atPath:url.path) {
            guard PluginPackage.digest(try Data(contentsOf:url))==hash else {throw LumaError.corruptData("相同版本的内容发生变化，请作者发布新版本")}
        } else {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try data.write(to:url,options:.atomic)}
        let item=InstalledPlugin(manifest:m,sha256:hash,installedAt:Date())
        var updated=index;updated[m.id]=item;try persist(updated);index=updated;return item
    }
    public func package(id: String) throws -> PluginPackage {
        guard let item=index[id] else {throw LumaError.unsupported("插件尚未安装")}
        try validatePath(id,item.manifest.version)
        let data=try Data(contentsOf:root.appendingPathComponent(id).appendingPathComponent(item.manifest.version+".lumaplugin"))
        guard PluginPackage.digest(data)==item.sha256 else {throw LumaError.corruptData("已安装插件校验失败")}
        let package=try PluginPackage.decode(data)
        guard package.manifest==item.manifest else {throw LumaError.corruptData("插件清单与安装记录不一致")};return package
    }
    public func activate(id: String,version: String) throws {
        try validatePath(id,version)
        let bytes=try Data(contentsOf:root.appendingPathComponent(id).appendingPathComponent(version+".lumaplugin"))
        let p=try PluginPackage.decode(bytes)
        guard p.manifest.id==id,p.manifest.version==version else {throw LumaError.corruptData("插件版本不匹配")}
        // Version activation is restricted to previously installed packages on disk.
        _=try install(bytes,commercialAuthorized:true)
    }
    public func uninstall(id: String) throws {
        guard let item=index[id] else {return};try validatePath(id,item.manifest.version)
        var updated=index;updated.removeValue(forKey:id);try persist(updated);index=updated
        // Keep immutable versions for rollback/reinstall; deleting here could break a queued job.
    }
    private func persist(_ value: [String:InstalledPlugin]) throws {try JSONEncoder().encode(value).write(to:root.appendingPathComponent("installed.json"),options:.atomic)}
}
private func validatePath(_ id: String,_ version: String) throws {
    guard id.range(of:"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+){1,7}$",options:.regularExpression) != nil,id.count<=100,
          version.range(of:"^(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})$",options:.regularExpression) != nil else {throw LumaError.corruptData("插件路径标识无效")}
}
