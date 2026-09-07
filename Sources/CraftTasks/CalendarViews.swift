import SwiftUI

// macOS UI for the Google Calendar integration — mirrors the web app's
// web/src/CalendarView.tsx. "Send to Calendar" is a one-way push from a task;
// the Calendar page is a thin weekly-agenda CRUD client over the dedicated
// "Craft Tasks" calendar.

private let repeatOptions = RepeatKind.allCases

// MARK: - shared date/time/repeat form

private struct EventFormState {
    var title: String
    var date: Date
    var time: Date
    var repeatKind: RepeatKind = .none
    var until: Date?
    var canRepeat: Bool = true

    var start: Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: date)
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day,
                                             hour: t.hour, minute: t.minute)) ?? date
    }
}

private struct EventFormFields: View {
    @Binding var form: EventFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TITLE").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textFaint)
                TextField("Event title", text: $form.title)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
            }

            HStack(spacing: 14) {
                DateChip(title: "Date", icon: "calendar", date: Binding(
                    get: { form.date }, set: { form.date = $0 ?? form.date }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textFaint)
                    DatePicker("", selection: $form.time, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.field)
                }
                Spacer()
            }

            if form.canRepeat {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REPEAT").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textFaint)
                        Picker("", selection: $form.repeatKind) {
                            ForEach(repeatOptions) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 200)
                    }
                    if form.repeatKind != .none {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("UNTIL (OPTIONAL)").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textFaint)
                            HStack(spacing: 6) {
                                DateChip(title: "No end", icon: "calendar", date: $form.until)
                                if form.until != nil {
                                    Button("×") { form.until = nil }.buttonStyle(.plain).foregroundColor(Theme.textFaint)
                                }
                            }
                        }
                    }
                    Spacer()
                }
            } else {
                Text("Part of a repeating series — changes apply to this occurrence only.")
                    .font(.system(size: 11)).foregroundColor(Theme.textFaint)
            }
        }
    }
}

// MARK: - Send to Calendar (from a task)

