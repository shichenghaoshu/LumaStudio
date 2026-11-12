import SwiftUI
struct MacBatchView: View {
    @ObservedObject var model: AppModel
    var body: some View { BatchWorkspace(model:model) }
}
