import Foundation
import SwiftUI
import UserNotifications

/// User-configurable pomodoro settings. Persisted as JSON in UserDefaults
/// (`pomodoroSettings`) and also carried in the app backup so it survives a
/// config export/restore.
struct PomodoroSettings: Codable, Equatable {
    var pomodoroMinutes: Int = 25
    /// Minutes between "are you still working on this?" reminders. 0 = off.
    var reminderMinutes: Int = 0

    static let `default` = PomodoroSettings()
}

/// Serializable snapshot of a running timer, mirrored to
/// `CraftTasks/pomodoro-run.json` so a quit/relaunch (or crash) mid-pomodoro
/// doesn't silently drop the in-progress work.
private struct PomodoroRunState: Codable {
    var taskId: String
    var taskTitle: String
    var status: String
    var phase: String            // running | pausedForReminder | awaitingLoopChoice
    var endsAt: Date?
    var intervalStart: Date
    var remaining: TimeInterval
}

/// One pomodoro timer for the whole app. Only one interval can run at a
/// time (`activeTaskId`), which is what makes "starting one disables all
/// others" true no matter which list the badges are shown on.
@MainActor
final class PomodoroController: ObservableObject {
    /// Set once by the app so notification-action handlers (which live on
    /// the AppDelegate, off the SwiftUI environment) can reach the live
    /// controller.
    static weak var shared: PomodoroController?

    enum Phase: String, Equatable {
        case idle
        case running
        case pausedForReminder
        case awaitingLoopChoice
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var activeTaskId: String?
    @Published private(set) var activeTaskTitle: String = ""
    /// The 2-word status the user types when starting a timer. Menu-bar
    /// only — never written to the task — but echoed into the work-log line.
    @Published private(set) var statusText: String = ""
    /// Seconds left in the current interval, updated once a second.
    @Published private(set) var remaining: TimeInterval = 0

    @Published var settings: PomodoroSettings = PomodoroController.loadSettings() {
        didSet {
            guard settings != oldValue else { return }
            Self.saveSettings(settings)
        }
    }

    /// Back-reference to the store, used to append work-log lines to a task
    /// (and route them through the store's retrying outbox).
    weak var store: Store?

    private var endsAt: Date?
    private var intervalStart: Date?
    private var ticker: Timer?
    private var reminderWork: DispatchWorkItem?
    private var authRequested = false

    init() {
        Self.shared = self
    }

    // MARK: - Query helpers used by the row badges

    var isActive: Bool { activeTaskId != nil }
    func isRunningTask(_ id: String) -> Bool { activeTaskId == id }
    func canStart(_ id: String) -> Bool { activeTaskId == nil }

    var labelString: String {
        switch phase {
        case .idle: return ""
        case .running: return "\(Self.clock(remaining))\(statusSuffix)"
        case .pausedForReminder: return "paused\(statusSuffix)"
        case .awaitingLoopChoice: return "done\(statusSuffix)"
        }
    }
    private var statusSuffix: String { statusText.isEmpty ? "" : " · \(statusText)" }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Control

    func start(task: CraftTask, status: String) {
        guard activeTaskId == nil else { return }
        requestAuthorizationIfNeeded()
        activeTaskId = task.id
        activeTaskTitle = task.displayTitle
        statusText = status.trimmingCharacters(in: .whitespacesAndNewlines)
        beginInterval()
        AppLog.shared.log("Pomodoro started \"\(statusText)\" [\(task.id)]")
    }

    /// User tapped the active badge. Running → stop & log. Paused → resume.
    func toggleActive() {
        switch phase {
        case .pausedForReminder: confirmStillWorking()
        case .running, .awaitingLoopChoice: stop()
        case .idle: break
        }
    }

    /// Full stop (badge tap while running, menu "Stop", or the task being
    /// completed/removed elsewhere). Writes the work-log line unless the
    /// current interval was already finalized (awaitingLoopChoice).
    func stop() {
        guard isActive else { return }
        if phase != .awaitingLoopChoice { finalizeInterval() }
        clear()
        AppLog.shared.log("Pomodoro stopped")
    }

    func startAnotherLoop() {
        guard phase == .awaitingLoopChoice, activeTaskId != nil else { return }
        beginInterval()
        AppLog.shared.log("Pomodoro loop restarted")
    }

    func confirmStillWorking() {
        guard phase == .pausedForReminder else { return }
        endsAt = Date().addingTimeInterval(remaining)
        phase = .running
        startTicker()
        scheduleReminder()
        persistRunState()
    }

    // MARK: - Interval lifecycle

    private func beginInterval() {
        let duration = TimeInterval(max(1, settings.pomodoroMinutes) * 60)
        intervalStart = Date()
        endsAt = Date().addingTimeInterval(duration)
        remaining = duration
        phase = .running
        startTicker()
        scheduleReminder()
        persistRunState()
    }

