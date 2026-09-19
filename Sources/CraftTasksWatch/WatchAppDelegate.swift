import WatchKit
import UserNotifications

/// Registers the same notification action categories the Mac and iPhone
/// apps register (AppDelegate in App.swift / CraftTasksiOSApp.swift) and
/// wires their responses back into the shared PomodoroController. Without
/// this, a pomodoro reminder/done notification on the Watch showed up but
/// tapping "Yes, still working" / "Start another" / "Stop" did nothing —
/// nobody was listening for the response.
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
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
