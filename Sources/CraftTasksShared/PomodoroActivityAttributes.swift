import ActivityKit
import Foundation

/// Shared between the app (starts/updates/ends the activity) and the
/// widget extension (renders it) — must be identical in both targets,
/// which is why this one file has membership in both.
struct PomodoroActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var taskTitle: String
        var statusText: String
        /// Mirrors PomodoroController.Phase.rawValue ("running" |
        /// "pausedForReminder" | "awaitingLoopChoice") — kept as a plain
        /// String rather than importing the enum itself, since the widget
        /// extension doesn't otherwise depend on Pomodoro.swift.
        var phase: String
        /// Set only while `phase == "running"` — the widget renders the
        /// live countdown from this via `Text(timerInterval:)`, which
        /// self-updates with no further app involvement.
        var endDate: Date?
        /// Snapshot of seconds left, captured the moment the phase left
        /// "running" (paused for a reminder, or the loop finished) — shown
        /// as a static number since there's no endDate to count down to.
        var remainingAtPause: TimeInterval?
    }

    var startedAt: Date
}
