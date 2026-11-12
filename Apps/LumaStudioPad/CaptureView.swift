import SwiftUI
struct PadCaptureView: View {
    @ObservedObject var model: AppModel
    var body: some View { CaptureWorkspace(model:model) }
}
