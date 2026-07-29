import SwiftUI

/// Sidebar uses List so macOS reserves space for traffic lights + toolbar.
/// Headphone search lives in the system sidebar search field (not under window chrome).
struct SidebarView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var headphoneQuery = ""

    var body: some View {
        List {
            Section {
                flatRow {
                    PresetPanelView(viewModel: viewModel)
                }
            } header: {
                OpenEQSectionTitle(title: "Presets")
            }

            Section {
                flatRow {
                    HeadphoneLibraryView(
                        viewModel: viewModel,
                        searchText: $headphoneQuery
                    )
                }
            } header: {
                OpenEQSectionTitle(title: "Headphones")
            }

            Section {
                flatRow {
                    DynamicsPanelView(viewModel: viewModel)
                }
            } header: {
                OpenEQSectionTitle(title: "Dynamics")
            }

            Section {
                flatRow {
                    AUv3PanelView(viewModel: viewModel)
                }
            } header: {
                OpenEQSectionTitle(title: "AUv3")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenEQ")
        .searchable(
            text: $headphoneQuery,
            placement: .sidebar,
            prompt: "Search headphones"
        )
    }

    /// Single flat section body — no nested card, clear list chrome.
    private func flatRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 10, trailing: 8))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
