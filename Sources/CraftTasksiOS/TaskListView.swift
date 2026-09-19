import SwiftUI

/// The task-list content used for Home / All Tasks / Today / This Week /
/// Inbox / a saved view — everything that's just "show `store.filter`'s
/// matching tasks". Groups + stacked/kanban layout come straight from the
/// filter, same as the Mac app and the PWA.
struct TaskListView: View {
    @EnvironmentObject var store: Store
    let title: String
    var showFilterControls: Bool = true

    private var tasks: [CraftTask] { store.apply(store.filter) }
    private var groups: [(String, [CraftTask])] { store.group(tasks, by: store.filter.groupBy ?? .document) }
    private var isKanban: Bool { (store.filter.layout ?? .stacked) == .kanban }

    var body: some View {
        VStack(spacing: 0) {
            header
            if tasks.isEmpty {
                emptyState
            } else if isKanban {
                kanbanBody
            } else {
                stackedBody
            }
        }
        .background(Theme.bg)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundColor(Theme.textHi)
                Text("\(tasks.count)").font(.system(size: 12)).foregroundColor(Theme.textFaint)
                Spacer()
            }
            if showFilterControls {
                HStack(spacing: 8) {
                    Chip(text: "Completed", icon: store.showCompleted ? "eye" : "eye.slash",
                         active: !store.showCompleted, small: true)
                        .onTapGesture { store.showCompleted.toggle() }
                    Chip(text: "Backlog", icon: store.showBacklog ? "eye" : "eye.slash",
                         active: !store.showBacklog, small: true)
                        .onTapGesture { store.showBacklog.toggle() }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .background(Theme.bg)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundColor(Theme.textFaint)
            Text("Nothing here").font(.system(size: 14)).foregroundColor(Theme.textLo)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var stackedBody: some View {
        List {
            ForEach(groups, id: \.0) { name, items in
                Section {
                    ForEach(items) { task in
                        TaskRowView(task: task)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Theme.bg)
                            .listRowSeparatorTint(Theme.stroke)
                    }
                } header: {
                    Text(name.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                        .foregroundColor(Theme.textFaint)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }

    private var kanbanBody: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(groups, id: \.0) { name, items in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(name.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
                            Text("\(items.count)").font(.system(size: 10)).foregroundColor(Theme.textFaint)
                        }
                        .foregroundColor(Theme.textFaint)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(items) { task in
                                    TaskRowView(task: task)
                                    Divider().overlay(Theme.stroke)
                                }
                            }
                        }
                    }
                    .frame(width: 300)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                }
            }
            .scrollTargetLayout()
            .padding(14)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}
