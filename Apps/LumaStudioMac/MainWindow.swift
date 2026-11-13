import SwiftUI
struct MainWindow: View {
    @State private var model=AppModel()
    var body: some View {StudioRoot(model:model).frame(minWidth:1040,minHeight:680).onAppear{MacLifecycleDelegate.model=model}.onOpenURL{url in if url.scheme=="lumastudio" {model.pairingInput=url.absoluteString;model.sync.discover();model.syncPresented=true}}}
}
