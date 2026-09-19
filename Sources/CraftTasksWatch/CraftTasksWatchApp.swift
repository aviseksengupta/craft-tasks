import SwiftUI
import WatchKit

@main
struct CraftTasksWatchApp: App {
    @StateObject private var store = Store()
    @StateObject private var pomodoro = PomodoroController()
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TodayListView()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .onAppear {
                    WatchSettingsReceiver.shared.store = store
                    WatchSettingsReceiver.shared.pomodoro = pomodoro
                    WatchSettingsReceiver.shared.applyCurrentContext()
                    guard store.pomodoro == nil else { return }
                    store.pomodoro = pomodoro
                    pomodoro.store = store
                    pomodoro.restoreIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        pomodoro.reconcileOnForeground()
                        Task { await store.sync() }
                        WatchSettingsReceiver.shared.applyCurrentContext()
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { pomodoro.phase == .pausedForReminder || pomodoro.phase == .awaitingLoopChoice },
                    set: { _ in }
                )) {
                    PomodoroAlarmView().environmentObject(pomodoro)
                }
        }
    }
}
