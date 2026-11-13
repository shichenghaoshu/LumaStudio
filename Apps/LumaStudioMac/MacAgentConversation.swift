import SwiftUI
import PhotoCore

struct MacAgentConversation: View {
    @ObservedObject var model: AppModel
    @State private var history=[AgentRun]()
    private let steps: [(AgentStage,String)]=[(.analysis,"分析照片"),(.planning,"生成方案"),(.rendering,"执行修图"),(.evaluation,"检查效果"),(.saving,"保存记录")]
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack{Image(systemName:"sparkles").foregroundStyle(studioAccent);Text("Luma 助手").font(.system(size:13,weight:.semibold));Spacer();Button{model.agentProcessPresented=true}label:{Image(systemName:"list.bullet.rectangle")}.buttonStyle(.plain).accessibilityLabel("展开 Agent 处理过程")}.padding(17)
            Text(model.cloudSettings.mode == .online ? "\(model.cloudSettings.provider.title) · \(model.cloudSettings.model)" : "本地模型与照片分析").font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,17).padding(.bottom,14)
            Divider()
            ScrollViewReader{proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:20) {
                        if history.isEmpty && !model.agentBusy && model.agentRun==nil {
                            VStack(alignment:.leading,spacing:14){Text("说说你想怎么修").font(.system(size:20,weight:.light));Text("每张照片独立分析，结果可以继续手动调整。").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                prompt("自动校正曝光与白平衡","自动校正曝光和白平衡，适度恢复高光和阴影，不要美颜，保留其他参数。")
                                prompt("自然人像，保留皮肤纹理","自然人像美颜，保留皮肤纹理，不要过度磨皮，肤色自然。")
                                prompt("低饱和的电影色调","柔和低饱和电影风格，保护高光，不要美颜。")
                            }.padding(.top,20)
                        }
                        ForEach(history.filter{$0.id != model.agentRun?.id}){run in resultCard(run)}
                        if model.agentBusy || model.agentProcessState == .failed {
                            Text(model.agentInstruction).font(.system(size:12)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
                            taskCard
                        }
                        if let run=model.agentRun {resultCard(run)}
                        Color.clear.frame(height:1).id("conversationEnd")
                    }.padding(17)
                }.onChange(of:model.agentEvents.count){_,_ in proxy.scrollTo("conversationEnd",anchor:.bottom)}
                    .onChange(of:model.agentRun?.id){_,_ in proxy.scrollTo("conversationEnd",anchor:.bottom)}
            }
            Divider()
            composer
        }.background(Color(white:0.08))
            .task(id:model.selectedID){await reloadHistory()}
            .onChange(of:model.agentRun?.id){_,_ in Task{await reloadHistory()}}
    }
    private func prompt(_ title: String,_ text: String)->some View {
        Button{model.instruction=text}label:{HStack{Text(title);Spacer();Image(systemName:"arrow.up.left")}.font(.system(size:11)).foregroundStyle(.secondary).padding(.vertical,10).overlay(alignment:.bottom){Color.white.opacity(0.07).frame(height:1)}}.buttonStyle(.plain)
    }
    private var taskCard: some View {
        VStack(alignment:.leading,spacing:11) {
            Text(model.agentProcessState == .failed ? "任务未完成" : "正在处理当前照片").font(.system(size:12,weight:.medium))
            ForEach(steps,id:\.0){stage,title in
                let events=model.agentEvents.filter{$0.stage==stage},done=events.contains{$0.kind == .finished}
                HStack(spacing:9){Image(systemName:done ? "checkmark.circle.fill" : (events.isEmpty ? "circle" : "circle.dotted")).foregroundStyle(done ? studioAccent : .secondary);Text(title);Spacer()}.font(.system(size:11))
            }
            Text(model.agentFailure ?? model.agentStatus).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Button("查看完整过程"){model.agentProcessPresented=true}.font(.caption)
        }.padding(13).frame(maxWidth:.infinity,alignment:.leading).background(Color(white:0.12),in:RoundedRectangle(cornerRadius:8))
    }
    private func resultCard(_ run: AgentRun)->some View {
        VStack(alignment:.leading,spacing:12) {
            Text(run.instruction).font(.system(size:12)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
            Label(run.completed ? "修图方案已生成" : "处理记录",systemImage:run.completed ? "checkmark.circle" : "clock").font(.system(size:12,weight:.medium)).foregroundStyle(studioAccent)
            Text(run.source).font(.system(size:10)).foregroundStyle(.secondary)
            if let reason=run.fallbackReason {Text(reason).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            if run.rounds.indices.contains(run.selectedRound) {
                Text("\(run.analysis.faceCount) 张人脸 · \(run.rounds.count) 轮效果检查").font(.system(size:10)).foregroundStyle(.secondary)
                HStack{
                    Button("应用此结果"){model.editDocument{doc in doc=ParameterLockPolicy.applying(run.selectedRecipe,preserving:doc)}}.disabled(model.agentBusy)
                    Button("导出照片"){model.exportToLibrary()}.disabled(model.agentBusy || model.rendering)
                }.font(.system(size:10)).buttonStyle(.bordered).controlSize(.small)
            }
            Text(run.timestamp,style:.time).font(.system(size:9)).foregroundStyle(.tertiary)
        }
    }
    private var composer: some View {
        VStack(alignment:.leading,spacing:11) {
            TextField("描述你想完成的修图…",text:$model.instruction,axis:.vertical).lineLimit(3...6).textFieldStyle(.plain).font(.system(size:12)).accessibilityLabel("修图要求")
            HStack {
                Button{model.choose(.photos)}label:{Image(systemName:"plus")}.help("导入照片").accessibilityLabel("助手导入照片")
                MacVoiceInputButton(model:model)
                Spacer()
                if model.agentBusy {Button("停止"){model.cancelAgent()}.font(.caption)}
                else {Button{model.runAgent()}label:{Image(systemName:"arrow.up").font(.system(size:13,weight:.semibold)).foregroundStyle(.black).frame(width:29,height:29).background(studioAccent,in:Circle())}.buttonStyle(.plain).accessibilityLabel("发送修图要求").disabled(model.selected==nil || model.instruction.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Toggle("自动检查并修正",isOn:$model.automaticCorrection).font(.system(size:10)).toggleStyle(.checkbox).disabled(model.agentBusy)
            Text("AI 已锁定 \(model.recipe.document.lockedParameters.count) 项 · 原片保留").font(.system(size:9)).foregroundStyle(.tertiary)
        }.padding(14).background(Color(white:0.12),in:RoundedRectangle(cornerRadius:10)).padding(12)
    }
    private func reloadHistory() async {
        guard let assetID=model.selectedID else{history=[];return}
        let directory=model.root.appendingPathComponent("AgentHistory/"+assetID.uuidString)
        let runs=await Task.detached(priority:.utility){()->[AgentRun] in
            let folders=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
            let recent=folders.sorted{((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)>((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}.prefix(20)
            let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
            return recent.compactMap{folder in
                let url=folder.appendingPathComponent("run.json")
                guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<8*1024*1024,let data=try? Data(contentsOf:url),let run=try? decoder.decode(AgentRun.self,from:data),run.assetID==assetID,run.rounds.indices.contains(run.selectedRound),(try? run.selectedRecipe.validateParameters()) != nil else{return nil};return run
            }.sorted{$0.timestamp<$1.timestamp}
        }.value
        guard model.selectedID==assetID,!Task.isCancelled else{return};history=runs
    }
}
