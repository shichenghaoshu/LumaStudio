import SwiftUI
struct PadBatchView: View {
    @ObservedObject var model: AppModel
    var body: some View { BatchWorkspace(model:model) }
}
