import SwiftUI

/// The app shell — mirrors the PWA's mobile chrome exactly: a bottom tab
/// bar (Home/Tasks/Today/Docs/Menu), a floating "+" button, and a
/// full-screen "Menu" sheet for everything else, instead of the Mac app's
/// three-pane desktop layout.
struct RootShellView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pomodoro: PomodoroController
    @State private var section: AppSection = .home
    @State private var showMenu = false
    @State private var showAddTask = false
    @State private var booted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                content
                    .toolbar(.hidden, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    PomodoroStatusBar()
                    bottomBar
                }
            }

            Button { showAddTask = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Theme.accent))
                    .craftShadow(radius: 10, y: 4)
            }
            .padding(.bottom, 92)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            guard !booted else { return }
            section = store.navigateHome()
            booted = true
        }
        .sheet(isPresented: $showMenu) { MenuView(section: $section) }
        .sheet(isPresented: $showAddTask) { AddTaskSheet() }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .documents: DocumentsView(section: $section)
        case .views: ViewsListView(section: $section)
        case .dashboards: DashboardsListView(section: $section)
        case .dashboard(let id): DashboardDetailView(dashboardId: id)
        case .calendar: CalendarPageView()
        default: TaskListView(title: title(for: section))
        }
    }

    private func title(for s: AppSection) -> String {
        switch s {
        case .home: return "Home"
        case .allTasks: return "All Tasks"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .inbox: return "Inbox"
        case .saved(let id): return store.savedFilters.first { $0.id == id }?.name ?? "View"
        default: return "Craft Tasks"
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tab(icon: "house", label: "Home", active: isHome) {
                section = store.navigateHome()
            }
            tab(icon: "tray.full", label: "Tasks", active: section == .allTasks) {
                store.selectAllTasks(); section = .allTasks
            }
            tab(icon: "sun.max", label: "Today", active: section == .today) {
                store.selectToday(); section = .today
            }
            tab(icon: "doc", label: "Docs", active: section == .documents) {
                section = .documents
            }
            tab(icon: "line.3.horizontal", label: "Menu", active: menuActive) {
                showMenu = true
            }
        }
        .padding(.top, 8)
        .background(Theme.panel)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
    }

    private var isHome: Bool { section == (store.homeSection ?? .home) }
    private var menuActive: Bool {
        switch section {
        case .inbox, .thisWeek, .views, .dashboards, .dashboard, .saved, .calendar: return true
        default: return false
        }
    }

    private func tab(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19, weight: active ? .semibold : .regular))
                Text(label).font(.system(size: 10, weight: active ? .semibold : .regular))
            }
            .foregroundColor(active ? Theme.textHi : Theme.textFaint)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }
}