    private func completeInterval() {
        ticker?.invalidate(); ticker = nil
        reminderWork?.cancel(); reminderWork = nil
        finalizeInterval()
        remaining = 0
        phase = .awaitingLoopChoice
        persistRunState()
        notifyDone()
    }

    /// Appends one `work-log …` line for the interval that just ended.
    private func finalizeInterval() {
        guard let start = intervalStart, let taskId = activeTaskId else { return }
        let line = Self.workLogLine(status: statusText, start: start, stop: Date())
        store?.appendWorkLog(taskId: taskId, line: line)
        intervalStart = nil
    }

    private func clear() {
        ticker?.invalidate(); ticker = nil
        reminderWork?.cancel(); reminderWork = nil
        activeTaskId = nil
        activeTaskTitle = ""
        statusText = ""
        remaining = 0
        endsAt = nil
        intervalStart = nil
        phase = .idle
        clearRunState()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - Ticking

    private func startTicker() {
        ticker?.invalidate()
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard phase == .running, let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)
        if remaining <= 0 { completeInterval() }
    }

    // MARK: - Reminders

    private func scheduleReminder() {
        reminderWork?.cancel()
        let n = settings.reminderMinutes
        guard n > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.fireReminder() }
        }
        reminderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 60, execute: work)
    }

    private func fireReminder() {
        guard phase == .running else { return }
        ticker?.invalidate(); ticker = nil
        remaining = max(0, endsAt?.timeIntervalSinceNow ?? 0)
        endsAt = nil
        phase = .pausedForReminder
        persistRunState()
        notifyReminder()
    }

    // MARK: - Work-log formatting

    static func workLogLine(status: String, start: Date, stop: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        // The status is a menu-bar-only label; it is deliberately not
        // written into the task's work-log line.
        return "work-log start:\(f.string(from: start)) stop:\(f.string(from: stop))"
    }

    // MARK: - Notifications

    private func requestAuthorizationIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyReminder() {
        let c = UNMutableNotificationContent()
        c.title = "Still working on this?"
        c.body = activeTaskTitle
        c.categoryIdentifier = "POMODORO_REMINDER"
        c.sound = .default
        post(c, id: "pomodoro-reminder")
    }

    private func notifyDone() {
        let c = UNMutableNotificationContent()
        c.title = "Pomodoro done"
        c.body = "\(activeTaskTitle) — run another loop?"
        c.categoryIdentifier = "POMODORO_DONE"
        c.sound = .default
        post(c, id: "pomodoro-done")
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Settings persistence

    private static let settingsKey = "pomodoroSettings"

    private static func loadSettings() -> PomodoroSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(PomodoroSettings.self, from: data) else {
            return .default
        }
        return s
    }

    private static func saveSettings(_ s: PomodoroSettings) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - Run-state persistence (crash / relaunch recovery)

    private var runStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftTasks/pomodoro-run.json")
    }

    private func persistRunState() {
        guard let taskId = activeTaskId, let intervalStart else { clearRunState(); return }
        let state = PomodoroRunState(
            taskId: taskId, taskTitle: activeTaskTitle, status: statusText,
            phase: phase.rawValue, endsAt: endsAt, intervalStart: intervalStart,
            remaining: remaining)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: runStateURL)
        }
    }

    private func clearRunState() {
        try? FileManager.default.removeItem(at: runStateURL)
    }

    /// Called once at launch (after `store` is wired) to pick a timer back
    /// up. An interval whose end time has already passed is finalized
    /// straight away so its work-log line still lands.
    func restoreIfNeeded() {
        guard let data = try? Data(contentsOf: runStateURL),
              let s = try? JSONDecoder().decode(PomodoroRunState.self, from: data) else { return }

        activeTaskId = s.taskId
        activeTaskTitle = s.taskTitle
        statusText = s.status
        intervalStart = s.intervalStart

        switch Phase(rawValue: s.phase) ?? .idle {
        case .running:
            if let end = s.endsAt, end.timeIntervalSinceNow > 0 {
                endsAt = end
                remaining = end.timeIntervalSinceNow
                phase = .running
                startTicker()
                scheduleReminder()
            } else {
                // Interval elapsed while the app was closed — log it and stop.
                let stop = s.endsAt ?? Date()
                store?.appendWorkLog(taskId: s.taskId,
                                     line: Self.workLogLine(status: s.status, start: s.intervalStart, stop: stop))
                clear()
            }
        case .pausedForReminder:
            remaining = s.remaining
            phase = .pausedForReminder
        case .awaitingLoopChoice:
            remaining = 0
            phase = .awaitingLoopChoice
        case .idle:
            clear()
        }
        AppLog.shared.log("Pomodoro restored (\(phase.rawValue))")
    }
}
