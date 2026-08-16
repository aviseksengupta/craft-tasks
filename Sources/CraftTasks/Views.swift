import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Section: Hashable, Codable {
    case home
    case allTasks
    case inbox
    case today
    case thisWeek
    case documents
    case views
    case dashboards
    case saved(UUID)
    case dashboard(UUID)
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State var section: Section = .home

    var body: some View {
        HStack(spacing: 0) {
            // Higher layout priority so the sidebar's fixed 210pt width is
            // always honored first on window resize — without this, an
            // HStack can start compressing a `.frame(width:)`-pinned child
            // once the window shrinks below the combined ideal width,
            // instead of shrinking the flexible content pane next to it.
            Sidebar(section: $section)
                .layoutPriority(1)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            Group {
                switch section {
                case .documents: DocumentsView(section: $section)
                case .views: ViewsPageView(section: $section)
                case .dashboards: DashboardsPageView(section: $section)
                case .dashboard(let id): DashboardView(dashboardId: id)
                default: TaskListView(section: $section)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .onAppear { section = store.navigateHome() }
    }
}

// MARK: - Sidebar

/// One configurable top-row nav destination. `id` is the stable key used
/// in Store.itemVisibility and must never change once shipped.
struct NavItemDef: Identifiable {
    let id: String
    let icon: String
    let label: String
    let section: Section
    let select: () -> Void
}

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @Binding var section: Section
    @State private var showAddTask = false
    @State private var showSidebarSettings = false
    @State private var showMoreItems = false

    /// Home is "active" whenever the current section IS whatever Home
    /// resolves to right now — not just the literal .home case, since Home
    /// can point at All Tasks, a saved view, a dashboard, etc.
    var homeIsActive: Bool {
        section == (store.homeSection ?? .home)
    }

    var navDefs: [NavItemDef] {
        [
            NavItemDef(id: "home", icon: "house", label: "Home", section: .home) { section = store.navigateHome() },
            NavItemDef(id: "allTasks", icon: "tray.full", label: "All Tasks", section: .allTasks) { store.selectAllTasks(); section = .allTasks },
            NavItemDef(id: "inbox", icon: "tray", label: "Inbox", section: .inbox) { store.selectInbox(); section = .inbox },
            NavItemDef(id: "today", icon: "sun.max", label: "Today", section: .today) { store.selectToday(); section = .today },
            NavItemDef(id: "thisWeek", icon: "calendar.badge.clock", label: "This Week", section: .thisWeek) { store.selectThisWeek(); section = .thisWeek },
            NavItemDef(id: "documents", icon: "doc.text", label: "Documents", section: .documents) { section = .documents },
            NavItemDef(id: "views", icon: "list.bullet.rectangle", label: "Views", section: .views) { section = .views },
            NavItemDef(id: "dashboards", icon: "square.grid.2x2", label: "Dashboards", section: .dashboards) { section = .dashboards },
        ]
    }

    private func visibility(_ id: String) -> ItemVisibility { store.itemVisibility[id] ?? .shown }
    private func isActive(_ def: NavItemDef) -> Bool { def.id == "home" ? homeIsActive : section == def.section }

    @ViewBuilder
    private func navRow(_ def: NavItemDef) -> some View {
        if def.id == "home" {
            SidebarItem(icon: def.icon, label: def.label, active: isActive(def)) { def.select() }
        } else {
            SidebarItem(icon: def.icon, label: def.label, active: isActive(def),
                        isHomeTarget: store.isHomeTarget(def.section)) { def.select() }
                .homeMenu(store: store, target: def.section)
        }
    }

    var body: some View {
        let alwaysShown = navDefs.filter { visibility($0.id) == .shown }
        let tuckedAway = navDefs.filter { visibility($0.id) == .hidden }

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textHi)
                Text("Craft Tasks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textHi)
                Spacer()
                Button { showSidebarSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 11)).foregroundColor(Theme.textFaint)
                }
                .buttonStyle(.plain)
                .help("Sidebar item settings")
                .sheet(isPresented: $showSidebarSettings) { SidebarSettingsSheet(navDefs: navDefs) }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Button { showAddTask = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 13, weight: .semibold))
                    Text("New Task").font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .padding(.horizontal, 12).padding(.bottom, 12)
            .sheet(isPresented: $showAddTask) { AddTaskView() }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(Theme.textFaint)
                TextField("Search tasks & documents", text: $store.searchText)
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(Theme.text)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundColor(Theme.textFaint)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.chipBg))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
            .padding(.horizontal, 12).padding(.bottom, 12)

            ForEach(alwaysShown) { def in navRow(def) }

            if !tuckedAway.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.15)) { showMoreItems.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showMoreItems ? 90 : 0))
                            .frame(width: 16)
                        Text("More").font(.system(size: 12)).foregroundColor(Theme.textLo)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                if showMoreItems {
                    ForEach(tuckedAway) { def in navRow(def) }
                }
            }

            let pinnedItems = store.pinnedItems
            if !pinnedItems.isEmpty {
                Text("PINNED")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                    .foregroundColor(Theme.textFaint)
                    .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 4)
                ForEach(pinnedItems) { item in
                    PinnedItemRow(item: item, active: section == item.ref.asSection, section: $section)
                }
            }

            Spacer()
            SyncStatus()
        }
        .frame(width: 210)
        .background(Theme.panel)
        .craftShadow(radius: 16, y: 0)
    }
}

extension PinnedRef {
    var asSection: Section {
        switch kind {
        case .view: return .saved(id)
        case .dashboard: return .dashboard(id)
        }
    }
}

/// One row in the sidebar's unified PINNED section — a saved view or a
/// dashboard, distinguished by icon, drag-reorderable across both kinds.
struct PinnedItemRow: View {
    @EnvironmentObject var store: Store
    let item: PinnedItem
    let active: Bool
    @Binding var section: Section
    @State private var hover = false
    @State private var renaming = false
    @State private var isTargeted = false

    var icon: String {
        switch item {
        case .view: return "line.3.horizontal.decrease"
        case .dashboard: return "square.grid.2x2"
        }
    }
    var isHome: Bool { store.isHomeTarget(item.ref.asSection) }

