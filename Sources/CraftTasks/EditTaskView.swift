import SwiftUI

struct EditTaskView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let task: CraftTask

    @State private var body_: String = ""
    @State private var state: TaskState = .todo
    @State private var scheduleDate: Date? = nil
    @State private var deadlineDate: Date? = nil
    @State private var newTag = ""
    // nil = Inbox, otherwise a target document id — lets a task be moved
    // between documents (or to/from the inbox) from the edit sheet.
    @State private var selectedDocumentId: String?

    // Description lives as the task's own child blocks in Craft, not on the
    // task line itself — fetched lazily only when this sheet opens.
    @State private var description: String = ""
    @State private var originalDescription: String = ""
    @State private var descriptionBlockIds: [String] = []
    @State private var loadingDescription = true
    @State private var saving = false
    @State private var saveError: String?
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    private var currentTags: [String] {
        let re = try! NSRegularExpression(pattern: "#([\\w/\\-]+)")
        let ns = body_ as NSString
        return re.matches(in: body_, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private var tagColor: Color? {
        for tag in currentTags {
            if let hexColor = store.tagColors[tag.lowercased()], let uint32 = UInt32(hexColor, radix: 16) {
                return Color(hex: uint32)
            }
        }
        return nil
    }

    private var checkboxRingColor: Color? {
        for tag in currentTags {
            if let hexColor = store.tagCheckboxColors[tag.lowercased()], let uint32 = UInt32(hexColor, radix: 16) {
                return Color(hex: uint32)
            }
        }
        return nil
    }

    private var inProgressColor: Color? {
        guard let hexColor = store.tagCheckboxColors["inprogress"], let uint32 = UInt32(hexColor, radix: 16) else { return nil }
        return Color(hex: uint32)
    }

    private var tagSuggestions: [String] {
        matchTags(newTag, in: store.allTags, excluding: currentTags)
    }

    private func toggleInProgress() {
        if let existing = currentTags.first(where: { $0.lowercased() == "inprogress" }) {
            removeTag(existing)
        } else {
            body_ = body_.trimmingCharacters(in: .whitespacesAndNewlines) + " #inprogress"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                StateCycleButton(state: $state, ringColor: checkboxRingColor)
                Text("Edit Task").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
                Spacer()
                if state == .todo {
                    InProgressToggle(isActive: currentTags.contains { $0.lowercased() == "inprogress" },
                                      activeColor: inProgressColor, toggle: toggleInProgress)
                }
                if let link = task.craftDeepLink(spaceId: store.spaceId) {
                    OpenInCraftButton(url: link)
                }
                documentPicker
            }

            // Task text (name / description, hashtags inline)
            VStack(alignment: .leading, spacing: 6) {
                label("TASK")
                TextEditor(text: $body_)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 64, maxHeight: 120)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chipBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
            }

            // Tags — click a chip to remove it
            VStack(alignment: .leading, spacing: 8) {
                label("TAGS")
                FlowRow(spacing: 6) {
                    ForEach(currentTags, id: \.self) { tag in
                        TagChip(tag: tag) { removeTag(tag) }
                    }
                    HStack(spacing: 4) {
                        Text("#").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                        TextField("add tag", text: $newTag)
                            .textFieldStyle(.plain).font(.system(size: 12))
                            .frame(width: 80)
                            .onSubmit { addTag(tagSuggestions.first) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.bg))
                    .overlay(Capsule().stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }

                if !newTag.trimmingCharacters(in: .whitespaces).isEmpty && !tagSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tagSuggestions, id: \.self) { tag in
                            Button { addTag(tag) } label: {
                                HStack {
                                    Text("#\(tag)").font(.system(size: 12)).foregroundColor(Theme.text)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelHi))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                }
            }

            // Description — the task block's own nested content in Craft
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    label("DESCRIPTION")
                    if loadingDescription {
                        ProgressView().controlSize(.mini).scaleEffect(0.5)
                    }
                }
                TextEditor(text: $description)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 50, maxHeight: 100)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chipBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                    .opacity(loadingDescription ? 0.4 : 1)
                    .disabled(loadingDescription)
            }

            // Dates
            HStack(spacing: 14) {
                DateChip(title: "Scheduled", icon: "calendar", date: $scheduleDate)
                DateChip(title: "Deadline", icon: "flag", date: $deadlineDate)
                Spacer()
            }

            if let saveError {
                Text(saveError).font(.system(size: 11)).foregroundColor(Theme.danger)
            }
            if let deleteError {
                Text(deleteError).font(.system(size: 11)).foregroundColor(Theme.destructive)
            }

            HStack {
                Button(deleting ? "Deleting…" : confirmingDelete ? "Confirm delete?" : "Delete") {
                    Task { await handleDelete() }
                }
                .disabled(saving || deleting)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.destructive))
                .buttonStyle(.plain)

                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving || deleting)
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving || deleting)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.panel)
        .overlay(alignment: .leading) {
            if let color = tagColor {
                color.frame(width: 4)
                    .cornerRadius(2, antialiased: true)
            }
        }
        .onAppear {
            body_ = task.markdownParts.body
            state = task.state
            scheduleDate = task.scheduleDay
            deadlineDate = task.deadlineDay
            selectedDocumentId = task.locationType == "inbox" ? nil : task.documentId
            Task { await loadDescription() }
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
                Image(systemName: selectedDocumentId == nil ? "tray" : "doc.text").font(.system(size: 9))
                Text(currentDocLabel).font(.system(size: 11)).lineLimit(1)
            }
            .foregroundColor(Theme.textFaint)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Move this task to a different document")
    }

    private var currentDocLabel: String {
        guard let id = selectedDocumentId else { return "Inbox" }
        return store.documents.first { $0.id == id }?.title ?? "Document"
    }

    private func loadDescription() async {
        do {
            let d = try await SyncEngine.fetchDescription(taskId: task.id)
            description = d.text
            originalDescription = d.text
            descriptionBlockIds = d.blockIds
        } catch {
            // Non-fatal: the task line itself already loaded fine.
            saveError = "Couldn't load description: \(error.localizedDescription)"
        }
        loadingDescription = false
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundColor(Theme.textFaint)
    }

    private func addTag(_ explicit: String? = nil) {
        let t = (explicit ?? newTag).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard !t.isEmpty else { return }
        body_ = body_.trimmingCharacters(in: .whitespacesAndNewlines) + " #\(t)"
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        body_ = body_.replacingOccurrences(of: #"\s*#"# + NSRegularExpression.escapedPattern(for: tag) + #"\b"#,
                                           with: "", options: .regularExpression)
    }

    /// Only sends a location if it actually changed from the task's
    /// current one — every other edit path (checkbox cycle, etc.) never
    /// touches location, so this keeps that the same unless you explicitly
    /// picked a different document above.
    private var destination: Store.TaskDestination {
        let originalId = task.locationType == "inbox" ? nil : task.documentId
        guard selectedDocumentId != originalId else { return .unchanged }
        if let id = selectedDocumentId { return .document(id) }
        return .inbox
    }

    private func save() async {
        // Task fields (name, tags, state, dates) go through the same
        // queued-and-retried path as everywhere else in the app.
        store.applyEdit(
            to: task,
            body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
            state: state,
            scheduleDate: scheduleDate.map { DateFormatter.ymd.string(from: $0) },
            deadlineDate: deadlineDate.map { DateFormatter.ymd.string(from: $0) },
            destination: destination)

        // Description lives on a different endpoint (child blocks) with no
        // offline queue of its own yet, so push it directly here and keep
        // the sheet open with an error instead of silently losing the edit.
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

/// One checkbox-like control: click cycles open → done → canceled → open.
struct StateCycleButton: View {
    @Binding var state: TaskState
    var ringColor: Color? = nil
    @State private var hover = false

    var body: some View {
        Button {
            switch state {
            case .todo: state = .done
            case .done: state = .canceled
            case .canceled: state = .todo
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(state == .todo ? Theme.chipBg : Theme.accent)
                RoundedRectangle(cornerRadius: 7)
                    .stroke(hover ? Theme.textLo : (state == .todo ? (ringColor ?? Theme.stroke) : Theme.stroke),
                            lineWidth: state == .todo && ringColor != nil ? 2 : 1.5)
                switch state {
                case .todo: EmptyView()
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                case .canceled:
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.black)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Click to cycle: open → done → canceled")
        .animation(.easeOut(duration: 0.12), value: state)
    }
}

/// Same one-click "#inprogress" toggle as the list row's InProgressButton,
/// but working against this sheet's unsaved `body_` instead of pushing an
/// edit immediately — the tag change is saved along with everything else.
struct InProgressToggle: View {
    let isActive: Bool
    let activeColor: Color?
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isActive || hover ? .black : Theme.textLo)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isActive ? (activeColor ?? Theme.accent) : (hover ? Theme.accent : Theme.panelHi)))
                .overlay(Circle().stroke(isActive ? (activeColor ?? Theme.accent) : (hover ? Theme.accent : Theme.stroke), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(isActive ? "Mark not in progress" : "Mark in progress")
    }
}

/// Large tag chip — the whole chip is the delete button.
struct TagChip: View {
    let tag: String
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text("#\(tag)").font(.system(size: 12, weight: .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(hover ? 1 : 0.45)
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(hover ? Theme.panelHi : Theme.chipBg))
            .foregroundColor(hover ? Theme.textHi : Theme.textLo)
            .overlay(Capsule().stroke(hover ? Theme.textLo : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Remove #\(tag)")
    }
}

/// Polished date control: unset shows "+ Title"; set shows the date with a
/// clear button; clicking opens a graphical calendar popover.
struct DateChip: View {
    let title: String
    let icon: String
    @Binding var date: Date?
    @State private var showPicker = false
    @State private var hover = false

    private var display: String {
        guard let d = date else { return title }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { showPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: date == nil ? "plus" : icon)
                        .font(.system(size: 10, weight: .medium))
                    VStack(alignment: .leading, spacing: 1) {
                        if date != nil {
                            Text(title.uppercased())
                                .font(.system(size: 8, weight: .semibold)).tracking(1)
                                .foregroundColor(Theme.textFaint)
                        }
                        Text(display).font(.system(size: 12, weight: date == nil ? .regular : .medium))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, date == nil ? 8 : 5)
            }
            .buttonStyle(.plain)

            if date != nil {
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(hover ? Theme.textHi : Theme.textFaint)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .help("Clear \(title.lowercased())")
            }
        }
        .foregroundColor(date == nil ? Theme.textLo : Theme.text)
        .background(RoundedRectangle(cornerRadius: 9).fill(hover ? Theme.panelHi : Theme.chipBg))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(date == nil ? Theme.stroke : Theme.textFaint.opacity(0.5), lineWidth: 1))
        .onHover { hover = $0 }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            MiniCalendar(date: $date)
        }
    }
}

