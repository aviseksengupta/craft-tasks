import Foundation
import CryptoKit

enum TaskState: String, Codable, CaseIterable {
    case todo, done, canceled

    var label: String {
        switch self {
        case .todo: return "Open"
        case .done: return "Done"
        case .canceled: return "Canceled"
        }
    }
}

struct CraftTask: Identifiable, Codable, Equatable {
    let id: String
    let markdown: String
    let state: TaskState
    let scheduleDate: String?      // "yyyy-MM-dd"
    let deadlineDate: String?      // "yyyy-MM-dd"
    let locationType: String       // "document" | "inbox" | "dailyNote"
    let documentId: String?
    let documentTitle: String?
    let completedAt: String?       // ISO8601
    let hash: String

    // Derived
    var title: String {
        var s = markdown
        // strip craft wrapper tags like <callout>, </callout>
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // strip checkbox prefix
        s = s.replacingOccurrences(of: #"^\s*-\s*\[[ xX-]?\]\s*"#, with: "", options: .regularExpression)
        // strip tags for display title? keep them inline but we also expose tags separately
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayTitle: String {
        var s = title
        s = s.replacingOccurrences(of: #"\s*#[\w/\-]+"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? title : s
    }

    var tags: [String] {
        let re = try! NSRegularExpression(pattern: "#([\\w/\\-]+)")
        let ns = title as NSString
        return re.matches(in: title, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).lowercased() }
    }

    var sourceName: String {
        if locationType == "inbox" { return "Inbox" }
        return documentTitle ?? "Untitled"
    }

    /// Whether this task carries the configured backlog/"later" tag, e.g. #later.
    func isBacklog(tag: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !t.isEmpty && tags.contains(t)
    }

    /// Deep link to open this task's own block in the Craft app, via the
    /// craftdocs:// URL scheme — lands on the task itself (including inside
    /// a nested subpage), not just the top of its containing document. nil
    /// for inbox tasks or before the space id (fetched via
    /// SyncEngine.fetchSpaceId) is known.
    func craftDeepLink(spaceId: String?) -> URL? {
        guard let spaceId, locationType != "inbox" else { return nil }
        return URL(string: "craftdocs://open?spaceId=\(spaceId)&blockId=\(id)")
    }

    var effectiveDate: String? { scheduleDate ?? deadlineDate }

    var scheduleDay: Date? { Self.day(scheduleDate) }
    var deadlineDay: Date? { Self.day(deadlineDate) }
    var completedDay: Date? {
        guard let c = completedAt else { return nil }
        return ISO8601DateFormatter.withFraction.date(from: c) ?? ISO8601DateFormatter().date(from: c)
    }

    static func day(_ s: String?) -> Date? {
        guard let s else { return nil }
        return DateFormatter.ymd.date(from: s)
    }

    /// Splits raw markdown into wrapper prefix (e.g. "<callout>"), checkbox
    /// prefix ("- [ ] "), editable body, and wrapper suffix, so edits can
    /// rewrite the body while preserving Craft's structural tags.
    struct MarkdownParts {
        var pre: String
        var check: String
        var body: String
        var post: String

        func rebuilt(body newBody: String, state: TaskState) -> String {
            var c = check
            if !c.isEmpty {
                let mark = state == .done ? "x" : (state == .canceled ? "-" : " ")
                c = c.replacingOccurrences(of: #"\[[ xX-]?\]"#, with: "[\(mark)]", options: .regularExpression)
            }
            return pre + c + newBody + post
        }
    }

    var markdownParts: MarkdownParts {
        let pattern = #"^(?<pre>(?:<[^>]+>\s*)*)(?<check>-\s*\[[ xX-]?\]\s*)?(?<body>[\s\S]*?)(?<post>(?:\s*</[^>]+>)*)$"#
        let re = try! NSRegularExpression(pattern: pattern)
        let ns = markdown as NSString
        guard let m = re.firstMatch(in: markdown, range: NSRange(location: 0, length: ns.length)) else {
            return MarkdownParts(pre: "", check: "", body: markdown, post: "")
        }
        func g(_ name: String) -> String {
            let r = m.range(withName: name)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        return MarkdownParts(pre: g("pre"), check: g("check"), body: g("body"), post: g("post"))
    }

    static func computeHash(json: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension DateFormatter {
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Filters

enum DateScope: String, Codable, CaseIterable, Identifiable {
    case any = "Any"
    case today = "Today"
    case overdue = "Overdue"
    case next7 = "Next 7 days"
    case thisMonth = "This month"
    case noDate = "No date"
    var id: String { rawValue }
}

/// Which of a task's two dates a DateScope filters against.
enum DateField: String, Codable, CaseIterable, Identifiable {
    case any = "Any date"        // scheduled, falling back to deadline
    case scheduled = "Scheduled"
    case deadline = "Deadline"
    var id: String { rawValue }
}

/// How a view lays out its groups: stacked one under another, or side by
/// side as kanban-style columns (one column per group).
enum ViewLayout: String, Codable, CaseIterable, Identifiable {
    case stacked = "Stacked"
    case kanban = "Kanban"
    var id: String { rawValue }
}

/// How a top-level sidebar nav item (Home, All Tasks, Inbox, …) is shown.
enum ItemVisibility: String, Codable, CaseIterable, Identifiable {
    case shown = "Always shown"
    case hidden = "Hidden"       // tucked behind the "More" disclosure
    case invisible = "Invisible" // not shown anywhere
    var id: String { rawValue }
}

enum GroupBy: String, Codable, CaseIterable, Identifiable {
    case document = "Document"
    case tag = "Tag"
    case schedule = "Scheduled"
    case deadline = "Deadline"
    case state = "State"
    var id: String { rawValue }
}

/// A dashboard widget's footprint on the grid, in grid units. Five standard
/// sizes — no free-form resize, so the grid always packs cleanly.
enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small = "Small"      // 1 col x 1 row
    case medium = "Medium"    // 2 col x 1 row
    case wide = "Wide"        // 3 col x 1 row
    case tall = "Tall"        // 1 col x 2 rows
    case large = "Large"      // 2 col x 2 rows
    case xlarge = "Extra Large"  // 3 col x 2 rows — large AND wide
    var id: String { rawValue }

    var colSpan: Int {
        switch self {
        case .small, .tall: return 1
        case .medium, .large: return 2
        case .wide, .xlarge: return 3
        }
    }
    var rowSpan: Int {
        switch self {
        case .tall, .large, .xlarge: return 2
        default: return 1
        }
    }
    var icon: String {
        switch self {
        case .small: return "square"
        case .medium: return "rectangle"
        case .wide: return "rectangle.arrowtriangle.2.outward"
        case .tall: return "rectangle.portrait"
        case .large: return "square.grid.2x2"
        case .xlarge: return "rectangle.grid.2x2"
        }
    }
}

/// One saved view placed on a dashboard's grid. Size is free-form (grid
/// units on a 6-column, ~110pt-row grid), set by dragging the widget's
/// resize handle rather than picking from fixed presets.
struct DashboardWidget: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var viewId: UUID
    var widthUnits: Int = 4   // ~ old "Medium"
    var heightUnits: Int = 2  // ~ one row

    init(id: UUID = UUID(), viewId: UUID, widthUnits: Int = 4, heightUnits: Int = 2) {
        self.id = id
        self.viewId = viewId
        self.widthUnits = widthUnits
        self.heightUnits = heightUnits
    }

    // Custom Codable so dashboards saved by the earlier (fixed WidgetSize)
    // version of this app still load, migrated onto the new finer grid.
    private enum CodingKeys: String, CodingKey { case id, viewId, widthUnits, heightUnits, size }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        viewId = try c.decode(UUID.self, forKey: .viewId)
        if let w = try? c.decode(Int.self, forKey: .widthUnits),
           let h = try? c.decode(Int.self, forKey: .heightUnits) {
            widthUnits = w
            heightUnits = h
        } else if let legacy = try? c.decode(WidgetSize.self, forKey: .size) {
            widthUnits = legacy.colSpan * 2
            heightUnits = legacy.rowSpan * 2
        } else {
            widthUnits = 4
            heightUnits = 2
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(viewId, forKey: .viewId)
        try c.encode(widthUnits, forKey: .widthUnits)
        try c.encode(heightUnits, forKey: .heightUnits)
    }
}

/// A dashboard is a drag-and-droppable grid of freely resizable widgets,
/// each one a saved view — not a stacked or kanban list.
struct Dashboard: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var widgets: [DashboardWidget] = []
    var pinned: Bool? = nil       // shows in the sidebar; nil == false, same convention as TaskFilter.pinned
    var order: Int? = nil         // position within the Dashboards page; nil sorts as 0
    var pinnedOrder: Int? = nil   // separate scale from `order` — pinned section mixes views+dashboards
    var sectionId: UUID? = nil    // reserved for future section grouping; unused for now

    init(id: UUID = UUID(), name: String, widgets: [DashboardWidget], pinned: Bool? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.pinned = pinned
        self.order = order
    }

    // Custom Codable so dashboards saved by the earlier (viewIds + layout)
    // version of this app still load, migrated into one medium widget per view.
    private enum CodingKeys: String, CodingKey { case id, name, widgets, viewIds, pinned, order, pinnedOrder, sectionId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let w = try? c.decode([DashboardWidget].self, forKey: .widgets) {
            widgets = w
        } else if let legacyIds = try? c.decode([UUID].self, forKey: .viewIds) {
            widgets = legacyIds.map { DashboardWidget(viewId: $0) }
        } else {
            widgets = []
        }
        pinned = try? c.decode(Bool?.self, forKey: .pinned)
        order = try? c.decode(Int?.self, forKey: .order)
        pinnedOrder = try? c.decode(Int?.self, forKey: .pinnedOrder)
        sectionId = try? c.decode(UUID?.self, forKey: .sectionId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(widgets, forKey: .widgets)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(order, forKey: .order)
        try c.encode(pinnedOrder, forKey: .pinnedOrder)
        try c.encode(sectionId, forKey: .sectionId)
    }
}

// MARK: - Tag Colors

struct TagColorsConfig: Codable, Equatable {
    var tagColors: [String: String] = [:]  // tag name → hex color (e.g. "FF5733")

    subscript(tag: String) -> String? {
        get { tagColors[tag.lowercased()] }
        set {
            if let value = newValue {
                tagColors[tag.lowercased()] = value
            } else {
                tagColors.removeValue(forKey: tag.lowercased())
            }
        }
    }
}

struct TaskFilter: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var tags: Set<String> = []           // task must have at least one of these
    var excludedTags: Set<String> = []   // task must have none of these
    var documentIds: Set<String> = []   // "inbox" sentinel allowed
    var states: Set<TaskState> = [.todo]
    var dateField: DateField = .any
    var dateScope: DateScope = .any
    var groupBy: GroupBy? = .document   // optional so pre-existing saved filters decode
    var layout: ViewLayout? = .stacked  // optional, same reason
    var pinned: Bool? = nil             // shows in the sidebar; nil == false, same reason
    var order: Int? = nil               // position within the Views page; nil sorts as 0
    var pinnedOrder: Int? = nil         // separate scale from `order` — pinned section mixes views+dashboards
    var sectionId: UUID? = nil          // reserved for future section grouping; unused for now

    init(id: UUID = UUID(), name: String = "", tags: Set<String> = [], excludedTags: Set<String> = [],
         documentIds: Set<String> = [], states: Set<TaskState> = [.todo], dateField: DateField = .any,
         dateScope: DateScope = .any, groupBy: GroupBy? = .document, layout: ViewLayout? = .stacked,
         pinned: Bool? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.tags = tags
        self.excludedTags = excludedTags
        self.documentIds = documentIds
        self.states = states
        self.dateField = dateField
        self.dateScope = dateScope
        self.groupBy = groupBy
        self.layout = layout
        self.pinned = pinned
        self.order = order
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tags, excludedTags, documentIds, states, dateField, dateScope, groupBy, layout, pinned
        case order, pinnedOrder, sectionId
    }

    /// Every field falls back to its default if the key is missing or
    /// fails to decode, instead of failing the whole object. Plain
    /// synthesized Codable requires every non-Optional field to be present,
    /// so adding a field like `excludedTags` here previously made every
    /// *existing* saved view fail to decode outright — Store.loadFilters()
    /// swallowed that error via `try?`, treated it as "no saved views," and
    /// the next save silently overwrote the real data with nothing. This
    /// makes that entire failure mode impossible going forward.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        tags = (try? c.decode(Set<String>.self, forKey: .tags)) ?? []
        excludedTags = (try? c.decode(Set<String>.self, forKey: .excludedTags)) ?? []
        documentIds = (try? c.decode(Set<String>.self, forKey: .documentIds)) ?? []
        states = (try? c.decode(Set<TaskState>.self, forKey: .states)) ?? [.todo]
        dateField = (try? c.decode(DateField.self, forKey: .dateField)) ?? .any
        dateScope = (try? c.decode(DateScope.self, forKey: .dateScope)) ?? .any
        groupBy = (try? c.decode(GroupBy?.self, forKey: .groupBy)) ?? .document
        layout = (try? c.decode(ViewLayout?.self, forKey: .layout)) ?? .stacked
        pinned = try? c.decode(Bool?.self, forKey: .pinned)
        order = try? c.decode(Int?.self, forKey: .order)
        pinnedOrder = try? c.decode(Int?.self, forKey: .pinnedOrder)
        sectionId = try? c.decode(UUID?.self, forKey: .sectionId)
    }

    var isEmpty: Bool {
        tags.isEmpty && excludedTags.isEmpty && documentIds.isEmpty && states == [.todo]
            && dateField == .any && dateScope == .any
            && (groupBy ?? .document) == .document
    }

    func matches(_ t: CraftTask, todayIncludesOverdue: Bool = false) -> Bool {
        if !states.isEmpty && !states.contains(t.state) { return false }
        if !tags.isEmpty && tags.isDisjoint(with: Set(t.tags)) { return false }
        if !excludedTags.isEmpty && !excludedTags.isDisjoint(with: Set(t.tags)) { return false }
        if !documentIds.isEmpty {
            let key = t.locationType == "inbox" ? "inbox" : (t.documentId ?? "")
            if !documentIds.contains(key) { return false }
        }

        let today = Calendar.current.startOfDay(for: Date())
        let date: Date?
        switch dateField {
        case .any: date = t.scheduleDay ?? t.deadlineDay
        case .scheduled: date = t.scheduleDay
        case .deadline: date = t.deadlineDay
        }
        switch dateScope {
        case .any: break
        case .noDate: if date != nil { return false }
        case .today:
            guard let d = date else { return false }
            if d != today {
                if !(todayIncludesOverdue && d < today && t.state == .todo) { return false }
            }
        case .overdue:
            guard let d = date else { return false }
            if !(d < today && t.state == .todo) { return false }
        case .next7:
            guard let d = date else { return false }
            guard let end = Calendar.current.date(byAdding: .day, value: 7, to: today) else { return false }
            if !(d >= today && d <= end) { return false }
        case .thisMonth:
            guard let d = date else { return false }
            if !Calendar.current.isDate(d, equalTo: today, toGranularity: .month) { return false }
        }
        return true
    }
}

// MARK: - Pinned sidebar items

/// Identifies a pinned item's kind independent of its full view/dashboard
/// value, so drag state and drop-target comparisons don't need to unpack
/// a PinnedItem at every call site.
struct PinnedRef: Equatable {
    enum Kind { case view, dashboard }
    let kind: Kind
    let id: UUID
}

/// A sidebar PINNED-section entry: either a saved view or a dashboard,
/// carrying its full value so rows can render name/icon without a lookup.
enum PinnedItem: Identifiable {
    case view(TaskFilter)
    case dashboard(Dashboard)

    var id: String {
        switch self {
        case .view(let f): return "view:\(f.id)"
        case .dashboard(let d): return "dashboard:\(d.id)"
        }
    }
    var ref: PinnedRef {
        switch self {
        case .view(let f): return PinnedRef(kind: .view, id: f.id)
        case .dashboard(let d): return PinnedRef(kind: .dashboard, id: d.id)
        }
    }
    var name: String {
        switch self {
        case .view(let f): return f.name
        case .dashboard(let d): return d.name
        }
    }
}

/// A live `@` mention that resolved to a date instead of a document.
struct DateMatch {
    let date: Date
    let label: String
}

private let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

/// Shared @-mention date parsing (Craft-style: `@15`, `@today`, `@tomorrow`,
/// `@monday`, `@3/15`, `@2026-03-15`) — mirrors web/src/modals.tsx
/// parseDateQuery so both apps recognize the same tokens.
func parseDateQuery(_ raw: String) -> DateMatch? {
    let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return nil }
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())

    if q.count >= 3, "today".hasPrefix(q) { return DateMatch(date: today, label: "Today") }
    if q.count >= 3, "tomorrow".hasPrefix(q) {
        let d = cal.date(byAdding: .day, value: 1, to: today)!
        return DateMatch(date: d, label: "Tomorrow")
    }
    if q.count >= 4, "yesterday".hasPrefix(q) {
        let d = cal.date(byAdding: .day, value: -1, to: today)!
        return DateMatch(date: d, label: "Yesterday")
    }
    if q.count >= 3, let wd = weekdayNames.firstIndex(where: { $0.hasPrefix(q) }) {
        let todayWeekday = cal.component(.weekday, from: today) - 1 // 0 = Sunday
        let diff = ((wd - todayWeekday) % 7 + 7) % 7
        let offset = diff == 0 ? 7 : diff
        let d = cal.date(byAdding: .day, value: offset, to: today)!
        let name = weekdayNames[wd]
        return DateMatch(date: d, label: name.prefix(1).uppercased() + name.dropFirst())
    }

    let isoRe = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})$"#)
    let ns = q as NSString
    if let m = isoRe.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)) {
        let year = Int(ns.substring(with: m.range(at: 1)))!
        let month = Int(ns.substring(with: m.range(at: 2)))!
        let day = Int(ns.substring(with: m.range(at: 3)))!
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return DateMatch(date: d, label: f.string(from: d))
    }

    let mdRe = try! NSRegularExpression(pattern: #"^(\d{1,2})[/-](\d{1,2})$"#)
    if let m = mdRe.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)) {
        let month = Int(ns.substring(with: m.range(at: 1)))!
        let day = Int(ns.substring(with: m.range(at: 2)))!
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = cal.dateComponents([.year], from: today)
        comps.month = month; comps.day = day
        guard var d = cal.date(from: comps) else { return nil }
        if d < today { comps.year = (comps.year ?? 0) + 1; d = cal.date(from: comps)! }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return DateMatch(date: d, label: f.string(from: d))
    }

    let dayRe = try! NSRegularExpression(pattern: #"^(\d{1,2})$"#)
    if let m = dayRe.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)) {
        let n = Int(ns.substring(with: m.range(at: 1)))!
        guard (1...31).contains(n) else { return nil }
        var comps = cal.dateComponents([.year, .month], from: today)
        comps.day = n
        guard var d = cal.date(from: comps) else { return nil }
        if d < today {
            comps.month = (comps.month ?? 0) + 1
            d = cal.date(from: comps)!
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return DateMatch(date: d, label: f.string(from: d))
    }
    return nil
}

/// Tag autocomplete: prefix matches first (alphabetical), then substring
/// matches (alphabetical) — used by the "add tag" field and the live
/// #tag token while typing a new task's title.
func matchTags(_ query: String, in allTags: [String], excluding: [String] = [], limit: Int = 8) -> [String] {
    let q = query.lowercased()
    let excludeSet = Set(excluding.map { $0.lowercased() })
    let pool = allTags.filter { !excludeSet.contains($0.lowercased()) }
    if q.isEmpty { return Array(pool.prefix(limit)) }
    let prefix = pool.filter { $0.lowercased().hasPrefix(q) }.sorted()
    let substring = pool.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }.sorted()
    return Array((prefix + substring).prefix(limit))
}
