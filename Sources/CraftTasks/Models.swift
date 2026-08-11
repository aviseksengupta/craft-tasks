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

    init(id: UUID = UUID(), name: String, widgets: [DashboardWidget]) {
        self.id = id
        self.name = name
        self.widgets = widgets
    }

    // Custom Codable so dashboards saved by the earlier (viewIds + layout)
    // version of this app still load, migrated into one medium widget per view.
    private enum CodingKeys: String, CodingKey { case id, name, widgets, viewIds }

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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(widgets, forKey: .widgets)
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

    init(id: UUID = UUID(), name: String = "", tags: Set<String> = [], excludedTags: Set<String> = [],
         documentIds: Set<String> = [], states: Set<TaskState> = [.todo], dateField: DateField = .any,
         dateScope: DateScope = .any, groupBy: GroupBy? = .document, layout: ViewLayout? = .stacked,
         pinned: Bool? = nil) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tags, excludedTags, documentIds, states, dateField, dateScope, groupBy, layout, pinned
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
