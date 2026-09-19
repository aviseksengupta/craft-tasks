import WatchConnectivity
import Foundation

/// Receives the pomodoro length and "Today includes overdue" setting
/// mirrored from the paired iPhone app — see the iOS-side WatchSettingsSync
/// for why (the Watch has no settings screen of its own).
@MainActor
final class WatchSettingsReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSettingsReceiver()

    weak var store: Store?
    weak var pomodoro: PomodoroController?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Applies whatever the phone last sent, even if that happened before
    /// this launch — WCSession retains the latest application context.
    func applyCurrentContext() {
        guard WCSession.isSupported() else { return }
        apply(WCSession.default.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.applyCurrentContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    private func apply(_ context: [String: Any]) {
        if let minutes = context["pomodoroMinutes"] as? Int {
            pomodoro?.settings.pomodoroMinutes = minutes
        }
        if let overdue = context["todayIncludesOverdue"] as? Bool {
            store?.todayIncludesOverdue = overdue
        }
    }
}
