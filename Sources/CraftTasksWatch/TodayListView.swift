import SwiftUI

/// The entire watch app: today's open tasks, nothing else. Two actions per
/// task — start a pomodoro, and mark in-progress/complete — both calling
/// the exact same shared Store/PomodoroController methods every other
/// client uses. No add task, no edit, no settings, no other lists.
struct TodayListView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pomodoro: PomodoroController

    /// "Today" means exactly what it means everywhere else in the app:
    /// TaskFilter's own .today date-scope logic, reused verbatim.
    private var todayFilter: TaskFilter {
        var f = TaskFilter()
        f.states = [.todo]
        f.dateScope = .today
        return f
    }

    private var tasks: [CraftTask] {
        // Always folds in overdue tasks — on Mac/iPhone this is the
        // "Today includes overdue" setting, but the watch deliberately has
        // no settings screen at all, so there's nowhere to turn it off.
        // Defaulting to on is the right call here: a watch glance is for
        // "what do I need to do right now," and a stale overdue task is
        // exactly that.
        store.tasks
            .filter { todayFilter.matches($0, todayIncludesOverdue: true) }
            .sorted(by: Store.taskSort)
    }

    var body: some View {
        NavigationStack {
            List {
                if store.syncing && tasks.isEmpty {
                    ProgressView()
                } else if tasks.isEmpty {
                    Text("Nothing due today").font(.system(size: 13)).foregroundColor(.secondary)
                } else {
                    ForEach(tasks) { task in
                        WatchTaskRow(task: task)
                    }
                }
            }
            .navigationTitle("Today")
            .refreshable { await store.sync() }
        }
        .task { await store.sync() }
    }
}

private struct WatchTaskRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pomodoro: PomodoroController
    let task: CraftTask
    @State private var showStart = false

    private var isInProgress: Bool { task.tags.contains("inprogress") }
    private var isRunning: Bool { pomodoro.isRunningTask(task.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.displayTitle).font(.system(size: 14, weight: .medium)).lineLimit(2)
            if isRunning {
                Text(pomodoro.labelString).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            HStack(spacing: 8) {
                Button {
                    store.toggleTag("inprogress", on: task)
                } label: {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(isInProgress ? .black : .primary)
                }
                .buttonStyle(.bordered)
                .tint(isInProgress ? .orange : .gray)

                Button {
                    store.markDone(task)
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button {
                    if isRunning { pomodoro.stop() }
                    else if pomodoro.canStart(task.id) { showStart = true }
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "timer")
                }
                .buttonStyle(.bordered)
                .tint(isRunning ? .red : .blue)
                .disabled(!isRunning && !pomodoro.canStart(task.id))
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Start Pomodoro", isPresented: $showStart, titleVisibility: .visible) {
            Button("Start (\(pomodoro.settings.pomodoroMinutes) min)") { pomodoro.start(task: task, status: "") }
            Button("Cancel", role: .cancel) {}
        }
    }
}
