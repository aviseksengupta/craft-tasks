import SwiftUI
import UserNotifications

@main
struct CraftTasksApp: App {
    @StateObject private var store = Store()
    @StateObject private var pomodoro = PomodoroController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    guard store.pomodoro == nil else { return }
                    store.pomodoro = pomodoro
                    pomodoro.store = store
                    pomodoro.restoreIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Sync Now") { Task { await store.sync() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: menuBarInserted) {
            PomodoroMenuContent()
                .environmentObject(store)
                .environmentObject(pomodoro)
        } label: {
            Image(systemName: pomodoro.phase == .pausedForReminder ? "pause.circle" : "timer")
            Text(pomodoro.labelString)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(get: { pomodoro.isActive }, set: { _ in })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Show pomodoro banners even while the app is frontmost.
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
