import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen banner + Dynamic Island for a running pomodoro — same idea
/// as Apple's own Timer app: once started, the countdown is driven purely
/// by `Text(timerInterval:)` from the state's `endDate`, so it keeps
/// ticking live with zero further app involvement.
struct PomodoroLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(state: context.state, font: .title3.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.taskTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !context.state.statusText.isEmpty {
                            Text(context.state.statusText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            } compactTrailing: {
                countdown(state: context.state, font: .caption.monospacedDigit().bold())
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func countdown(state: PomodoroActivityAttributes.ContentState, font: Font) -> some View {
        if state.phase == "running", let end = state.endDate {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(font)
                .frame(maxWidth: 64)
        } else {
            Text(state.phase == "pausedForReminder" ? "Paused" : "Done")
                .font(font)
        }
    }
}

private struct LockScreenView: View {
    let state: PomodoroActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.18)).frame(width: 44, height: 44)
                Image(systemName: state.phase == "pausedForReminder" ? "pause.fill" : "timer")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(state.taskTitle).font(.headline).lineLimit(2)
                if !state.statusText.isEmpty {
                    Text(state.statusText).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.phase == "running", let end = state.endDate {
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            } else if let remaining = state.remainingAtPause {
                Text(PomodoroLiveActivityWidget.clock(remaining))
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
    }

    private var subtitle: String {
        switch state.phase {
        case "pausedForReminder": return "Still working on this?"
        case "awaitingLoopChoice": return "Pomodoro done — open the app to loop or stop"
        default: return "Craft Tasks"
        }
    }
}

extension PomodoroLiveActivityWidget {
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
