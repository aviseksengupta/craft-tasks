import SwiftUI

/// Port of the Mac app's AddTaskView — identical parsing (inline #tag /
/// @document / @date autocomplete), iPhone-native chrome (full-height
/// sheet, no floating popover, suggestions inline under the field).
struct AddTaskSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var rawText = ""
    @State private var tags: [String] = []
    @State private var scheduleDate: Date? = nil
    @State private var deadlineDate: Date? = nil
    @State private var selectedDocument: DocumentSummary? = nil
    @State private var description = ""
    @State private var mentionQuery: String? = nil
    @State private var tagQuery: String? = nil
    @FocusState private var focused: Bool

    private var mentionMatches: [DocumentSummary] {
        guard let q = mentionQuery else { return [] }
        let pool = store.documents.filter { $0.id != "inbox" }
        let matches = q.isEmpty ? pool : pool.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return Array(matches.prefix(6))
    }
    private var tagMatches: [String] {
        guard let q = tagQuery else { return [] }
        return matchTags(q, in: store.allTags, excluding: tags, limit: 6)
    }
    private var dateMatch: DateMatch? {
        guard let q = mentionQuery else { return nil }
        return parseDateQuery(q)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing? Try #tag or @document", text: $rawText, axis: .vertical)
                        .focused($focused)
                        .onChange(of: rawText) { _, new in processInput(new) }
                    if dateMatch != nil || !mentionMatches.isEmpty || !tagMatches.isEmpty {
                        suggestionList
                    }
                } header: { Text("Title") }

                Section {
                    HStack {
                        Image(systemName: selectedDocument == nil ? "tray" : "doc.text").foregroundColor(Theme.textFaint)
                        Text(selectedDocument?.title ?? "Inbox")
                        Spacer()
                        if selectedDocument != nil {
                            Button { selectedDocument = nil } label: { Image(systemName: "xmark") }
                        }
                    }
                } header: { Text("Destination") }

                if !tags.isEmpty {
                    Section {
                        FlowRow(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in TagChip(tag: tag) { tags.removeAll { $0 == tag } } }
                        }
                    } header: { Text("Tags") }
                }

                Section {
                    TextField("Add more detail…", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                } header: { Text("Description") }

                Section {
                    DateChip(title: "Scheduled", icon: "calendar", date: $scheduleDate)
                    DateChip(title: "Deadline", icon: "flag", date: $deadlineDate)
                } header: { Text("Dates") }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { focused = true }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dateMatch {
                Button { chooseDate(dateMatch.date) } label: {
                    Label(dateMatch.label, systemImage: "calendar")
                }
            }
            ForEach(mentionMatches) { doc in
                Button { chooseMention(doc) } label: { Label(doc.title, systemImage: "doc.text") }
            }
            ForEach(tagMatches, id: \.self) { tag in
                Button { chooseTag(tag) } label: { Text("#\(tag)") }
            }
        }
    }

    private func processInput(_ newValue: String) {
        let ns = newValue as NSString
        let trailingRe = try! NSRegularExpression(pattern: #"[#@][\w/\-]*$"#)
        var committed = newValue
        var liveToken: String?
        if let m = trailingRe.firstMatch(in: newValue, range: NSRange(location: 0, length: ns.length)) {
            liveToken = ns.substring(with: m.range)
            committed = String(newValue.dropLast(liveToken!.count))
        }
        mentionQuery = (liveToken?.hasPrefix("@") == true) ? String(liveToken!.dropFirst()) : nil
        tagQuery = (liveToken?.hasPrefix("#") == true) ? String(liveToken!.dropFirst()) : nil

        let tagRe = try! NSRegularExpression(pattern: #"#([\w/\-]+)"#)
        let cns = committed as NSString
        let matches = tagRe.matches(in: committed, range: NSRange(location: 0, length: cns.length))
        if !matches.isEmpty {
            for m in matches {
                let t = cns.substring(with: m.range(at: 1)).lowercased()
                if !tags.contains(t) { tags.append(t) }
            }
            committed = tagRe.stringByReplacingMatches(in: committed, range: NSRange(location: 0, length: cns.length), withTemplate: "")
            committed = committed.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        }
        let rebuilt = committed + (liveToken ?? "")
        if rebuilt != newValue { rawText = rebuilt }
    }

    private func chooseMention(_ doc: DocumentSummary) {
        if let r = rawText.range(of: #"@[\w/\-]*$"#, options: .regularExpression) { rawText.removeSubrange(r) }
        rawText = rawText.trimmingCharacters(in: .whitespaces)
        selectedDocument = doc
        mentionQuery = nil
    }
    private func chooseDate(_ date: Date) {
        if let r = rawText.range(of: #"@[\w/\-]*$"#, options: .regularExpression) { rawText.removeSubrange(r) }
        rawText = rawText.trimmingCharacters(in: .whitespaces)
        scheduleDate = date
        mentionQuery = nil
    }
    private func chooseTag(_ tag: String) {
        if let r = rawText.range(of: #"#[\w/\-]*$"#, options: .regularExpression) { rawText.removeSubrange(r) }
        rawText = rawText.trimmingCharacters(in: .whitespaces) + " "
        if !tags.contains(tag) { tags.append(tag) }
        tagQuery = nil
    }

    private func save() {
        let title = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.createTask(
            title: title, tags: tags,
            scheduleDate: scheduleDate.map { DateFormatter.ymd.string(from: $0) },
            deadlineDate: deadlineDate.map { DateFormatter.ymd.string(from: $0) },
            documentId: selectedDocument?.id,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
