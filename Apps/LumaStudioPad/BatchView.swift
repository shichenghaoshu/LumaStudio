import SwiftUI
struct PadBatchView: View {
    @Bindable var model: AppModel
    var body: some View { BatchWorkspace(model:model) }
}
