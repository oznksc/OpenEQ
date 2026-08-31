import SwiftUI

struct GraphWorkspaceView: View {
    @Bindable var viewModel: OpenEQViewModel
    @Bindable var store: GraphStore

    var body: some View {
        GraphCanvasView(
            store: store,
            viewModel: viewModel,
            runningNodeIDs: viewModel.runningGraphNodeIDs
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
