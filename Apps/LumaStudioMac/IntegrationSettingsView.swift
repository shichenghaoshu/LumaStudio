import SwiftUI
import PhotoCore

struct IntegrationSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var section=0
    @State private var apiKey=""
    @State private var xiaozhiEndpoint=""
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:5) { Text("模型与语音接入").font(.title2.weight(.semibold));Text("选择参数方案的来源，并连接语音入口。").font(.caption).foregroundStyle(.secondary) }
                Spacer();Button("完成"){dismiss()}
            }.padding(24)
            Picker("接入类型",selection:$section) { Text("在线模型").tag(0);Text("语音与小智").tag(1);Text("开源组件").tag(2) }.pickerStyle(.segmented).padding(.horizontal,24).padding(.bottom,18)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if section==0 { cloudSettings }
                    else if section==1 { voiceSettings }
                    else { openSource }
                }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(width:710,height:590).background(Color(white:0.095))
            .onAppear{model.refreshIntegrationCredentials()}
            .onChange(of:model.cloudSettings.provider) { _,provider in
                model.cloudSettings.baseURL=provider.baseURL;model.cloudSettings.model=provider.model
                model.cloudSettings.style=provider == .openAI ? .responses : .chatCompletions
                apiKey="";model.refreshIntegrationCredentials()
            }
    }
    private var cloudSettings: some View {
        VStack(alignment:.leading,spacing:16) {
            Picker("方案来源",selection:$model.cloudSettings.mode) { Text("本地模型 / 规则").tag(PlannerMode.local);Text("在线模型 API").tag(PlannerMode.online) }.pickerStyle(.segmented)
            Text("在线模式会向所选服务发送修图要求和图像分析指标；图像渲染、配方与原片继续留在本机。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Picker("服务商",selection:$model.cloudSettings.provider) { ForEach(CloudProvider.allCases,id:\.self) { Text($0.title).tag($0) } }
            TextField("API Base URL",text:$model.cloudSettings.baseURL).textFieldStyle(.roundedBorder).accessibilityLabel("在线模型服务地址")
            TextField("模型 ID，以服务商控制台为准",text:$model.cloudSettings.model).textFieldStyle(.roundedBorder).accessibilityLabel("在线模型 ID")
            Picker("API 格式",selection:$model.cloudSettings.style) { Text("Chat Completions 兼容接口").tag(CloudAPIStyle.chatCompletions);Text("OpenAI Responses").tag(CloudAPIStyle.responses) }
            HStack {
                SecureField(model.cloudKeySaved ? "输入新密钥以替换已保存密钥" : "API 密钥，仅保存在系统钥匙串",text:$apiKey).textFieldStyle(.roundedBorder).accessibilityLabel("在线模型 API 密钥")
                Button("保存密钥") { model.saveCloudKey(apiKey);apiKey="" }.disabled(apiKey.isEmpty)
            }
            HStack {
                Label(model.cloudSessionKeyAvailable ? "本次会话密钥可用" : (model.cloudKeySaved ? "钥匙串密钥可用" : "未读取到可用密钥"),systemImage:model.cloudKeySaved || model.cloudSessionKeyAvailable ? "key.fill" : "key").font(.caption).foregroundStyle(.secondary)
                Button("本次会话使用") {model.useCloudKeyForSession(apiKey);apiKey=""}.disabled(apiKey.isEmpty).font(.caption)
                Spacer();if model.cloudKeySaved { Button("移除密钥",role:.destructive){model.removeCloudKey()}.font(.caption) }
            }
            Toggle("附带不超过 512 像素的照片预览",isOn:$model.cloudSettings.attachPreview).font(.callout)
            if model.cloudSettings.attachPreview { Text("开始在线处理时，这张小预览会上传到你填写的服务商；请使用支持图片输入的模型。预览不含原片 EXIF 信息。").font(.caption).foregroundStyle(studioAccent).fixedSize(horizontal:false,vertical:true) }
            Toggle("在线请求失败时，使用本地模型继续",isOn:$model.cloudSettings.fallbackToLocal).font(.callout)
            HStack { Button("测试在线连接"){model.testCloudConnection()}.disabled(model.cloudTesting || (!model.cloudKeySaved && !model.cloudSessionKeyAvailable));if model.cloudTesting { ProgressView().controlSize(.small) };Text(model.cloudConnectionStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
            Text("连接测试只发送一条简短测试文字。正式处理时，所有返回方案仍经过参数范围、工具与指令约束检查。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.disabled(model.agentBusy)
    }
    private var voiceSettings: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Mac 语音输入").font(.headline)
            Text("助手和处理过程页的麦克风按钮可把中文听写到修图要求中。点击后才请求麦克风和系统语音识别权限；默认使用离线识别。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Toggle("允许 Apple 系统在线听写",isOn:$model.allowAppleOnlineSpeech).font(.callout)
            Divider()
            Text("小智 MCP").font(.headline)
            Text("把小智控制台的 MCP 接入点保存在这里，小智即可提交修图要求和查询当前任务。该地址可能包含令牌，将保存在系统钥匙串。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack { SecureField("wss://… 小智 MCP 接入点",text:$xiaozhiEndpoint).textFieldStyle(.roundedBorder).accessibilityLabel("小智 MCP 接入点");Button("保存接入点"){model.saveXiaozhiEndpoint(xiaozhiEndpoint);xiaozhiEndpoint=""}.disabled(xiaozhiEndpoint.isEmpty) }
            HStack {
                Text(connectionStatus).font(.caption).foregroundStyle(.secondary);Spacer()
                if model.xiaozhiState == .connected || model.xiaozhiState == .connecting { Button("断开小智"){model.disconnectXiaozhi()} }
                else { Button("连接小智"){model.connectXiaozhi()}.disabled(!model.xiaozhiEndpointSaved) }
                if model.xiaozhiEndpointSaved,model.xiaozhiState != .connected,model.xiaozhiState != .connecting { Button("移除接入点",role:.destructive){model.removeXiaozhiEndpoint()} }
            }
            Toggle("收到最终语音要求后，自动处理当前照片",isOn:$model.automaticVoiceExecution).font(.callout)
            Text("关闭时，外部要求进入下方待处理列表。连接后可向对端返回当前照片名称和任务状态，照片内容不会经语音接口上传。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            Text("其他语音 AI / 本机 HTTP 接口").font(.headline)
            Text(model.localVoiceStatus).font(.caption).foregroundStyle(.secondary)
            HStack {
                if let port=model.localVoicePort {
                    Text("127.0.0.1:"+String(port)).font(.system(.caption,design:.monospaced));Button("复制接入配置"){model.copyVoiceBridgeConfiguration()};Spacer();Button("停止本机接口"){model.stopLocalVoiceBridge()}
                } else { Button(model.localVoiceStarting ? "正在启动…" : "启动本机接口"){model.startLocalVoiceBridge()}.disabled(model.localVoiceStarting) }
            }
            Text("接口只监听本机，必须使用本次启动生成的 Bearer 令牌。通过 POST /v1/voice/commands 提交最终文字；可配合仓库中的 MCP stdio 转接器。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if !model.voiceInbox.isEmpty {
                Divider();Text("语音待处理 · \(model.voiceInbox.count)").font(.headline)
                ForEach(model.voiceInbox) { command in
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:5) { Text(command.text).font(.callout);Text(command.source).font(.caption2).foregroundStyle(.secondary) }
                        Spacer();Button("填入要求"){model.useVoiceCommand(command,run:false)};Button("开始处理"){model.useVoiceCommand(command,run:true)}
                    }.disabled(model.agentBusy)
                }
            }
        }
    }
    private var connectionStatus: String {
        switch model.xiaozhiState {case .disconnected:return model.xiaozhiEndpointSaved ? "接入点已保存，尚未连接" : "未配置小智接入点";case .connecting:return "正在建立小智连接…";case .connected:return "小智 MCP WebSocket 已连接";case .failed:return "连接未完成，请检查接入点、令牌与网络"}
    }
    private var openSource: some View {
        VStack(alignment:.leading,spacing:18) {
            component("MetalPetal 1.25.2","MIT","已接入高通皮肤平滑，使用 Metal GPU 渲染；结合本平台皮肤蒙版、纹理与五官保护。",url:"https://github.com/MetalPetal/MetalPetal")
            Divider()
            component("swift-collections 1.1.4","Apache-2.0 + Runtime Library Exception","Deque 用于语音请求的有界记录和重试去重。",url:"https://github.com/apple/swift-collections")
            Divider()
            component("LibRaw 0.22.3","CDDL-1.0","系统无法显影的 RAW 可使用备用 16 位解码。原片不变；此路径保留相机白平衡并开放 RAW 曝光，其余调整使用基础影调。完整原始源码、许可与重建说明随交付提供。",url:"https://www.libraw.org/")
            Divider()
            component("llama.cpp b12110","MIT","已有本地 Qwen 推理继续可用；在线服务为可选方案来源。",url:"https://github.com/ggml-org/llama.cpp")
            Divider()
            Text("小智使用其公开 MCP 协议接入；语音硬件的 ASR、LLM 与播报仍由小智系统负责。当前美颜是实际图像算法，不代表已训练商业精修网络。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func component(_ title: String,_ license: String,_ description: String,url: String)->some View {
        VStack(alignment:.leading,spacing:7) { HStack { Text(title).font(.headline);Spacer();Text(license).font(.caption).foregroundStyle(.secondary) };Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Link("查看项目",destination:URL(string:url)!).font(.caption) }
    }
}