    private func select() {
        switch item {
        case .view(let f): store.selectSaved(f.id)
        case .dashboard: break
        }
        section = item.ref.asSection
    }
    private func unpin() {
        switch item {
        case .view(let f): store.togglePinned(f.id)
        case .dashboard(let d): store.togglePinnedDashboard(d.id)
        }
    }
    private func delete() {
        switch item {
        case .view(let f): store.deleteFilter(f.id)
        case .dashboard(let d):
            let wasShowing = section == .dashboard(d.id)
            store.deleteDashboard(d.id)
            if wasShowing { section = store.navigateHome() }
        }
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 10)).frame(width: 16)
                Text(item.name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                if isHome { Image(systemName: "house.fill").font(.system(size: 8)).foregroundColor(Theme.textFaint) }
            }
            .foregroundColor(active ? Theme.textHi : Theme.textLo)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(active ? Theme.panelHi : (hover ? Theme.panelHi.opacity(0.5) : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isTargeted ? Theme.accent : .clear, lineWidth: 2))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .draggable(pinnedRefEncoded(item.ref))
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = decodePinnedRef(raw) else { return false }
            store.movePinned(dragged, to: item.ref)
            return true
        } isTargeted: { isTargeted = $0 }
        .popover(isPresented: $renaming) {
            switch item {
            case .view(let f): RenameViewPopover(filter: f)
            case .dashboard(let d): RenameDashboardPopover(dashboard: d)
            }
        }
        .contextMenu {
            Button("Rename") { renaming = true }
            Button(isHome ? "Unset as Home" : "Set as Home") { store.setHomeTarget(item.ref.asSection) }
            Button("Unpin from Sidebar", action: unpin)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

/// PinnedRef round-tripped through a plain string for `.draggable`/
/// `.dropDestination(for: String.self)`, matching the pattern DashboardView
/// uses for widget ids (which only need a UUID, not a kind tag).
func pinnedRefEncoded(_ ref: PinnedRef) -> String {
    "\(ref.kind == .view ? "view" : "dashboard"):\(ref.id.uuidString)"
}
func decodePinnedRef(_ raw: String) -> PinnedRef? {
    let parts = raw.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
    let kind: PinnedRef.Kind = parts[0] == "view" ? .view : .dashboard
    return PinnedRef(kind: kind, id: id)
}

/// Per-item control over the top sidebar row: Always shown / Hidden (tucked
/// behind "More") / Invisible (not rendered at all, anywhere).
struct SidebarSettingsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let navDefs: [NavItemDef]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sidebar Items").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
            Text("Choose how each item behaves in the sidebar.")
                .font(.system(size: 11)).foregroundColor(Theme.textFaint)

            VStack(spacing: 12) {
                ForEach(navDefs) { def in
                    HStack {
                        Image(systemName: def.icon).font(.system(size: 11)).foregroundColor(Theme.textLo).frame(width: 16)
                        Text(def.label).font(.system(size: 12)).foregroundColor(Theme.text)
                        Spacer()
                        Picker("", selection: binding(for: def.id)) {
                            ForEach(ItemVisibility.allCases) { v in Text(v.rawValue).tag(v) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 270)
                    }
                }
            }

            Divider()

            Toggle("Today includes overdue", isOn: $store.todayIncludesOverdue)
                .font(.system(size: 12)).foregroundColor(Theme.text)
            Text("When enabled, the Today view also shows overdue tasks.")
                .font(.system(size: 11)).foregroundColor(Theme.textFaint)

            Divider()
            BackupRestoreSection()

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.panel)
    }

    private func binding(for id: String) -> Binding<ItemVisibility> {
        Binding(
            get: { store.itemVisibility[id] ?? .shown },
            set: { store.setItemVisibility(id, $0) })
    }
}

/// Export the current config (views, dashboards, pinned items, renamed
/// documents) as JSON, or restore from a previously exported (or default)
/// JSON — useful for getting back to a known state after a reinstall.
private struct BackupRestoreSection: View {
    @EnvironmentObject var store: Store
    @State private var json: String?
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backup & Restore").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
            Text("Export your saved views, dashboards, pinned items and renamed documents as JSON.")
                .font(.system(size: 11)).foregroundColor(Theme.textFaint)

            HStack(spacing: 8) {
                Button("Show config JSON") { json = store.exportBackupJSON() }
                Button("Export to file…") { exportToFile() }
                Button("Import from file…") { importFromFile() }
                Button("Reset to default") { resetToDefault() }
            }
            .font(.system(size: 11))

            if let json {
                ScrollView {
                    Text(json).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .padding(8)
                .background(Theme.bg)
                .cornerRadius(6)
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        status = "Copied to clipboard"
                    }
                    .font(.system(size: 11))
                    Spacer()
                }
            }
            if let status {
                Text(status).font(.system(size: 11)).foregroundColor(Theme.textFaint)
            }
        }
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "craft-tasks-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.exportBackupJSON().write(to: url, atomically: true, encoding: .utf8)
        status = "Exported to \(url.lastPathComponent)"
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try store.restoreBackup(fromJSON: text)
            status = "Config restored from \(url.lastPathComponent)"
        } catch {
            status = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func resetToDefault() {
        let alert = NSAlert()
        alert.messageText = "Reset to default configuration?"
        alert.informativeText = "This replaces your saved views, dashboards, and renamed documents."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.restoreDefaultConfig()
        status = "Reset to default configuration"
    }
}

struct NewDashboardSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var section: Section
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Dashboard").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
            TextField("Dashboard name", text: $name)
                .textFieldStyle(.roundedBorder).frame(width: 280)
            Text("COMBINE VIEWS")
                .font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundColor(Theme.textFaint)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.savedFilters) { f in
                    Button {
                        if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selected.contains(f.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13))
                                .foregroundColor(selected.contains(f.id) ? Theme.accent : Theme.textFaint)
                            Text(f.name).font(.system(size: 12)).foregroundColor(Theme.text)
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    store.saveDashboard(name: name, viewIds: store.savedFilters.map(\.id).filter { selected.contains($0) })
                    if let d = store.dashboards.last { section = .dashboard(d.id) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(Theme.panel)
    }
}

struct SidebarItem: View {
    let icon: String
    let label: String
    let active: Bool
    var isHomeTarget: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium)).frame(width: 16)
                Text(label).font(.system(size: 12, weight: active ? .semibold : .regular))
                Spacer()
                if isHomeTarget { Image(systemName: "house.fill").font(.system(size: 8)).foregroundColor(Theme.textFaint) }
            }
            .foregroundColor(active ? Theme.textHi : Theme.textLo)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(active ? Theme.panelHi : (hover ? Theme.panelHi.opacity(0.5) : .clear)))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

extension View {
    /// Right-click "Set as Home" / "Unset as Home" for any pinnable
    /// sidebar destination.
    func homeMenu(store: Store, target: Section) -> some View {
        contextMenu {
            Button(store.isHomeTarget(target) ? "Unset as Home" : "Set as Home") {
                store.setHomeTarget(target)
            }
        }
    }
}