struct SendToCalendarSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gcal = GoogleCalendar.shared
    let task: CraftTask

    @State private var form: EventFormState
    @State private var busy = false
    @State private var error: String?
    @State private var done = false

    init(task: CraftTask) {
        self.task = task
        let anchor = task.scheduleDay ?? task.deadlineDay ?? Date()
        let cal = Calendar.current
        _form = State(initialValue: EventFormState(
            title: task.displayTitle,
            date: cal.startOfDay(for: anchor),
            time: cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send to Calendar").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)

            if !gcal.isConnected {
                Text("Connect a Google account under Settings → Google Calendar first. Events are pushed to a dedicated “Craft Tasks” calendar.")
                    .font(.system(size: 12)).foregroundColor(Theme.textLo)
            } else if done {
                Label("Added to your Craft Tasks calendar.", systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundColor(Theme.textLo)
            } else {
                EventFormFields(form: $form)
                Text("One-way push — the event is independent of the task afterwards. Manage it in the Calendar view.")
                    .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                if let error {
                    Text(error).font(.system(size: 11)).foregroundColor(Theme.destructive)
                }
            }

            HStack {
                Spacer()
                Button(done ? "Close" : "Cancel") { dismiss() }.disabled(busy)
                if gcal.isConnected && !done {
                    Button(busy ? "Sending…" : "Send to Calendar") { Task { await send() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || form.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(22).frame(width: 460).background(Theme.panel)
    }

    private func send() async {
        busy = true; error = nil
        do {
            let calId = try await gcal.ensureCalendar(known: store.craftCalendarId)
            store.craftCalendarId = calId
            let link = task.craftDeepLink(spaceId: store.spaceId)?.absoluteString
            try await gcal.createEvent(calId: calId, .init(
                title: form.title.trimmingCharacters(in: .whitespaces),
                start: form.start,
                repeatKind: form.repeatKind,
                repeatUntil: form.until,
                craftTaskId: task.id,
                description: ["From Craft Tasks · \(task.sourceName)", link].compactMap { $0 }.joined(separator: "\n")
            ))
            done = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

// MARK: - Event editor (in the Calendar page)

struct EventEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gcal = GoogleCalendar.shared
    let calId: String
    let event: GCalEvent?
    let defaultStart: Date?
    let onChanged: () -> Void

    @State private var form: EventFormState
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingDelete = false

    private var isRecurringInstance: Bool { event?.recurringEventId != nil }

    init(calId: String, event: GCalEvent?, defaultStart: Date?, onChanged: @escaping () -> Void) {
        self.calId = calId; self.event = event; self.defaultStart = defaultStart; self.onChanged = onChanged
        let cal = Calendar.current
        let start = event?.start ?? defaultStart ?? Date()
        _form = State(initialValue: EventFormState(
            title: event?.summary ?? "",
            date: cal.startOfDay(for: start),
            time: start,
            canRepeat: event?.recurringEventId == nil
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event == nil ? "New event" : "Edit event")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)

            EventFormFields(form: $form)

            if let error {
                Text(error).font(.system(size: 11)).foregroundColor(Theme.destructive)
            }

            HStack {
                if let event {
                    if !confirmingDelete {
                        Button("Delete") { confirmingDelete = true }
                            .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.destructive))
                            .buttonStyle(.plain).disabled(busy)
                    } else if isRecurringInstance {
                        Button("This event") { Task { await remove(event.id) } }.disabled(busy)
                        Button("Whole series") { Task { await remove(event.recurringEventId ?? event.id) } }.disabled(busy)
                    } else {
                        Button("Confirm delete") { Task { await remove(event.id) } }
                            .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.destructive))
                            .buttonStyle(.plain).disabled(busy)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.disabled(busy)
                Button(busy ? "Saving…" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || form.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22).frame(width: 460).background(Theme.panel)
    }

    private func save() async {
        busy = true; error = nil
        let input = GoogleCalendar.EventInput(
            title: form.title.trimmingCharacters(in: .whitespaces),
            start: form.start,
            repeatKind: form.canRepeat ? form.repeatKind : .none,
            repeatUntil: form.until
        )
        do {
            if let event { try await gcal.updateEvent(calId: calId, eventId: event.id, input) }
            else { try await gcal.createEvent(calId: calId, input) }
            onChanged(); dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func remove(_ id: String) async {
        busy = true; error = nil
        do { try await gcal.deleteEvent(calId: calId, eventId: id); onChanged(); dismiss() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

// MARK: - Weekly agenda page

struct CalendarPageView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var gcal = GoogleCalendar.shared

    @State private var weekStart = CalendarPageView.monday(of: Date())
    @State private var events: [GCalEvent] = []
    @State private var loading = false
    @State private var error: String?
    @State private var connecting = false
    @State private var calId: String?
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let id = UUID()
        var event: GCalEvent?
        var start: Date?
    }

    private var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 7, to: weekStart)! }
    private var days: [Date] { (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: weekStart)! } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.stroke)
            if !gcal.isConnected {
                connectPrompt
            } else {
                agenda
            }
        }
        .background(Theme.bg)
        .sheet(item: $editing) { target in
            if let calId {
                EventEditSheet(calId: calId, event: target.event, defaultStart: target.start) { Task { await load() } }
                    .environmentObject(store)
            }
        }
        .task(id: weekStart) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Calendar").font(.system(size: 27, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
            Spacer()
            if gcal.isConnected {
                Text(weekLabel).font(.system(size: 12)).foregroundColor(Theme.textLo)
                Button("Today") { weekStart = Self.monday(of: Date()) }
                Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart)! } label: { Image(systemName: "chevron.left") }
                Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)! } label: { Image(systemName: "chevron.right") }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var connectPrompt: some View {
        VStack(spacing: 14) {
            Text("Connect a Google account to push tasks to a dedicated Craft Tasks calendar and manage those events here.")
                .font(.system(size: 13)).foregroundColor(Theme.textLo).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button(connecting ? "Connecting…" : "Connect Google Calendar") { Task { await connect() } }
                .disabled(connecting || GoogleCalendar.clientID.isEmpty)
            if GoogleCalendar.clientID.isEmpty {
                Text("Add your Google OAuth Client ID in Settings → Google Calendar first.")
                    .font(.system(size: 11)).foregroundColor(Theme.textFaint)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundColor(Theme.destructive) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var agenda: some View {
        ScrollView {
            if let error { Text(error).font(.system(size: 11)).foregroundColor(Theme.destructive).padding(16) }
            VStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    dayRow(day)
                    Divider().background(Theme.stroke)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
    }

    private func dayRow(_ day: Date) -> some View {
        let cal = Calendar.current
        let list = events.filter { cal.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
        let isToday = cal.isDateInToday(day)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.textFaint)
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundColor(isToday ? .black : Theme.textHi)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isToday ? Theme.accent : Color.clear))
                Button { editing = EditTarget(event: nil, start: cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)) } label: {
                    Image(systemName: "plus").font(.system(size: 10)).foregroundColor(Theme.textFaint)
                }.buttonStyle(.plain)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 6) {
                if list.isEmpty {
                    Text("—").font(.system(size: 12)).foregroundColor(Theme.textFaint).padding(.vertical, 4)
                }
                ForEach(list) { ev in
                    Button { editing = EditTarget(event: ev, start: nil) } label: {
                        HStack(spacing: 10) {
                            Text(ev.isAllDay ? "all day" : ev.start.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 11)).foregroundColor(Theme.textLo).frame(width: 62, alignment: .leading)
                            Text(ev.summary).font(.system(size: 13)).foregroundColor(Theme.textHi).lineLimit(1)
                            if ev.hasRecurrence { Image(systemName: "arrow.clockwise").font(.system(size: 9)).foregroundColor(Theme.textFaint) }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 1))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            Spacer()
        }
    }

    private var weekLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: weekEnd)!
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
            + (loading ? " · loading…" : "")
    }

    private func load() async {
        guard gcal.isConnected else { return }
        loading = true; error = nil
        do {
            let id = try await gcal.ensureCalendar(known: store.craftCalendarId)
            if id != store.craftCalendarId { store.craftCalendarId = id }
            calId = id
            events = try await gcal.listEvents(calId: id, from: weekStart, to: weekEnd)
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func connect() async {
        connecting = true; error = nil
        do { try await gcal.connect(); await load() }
        catch { self.error = error.localizedDescription }
        connecting = false
    }

    static func monday(of date: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let weekday = (cal.component(.weekday, from: start) + 5) % 7 // Mon = 0
        return cal.date(byAdding: .day, value: -weekday, to: start)!
    }
}

// MARK: - Settings section (embedded in SidebarSettingsSheet)

struct GoogleCalendarSettingsSection: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var gcal = GoogleCalendar.shared
    @State private var clientId = GoogleCalendar.clientID
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google Calendar").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
            Text("“Send to Calendar” pushes a task to a dedicated Craft Tasks calendar with a specific time. One-way push, no sync.")
                .font(.system(size: 11)).foregroundColor(Theme.textFaint)

            Text("OAUTH CLIENT ID (iOS TYPE)").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.textFaint)
            TextField("…apps.googleusercontent.com", text: $clientId, onCommit: commitClientId)
                .textFieldStyle(.roundedBorder).font(.system(size: 12)).frame(maxWidth: 360)
            Text("An iOS-type OAuth client from Google Cloud Console (bundle id com.avisek.crafttasks). No client secret needed.")
                .font(.system(size: 11)).foregroundColor(Theme.textFaint)

            HStack(spacing: 8) {
                if gcal.isConnected {
                    Label("Connected", systemImage: "checkmark.circle").font(.system(size: 12)).foregroundColor(Theme.textLo)
                    Button("Disconnect") { gcal.disconnect(); store.craftCalendarId = nil; status = "Disconnected" }
                } else {
                    Button(busy ? "Connecting…" : "Connect Google Calendar") { Task { await connect() } }
                        .disabled(busy || clientId.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let status { Text(status).font(.system(size: 11)).foregroundColor(Theme.textFaint) }
        }
    }

    private func commitClientId() {
        gcal.setClientID(clientId)
        status = clientId.trimmingCharacters(in: .whitespaces).isEmpty ? "Client ID cleared" : "Client ID saved"
    }

    private func connect() async {
        busy = true; status = nil
        gcal.setClientID(clientId)
        do {
            try await gcal.connect()
            let id = try await gcal.ensureCalendar(known: store.craftCalendarId)
            store.craftCalendarId = id
            status = "Connected — “Craft Tasks” calendar ready"
        } catch { status = error.localizedDescription }
        busy = false
    }
}
