import SwiftUI
import UserNotifications

@main
struct CraftTasksiOSApp: App {
    @StateObject private var store = Store()
    @StateObject private var pomodoro = PomodoroController()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let liveActivity = PomodoroLiveActivityManager()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .preferredColorScheme(.dark)
                .onAppear {
                    guard store.pomodoro == nil else { return }
                    store.pomodoro = pomodoro
                    pomodoro.store = store
                    pomodoro.restoreIfNeeded()
                    liveActivity.sync(with: pomodoro)
                    syncWatchSettings()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        pomodoro.reconcileOnForeground()
                        Task { await store.sync() }
                        liveActivity.sync(with: pomodoro)
                    }
                }
                .onChange(of: pomodoro.phase) { _, _ in liveActivity.sync(with: pomodoro) }
                .onChange(of: pomodoro.settings.pomodoroMinutes) { _, _ in syncWatchSettings() }
                .onChange(of: pomodoro.settings.reminderMinutes) { _, _ in syncWatchSettings() }
                .onChange(of: store.todayIncludesOverdue) { _, _ in syncWatchSettings() }
        }
    }

    private func syncWatchSettings() {
        WatchSettingsSync.shared.sync(.init(
            pomodoroMinutes: pomodoro.settings.pomodoroMinutes,
            reminderMinutes: pomodoro.settings.reminderMinutes,
            todayIncludesOverdue: store.todayIncludesOverdue))
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let stillWorking = UNNotificationAction(identifier: "STILL_WORKING", title: "Yes, still working", options: [])
        let another = UNNotificationAction(identifier: "ANOTHER_LOOP", title: "Start another", options: [])
        let stop = UNNotificationAction(identifier: "STOP_TIMER", title: "Stop", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "POMODORO_REMINDER", actions: [stillWorking],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "POMODORO_DONE", actions: [another, stop],
                                   intentIdentifiers: [], options: []),
        ])
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case "STILL_WORKING": PomodoroController.shared?.confirmStillWorking()
            case "ANOTHER_LOOP": PomodoroController.shared?.startAnotherLoop()
            case "STOP_TIMER": PomodoroController.shared?.stop()
            default: break
            }
            completionHandler()
        }
    }
}