struct SavedFilterRow: View {
    @EnvironmentObject var store: Store
    let filter: TaskFilter
    let active: Bool
    let isHome: Bool
    let select: () -> Void
    @State private var hover = false
    @State private var renaming = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10)).frame(width: 16)
                Text(filter.name).font(.system(size: 12)).lineLimit(1)
                Spacer()
                if isHome { Image(systemName: "house.fill").font(.system(size: 8)).foregroundColor(Theme.textFaint) }
            }
            .foregroundColor(active ? Theme.textHi : Theme.textLo)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(active ? Theme.panelHi : (hover ? Theme.panelHi.opacity(0.5) : .clear)))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popover(isPresented: $renaming) { RenameViewPopover(filter: filter) }
        .contextMenu {
            Button("Rename") { renaming = true }
            Button(isHome ? "Unset as Home" : "Set as Home") { store.setHomeTarget(.saved(filter.id)) }
            Button("Unpin from Sidebar") { store.togglePinned(filter.id) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteFilter(filter.id) }
        }
    }
}

struct SyncStatus: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            HStack(spacing: 6) {
                if store.syncing {
                    ProgressView().controlSize(.mini).scaleEffect(0.6)
                    Text("Syncing…").font(.system(size: 10)).foregroundColor(Theme.textLo)
                } else {
                    Button { Task { await store.sync() } } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                    }.buttonStyle(.plain).foregroundColor(Theme.textLo)
                    VStack(alignment: .leading, spacing: 1) {
                        if store.totalPendingCount > 0 {
                            Text("\(store.totalPendingCount) change(s) queued")
                                .font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.textHi)
                        }
                        if let err = store.syncError {
                            Text(err).font(.system(size: 9)).foregroundColor(Theme.danger).lineLimit(2)
                        } else {
                            Text(store.lastSyncSummary.isEmpty ? "Synced" : store.lastSyncSummary)
                                .font(.system(size: 9)).foregroundColor(Theme.textLo)
                            if let d = store.lastSync {
                                Text(d.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 9)).foregroundColor(Theme.textFaint)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

// MARK: - Task list + filter bar

struct TaskListView: View {
    @EnvironmentObject var store: Store
    @Binding var section: Section
    @State private var showSaveSheet = false
    @State private var newFilterName = ""

    var heading: String {
        switch section {
        // Reached only when Home has no target set — navigateHome() sends
        // a targeted Home straight to the concrete section (.saved, .allTasks…).
        case .home: return "Home"
        case .allTasks: return "All Tasks"
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .saved(let id): return store.savedFilters.first { $0.id == id }?.name ?? "View"
        case .documents, .dashboard, .views, .dashboards: return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            FilterBar()
            Rectangle().fill(Theme.stroke).frame(height: 1)
            list
        }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    /// The saved view the current screen corresponds to, if any — Home
    /// always resolves straight to .saved(id) when it targets a view, so
    /// only that case needs handling here. Today/This Week/All Tasks are
    /// never a saved view; a brand-new view can only be created from All Tasks.
    var editableViewId: UUID? {
        if case .saved(let id) = section { return id }
        return nil
    }

    var hasUnsavedViewChanges: Bool {
        guard let id = editableViewId, let saved = store.savedFilters.first(where: { $0.id == id }) else { return false }
        var current = store.filter
        current.id = saved.id
        current.name = saved.name
        current.pinned = saved.pinned
        return current != saved
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(heading).font(.system(size: 27, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
            Text("\(store.filtered.count)")
                .font(.system(size: 13)).foregroundColor(Theme.textFaint)
            Spacer()
            CompletedToggle()
            if let id = editableViewId {
                if hasUnsavedViewChanges {
                    Button { store.updateSavedFilter(id) } label: {
                        Chip(text: "Update view", icon: "arrow.triangle.2.circlepath")
                    }.buttonStyle(.plain)
                }
            } else if section == .allTasks && !store.filter.isEmpty {
                Button { newFilterName = ""; showSaveSheet = true } label: {
                    Chip(text: "Save view", icon: "plus")
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 14)
    }

    var list: some View {
        let groups = store.group(store.filtered, by: store.filter.groupBy ?? .document)
        let isKanban = (store.filter.layout ?? .stacked) == .kanban
        // SwiftUI's ScrollView centers content that's smaller than the
        // viewport on any active scroll axis — `.frame(maxWidth/maxHeight:
        // .infinity)` alone doesn't reliably override that once both axes
        // are active (as kanban needs). Measuring the viewport with
        // GeometryReader and setting *minWidth/minHeight* to that size
        // forces the content to never be smaller than the viewport, so
        // top-left alignment always has room to take effect.
        return GeometryReader { geo in
            ScrollView(isKanban ? [.vertical, .horizontal] : [.vertical]) {
                Group {
                    if isKanban {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(groups, id: \.0) { title, items in
                                KanbanColumn(title: title, items: items)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 18) {
                            ForEach(groups, id: \.0) { title, items in
                                TaskGroupBlock(title: title, items: items)
                            }
                        }
                    }
                    if store.filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundColor(Theme.textFaint)
                            Text("No tasks match this view").font(.system(size: 13)).foregroundColor(Theme.textLo)
                        }.padding(.top, 80)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
    }

    var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save current filter as view").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textHi)
            TextField("View name", text: $newFilterName)
                .textFieldStyle(.roundedBorder).frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }
                Button("Save") {
                    if !newFilterName.isEmpty {
                        store.saveCurrentFilter(named: newFilterName)
                        showSaveSheet = false
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(Theme.panel)
    }
}

/// One compact row of short, iconographic filter chips — no search field
/// here (that lives at the top of the sidebar) and no separate tag row
/// (tags are a multi-select dropdown like documents).
struct FilterBar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 8) {
            statePicker
            dateFieldPicker
            dateScopePicker
            documentPicker
            tagPicker
            groupPicker
            layoutToggle
            Spacer()
            if !store.filter.isEmpty {
                Button { store.filter = TaskFilter(); store.filter.states = [.todo] } label: {
                    Chip(text: "Clear", icon: "xmark")
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
    }

    var statePicker: some View {
        Menu {
            ForEach(TaskState.allCases, id: \.self) { s in
                Button {
                    if store.filter.states.contains(s) { store.filter.states.remove(s) }
                    else { store.filter.states.insert(s) }
                } label: {
                    HStack { Text(s.label); if store.filter.states.contains(s) { Image(systemName: "checkmark") } }
                }
            }
            Divider()
            Button("Any") { store.filter.states = [] }
        } label: {
            Chip(text: store.filter.states.isEmpty ? "Any"
                 : store.filter.states.map(\.label).sorted().joined(separator: ", "),
                 icon: "checkmark.circle", active: !store.filter.states.isEmpty && store.filter.states != [.todo])
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    /// Which date field a scope filters on — makes "Deadline" a real,
    /// scope-aware date filter instead of a plain present/absent toggle.
    var dateFieldPicker: some View {
        Menu {
            ForEach(DateField.allCases) { d in
                Button {
                    store.filter.dateField = d
                } label: {
                    HStack { Text(d.rawValue); if store.filter.dateField == d { Image(systemName: "checkmark") } }
                }
            }
        } label: {
            Chip(text: store.filter.dateField == .any ? "Date" : store.filter.dateField.rawValue,
                 icon: store.filter.dateField == .deadline ? "flag" : "calendar",
                 active: store.filter.dateField != .any)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    var dateScopePicker: some View {
        Menu {
            ForEach(DateScope.allCases) { d in
                Button(d.rawValue) { store.filter.dateScope = d }
            }
        } label: {
            Chip(text: store.filter.dateScope.rawValue,
                 active: store.filter.dateScope != .any)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    var documentPicker: some View {
        Menu {
            ForEach(store.documents) { d in
                Button {
                    if store.filter.documentIds.contains(d.id) { store.filter.documentIds.remove(d.id) }
                    else { store.filter.documentIds.insert(d.id) }
                } label: {
                    HStack { Text(d.title); if store.filter.documentIds.contains(d.id) { Image(systemName: "checkmark") } }
                }
            }
            Divider()
            Button("Docs: All") { store.filter.documentIds = [] }
        } label: {
            Chip(text: store.filter.documentIds.isEmpty ? "Docs: All"
                 : "Docs: \(store.filter.documentIds.count)",
                 icon: "doc.text", active: !store.filter.documentIds.isEmpty)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    /// Each tag cycles none → include (has tag) → exclude (doesn't have
    /// tag) → none, so a view can require a tag AND rule others out.
    var tagPicker: some View {
        let activeCount = store.filter.tags.count + store.filter.excludedTags.count
        return Menu {
            ForEach(store.allTags, id: \.self) { tag in
                Button {
                    if store.filter.tags.contains(tag) {
                        store.filter.tags.remove(tag)
                        store.filter.excludedTags.insert(tag)
                    } else if store.filter.excludedTags.contains(tag) {
                        store.filter.excludedTags.remove(tag)
                    } else {
                        store.filter.tags.insert(tag)
                    }
                } label: {
                    HStack {
                        Text("#\(tag)")
                        if store.filter.tags.contains(tag) { Image(systemName: "checkmark") }
                        else if store.filter.excludedTags.contains(tag) { Image(systemName: "minus.circle") }
                    }
                }
            }
            if store.allTags.isEmpty {
                Text("No tags yet").foregroundColor(Theme.textFaint)
            }
            Divider()
            Button("Tags: All") { store.filter.tags = []; store.filter.excludedTags = [] }
        } label: {
            Chip(text: activeCount == 0 ? "Tags: All" : "Tags: \(activeCount)",
                 icon: "tag", active: activeCount > 0)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Click a tag to require it, click again to exclude it, once more to clear")
    }

    var groupPicker: some View {
        Menu {
            ForEach(GroupBy.allCases) { g in
                Button {
                    store.filter.groupBy = g
                } label: {
                    HStack { Text(g.rawValue); if (store.filter.groupBy ?? .document) == g { Image(systemName: "checkmark") } }
                }
            }
        } label: {
            Chip(text: "By: \((store.filter.groupBy ?? .document).rawValue)",
                 icon: "square.stack.3d.up",
                 active: (store.filter.groupBy ?? .document) != .document)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    var layoutToggle: some View {
        Button {
            store.filter.layout = (store.filter.layout ?? .stacked) == .stacked ? .kanban : .stacked
        } label: {
            Chip(text: (store.filter.layout ?? .stacked).rawValue,
                 icon: (store.filter.layout ?? .stacked) == .kanban ? "rectangle.split.3x1" : "list.bullet",
                 active: (store.filter.layout ?? .stacked) == .kanban)
        }
        .buttonStyle(.plain)
        .help("Switch between stacked groups and side-by-side kanban columns")
    }
}

/// A group of tasks rendered as a raised card block. Header styling takes
/// its cue from Craft's document headers: a small icon glyph, generous
/// letter-spacing on the title, and a plain muted count — no accent rule.
struct TaskGroupBlock: View {
    let title: String
    let items: [CraftTask]
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textFaint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundColor(Theme.textHi)
                    Text("\(items.count)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textFaint)
                    Spacer()
                }
                .padding(.leading, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                        TaskRow(task: t)
                        if i < items.count - 1 {
                            Rectangle().fill(Theme.stroke.opacity(0.6)).frame(height: 1)
                                .padding(.leading, 46)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
                .craftShadow()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// One kanban-style column — a group rendered as a fixed-width card so
/// several groups can sit side by side instead of stacking.
struct KanbanColumn: View {
    let title: String
    let items: [CraftTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textHi)
                    .lineLimit(1)
                Text("\(items.count)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textFaint)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                    TaskRow(task: t)
                    if i < items.count - 1 {
                        Rectangle().fill(Theme.stroke.opacity(0.6)).frame(height: 1)
                            .padding(.leading, 46)
                    }
                }
                if items.isEmpty {
                    Text("Nothing here")
                        .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                        .padding(14)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
            .craftShadow()
        }
        .frame(width: 280, alignment: .top)
    }
}

/// Global show/hide completed toggle, shown in every view header.
struct CompletedToggle: View {
    @EnvironmentObject var store: Store
    var body: some View {
        Button { store.showCompleted.toggle() } label: {
            Chip(text: store.showCompleted ? "Completed shown" : "Completed hidden",
                 icon: store.showCompleted ? "eye" : "eye.slash",
                 active: !store.showCompleted)
        }
        .buttonStyle(.plain)
        .help("Show or hide completed & canceled tasks everywhere")
    }
}

// MARK: - Task row

struct TaskRow: View {
    @EnvironmentObject var store: Store
    let task: CraftTask
    @State private var hover = false
    @State private var editing = false

    var dateBadge: (String, Bool)? {
        let today = Calendar.current.startOfDay(for: Date())
        if let d = task.scheduleDay ?? task.deadlineDay {
            let overdue = d < today && task.state == .todo
            let df = DateFormatter(); df.dateFormat = "d MMM"
            if Calendar.current.isDateInToday(d) { return ("Today", false) }
            if Calendar.current.isDateInTomorrow(d) { return ("Tomorrow", false) }
            return (df.string(from: d), overdue)
        }
        return nil
    }

    /// A task still sitting in the local-create outbox — Craft hasn't
    /// confirmed it yet (e.g. created while offline). Editing is disabled
    /// until it syncs, since there's no real Craft id to push changes to yet.
    var isPending: Bool { task.id.hasPrefix("local-") }

    var body: some View {
        // RowCheckbox is a SIBLING here, not nested inside the "open
        // editor" Button below — a Button nested inside another Button's
        // label is unreliable to hit-test on macOS (the outer button's
        // gesture recognizer can win even with .buttonStyle(.plain)), which
        // is why clicking the checkbox was opening the editor instead of
        // toggling state. Two independent, non-overlapping Buttons in the
        // same HStack route clicks correctly.
        HStack(alignment: .top, spacing: 12) {
            RowCheckbox(task: task)
                .padding(.top, 1)

            Button { if !isPending { editing = true } } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.displayTitle)
                            .font(.system(size: 13))
                            .foregroundColor(task.state == .todo ? Theme.text : Theme.textFaint)
                            .strikethrough(task.state != .todo, color: Theme.textFaint)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if isPending {
                                HStack(spacing: 3) {
                                    ProgressView().controlSize(.mini).scaleEffect(0.5)
                                    Text("syncing").font(.system(size: 10)).foregroundColor(Theme.textFaint)
                                }
                            }
                            ForEach(task.tags, id: \.self) { tag in
                                Text("#\(tag)").font(.system(size: 10, weight: .medium)).foregroundColor(Theme.textLo)
                            }
                            if let badge = dateBadge {
                                HStack(spacing: 3) {
                                    Image(systemName: task.deadlineDate != nil && task.scheduleDate == nil ? "flag" : "calendar")
                                        .font(.system(size: 8))
                                    Text(badge.0).font(.system(size: 10, weight: badge.1 ? .semibold : .regular))
                                }
                                .foregroundColor(badge.1 ? Theme.danger : Theme.textFaint)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(badge.1 ? Theme.panelHi : .clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(badge.1 ? Theme.stroke : .clear, lineWidth: 1))
                            }
                            if task.state == .done, let c = task.completedDay {
                                Text("done \(c.formatted(.dateTime.day().month(.abbreviated)))")
                                    .font(.system(size: 10)).foregroundColor(Theme.textFaint)
                            }
                        }
                    }
                    Spacer()
                    if hover && !isPending {
                        Image(systemName: "pencil")
                            .font(.system(size: 10)).foregroundColor(Theme.textFaint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let link = task.craftDeepLink(spaceId: store.spaceId) {
                OpenInCraftButton(url: link)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(hover ? Theme.panelHi.opacity(0.5) : .clear)
        .opacity(isPending ? 0.7 : 1)
        .onHover { hover = $0 }
        .help(isPending ? "Still syncing to Craft — editing will be available once it's confirmed" : "")
        .sheet(isPresented: $editing) { EditTaskView(task: task) }
    }
}

/// Pronounced circular badge that opens a task's source document in the
/// Craft app — the app's own "square.stack.3d.up.fill" mark (also used as
/// the sidebar logo) doubles as the "open in Craft" affordance.
struct OpenInCraftButton: View {
    let url: URL
    @State private var hover = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(hover ? .black : Theme.textLo)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hover ? Theme.accent : Theme.panelHi))
                .overlay(Circle().stroke(hover ? Theme.accent : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Open in Craft")
    }
}

/// Checkbox on every list row: click cycles open → done → canceled → open,
/// syncing to Craft like any other edit. Tap targets stay clear of the
/// row's open-editor tap.
struct RowCheckbox: View {
    @EnvironmentObject var store: Store
    let task: CraftTask
    @State private var hover = false

    var isPending: Bool { task.id.hasPrefix("local-") }

    var body: some View {
        Button { if !isPending { store.cycleState(task) } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(task.state == .todo ? Color.clear : Theme.accent)
                RoundedRectangle(cornerRadius: 5)
                    .stroke(hover ? Theme.textHi : (task.state == .todo ? Theme.textLo : Theme.accent), lineWidth: 1.3)
                switch task.state {
                case .todo: EmptyView()
                case .done:
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                case .canceled:
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.black)
                }
            }
            .frame(width: 16, height: 16)
            // A stroke-only / clear-fill ZStack has an unreliable natural
            // hit-test area in SwiftUI on macOS — without an explicit
            // content shape, clicks landing squarely on the visible square
            // could still miss. This pins the tappable region to the full
            // frame (padded slightly beyond the glyph for a forgiving
            // margin), which is what was making checkbox clicks no-op.
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(isPending ? "Still syncing to Craft" : "Click to cycle state")
    }
}

// MARK: - Dashboard

/// Shared grid constants — a 6-column, ~110pt-row grid gives widgets much
/// finer-grained sizing than the old 5 fixed presets, while still auto-
/// flowing (no absolute x/y to manage).
enum DashboardGrid {
    static let columns = 6
    static let colWidth: CGFloat = 170
    static let rowHeight: CGFloat = 110
    static let spacing: CGFloat = 14
    static let minWidthUnits = 2
    static let minHeightUnits = 2
    static let maxHeightUnits = 8
}

/// Live drag-resize in progress: which widget, and its provisional size in
/// grid units. Held by DashboardView so the whole grid can reflow around it
/// as you drag, not just the one widget.
struct WidgetResizeState: Equatable {
    var widgetId: UUID
    var widthUnits: Int
    var heightUnits: Int
}

struct DashboardView: View {
    @EnvironmentObject var store: Store
    let dashboardId: UUID
    @State private var showAddViews = false
    @State private var draggedWidgetId: UUID?
    @State private var resizeState: WidgetResizeState?

    var dashboard: Dashboard? { store.dashboards.first { $0.id == dashboardId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(dashboard?.name ?? "Dashboard")
                    .font(.system(size: 25, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                Text("\(dashboard?.widgets.count ?? 0) widgets")
                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
                Spacer()
                CompletedToggle()
                Button { showAddViews = true } label: {
                    Chip(text: "Add view", icon: "plus")
                }
                .buttonStyle(.plain)
                .disabled(store.savedFilters.isEmpty)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            grid
        }
        .sheet(isPresented: $showAddViews) { AddWidgetsSheet(dashboardId: dashboardId) }
    }

    var grid: some View {
        let widgets = dashboard?.widgets ?? []
        // While a widget is being dragged to resize, substitute its live
        // provisional size so the whole grid reflows around it in real time.
        let spans = widgets.map { w -> (cols: Int, rows: Int) in
            if let r = resizeState, r.widgetId == w.id { return (r.widthUnits, r.heightUnits) }
            return (w.widthUnits, w.heightUnits)
        }
        // The grid's natural width (columns × colWidth) is often wider than
        // the window's content area. Without a horizontal scroll axis and a
        // hard width ceiling here, that extra width propagated straight up
        // through the layout tree and fought the window's own size on
        // resize — which is what was squeezing the fixed-width sidebar
        // instead of just clipping/scrolling the dashboard canvas.
        return GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if widgets.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundColor(Theme.textFaint)
                            Text("Add a saved view to get started").font(.system(size: 13)).foregroundColor(Theme.textLo)
                        }.padding(.top, 80)
                    } else {
                        DashboardGridLayout(columns: DashboardGrid.columns, colWidth: DashboardGrid.colWidth,
                                            rowHeight: DashboardGrid.rowHeight, spacing: DashboardGrid.spacing, spans: spans) {
                            ForEach(widgets) { w in
                                DashboardWidgetCard(
                                    dashboardId: dashboardId, widget: w,
                                    filter: store.savedFilters.first { $0.id == w.viewId },
                                    draggedWidgetId: $draggedWidgetId, resizeState: $resizeState)
                            }
                        }
                        .padding(24)
                        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: resizeState)
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Row-shelf packing layout for dashboard widgets: each widget declares a
/// (colSpan, rowSpan) footprint; widgets fill left to right and wrap to a
/// new row when they don't fit, like a simple flex-wrap grid.
struct DashboardGridLayout: Layout {
    var columns: Int
    var colWidth: CGFloat
    var rowHeight: CGFloat
    var spacing: CGFloat
    var spans: [(cols: Int, rows: Int)]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = packedFrames()
        let width = CGFloat(columns) * colWidth + CGFloat(max(0, columns - 1)) * spacing
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = packedFrames()
        for (i, subview) in subviews.enumerated() where i < frames.count {
            let f = frames[i]
            subview.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                          proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }

    /// Skyline/masonry packing: each widget is placed in whichever column
    /// span currently has the lowest "landing height", not just wrapped
    /// into fresh rows. This is what lets a short widget's leftover space
    /// (e.g. under a Small card next to a Tall one) get filled by the next
    /// widget instead of being stranded — a plain row-shelf packer treats
    /// a whole row as blocked until its tallest member clears.
    private func packedFrames() -> [CGRect] {
        var colHeights = [Int](repeating: 0, count: max(columns, 1))
        var frames: [CGRect] = []
        for span in spans {
            let w = max(1, min(span.cols, columns))
            var bestX = 0
            var bestY = Int.max
            for x in 0...(columns - w) {
                let y = colHeights[x..<(x + w)].max() ?? 0
                if y < bestY { bestY = y; bestX = x }
            }
            let originX = CGFloat(bestX) * (colWidth + spacing)
            let originY = CGFloat(bestY) * (rowHeight + spacing)
            let width = CGFloat(w) * colWidth + CGFloat(w - 1) * spacing
            let height = CGFloat(span.rows) * rowHeight + CGFloat(span.rows - 1) * spacing
            frames.append(CGRect(x: originX, y: originY, width: width, height: height))
            for x in bestX..<(bestX + w) { colHeights[x] = bestY + span.rows }
        }
        return frames
    }
}

/// One saved view as a fixed-size grid tile. Drag the grip to reorder;
/// the whole card is a drop target. Size and removal live in the "…" menu.
struct DashboardWidgetCard: View {
    @EnvironmentObject var store: Store
    let dashboardId: UUID
    let widget: DashboardWidget
    let filter: TaskFilter?
    @Binding var draggedWidgetId: UUID?
    @Binding var resizeState: WidgetResizeState?
    @State private var isTargeted = false
    @State private var resizeAnchor: (width: Int, height: Int)?

    private var isResizing: Bool { resizeState?.widgetId == widget.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isTargeted ? Theme.accent : (isResizing ? Theme.textLo : Theme.stroke),
                   lineWidth: isTargeted ? 2 : 1))
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .craftShadow()
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let draggedId = UUID(uuidString: raw) else { return false }
            store.moveWidget(draggedId, to: widget.id, in: dashboardId)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10)).foregroundColor(Theme.textFaint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .draggable(widget.id.uuidString)
                .help("Drag to reorder")
            Text(filter?.name ?? "View removed")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textHi).lineLimit(1)
            if let filter { Text("\(store.apply(filter).count)").font(.system(size: 11)).foregroundColor(Theme.textFaint) }
            Spacer()
            if isResizing, let r = resizeState {
                Text("\(r.widthUnits)×\(r.heightUnits)")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(Theme.textFaint)
            }
            Button { store.removeWidget(widget.id, from: dashboardId) } label: {
                Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(Theme.textFaint)
                    .frame(width: 20, height: 20).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Remove from dashboard")
        }
    }

    /// Drag from the bottom-right corner to resize freely — the grid
    /// reflows live as you drag, snapping to grid units on release.
    var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(isResizing ? Theme.textHi : Theme.textFaint)
            .padding(8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        let anchor = resizeAnchor ?? (widget.widthUnits, widget.heightUnits)
                        if resizeAnchor == nil { resizeAnchor = anchor }
                        let deltaCols = Int((value.translation.width / (DashboardGrid.colWidth + DashboardGrid.spacing)).rounded())
                        let deltaRows = Int((value.translation.height / (DashboardGrid.rowHeight + DashboardGrid.spacing)).rounded())
                        let newWidth = min(DashboardGrid.columns, max(DashboardGrid.minWidthUnits, anchor.0 + deltaCols))
                        let newHeight = min(DashboardGrid.maxHeightUnits, max(DashboardGrid.minHeightUnits, anchor.1 + deltaRows))
                        resizeState = WidgetResizeState(widgetId: widget.id, widthUnits: newWidth, heightUnits: newHeight)
                    }
                    .onEnded { _ in
                        if let r = resizeState, r.widgetId == widget.id {
                            store.setWidgetDimensions(widget.id, widthUnits: r.widthUnits, heightUnits: r.heightUnits, in: dashboardId)
                        }
                        resizeState = nil
                        resizeAnchor = nil
                    }
            )
            .help("Drag to resize")
    }

    @ViewBuilder
    var content: some View {
        if let filter {
            let tasks = store.apply(filter)
            if tasks.isEmpty {
                Text("Nothing here").font(.system(size: 12)).foregroundColor(Theme.textFaint)
            } else if (filter.layout ?? .stacked) == .kanban {
                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(store.group(tasks, by: filter.groupBy ?? .document), id: \.0) { title, items in
                            miniColumn(title: title, items: items)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.group(tasks, by: filter.groupBy ?? .document), id: \.0) { title, items in
                            miniColumn(title: title, items: items)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        } else {
            Text("This saved view was deleted").font(.system(size: 12)).foregroundColor(Theme.textFaint)
        }
    }

    /// One group's title + rows, sized to sit inside a widget tile (used
    /// for both the stacked and kanban layouts — kanban just lays several
    /// of these out side by side instead of one under another).
    private func miniColumn(title: String, items: [CraftTask]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundColor(Theme.textFaint)
            ForEach(items) { t in TaskRow(task: t) }
        }
        .frame(width: (filter?.layout ?? .stacked) == .kanban ? 180 : nil, alignment: .topLeading)
    }
}

struct AddWidgetsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let dashboardId: UUID
    @State private var selected: Set<UUID> = []

    var availableFilters: [TaskFilter] {
        let existing = Set(store.dashboards.first { $0.id == dashboardId }?.widgets.map(\.viewId) ?? [])
        return store.savedFilters.filter { !existing.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add views to dashboard").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
            if availableFilters.isEmpty {
                Text("All your saved views are already on this dashboard.")
                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableFilters) { f in
                        Button {
                            if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selected.contains(f.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 13))
                                    .foregroundColor(selected.contains(f.id) ? Theme.accent : Theme.textFaint)
                                Text(f.name).font(.system(size: 12)).foregroundColor(Theme.text)
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    store.addWidgets(viewIds: Array(selected), to: dashboardId)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 320)
        .background(Theme.panel)
    }
}

// MARK: - Views page

/// All saved views in one place, independent of the sidebar. Pinning here
/// is the only way a view shows up in the sidebar's PINNED VIEWS section —
/// saving a view from All Tasks no longer auto-adds it to the sidebar.
struct ViewsPageView: View {
    @EnvironmentObject var store: Store
    @Binding var section: Section

    let cols = [GridItem(.adaptive(minimum: 300), spacing: 18)]

    var visibleFilters: [TaskFilter] {
        store.searchText.isEmpty ? store.sortedFilters
            : store.sortedFilters.filter { $0.name.localizedCaseInsensitiveContains(store.searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Views").font(.system(size: 25, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                Text("\(visibleFilters.count)").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                Spacer()
                CompletedToggle()
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            if visibleFilters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 28)).foregroundColor(Theme.textFaint)
                    Text(store.savedFilters.isEmpty ? "Save a view from All Tasks to see it here" : "No views match your search")
                        .font(.system(size: 13)).foregroundColor(Theme.textLo)
                }.padding(.top, 80)
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(visibleFilters) { f in
                            ViewCard(filter: f, isHome: store.isHomeTarget(.saved(f.id))) {
                                store.selectSaved(f.id); section = .saved(f.id)
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// Mirrors DocumentCard's shape (icon badge, stat tiles, progress bar) so
/// the Views page and Documents page read as the same design language.
struct ViewCard: View {
    @EnvironmentObject var store: Store
    let filter: TaskFilter
    let isHome: Bool
    let open: () -> Void
    @State private var hover = false
    @State private var renaming = false
    @State private var isTargeted = false

    var pinned: Bool { filter.pinned ?? false }

    var stats: (total: Int, open: Int, done: Int, overdue: Int) {
        let matched = store.apply(filter)
        let today = Calendar.current.startOfDay(for: Date())
        let open = matched.filter { $0.state == .todo }.count
        let done = matched.filter { $0.state == .done }.count
        let overdue = matched.filter { $0.state == .todo && ($0.scheduleDay ?? $0.deadlineDay).map { $0 < today } == true }.count
        return (matched.count, open, done, overdue)
    }

    var progress: Double {
        let s = stats
        return s.total == 0 ? 0 : Double(s.total - s.open) / Double(s.total)
    }

    var criteria: String {
        var parts: [String] = []
        if !filter.states.isEmpty { parts.append(filter.states.map(\.label).sorted().joined(separator: "/")) }
        if filter.dateScope != .any { parts.append(filter.dateScope.rawValue) }
        if !filter.documentIds.isEmpty { parts.append("\(filter.documentIds.count) doc\(filter.documentIds.count == 1 ? "" : "s")") }
        if !filter.tags.isEmpty { parts.append("\(filter.tags.count) tag\(filter.tags.count == 1 ? "" : "s")") }
        if !filter.excludedTags.isEmpty { parts.append("−\(filter.excludedTags.count) tag\(filter.excludedTags.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "All tasks" : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.chipBg).frame(width: 36, height: 36)
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13)).foregroundColor(Theme.textLo)
                    }
                    .contentShape(Rectangle())
                    .draggable(filter.id.uuidString)
                    .help("Drag to reorder")
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(filter.name)
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundColor(Theme.textHi).lineLimit(1)
                            if isHome { Image(systemName: "house.fill").font(.system(size: 9)).foregroundColor(Theme.textFaint) }
                            Button { renaming = true } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundColor(hover ? Theme.textLo : .clear)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Rename this view")
                            .popover(isPresented: $renaming) { RenameViewPopover(filter: filter) }
                        }
                        Text(criteria).font(.system(size: 11)).foregroundColor(Theme.textFaint).lineLimit(1)
                    }
                    Spacer()
                    Button { store.togglePinned(filter.id) } label: {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundColor(pinned ? Theme.accent : (hover ? Theme.textLo : .clear))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(pinned ? "Unpin from sidebar" : "Pin to sidebar")
                }

                let s = stats
                HStack(spacing: 0) {
                    statTile("\(s.open)", "Open", bright: s.open > 0)
                    statDivider
                    statTile("\(s.done)", "Done")
                    statDivider
                    statTile("\(s.overdue)", "Overdue", bright: s.overdue > 0)
                }

                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.chipBg)
                            Capsule().fill(Theme.accent)
                                .frame(width: max(5, geo.size.width * progress))
                        }
                    }
                    .frame(height: 5)
                    Text(s.total == 0 ? "No matching tasks" : "\(Int(progress * 100))% complete")
                        .font(.system(size: 10)).foregroundColor(Theme.textFaint)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(hover ? Theme.panelHi : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isTargeted ? Theme.accent : (hover ? Theme.textFaint.opacity(0.4) : Theme.stroke),
                       lineWidth: isTargeted ? 2 : 1))
            .craftShadow(radius: hover ? 20 : 10, y: hover ? 8 : 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.12)) { hover = isHovering } }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let draggedId = UUID(uuidString: raw) else { return false }
            store.moveView(draggedId, to: filter.id)
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button("Rename") { renaming = true }
            Button(isHome ? "Unset as Home" : "Set as Home") { store.setHomeTarget(.saved(filter.id)) }
            Button(pinned ? "Unpin from Sidebar" : "Pin to Sidebar") { store.togglePinned(filter.id) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteFilter(filter.id) }
        }
    }

    var statDivider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1, height: 30)
    }

    func statTile(_ n: String, _ label: String, bright: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(bright ? Theme.textHi : Theme.textLo)
            Text(label).font(.system(size: 10)).foregroundColor(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Dashboards page

struct DashboardsPageView: View {
    @EnvironmentObject var store: Store
    @Binding var section: Section
    @State private var showNewDashboard = false

    let cols = [GridItem(.adaptive(minimum: 300), spacing: 18)]

    var visibleDashboards: [Dashboard] {
        store.searchText.isEmpty ? store.sortedDashboards
            : store.sortedDashboards.filter { $0.name.localizedCaseInsensitiveContains(store.searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dashboards").font(.system(size: 25, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                Text("\(visibleDashboards.count)").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                Spacer()
                Button { showNewDashboard = true } label: {
                    Chip(text: "New dashboard", icon: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            if visibleDashboards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundColor(Theme.textFaint)
                    Text(store.dashboards.isEmpty ? "Create a dashboard to see it here" : "No dashboards match your search")
                        .font(.system(size: 13)).foregroundColor(Theme.textLo)
                }.padding(.top, 80)
            } else {
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(visibleDashboards) { d in
                            DashboardCard(dashboard: d, isHome: store.isHomeTarget(.dashboard(d.id))) {
                                section = .dashboard(d.id)
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showNewDashboard) { NewDashboardSheet(section: $section) }
    }
}

/// Mirrors ViewCard's shape (icon badge, widget count) so the Dashboards
/// page reads as the same design language as Views.
struct DashboardCard: View {
    @EnvironmentObject var store: Store
    let dashboard: Dashboard
    let isHome: Bool
    let open: () -> Void
    @State private var hover = false
    @State private var renaming = false
    @State private var isTargeted = false

    var pinned: Bool { dashboard.pinned ?? false }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.chipBg).frame(width: 36, height: 36)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13)).foregroundColor(Theme.textLo)
                }
                .contentShape(Rectangle())
                .draggable(dashboard.id.uuidString)
                .help("Drag to reorder")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(dashboard.name)
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundColor(Theme.textHi).lineLimit(1)
                        if isHome { Image(systemName: "house.fill").font(.system(size: 9)).foregroundColor(Theme.textFaint) }
                        Button { renaming = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundColor(hover ? Theme.textLo : .clear)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Rename this dashboard")
                        .popover(isPresented: $renaming) { RenameDashboardPopover(dashboard: dashboard) }
                    }
                    Text("\(dashboard.widgets.count) widget\(dashboard.widgets.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundColor(Theme.textFaint).lineLimit(1)
                }
                Spacer()
                Button { store.togglePinnedDashboard(dashboard.id) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(pinned ? Theme.accent : (hover ? Theme.textLo : .clear))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin from sidebar" : "Pin to sidebar")
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(hover ? Theme.panelHi : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isTargeted ? Theme.accent : (hover ? Theme.textFaint.opacity(0.4) : Theme.stroke),
                       lineWidth: isTargeted ? 2 : 1))
            .craftShadow(radius: hover ? 20 : 10, y: hover ? 8 : 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.12)) { hover = isHovering } }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let draggedId = UUID(uuidString: raw) else { return false }
            store.moveDashboard(draggedId, to: dashboard.id)
            return true
        } isTargeted: { isTargeted = $0 }
        .contextMenu {
            Button("Rename") { renaming = true }
            Button(isHome ? "Unset as Home" : "Set as Home") { store.setHomeTarget(.dashboard(dashboard.id)) }
            Button(pinned ? "Unpin from Sidebar" : "Pin to Sidebar") { store.togglePinnedDashboard(dashboard.id) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteDashboard(dashboard.id) }
        }
    }
}

struct RenameDashboardPopover: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let dashboard: Dashboard
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dashboard name").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textHi)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 250)
        .onAppear { name = dashboard.name }
    }

    private func save() {
        store.renameDashboard(dashboard.id, to: name)
        dismiss()
    }
}

// MARK: - Documents view

struct DocumentsView: View {
    @EnvironmentObject var store: Store
    @Binding var section: Section

    let cols = [GridItem(.adaptive(minimum: 300), spacing: 18)]

    var visibleDocs: [DocumentSummary] {
        var docs = store.showCompleted ? store.documents : store.documents.filter { $0.open > 0 }
        if !store.searchText.isEmpty {
            docs = docs.filter { $0.title.localizedCaseInsensitiveContains(store.searchText) }
        }
        return docs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Documents").font(.system(size: 25, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                Text("\(visibleDocs.count) with tasks")
                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
                Spacer()
                CompletedToggle()
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ScrollView {
                LazyVGrid(columns: cols, spacing: 18) {
                    ForEach(visibleDocs) { doc in
                        DocumentCard(doc: doc) {
                            store.openDocument(id: doc.id)
                            section = .allTasks
                        }
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct DocumentCard: View {
    @EnvironmentObject var store: Store
    let doc: DocumentSummary
    let open: () -> Void
    @State private var hover = false
    @State private var renaming = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.chipBg).frame(width: 36, height: 36)
                        Image(systemName: doc.id == "inbox" ? "tray.fill" : "doc.text.fill")
                            .font(.system(size: 13)).foregroundColor(Theme.textLo)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(doc.title)
                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                .foregroundColor(Theme.textHi).lineLimit(1)
                            if doc.id != "inbox" {
                                Button { renaming = true } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundColor(hover ? Theme.textLo : .clear)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Rename in this app (Craft's own title is unaffected)")
                                .popover(isPresented: $renaming) {
                                    RenameDocumentPopover(doc: doc)
                                }
                            }
                        }
                        Text("\(doc.total) task\(doc.total == 1 ? "" : "s")")
                            .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(hover ? Theme.textLo : .clear)
                }

                HStack(spacing: 0) {
                    statTile("\(doc.open)", "Open", bright: doc.open > 0)
                    statDivider
                    statTile("\(doc.done)", "Done")
                    statDivider
                    statTile("\(doc.overdue)", "Overdue", bright: doc.overdue > 0)
                }

                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.chipBg)
                            Capsule().fill(Theme.accent)
                                .frame(width: max(5, geo.size.width * doc.progress))
                        }
                    }
                    .frame(height: 5)
                    Text("\(Int(doc.progress * 100))% complete")
                        .font(.system(size: 10)).foregroundColor(Theme.textFaint)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(hover ? Theme.panelHi : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hover ? Theme.textFaint.opacity(0.4) : Theme.stroke, lineWidth: 1))
            .craftShadow(radius: hover ? 20 : 10, y: hover ? 8 : 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.12)) { hover = isHovering } }
    }

    var statDivider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1, height: 30)
    }

    func statTile(_ n: String, _ label: String, bright: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(bright ? Theme.textHi : Theme.textLo)
            Text(label).font(.system(size: 10)).foregroundColor(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rename a document's *display name only* — Craft's own title (and its
/// document ID) are untouched and kept internally so the mapping survives
/// even if the document is later renamed on the Craft side.
struct RenameViewPopover: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let filter: TaskFilter
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("View name").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textHi)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 250)
        .onAppear { name = filter.name }
    }

    private func save() {
        store.renameFilter(filter.id, to: name)
        dismiss()
    }
}

struct RenameDocumentPopover: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let doc: DocumentSummary
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display name").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textHi)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(save)
            if doc.title != doc.craftTitle {
                Text("Craft: \(doc.craftTitle)")
                    .font(.system(size: 10)).foregroundColor(Theme.textFaint)
            }
            HStack {
                if doc.title != doc.craftTitle {
                    Button("Reset") { store.setDisplayName(id: doc.id, name: nil); dismiss() }
                        .font(.system(size: 11))
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 250)
        .onAppear { name = doc.title }
    }

    private func save() {
        store.setDisplayName(id: doc.id, name: name)
        dismiss()
    }
}
