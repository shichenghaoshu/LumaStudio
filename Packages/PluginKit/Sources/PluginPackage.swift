import Foundation
import CryptoKit
import PhotoDomain
import ToolRegistry
import ColorEngine

public enum PluginKind: String, Codable, CaseIterable, Sendable { case lut, recipe, localAdjustment, aiTool }
public enum PluginContext: String, Codable, CaseIterable, Sendable { case editor, batch, agent }
public enum PluginCapability: String, Codable, Sendable { case recipe = "edit.recipe", localMask = "edit.localMask", planner = "agent.plan", lut = "asset.lut" }
public struct PluginAuthor: Codable, Equatable, Sendable {
    public var id: String, name: String, roles: [String]
    public init(id: String, name: String, roles: [String]) { self.id=id;self.name=name;self.roles=roles }
}
public struct PluginLicense: Codable, Equatable, Sendable {
    public var type: String, terms: String
    public var spdx: String?, sourceURL: String?
    public var priceCents: Int?, currency: String?
    public init(type: String, terms: String, spdx: String?=nil, sourceURL: String?=nil, priceCents: Int?=nil, currency: String?=nil) {
        self.type=type;self.terms=terms;self.spdx=spdx;self.sourceURL=sourceURL;self.priceCents=priceCents;self.currency=currency
    }
}
public struct PluginManifest: Codable, Equatable, Sendable {
    public var id: String, version: String, name: String, summary: String
    public var author: PluginAuthor, kind: PluginKind, license: PluginLicense
    public var tags: [String], capabilities: [PluginCapability], supports: [PluginContext]
    public init(id: String, version: String, name: String, summary: String, author: PluginAuthor, kind: PluginKind, license: PluginLicense, tags: [String], capabilities: [PluginCapability], supports: [PluginContext] = PluginContext.allCases) {
        self.id=id;self.version=version;self.name=name;self.summary=summary;self.author=author;self.kind=kind;self.license=license;self.tags=tags;self.capabilities=capabilities;self.supports=supports
    }
}
public struct PluginPayload: Codable, Equatable, Sendable {
    public var groups: [RecipeSyncGroup]?, recipe: EditRecipe?, mask: LocalMask?, instruction: String?, lutAsset: String?, intensity: Float?
    public init(groups: [RecipeSyncGroup]?=nil, recipe: EditRecipe?=nil, mask: LocalMask?=nil, instruction: String?=nil, lutAsset: String?=nil, intensity: Float?=nil) {
        self.groups=groups;self.recipe=recipe;self.mask=mask;self.instruction=instruction;self.lutAsset=lutAsset;self.intensity=intensity
    }
}
public struct PluginAsset: Codable, Equatable, Sendable {
    public var path: String, sha256: String, data: String
    public init(path: String, bytes: Data) { self.path=path;sha256=PluginPackage.digest(bytes);data=bytes.base64EncodedString() }
}
/// Portable data only. Native code, shell commands and arbitrary network tools are not executable payloads.
public struct PluginPackage: Codable, Equatable, Sendable {
    public var schemaVersion=1
    public var manifest: PluginManifest, payload: PluginPayload
    public var assets: [PluginAsset]
    public init(manifest: PluginManifest, payload: PluginPayload, assets: [PluginAsset]=[]) { self.manifest=manifest;self.payload=payload;self.assets=assets }
    public static let maxBytes=12*1024*1024
    public static let allowedGroups: Set<RecipeSyncGroup> = [.tone,.whiteBalance,.color,.curves,.grading,.style,.beauty,.detail,.effects]
    public static func digest(_ data: Data) -> String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count<=maxBytes else { throw LumaError.corruptData("插件包超过 12 MB") }
        guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw LumaError.corruptData("插件包需为 JSON 对象")}
        try keys(root,["schemaVersion","manifest","payload","assets"])
        guard let m=root["manifest"] as? [String:Any],let p=root["payload"] as? [String:Any] else {throw LumaError.corruptData("缺少插件声明或内容")}
        try keys(m,["id","version","name","summary","author","kind","license","tags","capabilities","supports"])
        guard let a=m["author"] as? [String:Any],let l=m["license"] as? [String:Any] else {throw LumaError.corruptData("缺少作者或许可")}
        try keys(a,["id","name","roles"]);try keys(l,["type","terms","spdx","sourceURL","priceCents","currency"])
        try keys(p,["groups","recipe","mask","instruction","lutAsset","intensity"])
        if let r=p["recipe"] {try RecipeSchema.validate(JSONSerialization.data(withJSONObject:r))}
        if let mask=p["mask"] as? [String:Any] {
            try keys(mask,["id","kind","amount","adjustments","detail","inverted","feather","brushSize","flow","strokes"])
            try RecipeSchema.validate(JSONSerialization.data(withJSONObject:["version":2,"masks":[mask]]))
        }
        for asset in root["assets"] as? [[String:Any]] ?? [] {try keys(asset,["path","sha256","data"])}
        let value=try JSONDecoder().decode(Self.self,from:data);try value.validate();return value
    }
    public func encoded() throws -> Data {try validate();let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys];return try e.encode(self)}
    public func validate() throws {
        func require(_ ok: Bool,_ message: String) throws {if !ok {throw LumaError.corruptData(message)}}
        func match(_ s: String,_ p: String)->Bool {s.range(of:p,options:.regularExpression) != nil}
        func text(_ s: String,_ limit: Int)->Bool {!s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && s.count<=limit && !s.unicodeScalars.contains{$0.value<32 && $0.value != 10}}
        let m=manifest,p=payload,l=m.license
        try require(schemaVersion==1,"插件协议版本不支持")
        try require(match(m.id,"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+){1,7}$") && m.id.count<=100,"插件 ID 格式错误")
        try require(match(m.version,"^(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})\\.(0|[1-9][0-9]{0,3})$"),"版本需为 major.minor.patch")
        try require(text(m.name,80) && text(m.summary,600) && text(m.author.name,80),"插件名称、简介或作者无效")
        try require(match(m.author.id,"^[a-z][a-z0-9_-]{2,39}$"),"作者 ID 无效")
        try require(!m.author.roles.isEmpty && m.author.roles.count<=3 && Set(m.author.roles).isSubset(of:["photographer","colorist","developer"]),"作者角色无效")
        try require(m.tags.count<=8 && m.tags.allSatisfy{text($0,24)},"标签过多或过长")
        try require(!m.supports.isEmpty && Set(m.supports).count==m.supports.count && Set(m.capabilities).count==m.capabilities.count,"调用场景或能力声明无效")
        try require(["openSource","free","commercial"].contains(l.type) && text(l.terms,4000),"请提供许可类型和使用条款")
        if l.type=="openSource" {try require(["MIT","Apache-2.0","BSD-3-Clause","CC0-1.0","CC-BY-4.0"].contains(l.spdx ?? "") && l.sourceURL?.hasPrefix("https://")==true,"开源插件需声明支持的许可及 HTTPS 源码地址")}
        if l.type=="commercial" {try require((1...100_000_000).contains(l.priceCents ?? 0) && ["CNY","USD"].contains(l.currency ?? ""),"商业插件需提供有效价格与币种")}
        else {try require(l.priceCents==nil || l.priceCents==0,"免费插件不能包含收费价格")}
        try require(assets.count<=1 && Set(assets.map(\.path)).count==assets.count,"首版每包仅支持一个 LUT 资源")
        for a in assets {
            try require(match(a.path,"^[A-Za-z0-9_-]{1,64}\\.cube$"),"资源名称不能包含目录或路径")
            guard let bytes=Data(base64Encoded:a.data),bytes.count<=8*1024*1024 else {throw LumaError.corruptData("LUT 资源编码或大小无效")}
            try require(Self.digest(bytes)==a.sha256,"LUT 资源校验失败")
            _=try LUT3D(cube:String(decoding:bytes,as:UTF8.self))
        }
        let expected: Set<PluginCapability>
        switch m.kind {
        case .lut:
            expected=[.lut,.recipe]
            try require(assets.count==1 && p.lutAsset==assets.first?.path && p.intensity?.isFinite==true && (0...1).contains(p.intensity ?? -1),"LUT 插件需声明资源和 0–1 强度")
            try require(p.recipe==nil && p.mask==nil && p.instruction==nil && p.groups==nil,"LUT 插件含有其他执行内容")
        case .recipe:
            expected=[.recipe]
            guard let r=p.recipe,let groups=p.groups else {throw LumaError.corruptData("缺少配方或参数分组")}
            try ToolRegistry().validate(r)
            try require(!groups.isEmpty && Set(groups).isSubset(of:Self.allowedGroups) && Set(groups).count==groups.count,"配方只支持已声明的颜色、美颜、细节分组")
            try require(r.color.referenceProfileID==nil && (r.color.lut==nil || FilterIdentifiers.builtIn.contains(r.color.lut!)),"配方不能引用作者机器上的档案或 LUT；请单独发布 LUT 插件")
            try require(p.mask==nil && p.instruction==nil && p.lutAsset==nil && p.intensity==nil && assets.isEmpty,"配方插件含有其他执行内容")
        case .localAdjustment:
            expected=[.localMask]
            guard let mask=p.mask else {throw LumaError.corruptData("缺少局部处理声明")}
            var r=EditRecipe();r.masks=[mask];try ToolRegistry().validate(r)
            try require(p.recipe==nil && p.instruction==nil && p.lutAsset==nil && p.groups==nil && p.intensity==nil && assets.isEmpty,"局部插件含有其他执行内容")
        case .aiTool:
            expected=[.planner,.recipe]
            try require(text(p.instruction ?? "",2000),"AI 工具需要 1–2000 字的修图指令")
            try require(p.recipe==nil && p.mask==nil && p.lutAsset==nil && p.groups==nil && p.intensity==nil && assets.isEmpty,"AI 工具含有其他执行内容")
        }
        try require(Set(m.capabilities)==expected,"插件能力与执行内容不一致")
    }
    private static func keys(_ object: [String:Any],_ allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of:allowed) else {throw LumaError.corruptData("插件含有未知字段：\(Set(object.keys).subtracting(allowed).sorted().joined(separator:", "))")}
    }
}
