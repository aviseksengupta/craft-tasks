import SwiftUI

/// Full-screen menu — the iPhone stand-in for the Mac/PWA sidebar, opened
/// from the bottom bar's "Menu" tab. Same nav rows, pinned items, search
/// box and settings entry point as web/src/Sidebar.tsx.
struct MenuView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var section: AppSection
    @State private var showSettings = false
    @State private var showLog = false

    private func visibility(_ id: String) -> ItemVisibility { store.itemVisibility[id] ?? .shown }
    private var alwaysShown: [MenuNavItem] { MenuNavItem.all.filter { visibility($0.id) != .invisible } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(Theme.textFaint)
                        TextField("Search tasks & documents", text: $store.searchText)
                        if !store.searchText.isEmpty {
                            Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        }
                    }
                }

                if !store.pinnedItems.isEmpty {
                    Section("Pinned") {
                        ForEach(store.pinnedItems) { item in
                            Button {
                                navigate(to: item.ref)
                            } label: {
                                Label(item.name, systemImage: item.ref.kind == .view ? "line.3.horizontal.decrease" : "square.grid.2x2")
                            }
                        }
                    }
                }

                Section {
                    ForEach(alwaysShown) { item in
                        Button {
                            select(item)
                        } label: {
                            HStack {
                                Label(item.label, systemImage: item.icon)
                                Spacer()
                                if store.isHomeTarget(item.section) {
                                    Image(systemName: "house.fill").font(.system(size: 11)).foregroundColor(Theme.textFaint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { showLog = true } label: { Label("Sync Activity Log", systemImage: "clock") }
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    Button { Task { await store.sync() } } label: { Label("Sync Now", systemImage: "arrow.clockwise") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Craft Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLog) { LogViewerView() }
    }

    private func select(_ item: MenuNavItem) {
        switch item.section {
        case .home: section = store.navigateHome()
        case .allTasks: store.selectAllTasks(); section = .allTasks
        case .inbox: store.selectInbox(); section = .inbox
        case .today: store.selectToday(); section = .today
        case .thisWeek: store.selectThisWeek(); section = .thisWeek
        case .documents: section = .documents
        case .views: section = .views
        case .dashboards: section = .dashboards
        case .calendar: section = .calendar
        default: break
        }
        dismiss()
    }

    private func navigate(to ref: PinnedRef) {
        switch ref.kind {
        case .view: store.selectSaved(ref.id); section = .saved(ref.id)
        case .dashboard: section = .dashboard(ref.id)
        }
        dismiss()
    }
}
