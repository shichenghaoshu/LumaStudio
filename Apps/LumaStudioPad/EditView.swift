import SwiftUI
struct PadEditView: View {
    @ObservedObject var model: AppModel
    var body: some View { EditWorkspace(model:model) }
}
