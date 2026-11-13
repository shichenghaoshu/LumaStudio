import SwiftUI
struct PadEditView: View {
    @Bindable var model: AppModel
    var body: some View { EditWorkspace(model:model) }
}
