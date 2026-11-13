import SwiftUI
struct MainView: View {
    @State private var model=AppModel()
    var body: some View {StudioRoot(model:model).onOpenURL{url in if url.scheme=="lumastudio" {model.pairingInput=url.absoluteString;model.sync.discover();model.syncPresented=true}}}
}
