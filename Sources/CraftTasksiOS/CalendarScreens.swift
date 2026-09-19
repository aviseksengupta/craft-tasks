import SwiftUI

/// Weekly agenda — same concept as the Mac app's CalendarPageView and the
/// PWA's CalendarView.tsx: shows every event across the user's visible
/// Google calendars for the week, but only "Craft Tasks" calendar events
/// (the ones "Send to Calendar" creates) are editable.
struct CalendarPageView: View {
    @EnvironmentObject var store: Store
    @StateObject private var gcal = GoogleCalendar.shared
    @State private var weekStart = Calendar.current.startOfWeekContainingToday()
    @State private var events: [AgendaEvent] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var editingEvent: AgendaEvent?

    var body: some View {
        VStack(spacing: 0) {
            if !gcal.isConnected {
                notConnected
            } else {
                weekHeader
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError).font(.system(size: 13)).foregroundColor(Theme.danger).padding()
                } else {
                    agendaList
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weekStart) { if gcal.isConnected { await load() } }
        .sheet(item: $editingEvent) { EventEditSheet(agendaEvent: $0) { Task { await load() } } }
    }

    private var notConnected: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 28)).foregroundColor(Theme.textFaint)
            Text("Connect Google Calendar in Settings to see your agenda.")
                .font(.system(size: 13)).foregroundColor(Theme.textLo)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }

    private var weekHeader: some View {
        HStack {
            Button { weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart)! } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(weekRangeLabel).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textHi)
            Spacer()
            Button { weekStart = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)! } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .bottom)
    }

    private var weekRangeLabel: String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(f.string(from: weekStart)) – \(f.string(from: end))"
    }

    private var byDay: [(Date, [AgendaEvent])] {
        let cal = Calendar.current
        var buckets: [Date: [AgendaEvent]] = [:]
        for e in events {
            let day = cal.startOfDay(for: e.event.start)
            buckets[day, default: []].append(e)
        }
        return (0..<7).compactMap { i -> (Date, [AgendaEvent])? in
            guard let day = cal.date(byAdding: .day, value: i, to: weekStart) else { return nil }
            return (day, (buckets[day] ?? []).sorted { $0.event.start < $1.event.start })
        }
    }

    private var agendaList: some View {
        List {
            ForEach(byDay, id: \.0) { day, items in
                Section {
                    if items.isEmpty {
                        Text("No events").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                    } else {
                        ForEach(items) { e in
                            Button {
                                if e.editable { editingEvent = e }
                            } label: {
                                HStack {
                                    Circle().fill(e.color.map { Color(hex: UInt32($0.dropFirst(), radix: 16) ?? 0) } ?? Theme.accent)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.event.summary).font(.system(size: 14)).foregroundColor(Theme.text)
                                        Text(e.event.isAllDay ? "All day" : timeString(e.event.start))
                                            .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                                    }
                                    Spacer()
                                    if !e.editable { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundColor(Theme.textFaint) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(dayLabel(day)).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.textFaint)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMM"
        return f.string(from: d).uppercased()
    }
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: d)
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let calId = try await gcal.ensureCalendar(known: store.craftCalendarId)
            if store.craftCalendarId != calId { store.craftCalendarId = calId }
            let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
            events = try await gcal.listAgenda(craftCalId: calId, from: weekStart, to: end)
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }
}

extension Calendar {
    func startOfWeekContainingToday() -> Date {
        let today = startOfDay(for: Date())
        let weekday = component(.weekday, from: today)
        let diff = (weekday - firstWeekday + 7) % 7
        return date(byAdding: .day, value: -diff, to: today) ?? today
    }
}

/// One-shot "Send to Calendar" push for a task — mirrors the Mac app's
/// SendToCalendarSheet exactly (title/date/time/repeat+until, no sync back).
struct SendToCalendarSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gcal = GoogleCalendar.shared
    let task: CraftTask

    @State private var date = Date()
    @State private var durationMinutes = 30
    @State private var repeatKind: RepeatKind = .none
    @State private var repeatUntil: Date?
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if !gcal.isConnected {
                    Text("Connect Google Calendar in Settings first.").foregroundColor(Theme.textLo)
                } else {
                    Section("When") {
                        DatePicker("Date & time", selection: $date)
                        Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...240, step: 5)
                    }
                    Section("Repeat") {
                        Picker("Repeat", selection: $repeatKind) {
                            ForEach([RepeatKind.none, .daily, .weekly, .weekday, .monthly], id: \.self) { k in
                                Text(k.label).tag(k)
                            }
                        }
                        if repeatKind != .none {
                            DatePicker("Until", selection: Binding(get: { repeatUntil ?? date }, set: { repeatUntil = $0 }), displayedComponents: .date)
                        }
                    }
                    if let error { Text(error).foregroundColor(Theme.danger) }
                }
            }
            .navigationTitle("Send to Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") { Task { await send() } }
                        .disabled(!gcal.isConnected || sending)
                }
            }
        }
    }

    private func send() async {
        sending = true
        error = nil
        do {
            let calId = try await gcal.ensureCalendar(known: store.craftCalendarId)
            if store.craftCalendarId != calId { store.craftCalendarId = calId }
            let input = GoogleCalendar.EventInput(
                title: task.displayTitle, start: date, durationMinutes: durationMinutes,
                repeatKind: repeatKind, repeatUntil: repeatUntil, craftTaskId: task.id)
            _ = try await gcal.createEvent(calId: calId, input)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        sending = false
    }
}

/// Edit or delete an existing "Craft Tasks" calendar event.
struct EventEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gcal = GoogleCalendar.shared
    let agendaEvent: AgendaEvent
    let onChange: () -> Void

    @State private var title: String
    @State private var date: Date
    @State private var saving = false
    @State private var error: String?

    init(agendaEvent: AgendaEvent, onChange: @escaping () -> Void) {
        self.agendaEvent = agendaEvent
        self.onChange = onChange
        _title = State(initialValue: agendaEvent.event.summary)
        _date = State(initialValue: agendaEvent.event.start)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Date & time", selection: $date)
                if let error { Text(error).foregroundColor(Theme.danger) }
                Button(role: .destructive) { Task { await delete() } } label: { Text("Delete event") }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        do {
            _ = try await gcal.updateEvent(calId: agendaEvent.calendarId, eventId: agendaEvent.event.id,
                                           GoogleCalendar.EventInput(title: title, start: date))
            onChange(); dismiss()
        } catch { self.error = error.localizedDescription }
        saving = false
    }
    private func delete() async {
        saving = true
        do {
            try await gcal.deleteEvent(calId: agendaEvent.calendarId, eventId: agendaEvent.event.id)
            onChange(); dismiss()
        } catch { self.error = error.localizedDescription }
        saving = false
    }
}
