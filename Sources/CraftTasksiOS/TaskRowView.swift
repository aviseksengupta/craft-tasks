import SwiftUI

/// Port of the Mac app's TaskRow (Views.swift) — same badges, same
/// Store calls, touch-first layout (swipe actions instead of hover, a
/// tap opens the edit sheet instead of a hover-revealed pencil icon).
struct TaskRowView: View {
    @EnvironmentObject var store: Store
    let task: CraftTask
    @State private var editing = false

    var tagColor: Color? {
        for tag in task.tags {
            if let hex = store.tagColors[tag], let uint32 = UInt32(hex, radix: 16) { return Color(hex: uint32) }
        }
        return nil
    }

    var dateBadge: (String, Bool)? {
        let today = Calendar.current.startOfDay(for: Date())
        guard let d = task.scheduleDay ?? task.deadlineDay else { return nil }
        let overdue = d < today && task.state == .todo
        if Calendar.current.isDateInToday(d) { return ("Today", false) }
        if Calendar.current.isDateInTomorrow(d) { return ("Tomorrow", false) }
        let df = DateFormatter(); df.dateFormat = "d MMM"
        return (df.string(from: d), overdue)
    }

    var isPending: Bool { task.id.hasPrefix("local-") }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RowCheckboxView(task: task).padding(.top, 1)

            Button { if !isPending { editing = true } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.displayTitle)
                        .font(.system(size: 15))
                        .foregroundColor(task.state == .todo ? Theme.text : Theme.textFaint)
                        .strikethrough(task.state != .todo, color: Theme.textFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if isPending {
                            HStack(spacing: 3) {
                                ProgressView().controlSize(.mini)
                                Text("syncing").font(.system(size: 11)).foregroundColor(Theme.textFaint)
                            }
                        }
                        ForEach(task.tags, id: \.self) { tag in
                            Text("#\(tag)").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textLo)
                        }
                        if let badge = dateBadge {
                            HStack(spacing: 3) {
                                Image(systemName: task.deadlineDate != nil && task.scheduleDate == nil ? "flag" : "calendar")
                                    .font(.system(size: 9))
                                Text(badge.0).font(.system(size: 11, weight: badge.1 ? .semibold : .regular))
                            }
                            .foregroundColor(badge.1 ? Theme.danger : Theme.textFaint)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(badge.1 ? Theme.panelHi : .clear)
                            .clipShape(Capsule())
                        }
                        if task.state == .done, let c = task.completedDay {
                            Text("done \(c.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.system(size: 11)).foregroundColor(Theme.textFaint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if task.state == .todo && !isPending {
                VStack(spacing: 6) {
                    InProgressBadge(task: task)
                    PomodoroRowButton(task: task)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .opacity(isPending ? 0.7 : 1)
        .overlay(alignment: .leading) {
            if let tagColor { tagColor.frame(width: 4).cornerRadius(2, antialiased: true) }
        }
        .sheet(isPresented: $editing) { EditTaskSheet(task: task) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isPending {
                Button(role: .destructive) { Task { try? await store.deleteTask(task) } } label: {
                    Label("Delete", systemImage: "trash")
                }
                if let link = task.craftDeepLink(spaceId: store.spaceId) {
                    Link(destination: link) { Label("Craft", systemImage: "arrow.up.forward.app") }
                        .tint(Theme.textLo)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isPending { Button { store.cycleState(task) } label: { Label("Cycle", systemImage: "checkmark") }.tint(.green) }
        }
    }
}

struct InProgressBadge: View {
    @EnvironmentObject var store: Store
    let task: CraftTask
    static let tagName = "inprogress"

    var isActive: Bool { task.tags.contains(Self.tagName) }
    var activeColor: Color {
        if let hex = store.tagCheckboxColors[Self.tagName], let uint32 = UInt32(hex, radix: 16) { return Color(hex: uint32) }
        return Theme.accent
    }

    var body: some View {
        InProgressToggle(isActive: isActive, activeColor: isActive ? activeColor : nil) {
            store.toggleTag(Self.tagName, on: task)
        }
    }
}

struct RowCheckboxView: View {
    @EnvironmentObject var store: Store
    let task: CraftTask
    var isPending: Bool { task.id.hasPrefix("local-") }

    var checkboxRingColor: Color? {
        for tag in task.tags {
            if let hex = store.tagCheckboxColors[tag], let uint32 = UInt32(hex, radix: 16) { return Color(hex: uint32) }
        }
        return nil
    }

    var body: some View {
        Button { if !isPending { store.cycleState(task) } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(task.state == .todo ? Theme.chipBg : Theme.accent)
                RoundedRectangle(cornerRadius: 7)
                    .stroke(task.state == .todo ? (checkboxRingColor ?? Theme.stroke) : Theme.stroke,
                            lineWidth: task.state == .todo && checkboxRingColor != nil ? 2 : 1.5)
                switch task.state {
                case .todo: EmptyView()
                case .done: Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                case .canceled: Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.black)
                }
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }
}
