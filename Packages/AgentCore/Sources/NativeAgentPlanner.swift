import Foundation
import PhotoDomain
import ToolRegistry
import ModelManager
#if canImport(llama) && os(macOS)
import llama
#endif

/// Native, in-process inference. The optional model is a base model unless its manifest proves otherwise.
public actor NativeAgentPlanner: AgentPlanner {
    private let model: InstalledModel?
    private let initialFallbackReason: String?
    public init(model: InstalledModel?,fallbackReason: String?=nil) { self.model=model;initialFallbackReason=fallbackReason }
    public func plan(_ context: PlanningContext) async throws -> AgentPlan {
        let start=Date()
        var failure=initialFallbackReason
        if let model {
            #if canImport(llama) && os(macOS)
            let signal=InferenceSignal(timeout:45)
            do {
                let raw=try await withTaskCancellationHandler(operation:{
                    let engine=try NativeLlama(url:model.url)
                    return try engine.generate(prompt:Self.prompt(context),grammar:EditRecipeGrammar.make(),signal:signal)
                },onCancel:{signal.cancel()})
                try Task.checkCancellation()
                let decoded=try ToolRegistry().proposal(Data(raw.utf8),preserving:context.currentRecipe)
                var recipe=try IntentSafetyGate.enforce(decoded,context:context)
                let intent=InstructionParser.parse(context.instruction)
                if let region=intent.requestedLocalRegion,!recipe.masks.contains(where:{$0.kind==region}) { throw LumaError.corruptData("模型没有保留指令要求的局部区域") }
                if intent.beautyForbidden || context.analysis.faceCount==0 { recipe.beauty.enabled=false }
                recipe.beauty.texturePreservation=max(0.9,recipe.beauty.texturePreservation)
                if recipe.color.referenceProfileID != context.referenceProfileID { recipe.color.referenceProfileID=nil }
                recipe.operations=[];try ToolRegistry().validate(recipe)
                return AgentPlan(recipe:recipe,source:model.manifest.displayName+" + 约束检查",fallbackReason:nil,planningMilliseconds:Date().timeIntervalSince(start)*1000)
            } catch is CancellationError { throw CancellationError() }
            catch { failure="本地模型本次未生成可执行方案，已使用规则："+error.localizedDescription }
            #else
            failure="此构建未包含原生语言模型运行器，已使用本地规则"
            #endif
        }
        try Task.checkCancellation()
        let recipe=try LocalRulePlanner().plan(context)
        return AgentPlan(recipe:recipe,source:"本地规则 + Vision",fallbackReason:failure,planningMilliseconds:Date().timeIntervalSince(start)*1000)
    }
    public static func prompt(_ c: PlanningContext)->String {
        let current=c.currentRecipe.map{compactPromptRecipe($0)} ?? "null"
        let draft=(try? LocalRulePlanner().plan(c)).map{compactPromptRecipe($0)} ?? "null"
        let m=c.analysis.metrics
        let profile=c.referenceProfileID.map{"\"\($0)\""} ?? "null"
        let system="""
        You are LumaStudio's local photo parameter planner. Translate the user's Chinese or English request into ONE EditRecipe JSON object. Do not write explanations or code. Use only supported tools and fields. Make meaningful parameter changes that satisfy the instruction. Keep unrelated controls neutral. A scene analysis is supplied; you cannot see the image. For continuation requests modify current_recipe. Do not beautify unless asked. Preserve texture. 提亮 means exposure +0.35. 压暗 means exposure -0.35. 暖一点 means temperature 7200. 冷一点 means temperature 5800. 降低饱和度 means saturation 0.85. 美颜 means beauty enabled true strength 0.35. 不要美颜 means beauty enabled false.
        REQUIRED keys, in this order: version,global,color,beauty,masks,operations,evaluation.
        version:1.
        global: object with optional numeric fields exposure[-3,3] EV default0,contrast[0.5,1.5] default1,highlights/shadows/whites/blacks/vibrance[-1,1] default0,temperature[2500,10000] default6500 (higher=warmer),tint[-100,100] default0,saturation[0,2] default1.
        color: {"lut":null or "natural"/"portrait"/"film"/"warm"/"cool"/"clean","intensity":0..1,"referenceProfileID":null or supplied reference id}. This base-model planner uses these three color keys only.
        beauty: {"enabled":boolean,"strength":0..1,"skinTone":0..1,"blemishRemoval":0..1,"texturePreservation":0.9..1}. Default disabled,strength0.35,texturePreservation0.94. Never enable when face_count=0 or user forbids it.
        masks: [] or [{"id":"local_1","kind":"face"/"skin"/"subject"/"background","amount":1,"adjustments":{same numeric fields as global}}]. If user says only background/face/person, put adjustments in that mask and leave global neutral. Hair and sky are unavailable.
        operations:[] (the registry compiles safe ordered tool calls).
        evaluation:{"automaticCorrection":true,"maxCorrections":2,"preserveSkin":true}.
        Example: {"version":1,"global":{"exposure":0.3,"temperature":7000},"color":{"lut":null,"intensity":0.5},"beauty":{"enabled":false},"masks":[],"operations":[],"evaluation":{"maxCorrections":2}}
        """
        let user="""
        scene:\(c.analysis.scene),face_count:\(c.analysis.faceCount),mean_luminance:\(String(format:"%.3f",m.meanLuminance)),clipped_highlights:\(String(format:"%.3f",m.clippedHighlights)),crushed_shadows:\(String(format:"%.3f",m.crushedShadows)).
        reference_id:\(profile)
        confirmed_preferences: beauty_strength=\(c.preferences.beautyStrength),temperature=\(c.preferences.temperature),saturation=\(c.preferences.saturation); count=\(c.preferences.confirmationCount). Use only for unspecified style.
        current_recipe:\(current)
        draft_recipe_from_rule_preflight:\(draft)
        Refine or keep the draft to satisfy user_instruction. Preserve useful non-neutral values in the draft. Do not reset an explicit brightness/warmth/local adjustment to neutral.
        previous_instructions:\(c.previousInstructions.joined(separator:"; ").prefix(300))
        user_instruction:\(c.instruction)
        """
        return "<|im_start|>system\n"+system+"<|im_end|>\n<|im_start|>user\n"+user+"<|im_end|>\n<|im_start|>assistant\n"
    }
    private static func compactPromptRecipe(_ recipe: EditRecipe)->String {
        // The installed 1.5B model keeps its bounded v1 grammar; merge its patch
        // back into v2 so advanced/manual controls and brush data remain untouched.
        guard let data=try? JSONEncoder().encode(recipe),var object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {return "null"}
        object=object.filter{["global","color","beauty","masks","operations","evaluation"].contains($0.key)};object["version"]=1
        if let g=object["global"] as? [String:Any] {object["global"]=g.filter{["exposure","contrast","highlights","shadows","whites","blacks","temperature","tint","saturation","vibrance"].contains($0.key)}}
        if let color=object["color"] as? [String:Any] {object["color"]=color.filter{["lut","intensity","referenceProfileID"].contains($0.key)}}
        if let beauty=object["beauty"] as? [String:Any] {object["beauty"]=beauty.filter{["enabled","strength","skinTone","blemishRemoval","texturePreservation"].contains($0.key)}}
        object["masks"]=[]
        guard let value=try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys) else {return "null"}
        return String(decoding:value,as:UTF8.self)
    }
    static let grammar = #"""
    root ::= "{" ws "\"version\"" ws ":" ws "1" ws "," ws "\"global\"" ws ":" ws object "," ws "\"color\"" ws ":" ws object "," ws "\"beauty\"" ws ":" ws object "," ws "\"masks\"" ws ":" ws array "," ws "\"operations\"" ws ":" ws "[]" ws "," ws "\"evaluation\"" ws ":" ws object "}" ws
    value ::= object | array | string | number | "true" ws | "false" ws | "null" ws
    object ::= "{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws
    array ::= "[" ws (value ("," ws value)*)? "]" ws
    string ::= "\"" ([a-zA-Z0-9_.-])* "\"" ws
    number ::= "-"? ([0-9] | [1-9] [0-9]{1,3}) ("." [0-9]{1,4})? ws
    ws ::= [ \t\n\r]{0,4}
    """#
}

#if canImport(llama) && os(macOS)
private final class InferenceSignal: @unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    let deadline: Date
    init(timeout: TimeInterval) { deadline=Date().addingTimeInterval(timeout) }
    func cancel() { lock.lock();cancelled=true;lock.unlock() }
    var shouldAbort: Bool { lock.lock();let v=cancelled;lock.unlock();return v || Date()>deadline }
    func check() throws {
        lock.lock();let v=cancelled;lock.unlock()
        if v { throw CancellationError() }
        if Date()>deadline { throw LumaError.unsupported("参数生成超时") }
    }
}
private final class NativeLlama {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    init(url: URL) throws {
        llama_log_set({_,_,_ in},nil)
        llama_backend_init()
        var p=llama_model_default_params();p.n_gpu_layers = -1
        guard let m=llama_model_load_from_file(url.path,p) else { throw LumaError.unsupported("无法加载 GGUF 模型") }
        model=m
        var architecture=[CChar](repeating:0,count:128)
        let length=llama_model_meta_val_str(m,"general.architecture",&architecture,architecture.count)
        guard length>0,String(cString:architecture)=="qwen2" else { llama_model_free(m);throw LumaError.unsupported("此模型的对话模板尚未适配；当前原生运行器支持 Qwen2.5 系列") }
        guard let v=llama_model_get_vocab(m) else { llama_model_free(m);throw LumaError.corruptData("模型词表") };vocab=v
        var cp=llama_context_default_params();cp.n_ctx=4096;cp.n_batch=512;cp.n_ubatch=256
        cp.n_threads=Int32(min(6,ProcessInfo.processInfo.activeProcessorCount));cp.n_threads_batch=cp.n_threads
        guard let c=llama_init_from_model(m,cp) else { llama_model_free(m);throw LumaError.unsupported("模型上下文内存分配失败") };context=c
    }
    deinit { llama_free(context);llama_model_free(model) }
    func generate(prompt: String,grammar: String,signal: InferenceSignal) throws -> String {
        try signal.check()
        let holder=Unmanaged.passUnretained(signal).toOpaque()
        llama_set_abort_callback(context,{p in guard let p else { return false };return Unmanaged<InferenceSignal>.fromOpaque(p).takeUnretainedValue().shouldAbort},holder)
        defer { llama_set_abort_callback(context,nil,nil) }
        let required = -llama_tokenize(vocab,prompt,Int32(prompt.utf8.count),nil,0,true,true)
        guard required>0,required<3000 else { throw LumaError.unsupported("指令与上下文超过本地模型长度限制") }
        var tokens=[llama_token](repeating:0,count:Int(required))
        guard llama_tokenize(vocab,prompt,Int32(prompt.utf8.count),&tokens,required,true,true)==required else { throw LumaError.corruptData("指令分词失败") }
        guard let batch=llama_batch_ext_init(context),let sampler=llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw LumaError.unsupported("推理资源分配失败") }
        defer { llama_batch_ext_free(batch);llama_sampler_free(sampler) }
        guard let grammarSampler=llama_sampler_init_grammar(vocab,grammar,"root") else { throw LumaError.corruptData("生成约束未能初始化") }
        llama_sampler_chain_add(sampler,grammarSampler);llama_sampler_chain_add(sampler,llama_sampler_init_greedy())
        func decode(_ input: ArraySlice<llama_token>,at position: Int32) throws {
            try signal.check();llama_batch_ext_clear(batch)
            for (i,token) in input.enumerated() {
                let index=llama_batch_ext_add_token(batch,0,token);var pos=position+Int32(i)
                guard index>=0,llama_batch_ext_set_pos(batch,index,&pos) else { throw LumaError.corruptData("推理批次位置") }
            }
            _=llama_batch_ext_set_output_logits(batch,Int32(input.count-1),true)
            guard llama_process(context,LLAMA_PROCESS_TYPE_DECODE,batch)==0 else { try signal.check();throw LumaError.unsupported("本地模型推理失败") }
        }
        var position=0
        while position<tokens.count { let end=min(tokens.count,position+512);try decode(tokens[position..<end],at:Int32(position));position=end }
        var output=[UInt8]();var ended=false
        for _ in 0..<900 {
            try signal.check();let token=llama_sampler_sample(sampler,context,-1)
            if llama_vocab_is_eog(vocab,token) { ended=true;break }
            var piece=[CChar](repeating:0,count:512)
            var count=llama_token_to_piece(vocab,token,&piece,Int32(piece.count),0,false)
            if count<0 { guard -count<16384 else { throw LumaError.corruptData("异常 token") };piece=[CChar](repeating:0,count:Int(-count));count=llama_token_to_piece(vocab,token,&piece,Int32(piece.count),0,false) }
            guard count>=0,output.count+Int(count)<=64*1024 else { throw LumaError.corruptData("模型响应过长") }
            output.append(contentsOf:piece.prefix(Int(count)).map{UInt8(bitPattern:$0)})
            let one=[token];try decode(one[...],at:Int32(position));position += 1
        }
        guard ended else { throw LumaError.unsupported("模型未在限定长度内完成计划") }
        return String(decoding:output,as:UTF8.self)
    }
}
#endif
