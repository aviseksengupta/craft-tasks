import SwiftUI
import UIKit

/// Port of the Mac app's SidebarSettingsSheet — item visibility, backlog
/// tag, tag colors, pomodoro settings, Google Calendar, sync log.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pomodoro: PomodoroController
    @Environment(\.dismiss) private var dismiss
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sidebar Items") {
                    ForEach(MenuNavItem.all) { item in
                        Picker(item.label, selection: binding(for: item.id)) {
                            ForEach(ItemVisibility.allCases) { v in Text(v.rawValue).tag(v) }
                        }
                    }
                }

                Section {
                    Toggle("Today includes overdue", isOn: $store.todayIncludesOverdue)
                } footer: { Text("When enabled, the Today view also shows overdue open tasks.") }

                Section {
                    TextField("later", text: Binding(get: { store.backlogTag }, set: { store.setBacklogTag($0) }))
                } header: { Text("Backlog Tag") } footer: {
                    Text("Tasks tagged #\(store.effectiveBacklogTag) are backlog/later tasks and can be hidden with the Backlog toggle.")
                }

                Section("Tag Colors") {
                    if store.allTags.isEmpty {
                        Text("No tags yet.").foregroundColor(Theme.textFaint)
                    } else {
                        ForEach(store.allTags.sorted(), id: \.self) { tag in
                            NavigationLink {
                                TagColorPickerView(tag: tag)
                            } label: {
                                HStack {
                                    Text("#\(tag)")
                                    Spacer()
                                    if let hex = store.tagColors[tag], let v = UInt32(hex, radix: 16) {
                                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: v)).frame(width: 18, height: 18)
                                    }
                                    if let hex = store.tagCheckboxColors[tag], let v = UInt32(hex, radix: 16) {
                                        Circle().stroke(Color(hex: v), lineWidth: 2).frame(width: 16, height: 16)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Stepper("Length: \(pomodoro.settings.pomodoroMinutes) min", value: $pomodoro.settings.pomodoroMinutes, in: 1...180)
                    Stepper(pomodoro.settings.reminderMinutes == 0 ? "Reminder: Off" : "Reminder: \(pomodoro.settings.reminderMinutes) min",
                            value: $pomodoro.settings.reminderMinutes, in: 0...120)
                } header: {
                    Text("Pomodoro")
                } footer: {
                    Text("0 = no reminder. Otherwise the timer pauses every N minutes and asks whether you're still working — it only resumes on Yes.")
                }

                Section {
                    GoogleCalendarSettingsRow()
                } header: { Text("Google Calendar") }

                Section {
                    BackupRestoreRow()
                } header: { Text("Backup & Restore") } footer: {
                    Text("Export your saved views, dashboards, pinned items and renamed documents as JSON — the same format the Mac app and web app use, so a config exported from one can be imported into another.")
                }

                Section {
                    HStack {
                        Text("Last sync")
                        Spacer()
                        Text(store.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Never")
                            .foregroundColor(Theme.textFaint)
                    }
                    Button("Sync now") { Task { await store.sync() } }
                    Button("View sync log") { showLog = true }
                } header: { Text("Sync") }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showLog) { LogViewerView() }
    }

    private func binding(for id: String) -> Binding<ItemVisibility> {
        Binding(get: { store.itemVisibility[id] ?? .shown }, set: { store.setItemVisibility(id, $0) })
    }
}

/// The same nav-item id set as MenuView, shared for the visibility picker.
struct MenuNavItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let section: AppSection

    static let all: [MenuNavItem] = [
        .init(id: "home", icon: "house", label: "Home", section: .home),
        .init(id: "allTasks", icon: "tray.full", label: "All Tasks", section: .allTasks),
        .init(id: "inbox", icon: "tray", label: "Inbox", section: .inbox),
        .init(id: "today", icon: "sun.max", label: "Today", section: .today),
        .init(id: "thisWeek", icon: "calendar.badge.clock", label: "This Week", section: .thisWeek),
        .init(id: "documents", icon: "doc", label: "Documents", section: .documents),
        .init(id: "views", icon: "list.bullet.rectangle", label: "Views", section: .views),
        .init(id: "dashboards", icon: "square.grid.2x2", label: "Dashboards", section: .dashboards),
        .init(id: "calendar", icon: "calendar", label: "Calendar", section: .calendar),
    ]
}

struct GoogleCalendarSettingsRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var gcal = GoogleCalendar.shared
    @State private var clientId = GoogleCalendar.clientID
    @State private var busy = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\"Send to Calendar\" pushes a task to a dedicated Craft Tasks calendar with a specific time. One-way push, no sync.")
                .font(.system(size: 12)).foregroundColor(Theme.textFaint)
            TextField("OAuth client id (…apps.googleusercontent.com)", text: $clientId, onCommit: commitClientId)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if gcal.isConnected {
                Label("Connected", systemImage: "checkmark.circle").foregroundColor(Theme.textLo)
                Button("Disconnect") { gcal.disconnect(); store.craftCalendarId = nil; status = "Disconnected" }
            } else {
                Button(busy ? "Connecting…" : "Connect Google Calendar") { Task { await connect() } }
                    .disabled(busy || clientId.trimmingCharacters(in: .whitespaces).isEmpty)
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
            status = "Connected — \"Craft Tasks\" calendar ready"
        } catch { status = error.localizedDescription }
        busy = false
    }
}

