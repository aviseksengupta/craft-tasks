import SwiftUI

/// Shared small controls used across the task list, add/edit sheets and
/// dashboards — ported from the Mac app's EditTaskView.swift/Views.swift,
/// with hover states dropped (touch has no hover) and popovers kept (they
/// degrade to a sheet-like presentation on iPhone automatically).

struct TagChip: View {
    let tag: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text("#\(tag)").font(.system(size: 12, weight: .medium))
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.6)
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(Theme.chipBg))
            .foregroundColor(Theme.textLo)
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct DateChip: View {
    let title: String
    let icon: String
    @Binding var date: Date?
    @State private var showPicker = false

    private var display: String {
        guard let d = date else { return title }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { showPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: date == nil ? "plus" : icon).font(.system(size: 10, weight: .medium))
                    VStack(alignment: .leading, spacing: 1) {
                        if date != nil {
                            Text(title.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1)
                                .foregroundColor(Theme.textFaint)
                        }
                        Text(display).font(.system(size: 12, weight: date == nil ? .regular : .medium))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, date == nil ? 8 : 5)
            }
            .buttonStyle(.plain)

            if date != nil {
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundColor(Theme.textFaint)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .foregroundColor(date == nil ? Theme.textLo : Theme.text)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.chipBg))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(date == nil ? Theme.stroke : Theme.textFaint.opacity(0.5), lineWidth: 1))
        .sheet(isPresented: $showPicker) {
            MiniCalendarSheet(date: $date, title: title)
                .presentationDetents([.medium])
        }
    }
}

/// Same graphical month calendar as the Mac app's MiniCalendar, wrapped in
/// a sheet (a popover on iPhone has no anchor chrome worth keeping).
struct MiniCalendarSheet: View {
    @Binding var date: Date?
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth: Date

    init(date: Binding<Date?>, title: String) {
        _date = date
        self.title = title
        _displayedMonth = State(initialValue: date.wrappedValue ?? Date())
    }

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textHi)
                Spacer()
                Button("Done") { dismiss() }.foregroundColor(Theme.accent)
            }
            header
            weekdayRow
            dayGrid
            Rectangle().fill(Theme.stroke).frame(height: 1)
            quickActions
            Spacer()
        }
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            monthStepButton("chevron.left") { shiftMonth(-1) }
            Spacer()
            Text(monthTitle).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.textHi)
            Spacer()
            monthStepButton("chevron.right") { shiftMonth(1) }
        }
    }

    private func monthStepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.textLo)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.chipBg))
        }
        .buttonStyle(.plain)
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: displayedMonth) { displayedMonth = d }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var days: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) { result.append(d) }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var dayGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                if let d { dayCell(d) } else { Color.clear.frame(height: 36) }
            }
        }
    }

    private func dayCell(_ d: Date) -> some View {
        let isSelected = date.map { cal.isDate($0, inSameDayAs: d) } ?? false
        let isToday = cal.isDateInToday(d)
        return Button {
            date = cal.startOfDay(for: d)
        } label: {
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .black : Theme.text)
                .frame(width: 36, height: 36)
                .background(Circle().fill(isSelected ? Theme.accent : Color.clear))
                .overlay(Circle().stroke(isToday && !isSelected ? Theme.textLo : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            quickButton("Today") { let d = cal.startOfDay(for: Date()); date = d; displayedMonth = d }
            quickButton("Tomorrow") {
                guard let d = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) else { return }
                date = d; displayedMonth = d
            }
            Spacer()
            if date != nil {
                Button("Clear") { date = nil }.font(.system(size: 13)).foregroundColor(Theme.textFaint)
            }
        }
    }

    private func quickButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.chipBg))
                .foregroundColor(Theme.textLo)
        }
        .buttonStyle(.plain)
    }
}

/// Minimal wrapping HStack for tag chips — identical layout to the Mac app.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct StateCycleButton: View {
    @Binding var state: TaskState
    var ringColor: Color? = nil

    var body: some View {
        Button {
            switch state {
            case .todo: state = .done
            case .done: state = .canceled
            case .canceled: state = .todo
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(state == .todo ? Theme.chipBg : Theme.accent)
                RoundedRectangle(cornerRadius: 7)
                    .stroke(state == .todo ? (ringColor ?? Theme.stroke) : Theme.stroke,
                            lineWidth: state == .todo && ringColor != nil ? 2 : 1.5)
                switch state {
                case .todo: EmptyView()
                case .done: Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                case .canceled: Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(.black)
                }
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: state)
    }
}

/// One-tap "#inprogress" toggle — same visual language as the row badge.
struct InProgressToggle: View {
    let isActive: Bool
    let activeColor: Color?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .black : Theme.textLo)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isActive ? (activeColor ?? Theme.accent) : Theme.panelHi))
                .overlay(Circle().stroke(isActive ? (activeColor ?? Theme.accent) : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Opens the task's own block in Craft via its craftdocs:// deep link.
struct OpenInCraftButton: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textLo)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.panelHi))
                        .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                }
            } else {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textFaint.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.panelHi.opacity(0.5)))
                    .overlay(Circle().stroke(Theme.stroke.opacity(0.5), lineWidth: 1))
            }
        }
    }
}
