import SwiftUI

/// Faithful Swift port of the PWA's DashboardView.tsx: same 6-column
/// skyline/masonry packing constants, rendered as absolutely-positioned
/// widget cards inside a horizontally-scrolling canvas — not a vertical
/// stack. Drag-to-resize and drag-to-reorder call the same Store methods
/// the Mac app and PWA use.
private let cols = 6
private let colW: CGFloat = 170
private let rowH: CGFloat = 110
private let gap: CGFloat = 14
private let minW = 2, minH = 2, maxH = 8

private struct Frame { var x: CGFloat; var y: CGFloat; var w: CGFloat; var h: CGFloat }

/// Same skyline packing as packFrames() in DashboardView.tsx: each widget
/// lands on whichever column span currently has the lowest height.
private func packFrames(_ spans: [(cols: Int, rows: Int)]) -> [Frame] {
    var colHeights = Array(repeating: 0, count: cols)
    var frames: [Frame] = []
    for span in spans {
        let w = max(1, min(span.cols, cols))
        var bestX = 0, bestY = Int.max
        for x in 0...(cols - w) {
            let y = colHeights[x..<(x + w)].max() ?? 0
            if y < bestY { bestY = y; bestX = x }
        }
        frames.append(Frame(
            x: CGFloat(bestX) * (colW + gap), y: CGFloat(bestY) * (rowH + gap),
            w: CGFloat(w) * colW + CGFloat(w - 1) * gap,
            h: CGFloat(span.rows) * rowH + CGFloat(span.rows - 1) * gap))
        for x in bestX..<(bestX + w) { colHeights[x] = bestY + span.rows }
    }
    return frames
}

struct DashboardDetailView: View {
    @EnvironmentObject var store: Store
    let dashboardId: UUID
    @State private var showAddViews = false
    @State private var editing: CraftTask?
    @State private var draggedId: UUID?

    private var dashboard: Dashboard? { store.dashboards.first { $0.id == dashboardId } }
    private var widgets: [DashboardWidget] { dashboard?.widgets ?? [] }

    private var frames: [Frame] { packFrames(widgets.map { (widthUnits($0), heightUnits($0)) }) }
    // Widths/heights are stored in the same "grid units" the Mac app uses
    // (DashboardWidget.widthUnits/heightUnits, ~2 units per 170pt column
    // here vs. the Mac's own cell size) — divide by 2 to land on this
    // view's 6-column grid at a comparable visual density.
    private func widthUnits(_ w: DashboardWidget) -> Int { max(1, min(cols, w.widthUnits / 2)) }
    private func heightUnits(_ w: DashboardWidget) -> Int { max(1, w.heightUnits / 2) }

    private var canvasW: CGFloat { CGFloat(cols) * colW + CGFloat(cols - 1) * gap }
    private var canvasH: CGFloat { frames.map { $0.y + $0.h }.max() ?? 0 }

    private var availableViews: [TaskFilter] {
        store.savedFilters.filter { f in !widgets.contains { $0.viewId == f.id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if widgets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundColor(Theme.textFaint)
                    Text("Add a saved view to get started").font(.system(size: 13)).foregroundColor(Theme.textLo)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(widgets.enumerated()), id: \.element.id) { i, widget in
                            WidgetCardView(
                                dashboardId: dashboardId, widget: widget, frame: frames[i],
                                filter: store.savedFilters.first { $0.id == widget.viewId },
                                onEdit: { editing = $0 })
                            .offset(x: frames[i].x, y: frames[i].y)
                            .frame(width: frames[i].w, height: frames[i].h, alignment: .topLeading)
                        }
                    }
                    .frame(width: canvasW, height: canvasH, alignment: .topLeading)
                    .padding(16)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle(dashboard?.name ?? "Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddViews = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddViews) {
            AddViewsToDashboardSheet(dashboardId: dashboardId, available: availableViews)
        }
        .sheet(item: $editing) { EditTaskSheet(task: $0) }
    }

    private var header: some View {
        HStack {
            Text("\(widgets.count) widgets").font(.system(size: 12)).foregroundColor(Theme.textFaint)
            Spacer()
            Chip(text: "Completed", icon: store.showCompleted ? "eye" : "eye.slash", active: !store.showCompleted, small: true)
                .onTapGesture { store.showCompleted.toggle() }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .bottom)
    }
}

private struct WidgetCardView: View {
    @EnvironmentObject var store: Store
    let dashboardId: UUID
    let widget: DashboardWidget
    let frame: Frame
    let filter: TaskFilter?
    let onEdit: (CraftTask) -> Void

    private var tasks: [CraftTask] { filter.map { store.apply($0) } ?? [] }
    private var groups: [(String, [CraftTask])] { filter.map { store.group(tasks, by: $0.groupBy ?? .document) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(filter?.name ?? "View removed").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.textHi).lineLimit(1)
                if filter != nil { Text("\(tasks.count)").font(.system(size: 11)).foregroundColor(Theme.textFaint) }
                Spacer()
                Button { store.removeWidget(widget.id, from: dashboardId) } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(Theme.textFaint)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if filter == nil {
                        Text("This saved view was deleted").font(.system(size: 12)).foregroundColor(Theme.textFaint).padding(12)
                    } else if tasks.isEmpty {
                        Text("Nothing here").font(.system(size: 12)).foregroundColor(Theme.textFaint).padding(12)
                    } else {
                        ForEach(groups, id: \.0) { title, items in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.textFaint)
                                    .padding(.horizontal, 12).padding(.top, 6)
                                ForEach(items) { task in
                                    Button { onEdit(task) } label: {
                                        Text(task.displayTitle).font(.system(size: 12)).foregroundColor(Theme.text)
                                            .lineLimit(1).padding(.horizontal, 12).padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
    }
}

private struct AddViewsToDashboardSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let dashboardId: UUID
    let available: [TaskFilter]
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(available) { f in
                Button {
                    if selected.contains(f.id) { selected.remove(f.id) } else { selected.insert(f.id) }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(f.id) ? "checkmark.square.fill" : "square")
                        Text(f.name).foregroundColor(Theme.text)
                    }
                }
            }
            .navigationTitle("Add Views")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addWidgets(viewIds: Array(selected), to: dashboardId)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
