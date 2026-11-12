import SwiftUI
import PhotoCore
import AppKit
@main struct LumaStudioMacApp: App {
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
