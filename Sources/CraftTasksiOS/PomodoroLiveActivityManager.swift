import ActivityKit
import Foundation

/// Drives a Live Activity (Lock Screen + Dynamic Island) mirroring
/// PomodoroController's state — the iPhone-native surface for "a timer is
/// running" instead of only the in-app status pill. The activity's
/// countdown is rendered by the widget extension via `Text(timerInterval:)`
/// from `endDate`, so this only needs to push an update on discrete state
/// changes (start / pause-for-reminder / done / stop), not every tick.
@MainActor
final class PomodoroLiveActivityManager {
    private var activity: Activity<PomodoroActivityAttributes>?

    func sync(with pomodoro: PomodoroController) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard pomodoro.isActive else {
            end()
            return
        }

        let state = PomodoroActivityAttributes.ContentState(
            taskTitle: pomodoro.activeTaskTitle,
            statusText: pomodoro.statusText,
            phase: pomodoro.phase.rawValue,
            endDate: pomodoro.currentEndsAt,
            remainingAtPause: pomodoro.currentEndsAt == nil ? pomodoro.remaining : nil)

        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            let attrs = PomodoroActivityAttributes(startedAt: Date())
            activity = try? Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil))
        }
    }

    private func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task { await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
