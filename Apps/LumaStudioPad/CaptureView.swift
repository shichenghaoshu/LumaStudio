import SwiftUI
struct PadCaptureView: View {
    @Bindable var model: AppModel
    var body: some View { CaptureWorkspace(model:model) }
}
