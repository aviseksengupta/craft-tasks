import SwiftUI

/// Create a new Craft task. The title field scans as you type: a completed
/// `#tag` (finished with a space) is stripped out and turned into a tag
/// chip; a trailing `@query` opens a live document-picker so "@Some Doc"
/// targets the task at that document instead of the inbox.
struct AddTaskView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var rawText = ""
    @State private var tags: [String] = []
    @State private var scheduleDate: Date? = nil
    @State private var deadlineDate: Date? = nil
    @State private var selectedDocument: DocumentSummary? = nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundColor(Theme.accent)
                Text("New Task").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                label("TITLE")
                TextField("What needs doing? Try #tag or @document", text: $rawText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chipBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                    .focused($focused)
                    .onChange(of: rawText) { _, new in processInput(new) }
                    .onSubmit {
                        if let first = mentionMatches.first { chooseMention(first) }
                        else if let first = tagMatches.first { chooseTag(first) }
                        else { save() }
                    }

                if !mentionMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(mentionMatches) { doc in
                            Button { chooseMention(doc) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text").font(.system(size: 10)).foregroundColor(Theme.textFaint)
                                    Text(doc.title).font(.system(size: 12)).foregroundColor(Theme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                        if mentionMatches.isEmpty {
                            Text("No matching documents").font(.system(size: 11)).foregroundColor(Theme.textFaint)
                                .padding(10)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelHi))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                }

                if !tagMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tagMatches, id: \.self) { tag in
                            Button { chooseTag(tag) } label: {
                                HStack(spacing: 8) {
                                    Text("#\(tag)").font(.system(size: 12)).foregroundColor(Theme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelHi))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                }
            }

            // Destination — inbox by default, or wherever @mention resolved to
            HStack(spacing: 6) {
                Image(systemName: selectedDocument == nil ? "tray" : "doc.text")
                    .font(.system(size: 10)).foregroundColor(Theme.textFaint)
                Text(selectedDocument?.title ?? "Inbox")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textLo)
                if selectedDocument != nil {
                    Button { selectedDocument = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }.buttonStyle(.plain).foregroundColor(Theme.textFaint)
                }
            }

            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    label("TAGS")
                    FlowRow(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(tag: tag) { tags.removeAll { $0 == tag } }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                DateChip(title: "Scheduled", icon: "calendar", date: $scheduleDate)
                DateChip(title: "Deadline", icon: "flag", date: $deadlineDate)
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Task") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.panel)
        .onAppear { focused = true }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundColor(Theme.textFaint)
    }

    /// Splits input into a "committed" portion (safe to scan) and a
    /// trailing in-progress `#`/`@` token still being typed, so a tag
    /// isn't yanked away mid-keystroke and a mention shows live suggestions.
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
        if let r = rawText.range(of: #"@[\w/\-]*$"#, options: .regularExpression) {
            rawText.removeSubrange(r)
        }
        rawText = rawText.trimmingCharacters(in: .whitespaces)
        selectedDocument = doc
        mentionQuery = nil
    }

    private func chooseTag(_ tag: String) {
        if let r = rawText.range(of: #"#[\w/\-]*$"#, options: .regularExpression) {
            rawText.removeSubrange(r)
        }
        rawText = rawText.trimmingCharacters(in: .whitespaces) + " "
        if !tags.contains(tag) { tags.append(tag) }
        tagQuery = nil
    }

    /// Creation is optimistic and queued if offline (see Store.createTask),
    /// so this never fails from the sheet's point of view — it always adds
    /// the task locally and dismisses immediately, whether or not Craft is
    /// reachable right now.
    private func save() {
        let title = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.createTask(
            title: title, tags: tags,
            scheduleDate: scheduleDate.map { DateFormatter.ymd.string(from: $0) },
            deadlineDate: deadlineDate.map { DateFormatter.ymd.string(from: $0) },
            documentId: selectedDocument?.id)
        dismiss()
    }
}
