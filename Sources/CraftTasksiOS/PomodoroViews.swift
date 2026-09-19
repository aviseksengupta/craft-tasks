import SwiftUI

/// Per-row pomodoro badge — tapping an idle badge asks for the optional
/// status text (mirrors the Mac app's menu-bar prompt), tapping the active
/// task's badge stops it. Same underlying PomodoroController calls as
/// every other platform.
struct PomodoroRowButton: View {
    @EnvironmentObject var pomodoro: PomodoroController
    let task: CraftTask
    @State private var showStart = false

    var body: some View {
        Button {
            if pomodoro.isRunningTask(task.id) {
                pomodoro.toggleActive()
            } else if pomodoro.canStart(task.id) {
                showStart = true
            }
        } label: {
            Image(systemName: pomodoro.isRunningTask(task.id) ? "timer.circle.fill" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(pomodoro.isRunningTask(task.id) ? .black : Theme.textLo)
                .frame(width: 26, height: 26)
                .background(Circle().fill(pomodoro.isRunningTask(task.id) ? Theme.accent : Theme.panelHi))
                .overlay(Circle().stroke(pomodoro.isRunningTask(task.id) ? Theme.accent : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!pomodoro.canStart(task.id) && !pomodoro.isRunningTask(task.id))
        .opacity(!pomodoro.canStart(task.id) && !pomodoro.isRunningTask(task.id) ? 0.35 : 1)
        .sheet(isPresented: $showStart) { StartPomodoroSheet(task: task) }
    }
}

struct StartPomodoroSheet: View {
    @EnvironmentObject var pomodoro: PomodoroController
    @Environment(\.dismiss) private var dismiss
    let task: CraftTask
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start Pomodoro").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.textHi)
            Text(task.displayTitle).font(.system(size: 13)).foregroundColor(Theme.textLo).lineLimit(2)
            VStack(alignment: .leading, spacing: 6) {
                Text("STATUS (OPTIONAL)").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundColor(Theme.textFaint)
                TextField("What are you doing?", text: $status)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chipBg))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
            }
            Text("\(pomodoro.settings.pomodoroMinutes) minutes").font(.system(size: 12)).foregroundColor(Theme.textFaint)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start") {
                    pomodoro.start(task: task, status: status)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .padding(22)
        .presentationDetents([.height(260)])
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Persistent status pill shown above the bottom tab bar whenever a
/// pomodoro is running — the iPhone stand-in for the Mac app's menu bar
/// entry. Tapping it opens the same controls as `PomodoroMenuContent`.
struct PomodoroStatusBar: View {
    @EnvironmentObject var pomodoro: PomodoroController
    @State private var showSheet = false

    private var timerDisplay: String {
        switch pomodoro.phase {
        case .running: return PomodoroController.clock(pomodoro.remaining)
        case .pausedForReminder: return "Paused"
        case .awaitingLoopChoice: return "Done"
        case .idle: return ""
        }
    }

    private var subtitle: String {
        if !pomodoro.statusText.isEmpty { return pomodoro.statusText }
        switch pomodoro.phase {
        case .pausedForReminder: return "Still working on this?"
        case .awaitingLoopChoice: return "Run another loop?"
        default: return "In progress"
        }
    }

    var body: some View {
        if pomodoro.isActive {
            HStack(spacing: 12) {
                Button { showSheet = true } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.16)).frame(width: 48, height: 48)
                            Image(systemName: pomodoro.phase == .pausedForReminder ? "pause.fill" : "timer")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pomodoro.activeTaskTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textHi)
                                .lineLimit(1)
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textLo)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(timerDisplay)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { pomodoro.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.destructive))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 76)
            .background(Theme.panelHi)
            .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
            .sheet(isPresented: $showSheet) { PomodoroControlSheet() }
        }
    }
}

struct PomodoroControlSheet: View {
    @EnvironmentObject var pomodoro: PomodoroController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "timer").foregroundColor(Theme.accent)
                Text("Pomodoro").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.textHi)
                Spacer()
                Text(PomodoroController.clock(pomodoro.remaining))
                    .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundColor(Theme.textHi)
            }
            Text(pomodoro.activeTaskTitle).font(.system(size: 14)).foregroundColor(Theme.textLo)
            if !pomodoro.statusText.isEmpty {
                Text(pomodoro.statusText).font(.system(size: 12)).foregroundColor(Theme.textFaint)
            }

            switch pomodoro.phase {
            case .running:
                Button {
                    pomodoro.stop(); dismiss()
                } label: { fullWidthButton("Stop", destructive: true) }
            case .pausedForReminder:
                Text("Still working on this?").font(.system(size: 13)).foregroundColor(Theme.danger)
                Button {
                    pomodoro.confirmStillWorking(); dismiss()
                } label: { fullWidthButton("Yes, still working") }
                Button {
                    pomodoro.stop(); dismiss()
                } label: { fullWidthButton("Stop", destructive: true) }
            case .awaitingLoopChoice:
                Text("Pomodoro done — run another loop?").font(.system(size: 13)).foregroundColor(Theme.textLo)
                Button {
                    pomodoro.startAnotherLoop(); dismiss()
                } label: { fullWidthButton("Start another") }
                Button {
                    pomodoro.stop(); dismiss()
                } label: { fullWidthButton("Stop", destructive: true) }
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .padding(22)
        .presentationDetents([.medium])
        .background(Theme.bg.ignoresSafeArea())
    }

    private func fullWidthButton(_ title: String, destructive: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(destructive ? .white : .black)
            .background(RoundedRectangle(cornerRadius: 10).fill(destructive ? Theme.destructive : Theme.accent))
    }
}
