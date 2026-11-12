import SwiftUI
struct MainWindow: View {
    @StateObject private var model=AppModel()
    var body: some View {StudioRoot(model:model).frame(minWidth:1040,minHeight:680).onOpenURL{url in if url.scheme=="lumastudio" {model.pairingInput=url.absoluteString;model.sync.discover();model.syncPresented=true}}}
}
