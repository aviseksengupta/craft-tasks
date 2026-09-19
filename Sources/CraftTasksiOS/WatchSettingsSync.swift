import WatchConnectivity
import Foundation

/// Pushes the pomodoro length, reminder interval, and "Today includes
/// overdue" setting to the paired Watch app via WatchConnectivity's
/// application context. The Watch has no settings screen of its own —
/// these are the only per-device settings that change what it shows/does,
/// so rather than duplicate a settings UI there, it just mirrors whatever's
/// set here. `updateApplicationContext` (not a message/transfer) is the
/// right primitive for this: it only ever keeps the latest value, delivered
/// to the Watch next time it's reachable even if it wasn't running when
/// this was called.
@MainActor
final class WatchSettingsSync: NSObject, WCSessionDelegate {
    static let shared = WatchSettingsSync()

    struct Settings {
        var pomodoroMinutes: Int
        var reminderMinutes: Int
        var todayIncludesOverdue: Bool
    }

    /// The most recent values `sync(...)` was asked to send. Activation is
    /// asynchronous — a call made right at launch (the common case, from
    /// `.onAppear`) almost always arrives before `WCSession` finishes
    /// activating, so it has nothing to actually send yet. Caching the
    /// last request and flushing it once `activationDidCompleteWith`
    /// fires (state `.activated`) means that first call isn't just lost.
    private var pending: Settings?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sync(_ settings: Settings) {
        pending = settings
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        send(settings)
    }

    private func send(_ settings: Settings) {
        try? WCSession.default.updateApplicationContext([
            "pomodoroMinutes": settings.pomodoroMinutes,
            "reminderMinutes": settings.reminderMinutes,
            "todayIncludesOverdue": settings.todayIncludesOverdue,
        ])
        pending = nil
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard activationState == .activated, let pending else { return }
            self.send(pending)
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
