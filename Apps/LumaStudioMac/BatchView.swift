import SwiftUI
struct MacBatchView: View {
    @Bindable var model: AppModel
    var body: some View { BatchWorkspace(model:model) }
}
