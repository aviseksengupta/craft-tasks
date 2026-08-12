import Foundation
import SwiftUI

struct DocumentSummary: Identifiable {
    let id: String            // documentId or "inbox"
    let title: String         // display name (user override, else Craft title)
    let craftTitle: String    // live title as it currently is in Craft
    let open: Int
    let done: Int
    let canceled: Int
    let overdue: Int
    var total: Int { open + done + canceled }
    var progress: Double { total == 0 ? 0 : Double(done + canceled) / Double(total) }
}

@MainActor
final class Store: ObservableObject {
    @Published var tasks: [CraftTask] = []
    @Published var filter = TaskFilter()
    @Published var savedFilters: [TaskFilter] = []
    @Published var dashboards: [Dashboard] = []
    /// What "Home" points to. Any pinnable destination — a saved view, a
    /// dashboard, or one of the built-in sections (All Tasks, Today, This
    /// Week, Documents, Views) — can be Home. nil falls back to the
    /// classic "open tasks" default.
    @Published var homeSection: Section?
    /// Per-item visibility for the top sidebar nav row, keyed by NavItemDef.id.
    /// Missing entries default to .shown.
    @Published var itemVisibility: [String: ItemVisibility] = [:]
    @Published var syncing = false
    @Published var lastSync: Date?
    @Published var lastSyncSummary: String = ""
    @Published var syncError: String?
    @Published var pendingCount = 0
    @Published var pendingCreateCount = 0
    var totalPendingCount: Int { pendingCount + pendingCreateCount }
    @Published var showCompleted: Bool = UserDefaults.standard.object(forKey: "showCompleted") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showCompleted, forKey: "showCompleted") }
    }
    @Published var todayIncludesOverdue: Bool = UserDefaults.standard.object(forKey: "todayIncludesOverdue") as? Bool ?? false {
        didSet { UserDefaults.standard.set(todayIncludesOverdue, forKey: "todayIncludesOverdue") }
    }
    /// Global search, deliberately NOT part of TaskFilter: every nav action
    /// (Home, All Tasks, clicking a document, …) rebuilds `filter` from
    /// scratch, which was silently wiping out anything typed here. Living
    /// on the Store instead means it survives navigation and applies
    /// uniformly everywhere tasks are shown — including dashboard widgets.
    @Published var searchText: String = ""
    /// documentId ("inbox" for the inbox) -> user-chosen display name.
    /// The Craft-side title (CraftTask.documentTitle) is always kept as-is
    /// internally and used as the fallback / reset value.
    @Published var documentDisplayNames: [String: String] = [:]
    /// Needed to build "open in Craft" deep links; nil until fetched (once,
    /// then cached — Craft doesn't expose it via /tasks).
    @Published var spaceId: String? = UserDefaults.standard.string(forKey: "craftSpaceId") {
        didSet { UserDefaults.standard.set(spaceId, forKey: "craftSpaceId") }
    }

    private let db = Database()
    private var timer: Timer?

    var allTags: [String] {
        var counts: [String: Int] = [:]
        for t in tasks { for tag in t.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }

    /// Resolves the display name for a document/inbox key, falling back to
    /// the live Craft title until the user renames it.
    func displayName(id: String, craftTitle: String) -> String {
        documentDisplayNames[id] ?? craftTitle
    }

    func setDisplayName(id: String, name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            documentDisplayNames[id] = trimmed
        } else {
            documentDisplayNames.removeValue(forKey: id)
        }
        persistFilters()
    }

    var documents: [DocumentSummary] {
        var groups: [String: (title: String, tasks: [CraftTask])] = [:]
        let today = Calendar.current.startOfDay(for: Date())
        for t in tasks {
            let key = t.locationType == "inbox" ? "inbox" : (t.documentId ?? "unknown")
            groups[key, default: (t.sourceName, [])].tasks.append(t)
        }
        return groups.map { key, g in
            DocumentSummary(
                id: key, title: displayName(id: key, craftTitle: g.title), craftTitle: g.title,
                open: g.tasks.filter { $0.state == .todo }.count,
                done: g.tasks.filter { $0.state == .done }.count,
                canceled: g.tasks.filter { $0.state == .canceled }.count,
                overdue: g.tasks.filter { $0.state == .todo && ($0.scheduleDay ?? $0.deadlineDay).map { $0 < today } == true }.count)
        }.sorted { $0.open == $1.open ? $0.title < $1.title : $0.open > $1.open }
    }

    var filtered: [CraftTask] { apply(filter) }

    /// Filter + sort used everywhere (main list and dashboard sections).
    func apply(_ f: TaskFilter) -> [CraftTask] {
        tasks.filter {
            f.matches($0, todayIncludesOverdue: todayIncludesOverdue) && (showCompleted || $0.state == .todo)
                && (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText))
        }.sorted(by: Self.taskSort)
    }

    // open first, then by date (soonest), undated last, then title
    static func taskSort(_ a: CraftTask, _ b: CraftTask) -> Bool {
        if a.state != b.state { return a.state == .todo }
        let da = a.scheduleDay ?? a.deadlineDay
        let dbb = b.scheduleDay ?? b.deadlineDay
        switch (da, dbb) {
        case let (x?, y?): if x != y { return x < y }
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.state == .done, let ca = a.completedDay, let cb = b.completedDay, ca != cb { return ca > cb }
        return a.displayTitle < b.displayTitle
    }

    /// Groups already-filtered tasks by the given criterion, preserving order.
    /// Instance method (not static) so `.document` grouping can resolve
    /// each document's user-chosen display name.
    func group(_ tasks: [CraftTask], by g: GroupBy) -> [(String, [CraftTask])] {
        func dateBucket(_ d: Date?, isOpen: Bool) -> String {
            guard let d else { return "No date" }
            let today = Calendar.current.startOfDay(for: Date())
            if d < today { return isOpen ? "Overdue" : "Earlier" }
            if Calendar.current.isDateInToday(d) { return "Today" }
            if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
            if let end = Calendar.current.date(byAdding: .day, value: 7, to: today), d <= end { return "Next 7 days" }
            return "Later"
        }
        let bucketOrder = ["Overdue", "Earlier", "Today", "Tomorrow", "Next 7 days", "Later", "No date"]

        var order: [String] = []
        var map: [String: [CraftTask]] = [:]
        for t in tasks {
            let key: String
            switch g {
            case .document:
                let docKey = t.locationType == "inbox" ? "inbox" : (t.documentId ?? "unknown")
                key = displayName(id: docKey, craftTitle: t.sourceName)
            case .tag:
                let tags = t.tags.sorted()
                key = tags.isEmpty ? "No tags" : tags.map { "#\($0)" }.joined(separator: "  ")
            case .schedule: key = dateBucket(t.scheduleDay, isOpen: t.state == .todo)
            case .deadline: key = dateBucket(t.deadlineDay, isOpen: t.state == .todo)
            case .state: key = t.state.label
            }
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(t)
        }
        switch g {
        case .schedule, .deadline:
            order.sort { (bucketOrder.firstIndex(of: $0) ?? 99) < (bucketOrder.firstIndex(of: $1) ?? 99) }
        case .tag:
            order.sort { a, b in
                if a == "No tags" { return false }
                if b == "No tags" { return true }
                return a < b
            }
        case .state:
            let so = ["Open", "Done", "Canceled"]
            order.sort { (so.firstIndex(of: $0) ?? 9) < (so.firstIndex(of: $1) ?? 9) }
        case .document: break
        }
        return order.map { ($0, map[$0]!) }
    }

    // MARK: navigation — each call sets the filter explicitly so it can
    // never be clobbered by an unrelated view's default (see openDocument).

    /// The plain "open tasks" fallback used when Home has no target set.
    func selectHome() {
        var f = TaskFilter(); f.states = [.todo]; filter = f
    }

    /// Resolves where clicking "Home" actually navigates to, applying that
    /// destination's filter as a side effect where relevant, and falling
    /// back to the plain open-tasks default if the target was deleted.
    func navigateHome() -> Section {
        switch homeSection {
        case .saved(let id):
            guard let f = savedFilters.first(where: { $0.id == id }) else { selectHome(); return .home }
            filter = f
            return .saved(id)
        case .dashboard(let id):
            guard dashboards.contains(where: { $0.id == id }) else { selectHome(); return .home }
            return .dashboard(id)
        case .allTasks: selectAllTasks(); return .allTasks
        case .inbox: selectInbox(); return .inbox
        case .today: selectToday(); return .today
        case .thisWeek: selectThisWeek(); return .thisWeek
        case .documents: return .documents
        case .views: return .views
        case .home, nil: selectHome(); return .home
        }
    }

    func selectAllTasks() {
        var f = TaskFilter(); f.states = []; filter = f
    }

    func selectToday() { filter = todayFilter }
    func selectThisWeek() { filter = thisWeekFilter }
    func selectInbox() { filter = inboxFilter }

    func selectSaved(_ id: UUID) {
        if let f = savedFilters.first(where: { $0.id == id }) { filter = f }
    }

    /// Jump to All Tasks pre-filtered to one document (from the Documents grid).
    func openDocument(id: String) {
        var f = TaskFilter(); f.states = []; f.documentIds = [id]
        filter = f
    }

    /// One-click state cycle from any list row; pushes like a normal edit.
    func cycleState(_ task: CraftTask) {
        let next: TaskState
        switch task.state {
        case .todo: next = .done
        case .done: next = .canceled
        case .canceled: next = .todo
        }
        applyEdit(to: task, body: task.markdownParts.body, state: next,
                  scheduleDate: task.scheduleDate, deadlineDate: task.deadlineDate)
    }

    init() {
        tasks = db.loadAll()
        pendingCount = db.pendingUpdates().count
        pendingCreateCount = db.pendingCreates().count
        if let s = db.getMeta("lastSync") { lastSync = ISO8601DateFormatter().date(from: s) }
        loadFilters()
        Task { await sync() }
        if spaceId == nil { Task { spaceId = try? await SyncEngine.fetchSpaceId() } }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.sync() }
        }
    }

    func sync() async {
        guard !syncing else { return }
        syncing = true
        syncError = nil
        defer { syncing = false }
        // Push queued local edits and new tasks before pulling, so a slow
        // or offline moment never gets clobbered by the next sync's data —
        // this is what makes "add a task while offline" work reliably.
        await flushPending()
        await flushPendingCreates()
        do {
            // Also protect any create that's STILL queued (still offline)
            // from being swept up as "gone" by the diff below.
            let pendingIds = Set(db.pendingUpdates().map(\.taskId))
                .union(db.pendingCreates().map(\.localId))
            let r = try await SyncEngine.fetchAndDiff(db: db, skipping: pendingIds)
            if !r.unchanged { tasks = db.loadAll() }
            lastSync = Date()
            lastSyncSummary = r.unchanged
                ? "Up to date · \(r.total) tasks"
                : "+\(r.added) · ~\(r.updated) · −\(r.removed) · \(r.total) tasks"
        } catch {
            syncError = Self.describe(error)
        }
    }

    /// Prefers Craft's own error message when available (e.g. "Cannot
    /// modify document in trash") over a generic "Offline" label — a
    /// permanent rejection isn't a connectivity problem and saying so was
    /// actively misleading (repeatedly retrying it never helped).
    static func describe(_ error: Error) -> String {
        (error as? SyncError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: creating

    /// Creates a task: it appears locally immediately (optimistic, with a
    /// temporary "local-…" id) and is pushed to Craft right away in the
    /// background. If that push fails — no internet, Craft unreachable —
    /// the create is queued in the same durable outbox pattern as edits and
    /// is retried before every subsequent sync, so adding tasks works the
    /// same whether or not you're online. Never throws: from the caller's
    /// perspective, creating a task always "succeeds" immediately.
    func createTask(title: String, tags: [String], scheduleDate: String?,
                     deadlineDate: String?, documentId: String?) {
        let tagSuffix = tags.isEmpty ? "" : " " + tags.map { "#\($0)" }.joined(separator: " ")
        let markdown = "- [ ] " + title.trimmingCharacters(in: .whitespacesAndNewlines) + tagSuffix
        let location: [String: Any] = documentId.map { ["type": "document", "documentId": $0] } ?? ["type": "inbox"]

        let localId = "local-\(UUID().uuidString)"
        let optimistic = CraftTask(
            id: localId, markdown: markdown, state: .todo,
            scheduleDate: scheduleDate, deadlineDate: deadlineDate,
            locationType: documentId == nil ? "inbox" : "document",
            documentId: documentId,
            documentTitle: documentId.flatMap { id in documents.first { $0.id == id }?.title },
            completedAt: nil, hash: "pending-create")
        db.upsert(optimistic)
        tasks = db.loadAll()

        var payload: [String: Any] = ["markdown": markdown, "location": location]
        var taskInfo: [String: Any] = [:]
        if let scheduleDate { taskInfo["scheduleDate"] = scheduleDate }
        if let deadlineDate { taskInfo["deadlineDate"] = deadlineDate }
        if !taskInfo.isEmpty { payload["taskInfo"] = taskInfo }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            db.enqueuePendingCreate(localId: localId, payload: json)
        }
        pendingCreateCount = db.pendingCreates().count
        Task { await flushPendingCreates() }
    }

    /// Pushes queued new-task creations to Craft, replacing each local
    /// temp-id row with the real server-issued task once it succeeds.
    /// Creations that still fail (offline) stay queued for the next call —
    /// this runs before every sync, so they're retried automatically.
    func flushPendingCreates() async {
        let pending = db.pendingCreates()
        pendingCreateCount = pending.count
        guard !pending.isEmpty else { return }
        for item in pending {
            guard let data = item.payload.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let markdown = dict["markdown"] as? String,
                  let location = dict["location"] as? [String: Any] else {
                db.removePendingCreate(localId: item.localId)
                continue
            }
            let ti = dict["taskInfo"] as? [String: Any] ?? [:]
            do {
                let created = try await SyncEngine.createTask(
                    markdown: markdown, location: location,
                    scheduleDate: ti["scheduleDate"] as? String, deadlineDate: ti["deadlineDate"] as? String)
                db.delete(ids: [item.localId])
                db.upsert(created)
                db.removePendingCreate(localId: item.localId)
            } catch {
                // Stays queued either way, but only report it as blocked
                // (vs. silently retrying) when it's a permanent rejection —
                // same reasoning as flushPending() above.
                if (error as? SyncError)?.isLikelyTransient == false {
                    syncError = "New task can't sync: \(Self.describe(error))"
                }
            }
        }
        tasks = db.loadAll()
        pendingCreateCount = db.pendingCreates().count
    }

    /// Where an edit should move a task to. .unchanged (the default) never
    /// sends a location, so every call site that doesn't care about moving
    /// tasks (checkbox cycle, etc.) is unaffected; .inbox / .document(id)
    /// explicitly relocate it.
    enum TaskDestination {
        case unchanged
        case inbox
        case document(String)
    }

    /// Applies an edit locally (optimistic), queues it, and pushes to Craft
    /// immediately. If Craft is unreachable the edit stays queued and is
    /// flushed before the next sync.
    func applyEdit(to task: CraftTask, body: String, state: TaskState,
                   scheduleDate: String?, deadlineDate: String?,
                   destination: TaskDestination = .unchanged) {
        let newMarkdown = task.markdownParts.rebuilt(body: body, state: state)

        var locationType = task.locationType
        var documentId = task.documentId
        var documentTitle = task.documentTitle
        var locationPayload: [String: Any]?
        switch destination {
        case .unchanged:
            break
        case .inbox:
            locationType = "inbox"; documentId = nil; documentTitle = nil
            locationPayload = ["type": "inbox"]
        case .document(let id):
            locationType = "document"; documentId = id
            documentTitle = documents.first { $0.id == id }?.title ?? task.documentTitle
            locationPayload = ["type": "document", "documentId": id]
        }

        let updated = CraftTask(
            id: task.id, markdown: newMarkdown, state: state,
            scheduleDate: scheduleDate, deadlineDate: deadlineDate,
            locationType: locationType, documentId: documentId,
            documentTitle: documentTitle,
            completedAt: state == .todo ? nil : task.completedAt,
            hash: "dirty")   // forces refresh from server after push
        db.upsert(updated)
        tasks = db.loadAll()

        var payload: [String: Any] = [
            "id": task.id,
            "markdown": newMarkdown,
            "taskInfo": [
                "state": state.rawValue,
                "scheduleDate": scheduleDate as Any? ?? NSNull(),
                "deadlineDate": deadlineDate as Any? ?? NSNull(),
            ],
        ]
        if let locationPayload { payload["location"] = locationPayload }
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            db.enqueuePending(taskId: task.id, payload: json)
        }
        pendingCount = db.pendingUpdates().count
        Task { await flushPending() }
    }

    func flushPending() async {
        let pending = db.pendingUpdates()
        pendingCount = pending.count
        guard !pending.isEmpty else { return }
        let payloads = pending.compactMap { item -> [String: Any]? in
            guard let data = item.payload.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        do {
            try await SyncEngine.pushUpdates(payloads)
            db.removePending(taskIds: pending.map(\.taskId))
            pendingCount = 0
        } catch {
            let reason = Self.describe(error)
            syncError = (error as? SyncError)?.isLikelyTransient == false
                ? "\(pending.count) change(s) can't sync: \(reason)"
                : "Offline — \(pending.count) change(s) queued"
        }
    }

    /// Deletes a task from Craft synchronously, then removes it locally only
    /// once Craft confirms — deliberately not queued, unlike edits/creates,
    /// so a delete never silently "succeeds" locally while still pending.
    func deleteTask(_ task: CraftTask) async throws {
        try await SyncEngine.deleteTask(id: task.id)
        db.delete(ids: [task.id])
        db.removePending(taskIds: [task.id])
        tasks = db.loadAll()
        pendingCount = db.pendingUpdates().count
    }

    // MARK: saved filters persistence
    private var filtersURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftTasks/filters.json")
    }

    private var filtersBackupURL: URL { filtersURL.appendingPathExtension("bak") }

    private struct FiltersFile: Codable {
        var filters: [TaskFilter]
        var homeId: UUID?        // legacy: home was always a saved view
        var homeSection: Section?
        var dashboards: [Dashboard]?
        var documentDisplayNames: [String: String]?
        var itemVisibility: [String: ItemVisibility]?
    }

    private func loadFilters() {
        if let data = try? Data(contentsOf: filtersURL),
           let f = try? JSONDecoder().decode(FiltersFile.self, from: data) {
            applyFiltersFile(f)
        } else if let data = try? Data(contentsOf: filtersBackupURL),
                  let f = try? JSONDecoder().decode(FiltersFile.self, from: data) {
            // Primary file missing or failed to parse — fall back to the
            // last-known-good backup rather than silently starting empty
            // (which would then get persisted over the primary, destroying
            // it for good). Re-save immediately so the backup becomes primary.
            NSLog("CraftTasks: filters.json failed to load, recovered \(f.filters.count) view(s) from backup")
            applyFiltersFile(f)
            persistFilters()
        } else if FileManager.default.fileExists(atPath: filtersURL.path) {
            NSLog("CraftTasks: filters.json exists but failed to decode, and no usable backup was found")
        }
        migrateSeedOutOfSavedViews()
    }

    private func applyFiltersFile(_ f: FiltersFile) {
        savedFilters = f.filters
        dashboards = f.dashboards ?? []
        documentDisplayNames = f.documentDisplayNames ?? [:]
        itemVisibility = f.itemVisibility ?? [:]
        if let hs = f.homeSection {
            homeSection = hs
        } else if let legacyId = f.homeId {
            homeSection = .saved(legacyId)
        }
    }

    /// One-time cleanup: an earlier build seeded "Today"/"This Week" into
    /// savedFilters. They now live as pinned sidebar items instead (see
    /// todayFilter/thisWeekFilter below), so strip any leftover copies.
    private func migrateSeedOutOfSavedViews() {
        let key = "removedSeedFromSavedViewsV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let before = savedFilters.count
        savedFilters.removeAll { $0.name == "Today" || $0.name == "This Week" }
        if savedFilters.count != before { persistFilters() }
    }

    /// Built-in views, always available, never persisted or shown as a
    /// deletable saved view — pinned in the sidebar between All Tasks and
    /// Documents.
    var todayFilter: TaskFilter {
        var f = TaskFilter(name: "Today")
        f.states = [.todo]; f.dateField = .any; f.dateScope = .today
        return f
    }
    var thisWeekFilter: TaskFilter {
        var f = TaskFilter(name: "This Week")
        f.states = [.todo]; f.dateField = .any; f.dateScope = .next7
        return f
    }
    var inboxFilter: TaskFilter {
        var f = TaskFilter(name: "Inbox")
        f.states = [.todo]; f.documentIds = ["inbox"]
        return f
    }

    private func persistFilters() {
        let f = FiltersFile(filters: savedFilters, homeId: nil, homeSection: homeSection, dashboards: dashboards,
                            documentDisplayNames: documentDisplayNames, itemVisibility: itemVisibility)
        guard let data = try? JSONEncoder().encode(f) else { return }
        // Roll the current file to a backup *before* overwriting it, so a
        // future decode regression (like the one that caused this) can be
        // recovered from on next launch instead of being unrecoverable.
        if FileManager.default.fileExists(atPath: filtersURL.path) {
            try? FileManager.default.removeItem(at: filtersBackupURL)
            try? FileManager.default.copyItem(at: filtersURL, to: filtersBackupURL)
        }
        try? data.write(to: filtersURL)
    }

    // MARK: backup / restore — a single JSON document capturing everything
    // needed to recreate the app's state (views, dashboards, pinned items,
    // renamed docs, visibility settings). Mirrors the web app's export
    // schema so a config exported from one app can be imported into the
    // other. Deliberately excludes cached tasks, which come from Craft.
    static let backupSchemaVersion = 1

    struct AppBackup: Codable {
        var schemaVersion: Int
        var exportedAt: String
        var apiBase: String?
        var showCompleted: Bool
        var config: BackupConfig
    }

    struct BackupConfig: Codable {
        var filters: [TaskFilter]
        var homeSection: Section?
        var dashboards: [Dashboard]
        var documentDisplayNames: [String: String]
        var itemVisibility: [String: ItemVisibility]
    }

    static let defaultBackup = AppBackup(
        schemaVersion: backupSchemaVersion, exportedAt: "", apiBase: nil, showCompleted: true,
        config: BackupConfig(filters: [], homeSection: nil, dashboards: [], documentDisplayNames: [:], itemVisibility: [:]))

    func buildBackup() -> AppBackup {
        let iso = ISO8601DateFormatter().string(from: Date())
        return AppBackup(
            schemaVersion: Self.backupSchemaVersion, exportedAt: iso,
            apiBase: SyncEngine.apiBase, showCompleted: showCompleted,
            config: BackupConfig(filters: savedFilters, homeSection: homeSection, dashboards: dashboards,
                                  documentDisplayNames: documentDisplayNames, itemVisibility: itemVisibility))
    }

    func exportBackupJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(buildBackup()) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func applyBackup(_ backup: AppBackup) {
        savedFilters = backup.config.filters
        dashboards = backup.config.dashboards
        documentDisplayNames = backup.config.documentDisplayNames
        itemVisibility = backup.config.itemVisibility
        homeSection = backup.config.homeSection
        showCompleted = backup.showCompleted
        persistFilters()
    }

    func restoreBackup(fromJSON json: String) throws {
        let data = Data(json.utf8)
        let backup = try JSONDecoder().decode(AppBackup.self, from: data)
        applyBackup(backup)
    }

    func restoreDefaultConfig() {
        applyBackup(Self.defaultBackup)
    }

    func setItemVisibility(_ id: String, _ v: ItemVisibility) {
        itemVisibility[id] = v
        persistFilters()
    }

    func saveDashboard(name: String, viewIds: [UUID]) {
        dashboards.append(Dashboard(name: name, widgets: viewIds.map { DashboardWidget(viewId: $0) }))
        persistFilters()
    }

    func deleteDashboard(_ id: UUID) {
        dashboards.removeAll { $0.id == id }
        if homeSection == .dashboard(id) { homeSection = nil }
        persistFilters()
    }

    /// Adds saved views to an existing dashboard as new medium widgets,
    /// skipping any already present.
    func addWidgets(viewIds: [UUID], to dashboardId: UUID) {
        guard let idx = dashboards.firstIndex(where: { $0.id == dashboardId }) else { return }
        let existing = Set(dashboards[idx].widgets.map(\.viewId))
        let toAdd = viewIds.filter { !existing.contains($0) }
        dashboards[idx].widgets.append(contentsOf: toAdd.map { DashboardWidget(viewId: $0) })
        persistFilters()
    }

    func removeWidget(_ widgetId: UUID, from dashboardId: UUID) {
        guard let idx = dashboards.firstIndex(where: { $0.id == dashboardId }) else { return }
        dashboards[idx].widgets.removeAll { $0.id == widgetId }
        persistFilters()
    }

    func setWidgetDimensions(_ widgetId: UUID, widthUnits: Int, heightUnits: Int, in dashboardId: UUID) {
        guard let dIdx = dashboards.firstIndex(where: { $0.id == dashboardId }),
              let wIdx = dashboards[dIdx].widgets.firstIndex(where: { $0.id == widgetId }) else { return }
        dashboards[dIdx].widgets[wIdx].widthUnits = widthUnits
        dashboards[dIdx].widgets[wIdx].heightUnits = heightUnits
        persistFilters()
    }

    /// Reorders widgets by moving the dragged one to sit where the target
    /// one is — drag-and-drop repositioning on the dashboard grid.
    func moveWidget(_ draggedId: UUID, to targetId: UUID, in dashboardId: UUID) {
        guard let dIdx = dashboards.firstIndex(where: { $0.id == dashboardId }),
              let from = dashboards[dIdx].widgets.firstIndex(where: { $0.id == draggedId }),
              let to = dashboards[dIdx].widgets.firstIndex(where: { $0.id == targetId }),
              from != to else { return }
        let item = dashboards[dIdx].widgets.remove(at: from)
        dashboards[dIdx].widgets.insert(item, at: to)
        persistFilters()
    }

    func saveCurrentFilter(named name: String) {
        var f = filter
        f.id = UUID()
        f.name = name
        savedFilters.append(f)
        persistFilters()
    }

    /// Overwrites an existing saved view's criteria with the current filter,
    /// keeping its id and name. Used when the current view IS a saved view
    /// (or Home, when Home points at one) — creating a brand-new view is
    /// only offered from All Tasks.
    func updateSavedFilter(_ id: UUID) {
        guard let idx = savedFilters.firstIndex(where: { $0.id == id }) else { return }
        var updated = filter
        updated.id = id
        updated.name = savedFilters[idx].name
        updated.pinned = savedFilters[idx].pinned
        savedFilters[idx] = updated
        persistFilters()
    }

    func togglePinned(_ id: UUID) {
        guard let idx = savedFilters.firstIndex(where: { $0.id == id }) else { return }
        savedFilters[idx].pinned = !(savedFilters[idx].pinned ?? false)
        persistFilters()
    }

    func renameFilter(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = savedFilters.firstIndex(where: { $0.id == id }) else { return }
        savedFilters[idx].name = trimmed
        persistFilters()
    }

    func deleteFilter(_ id: UUID) {
        savedFilters.removeAll { $0.id == id }
        for i in dashboards.indices { dashboards[i].widgets.removeAll { $0.viewId == id } }
        if homeSection == .saved(id) { homeSection = nil }
        persistFilters()
    }

    /// Sets or clears what Home points to. Pass the same target again to
    /// unset it (toggle behavior used by every "Set/Unset as Home" menu item).
    func setHomeTarget(_ target: Section) {
        homeSection = (homeSection == target) ? nil : target
        persistFilters()
    }

    func isHomeTarget(_ target: Section) -> Bool { homeSection == target }
}
