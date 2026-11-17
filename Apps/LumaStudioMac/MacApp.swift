import SwiftUI
import PhotoCore
import AppKit
@main struct LumaStudioMacApp: App {
    @NSApplicationDelegateAdaptor(MacLifecycleDelegate.self) private var lifecycle
    var body: some Scene {
        WindowGroup("拾光") { MainWindow().preferredColorScheme(.dark) }
            .defaultSize(width: 1320, height: 860)
            .commands {
                CommandMenu("工作区") {
                    Button("精修工作区") {MacLifecycleDelegate.model?.page = .edit;MacLifecycleDelegate.model?.editorAssistantOpen=false}.keyboardShortcut("1",modifiers:.command)
                    Button("AI 助手工作区") {MacLifecycleDelegate.model?.page = .edit;MacLifecycleDelegate.model?.editorAssistantOpen=true}.keyboardShortcut("2",modifiers:.command)
                    Button("批量工作区") {MacLifecycleDelegate.model?.page = .batch}.keyboardShortcut("3",modifiers:.command)
                    Divider()
                    Button("紧凑布局") { NSApp.keyWindow?.setContentSize(NSSize(width:1040,height:680)) }
                    Button("标准布局") { NSApp.keyWindow?.setContentSize(NSSize(width:1320,height:860)) }
                }
            }
        Settings {StudioAppearanceSettings()}
    }
}

@MainActor final class MacLifecycleDelegate: NSObject,NSApplicationDelegate {
    static weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication)->NSApplication.TerminateReply {
        guard let model=Self.model else {return .terminateNow}
        Task {let saved=await model.flushRecipeBeforeQuit();sender.reply(toApplicationShouldTerminate:saved)}
        return .terminateLater
    }
}
