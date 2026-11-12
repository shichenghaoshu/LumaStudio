import SwiftUI
import Speech
import AVFoundation
import PhotoCore

@MainActor final class SpeechInputController: ObservableObject {
    @Published var recording=false
    @Published var starting=false
    @Published var status=""
    private let engine=AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void,Never>?
    private var tapped=false
    private var generation=UUID()
    func start(allowOnline: Bool,onText: @escaping @MainActor (String)->Void) async {
        guard !recording,!starting else { return }
        starting=true;let token=UUID();generation=token
        defer { if token==generation { starting=false } }
        let authorization=await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization{continuation.resume(returning:$0)} }
        guard token==generation else { return }
        guard authorization == .authorized else { status="语音识别未获授权，可在系统设置中开启";return }
        let microphone=await AVCaptureDevice.requestAccess(for:.audio)
        guard token==generation else { return }
        guard microphone else { status="麦克风未获授权，可在系统设置中开启";return }
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"zh-CN")),recognizer.isAvailable else { status="系统中文听写暂不可用，可使用外部语音接口";return }
        guard allowOnline || recognizer.supportsOnDeviceRecognition else { status="当前系统没有可用的离线中文识别，可在接入设置允许系统在线听写";return }
        let request=SFSpeechAudioBufferRecognitionRequest();request.shouldReportPartialResults=true
        request.requiresOnDeviceRecognition = !allowOnline;request.taskHint = .dictation
        let input=engine.inputNode,format=input.outputFormat(forBus:0)
        guard format.sampleRate>0,format.channelCount>0 else { status="没有可用的麦克风输入";return }
        self.request=request
        input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,_ in request.append(buffer) };tapped=true
        do {
            engine.prepare();try engine.start();recording=true;status=allowOnline ? "正在系统听写…" : "正在本机听写…"
            task=recognizer.recognitionTask(with:request) { [weak self] result,error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { onText(String(result.bestTranscription.formattedString.prefix(1000)));if result.isFinal { self.stop() } }
                    if error != nil,self.recording { self.stop();self.status="听写已结束，可以继续编辑文字" }
                }
            }
            timeout=Task { [weak self] in do { try await Task.sleep(for:.seconds(45));self?.stop() } catch {} }
        } catch { stop();status="麦克风启动失败，请检查系统输入设备" }
    }
    func stop() {
        generation=UUID();starting=false
        timeout?.cancel();timeout=nil
        if tapped { engine.inputNode.removeTap(onBus:0);tapped=false }
        engine.stop();request?.endAudio();request=nil;task?.cancel();task=nil
        if recording { status="听写文字已保留" };recording=false
    }
}

struct MacVoiceInputButton: View {
    @ObservedObject var model: AppModel
    @StateObject private var speech=SpeechInputController()
    @State private var statusPresented=false
    var body: some View {
        Button {
            if speech.recording { speech.stop() }
            else { Task { await speech.start(allowOnline:model.allowAppleOnlineSpeech) { text in model.instruction=text };if !speech.recording { statusPresented=true } } }
        } label:{Label(speech.recording ? "结束听写" : "语音输入",systemImage:speech.recording ? "stop.circle.fill" : "mic")}
            .font(.system(size:11)).buttonStyle(.borderless).foregroundStyle(speech.recording ? studioAccent : .secondary)
            .disabled(model.agentBusy || speech.starting).accessibilityLabel(speech.recording ? "结束语音输入" : "开始语音输入")
            .popover(isPresented:$statusPresented) { Text(speech.status).font(.callout).padding(18).frame(width:300) }
            .onDisappear{speech.stop()}
    }
}