/// A compact, themed month calendar — replaces the stock AppKit graphical
/// DatePicker, which ignores the app's dark palette and looks out of place.
struct MiniCalendar: View {
    @Binding var date: Date?
    @State private var displayedMonth: Date

    init(date: Binding<Date?>) {
        _date = date
        _displayedMonth = State(initialValue: date.wrappedValue ?? Date())
    }

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayRow
            dayGrid
            Rectangle().fill(Theme.stroke).frame(height: 1)
            quickActions
        }
        .padding(14)
        .frame(width: 232)
        .background(Theme.panel)
    }

    private var header: some View {
        HStack {
            monthStepButton("chevron.left") { shiftMonth(-1) }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textHi)
            Spacer()
            monthStepButton("chevron.right") { shiftMonth(1) }
        }
    }

    private func monthStepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textLo)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.chipBg))
        }
        .buttonStyle(.plain)
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: displayedMonth) { displayedMonth = d }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Leading/trailing nils pad the grid out to full weeks.
    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) { result.append(d) }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var dayGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                if let d { dayCell(d) } else { Color.clear.frame(height: 26) }
            }
        }
    }

    private func dayCell(_ d: Date) -> some View {
        let isSelected = date.map { cal.isDate($0, inSameDayAs: d) } ?? false
        let isToday = cal.isDateInToday(d)
        return Button {
            date = cal.startOfDay(for: d)
        } label: {
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .black : Theme.text)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isSelected ? Theme.accent : Color.clear))
                .overlay(Circle().stroke(isToday && !isSelected ? Theme.textLo : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        HStack(spacing: 6) {
            quickButton("Today") {
                let d = cal.startOfDay(for: Date()); date = d; displayedMonth = d
            }
            quickButton("Tomorrow") {
                guard let d = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) else { return }
                date = d; displayedMonth = d
            }
            Spacer()
            if date != nil {
                Button("Clear") { date = nil } .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                    .buttonStyle(.plain)
            }
        }
    }

    private func quickButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Theme.chipBg))
                .foregroundColor(Theme.textLo)
        }
        .buttonStyle(.plain)
    }
}

/// Minimal wrapping HStack for tag chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
