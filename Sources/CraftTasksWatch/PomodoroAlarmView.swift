import SwiftUI
import WatchKit

/// Takes over the whole screen the moment a pomodoro reminder fires or a
/// loop finishes — the "cannot be missed" surface the user asked for,
/// on top of (not instead of) the ordinary local notification. Plays a
/// repeating haptic the whole time it's up, which only a system alert or
/// another app coming frontmost can interrupt; there's no watchOS API for
/// a haptic that keeps firing once the screen sleeps or the app is
/// backgrounded without Apple's alarm-clock entitlement, so this covers
/// the case where you're actually looking at the watch, and the
/// time-sensitive notification (Pomodoro.swift) covers the rest.
struct PomodoroAlarmView: View {
    @EnvironmentObject var pomodoro: PomodoroController
    @State private var hapticTimer: Timer?

    private var isDone: Bool { pomodoro.phase == .awaitingLoopChoice }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "bell.and.waves.left.and.right.fill")
                .font(.system(size: 34))
                .foregroundColor(.orange)
                .symbolEffect(.pulse, options: .repeating)

            Text(isDone ? "Pomodoro done" : "Still working on this?")
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.center)

            Text(pomodoro.activeTaskTitle)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Spacer(minLength: 6)

            if isDone {
                Button("Start another") { pomodoro.startAnotherLoop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            } else {
                Button("Yes, still working") { pomodoro.confirmStillWorking() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            Button("Stop", role: .destructive) { pomodoro.stop() }
        }
        .padding()
        .onAppear(perform: startHapticLoop)
        .onDisappear(perform: stopHapticLoop)
    }

    private func startHapticLoop() {
        stopHapticLoop()
        WKInterfaceDevice.current().play(.notification)
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func stopHapticLoop() {
        hapticTimer?.invalidate()
        hapticTimer = nil
    }
}
