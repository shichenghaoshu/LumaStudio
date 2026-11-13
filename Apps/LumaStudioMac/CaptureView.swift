import SwiftUI
struct MacCaptureView: View {
    @Bindable var model: AppModel
    var body: some View { CaptureWorkspace(model:model) }
}
