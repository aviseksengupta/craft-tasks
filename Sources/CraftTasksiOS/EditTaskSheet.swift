import SwiftUI

/// Port of the Mac app's EditTaskView — same fields, same Store calls
/// (`applyEdit`, `deleteTask`, `SyncEngine.fetchDescription`/`pushDescription`).
struct EditTaskSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let task: CraftTask

    @State private var body_: String = ""
    @State private var state: TaskState = .todo
    @State private var scheduleDate: Date? = nil
    @State private var deadlineDate: Date? = nil
    @State private var mentionQuery: String? = nil
    @State private var tagQuery: String? = nil
    @State private var selectedDocumentId: String?
    @State private var description: String = ""
    @State private var originalDescription: String = ""
    @State private var descriptionBlockIds: [String] = []
    @State private var loadingDescription = true
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var sendingToCalendar = false

    private var currentTags: [String] {
        let re = try! NSRegularExpression(pattern: "#([\\w/\\-]+)")
        let ns = body_ as NSString
        return re.matches(in: body_, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }
    private var checkboxRingColor: Color? {
        for tag in currentTags {
            if let hex = store.tagCheckboxColors[tag.lowercased()], let uint32 = UInt32(hex, radix: 16) { return Color(hex: uint32) }
        }
        return nil
    }
    private var inProgressColor: Color? {
        guard let hex = store.tagCheckboxColors["inprogress"], let uint32 = UInt32(hex, radix: 16) else { return nil }
        return Color(hex: uint32)
    }
    private var mentionMatches: [DocumentSummary] {
        guard let q = mentionQuery else { return [] }
        let pool = store.documents.filter { $0.id != "inbox" }
        let matches = q.isEmpty ? pool : pool.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return Array(matches.prefix(6))
    }
    private var dateMatch: DateMatch? {
        guard let q = mentionQuery else { return nil }
        return parseDateQuery(q)
    }
    private var tagSuggestions: [String] {
        guard let q = tagQuery else { return [] }
        return matchTags(q, in: store.allTags, excluding: currentTags, limit: 6)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        StateCycleButton(state: $state, ringColor: checkboxRingColor)
                        if state == .todo {
                            InProgressToggle(isActive: currentTags.contains { $0.lowercased() == "inprogress" },
                                              activeColor: inProgressColor, toggle: toggleInProgress)
                        }
                        Spacer()
                        OpenInCraftButton(url: task.craftDeepLink(spaceId: store.spaceId))
                    }
                    documentPicker
                } header: { Text("Status") }

                Section {
                    TextField("Task", text: $body_, axis: .vertical)
                        .lineLimit(2...6)
                        .onChange(of: body_) { _, new in processBody(new) }
                    if dateMatch != nil || !mentionMatches.isEmpty || !tagSuggestions.isEmpty {
                        suggestionList
                    }
                } header: { Text("Task") }

                if !currentTags.isEmpty {
                    Section {
                        FlowRow(spacing: 6) {
                            ForEach(currentTags, id: \.self) { tag in TagChip(tag: tag) { removeTag(tag) } }
                        }
                    } header: { Text("Tags") }
                }

                Section {
                    if loadingDescription {
                        ProgressView()
                    } else {
                        TextField("Add more detail…", text: $description, axis: .vertical).lineLimit(3...8)
                    }
                } header: { Text("Description") }

                Section {
                    DateChip(title: "Scheduled", icon: "calendar", date: $scheduleDate)
                    DateChip(title: "Deadline", icon: "flag", date: $deadlineDate)
                } header: { Text("Dates") }

                Section {
                    Button { sendingToCalendar = true } label: {
                        Label("Send to Calendar", systemImage: "calendar.badge.clock")
                    }
                }

                if let saveError { Text(saveError).font(.system(size: 12)).foregroundColor(Theme.danger) }
                if let deleteError { Text(deleteError).font(.system(size: 12)).foregroundColor(Theme.destructive) }

                Section {
                    Button(role: .destructive) {
                        Task { await handleDelete() }
                    } label: {
                        Text(deleting ? "Deleting…" : confirmingDelete ? "Confirm delete?" : "Delete")
                    }
                    .disabled(saving || deleting)
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving || deleting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving || deleting)
                }
            }
        }
        .sheet(isPresented: $sendingToCalendar) { SendToCalendarSheet(task: task) }
        .onAppear {
            body_ = task.markdownParts.body
            state = task.state
            scheduleDate = task.scheduleDay
            deadlineDate = task.deadlineDay
            selectedDocumentId = task.locationType == "inbox" ? nil : task.documentId
            Task { await loadDescription() }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let dateMatch {
                Button { chooseDate(dateMatch.date) } label: { Label(dateMatch.label, systemImage: "calendar") }
            }
            ForEach(mentionMatches) { doc in
                Button { chooseMention(doc) } label: { Label(doc.title, systemImage: "doc.text") }
            }
            ForEach(tagSuggestions, id: \.self) { tag in
                Button { chooseTag(tag) } label: { Text("#\(tag)") }
            }
        }
    }

    private var documentPicker: some View {
        Menu {
            Button { selectedDocumentId = nil } label: {
                HStack { Text("Inbox"); if selectedDocumentId == nil { Image(systemName: "checkmark") } }
            }
            if !store.documents.isEmpty {
                Divider()
                ForEach(store.documents.filter { $0.id != "inbox" }) { doc in
                    Button { selectedDocumentId = doc.id } label: {
                        HStack { Text(doc.title); if selectedDocumentId == doc.id { Image(systemName: "checkmark") } }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedDocumentId == nil ? "tray" : "doc.text")
                Text(currentDocLabel).lineLimit(1)
            }
            .foregroundColor(Theme.textFaint)
        }
    }

    private var currentDocLabel: String {
        guard let id = selectedDocumentId else { return "Inbox" }
        return store.documents.first { $0.id == id }?.title ?? "Document"
    }

    private func processBody(_ newValue: String) {
        let ns = newValue as NSString
        let trailingRe = try! NSRegularExpression(pattern: #"[#@][\w/\-]*$"#)
        var liveToken: String?
        if let m = trailingRe.firstMatch(in: newValue, range: NSRange(location: 0, length: ns.length)) {
            liveToken = ns.substring(with: m.range)
        }
        mentionQuery = (liveToken?.hasPrefix("@") == true) ? String(liveToken!.dropFirst()) : nil
        tagQuery = (liveToken?.hasPrefix("#") == true) ? String(liveToken!.dropFirst()) : nil
    }

    private func chooseMention(_ doc: DocumentSummary) {
        if let r = body_.range(of: #"@[\w/\-]*$"#, options: .regularExpression) { body_.removeSubrange(r) }
        body_ = body_.trimmingCharacters(in: .whitespaces)
        selectedDocumentId = doc.id
        mentionQuery = nil
    }
    private func chooseDate(_ date: Date) {
        if let r = body_.range(of: #"@[\w/\-]*$"#, options: .regularExpression) { body_.removeSubrange(r) }
        body_ = body_.trimmingCharacters(in: .whitespaces)
        scheduleDate = date
        mentionQuery = nil
    }
    private func chooseTag(_ tag: String) {
        if let r = body_.range(of: #"#[\w/\-]*$"#, options: .regularExpression) { body_.removeSubrange(r) }
        body_ = body_.trimmingCharacters(in: .whitespaces) + " #\(tag)"
        tagQuery = nil
    }
    private func toggleInProgress() {
        if let existing = currentTags.first(where: { $0.lowercased() == "inprogress" }) {
            removeTag(existing)
        } else {
            body_ = body_.trimmingCharacters(in: .whitespacesAndNewlines) + " #inprogress"
        }
    }
    private func removeTag(_ tag: String) {
        body_ = body_.replacingOccurrences(of: #"\s*#"# + NSRegularExpression.escapedPattern(for: tag) + #"\b"#,
                                           with: "", options: .regularExpression)
    }

    private var destination: Store.TaskDestination {
        let originalId = task.locationType == "inbox" ? nil : task.documentId
        guard selectedDocumentId != originalId else { return .unchanged }
        if let id = selectedDocumentId { return .document(id) }
        return .inbox
    }

    private func loadDescription() async {
        do {
            let d = try await SyncEngine.fetchDescription(taskId: task.id)
            description = d.text
            originalDescription = d.text
            descriptionBlockIds = d.blockIds
        } catch {
            saveError = "Couldn't load description: \(error.localizedDescription)"
        }
        loadingDescription = false
    }

    private func save() async {
        store.applyEdit(
            to: task, body: body_.trimmingCharacters(in: .whitespacesAndNewlines), state: state,
            scheduleDate: scheduleDate.map { DateFormatter.ymd.string(from: $0) },
            deadlineDate: deadlineDate.map { DateFormatter.ymd.string(from: $0) },
            destination: destination)

        if description != originalDescription {
            saving = true
            saveError = nil
            do {
                try await SyncEngine.pushDescription(taskId: task.id, existingBlockIds: descriptionBlockIds, newText: description)
            } catch {
                saving = false
                saveError = "Task saved, but description failed to sync: \(error.localizedDescription). Try again."
                return
            }
            saving = false
        }
        dismiss()
    }

    private func handleDelete() async {
        guard confirmingDelete else { confirmingDelete = true; return }
        deleting = true
        deleteError = nil
        do {
            try await store.deleteTask(task)
            dismiss()
        } catch {
            deleting = false
            deleteError = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}
