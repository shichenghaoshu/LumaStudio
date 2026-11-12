import SwiftUI
struct MacCaptureView: View {
    @ObservedObject var model: AppModel
    var body: some View { CaptureWorkspace(model:model) }
}