/// Port of the Mac app's BackupRestoreSection — same underlying
/// `Store.exportBackupJSON()`/`restoreBackup(fromJSON:)`/`restoreDefaultConfig()`,
/// with iOS-native chrome (share sheet + file picker instead of NSSavePanel/
/// NSOpenPanel, `UIPasteboard` instead of `NSPasteboard`).
struct BackupRestoreRow: View {
    @EnvironmentObject var store: Store
    @State private var showJSON = false
    @State private var json = ""
    @State private var status: String?
    @State private var shareURL: URL?
    @State private var showImportSheet = false
    @State private var confirmingReset = false

    var body: some View {
        // Group, not VStack/HStack — a Form Section treats each of a
        // Group's children as its own row with its own tap target. Stacking
        // several Buttons inside a VStack instead merges them into ONE row.
        //
        // Just as important: each presentation modifier (.sheet/
        // .confirmationDialog/etc.) is attached directly to the ONE button
        // that triggers it, not to this shared Group. A modifier attached
        // to the Group itself only ends up bound to one of the rows it
        // explodes into (whichever SwiftUI treats as that row's identity),
        // so only that single button actually worked — the others opened
        // nothing. Scoping each modifier to its own row's button fixes that.
        Group {
            Button("Show config JSON") {
                json = store.exportBackupJSON()
                showJSON = true
            }
            .sheet(isPresented: $showJSON) { ConfigJSONView(json: json) }

            Button("Share config file…") { shareToFile() }
                .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }

            Button("Import config JSON…") { showImportSheet = true }
                .sheet(isPresented: $showImportSheet) {
                    ImportConfigView { text in
                        do {
                            try store.restoreBackup(fromJSON: text)
                            status = "Config restored"
                        } catch {
                            status = "Restore failed: \(error.localizedDescription)"
                        }
                    }
                }

            Button("Reset to default", role: .destructive) { confirmingReset = true }
                .confirmationDialog("Reset to default configuration?", isPresented: $confirmingReset, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        store.restoreDefaultConfig()
                        status = "Reset to default configuration"
                    }
                } message: {
                    Text("This replaces your saved views, dashboards, and renamed documents.")
                }

            if let status {
                Text(status).font(.system(size: 12)).foregroundColor(Theme.textFaint)
            }
        }
    }

    private func shareToFile() {
        let text = store.exportBackupJSON()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("craft-tasks-config.json")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// Paste-JSON import — the primary way to restore config on iOS, since
/// getting a file onto the phone is more friction than copying text
/// (e.g. from the Mac app's "Show config JSON" via Universal Clipboard,
/// or pasted from Messages/Notes).
private struct ImportConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    let onImport: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste the config JSON exported from the Mac app, the web app, or another device.")
                    .font(.system(size: 12)).foregroundColor(Theme.textFaint)
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chipBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                Button("Paste from Clipboard") { text = UIPasteboard.general.string ?? "" }
                if let error {
                    Text(error).font(.system(size: 12)).foregroundColor(Theme.danger)
                }
                Spacer()
            }
            .padding()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Import Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") {
                        onImport(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

private struct ConfigJSONView: View {
    @Environment(\.dismiss) private var dismiss
    let json: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Config JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") { UIPasteboard.general.string = json }
                }
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct TagColorPickerView: View {
    @EnvironmentObject var store: Store
    let tag: String

    let swatches: [(String, Color)] = [
        ("ff5733", Color(hex: 0xFF5733)), ("33ff57", Color(hex: 0x33FF57)), ("3357ff", Color(hex: 0x3357FF)),
        ("ff33f5", Color(hex: 0xFF33F5)), ("ffd700", Color(hex: 0xFFD700)), ("ff8c00", Color(hex: 0xFF8C00)),
        ("00ced1", Color(hex: 0x00CED1)), ("ff69b4", Color(hex: 0xFF69B4)), ("e74c3c", Color(hex: 0xE74C3C)),
        ("2ecc71", Color(hex: 0x2ECC71)), ("1abc9c", Color(hex: 0x1ABC9C)), ("3498db", Color(hex: 0x3498DB)),
        ("9b59b6", Color(hex: 0x9B59B6)), ("8e44ad", Color(hex: 0x8E44AD)), ("f1c40f", Color(hex: 0xF1C40F)),
        ("e67e22", Color(hex: 0xE67E22)), ("95a5a6", Color(hex: 0x95A5A6)), ("2c3e50", Color(hex: 0x2C3E50)),
    ]
    let cols = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        Form {
            Section("Border color") {
                swatchGrid { store.setTagColor(tag: tag, color: $0) }
                Button("Clear") { store.setTagColor(tag: tag, color: nil) }
            }
            Section("Checkbox color") {
                swatchGrid { store.setTagCheckboxColor(tag: tag, color: $0) }
                Button("Clear") { store.setTagCheckboxColor(tag: tag, color: nil) }
            }
        }
        .navigationTitle("#\(tag)")
    }

    private func swatchGrid(_ pick: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(swatches, id: \.0) { hex, color in
                Button { pick(hex) } label: {
                    Circle().fill(color).frame(width: 32, height: 32)
                }
            }
        }
    }
}

struct LogViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = AppLog.shared.recent(120)

    var body: some View {
        NavigationStack {
            List(lines.reversed(), id: \.self) { line in
                Text(line).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textLo)
            }
            .navigationTitle("Sync Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { AppLog.shared.clear(); lines = [] }
                }
            }
        }
    }
}
