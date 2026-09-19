import SwiftUI

/// Documents grid — one card per Craft document (+ Inbox), tapping jumps
/// into All Tasks filtered to it. Mirrors the Mac app's DocumentCard.
struct DocumentsView: View {
    @EnvironmentObject var store: Store
    @Binding var section: AppSection
    let cols = [GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(store.documents) { doc in
                    Button {
                        store.openDocument(id: doc.id)
                        section = .allTasks
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Theme.chipBg).frame(width: 36, height: 36)
                                Image(systemName: doc.id == "inbox" ? "tray.fill" : "doc.text.fill")
                                    .font(.system(size: 13)).foregroundColor(Theme.textLo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                                Text("\(doc.total) task\(doc.total == 1 ? "" : "s") · \(doc.open) open")
                                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Documents")
    }
}

/// Saved views grid — tapping opens the view as the current task list.
struct ViewsListView: View {
    @EnvironmentObject var store: Store
    @Binding var section: AppSection
    @State private var showNewView = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 14) {
                ForEach(store.sortedFilters) { f in
                    Button {
                        store.selectSaved(f.id)
                        section = .saved(f.id)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Theme.chipBg).frame(width: 36, height: 36)
                                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13)).foregroundColor(Theme.textLo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                                Text("\(store.apply(f).count) tasks").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                            }
                            Spacer()
                            Button { store.togglePinned(f.id) } label: {
                                Image(systemName: (f.pinned ?? false) ? "pin.fill" : "pin")
                                    .font(.system(size: 12))
                                    .foregroundColor((f.pinned ?? false) ? Theme.accent : Theme.textFaint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { store.deleteFilter(f.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                if store.sortedFilters.isEmpty {
                    Text("Open All Tasks, set up filters, then save it as a view.")
                        .font(.system(size: 13)).foregroundColor(Theme.textLo).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Views")
    }
}

/// Dashboards grid — tapping opens the masonry/scroll-snap board.
struct DashboardsListView: View {
    @EnvironmentObject var store: Store
    @Binding var section: AppSection
    @State private var showNewDashboard = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 14) {
                ForEach(store.sortedDashboards) { d in
                    Button { section = .dashboard(d.id) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Theme.chipBg).frame(width: 36, height: 36)
                                Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundColor(Theme.textLo)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                                Text("\(d.widgets.count) widget\(d.widgets.count == 1 ? "" : "s")")
                                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
                            }
                            Spacer()
                            Button { store.togglePinnedDashboard(d.id) } label: {
                                Image(systemName: (d.pinned ?? false) ? "pin.fill" : "pin")
                                    .font(.system(size: 12))
                                    .foregroundColor((d.pinned ?? false) ? Theme.accent : Theme.textFaint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { store.deleteDashboard(d.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Dashboards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewDashboard = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNewDashboard) { NewDashboardSheet(section: $section) }
    }
}

struct NewDashboardSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var section: AppSection
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Dashboard name", text: $name)
                Section("Combine views") {
                    ForEach(store.savedFilters) { f in
                        Button {
                            if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(f.id) ? "checkmark.square.fill" : "square")
                                Text(f.name).foregroundColor(Theme.text)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.saveDashboard(name: name, viewIds: store.savedFilters.map(\.id).filter { selected.contains($0) })
                        if let d = store.dashboards.last { section = .dashboard(d.id) }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
            }
        }
    }
}
