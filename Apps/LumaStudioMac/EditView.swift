import SwiftUI
struct MacEditView: View {
    @Bindable var model: AppModel
    var body: some View {
        if model.agentProcessPresented { AgentProcessWorkspace(model:model) }
        else { MacEditWorkspace(model:model) }
    }
}
