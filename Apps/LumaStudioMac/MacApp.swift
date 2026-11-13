import SwiftUI
import PhotoCore
import AppKit
@main struct LumaStudioMacApp: App {
    @NSApplicationDelegateAdaptor(MacLifecycleDelegate.self) private var lifecycle
    var body: some Scene {
        WindowGroup("LumaStudio") { MainWindow().preferredColorScheme(.dark) }
            .defaultSize(width: 1320, height: 860)
            .commands {
                CommandMenu("工作区") {
                    Button("紧凑布局") { NSApp.keyWindow?.setContentSize(NSSize(width:1040,height:680)) }
                    Button("标准布局") { NSApp.keyWindow?.setContentSize(NSSize(width:1320,height:860)) }
                }
            }
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
