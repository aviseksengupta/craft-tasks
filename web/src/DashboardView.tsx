import { useMemo, useRef, useState } from 'react'
import { CraftTask, Dashboard, DashboardWidget, TaskFilter } from './types'
import { useStore } from './store'
import { Chip, Icon, PageHeadSticky } from './ui'
import { CompletedToggle } from './TaskList'
import { TaskRow } from './TaskRow'
import { EditTaskModal, ViewPicker } from './modals'

// 6-column grid, skyline packing — same constants as the macOS app.
const COLS = 6
const COL_W = 170
const ROW_H = 110
const GAP = 14
const MIN_W = 2, MIN_H = 2, MAX_H = 8

interface Frame { x: number; y: number; w: number; h: number }

/// Skyline/masonry packing: each widget lands on whichever column span
/// currently has the lowest height, so short widgets backfill gaps.
function packFrames(spans: { cols: number; rows: number }[]): Frame[] {
  const colHeights = Array<number>(COLS).fill(0)
  const frames: Frame[] = []
  for (const span of spans) {
    const w = Math.max(1, Math.min(span.cols, COLS))
    let bestX = 0, bestY = Infinity
    for (let x = 0; x <= COLS - w; x++) {
      const y = Math.max(...colHeights.slice(x, x + w))
      if (y < bestY) { bestY = y; bestX = x }
    }
    frames.push({
      x: bestX * (COL_W + GAP),
      y: bestY * (ROW_H + GAP),
      w: w * COL_W + (w - 1) * GAP,
      h: span.rows * ROW_H + (span.rows - 1) * GAP,
    })
    for (let x = bestX; x < bestX + w; x++) colHeights[x] = bestY + span.rows
  }
  return frames
}

interface ResizeState { widgetId: string; widthUnits: number; heightUnits: number }

export function DashboardView({ dashboardId }: { dashboardId: string }) {
  const store = useStore()
  const [showAddViews, setShowAddViews] = useState(false)
  const [editing, setEditing] = useState<CraftTask | null>(null)
  const [resizeState, setResizeState] = useState<ResizeState | null>(null)
  const [dropTarget, setDropTarget] = useState<string | null>(null)
  const draggedId = useRef<string | null>(null)

  const dashboard: Dashboard | undefined = store.dashboards.find(d => d.id === dashboardId)
  const widgets = useMemo(() => dashboard?.widgets ?? [], [dashboard])

  const frames = useMemo(() => packFrames(widgets.map(w => {
    if (resizeState && resizeState.widgetId === w.id) {
      return { cols: resizeState.widthUnits, rows: resizeState.heightUnits }
    }
    return { cols: w.widthUnits, rows: w.heightUnits }
  })), [widgets, resizeState])

  const canvasW = COLS * COL_W + (COLS - 1) * GAP
  const canvasH = frames.length ? Math.max(...frames.map(f => f.y + f.h)) : 0

  const availableViews = store.savedFilters
    .filter(f => !widgets.some(w => w.viewId === f.id))
    .map(f => ({ id: f.id, name: f.name }))

  return (
    <>
      <PageHeadSticky>
        <div className="page-header">
          <h1 style={{ fontSize: 25 }}>{dashboard?.name ?? 'Dashboard'}</h1>
          <span className="count">{widgets.length} widgets</span>
          <span className="spacer" />
          <CompletedToggle />
          <Chip text="Add view" icon="plus" onClick={() => setShowAddViews(true)} />
        </div>
        <div className="hairline" />
      </PageHeadSticky>
      <div className="dash-scroll">
        {widgets.length === 0 ? (
          <div className="empty-state">
            <div className="big"><Icon name="grid" size={28} /></div>
            Add a saved view to get started
          </div>
        ) : (
          <>
            {/* Invisible in-flow snap targets, one per grid column —
                direct children of .dash-scroll, no wrapper div. Three
                things ruled out simpler options, each confirmed by
                testing an actual scroll settle position rather than just
                reading the spec: putting scroll-snap-align on the widgets
                themselves does nothing (they're position:absolute for the
                masonry packing, and out-of-flow boxes are never valid
                snap targets); wrapping these markers in a track div does
                nothing either (scroll-snap-align only takes effect on the
                scroll container's *direct* children — one extra level of
                nesting silently disqualifies it); and a flex/grid wrapper
                for the row would've pushed .dash-canvas to the right of
                it. display:inline-block sidesteps that last problem: the
                columns lay out left-to-right on their own inline
                formatting context, but .dash-canvas is block-level right
                after them, so it starts its own new line back at the
                left edge regardless — see .dash-scroll's white-space:
                nowrap (needed so these don't wrap to a second line) and
                .dash-canvas's white-space:normal (resets that inherited
                nowrap before it reaches real widget text). Column
                width/gap must mirror COL_W/GAP above. */}
            {Array.from({ length: COLS }).map((_, i) => <div key={i} className="dash-snap-col" />)}
            <div className="dash-canvas" style={{ width: canvasW + 48, height: canvasH + 48 }}>
            {widgets.map((w, i) => (
              <WidgetCard key={w.id} dashboardId={dashboardId} widget={w}
                          frame={frames[i]}
                          filter={store.savedFilters.find(f => f.id === w.viewId)}
                          resizing={resizeState?.widgetId === w.id}
                          resizeState={resizeState}
                          isDropTarget={dropTarget === w.id}
                          onEdit={setEditing}
                          onDragStart={() => { draggedId.current = w.id }}
                          onDragOver={() => setDropTarget(w.id)}
                          onDragLeave={() => setDropTarget(t => t === w.id ? null : t)}
                          onDrop={() => {
                            if (draggedId.current && draggedId.current !== w.id) {
                              store.moveWidget(draggedId.current, w.id, dashboardId)
                            }
                            draggedId.current = null
                            setDropTarget(null)
                          }}
                          setResizeState={setResizeState} />
            ))}
            </div>
          </>
        )}
      </div>
      {showAddViews && (
        <ViewPicker title="Add views to dashboard" cta="Add" views={availableViews}
                    onClose={() => setShowAddViews(false)}
                    onDone={(_, ids) => store.addWidgets(ids, dashboardId)} />
      )}
      {editing && <EditTaskModal task={editing} onClose={() => setEditing(null)} />}
    </>
  )
}

function WidgetCard({ dashboardId, widget, frame, filter, resizing, resizeState, isDropTarget,
                      onEdit, onDragStart, onDragOver, onDragLeave, onDrop, setResizeState }: {
  dashboardId: string
  widget: DashboardWidget
  frame: Frame
  filter: TaskFilter | undefined
  resizing: boolean
  resizeState: ResizeState | null
  isDropTarget: boolean
  onEdit: (t: CraftTask) => void
  onDragStart: () => void
  onDragOver: () => void
  onDragLeave: () => void
  onDrop: () => void
  setResizeState: (s: ResizeState | null) => void
}) {
  const store = useStore()
  const anchor = useRef<{ w: number; h: number; startX: number; startY: number } | null>(null)

  const tasks = filter ? store.apply(filter) : []
  const groups = filter ? store.group(tasks, filter.groupBy) : []
  const isKanban = filter?.layout === 'Kanban'

  const onResizePointerDown = (e: React.PointerEvent) => {
    e.preventDefault()
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
    anchor.current = { w: widget.widthUnits, h: widget.heightUnits, startX: e.clientX, startY: e.clientY }
  }
  const onResizePointerMove = (e: React.PointerEvent) => {
    if (!anchor.current) return
    const dCols = Math.round((e.clientX - anchor.current.startX) / (COL_W + GAP))
    const dRows = Math.round((e.clientY - anchor.current.startY) / (ROW_H + GAP))
    setResizeState({
      widgetId: widget.id,
      widthUnits: Math.min(COLS, Math.max(MIN_W, anchor.current.w + dCols)),
      heightUnits: Math.min(MAX_H, Math.max(MIN_H, anchor.current.h + dRows)),
    })
  }
  const onResizePointerUp = () => {
    if (anchor.current && resizeState && resizeState.widgetId === widget.id) {
      store.setWidgetDimensions(widget.id, resizeState.widthUnits, resizeState.heightUnits, dashboardId)
    }
    anchor.current = null
    setResizeState(null)
  }

  return (
    <div className={`dash-widget${resizing ? ' resizing' : ''}${isDropTarget ? ' drop-target' : ''}`}
         style={{ left: frame.x + 24, top: frame.y + 24, width: frame.w, height: frame.h }}
         onDragOver={e => { e.preventDefault(); onDragOver() }}
         onDragLeave={onDragLeave}
         onDrop={e => { e.preventDefault(); onDrop() }}>
      <div className="dash-widget-head">
        <span className="grip" draggable
              onDragStart={e => { e.dataTransfer.setData('text/plain', widget.id); onDragStart() }}
              title="Drag to reorder">
          <Icon name="gripLines" size={11} />
        </span>
        <span className="w-title">{filter?.name ?? 'View removed'}</span>
        {filter && <span className="w-count">{tasks.length}</span>}
        <span style={{ flex: 1 }} />
        {resizing && resizeState && (
          <span className="w-count">{resizeState.widthUnits}×{resizeState.heightUnits}</span>
        )}
        <button className="icon-btn" onClick={() => store.removeWidget(widget.id, dashboardId)}
                title="Remove from dashboard">
          <Icon name="xmark" size={9} />
        </button>
      </div>
      <div className="hairline" />
      <div className={`dash-widget-body${isKanban ? ' kanban' : ''}`}>
        {!filter ? (
          <div className="menu-note">This saved view was deleted</div>
        ) : tasks.length === 0 ? (
          <div className="menu-note">Nothing here</div>
        ) : groups.map(([title, items]) => (
          <div key={title} className={`mini-col${isKanban ? ' kanban' : ''}`}>
            <div className="mini-col-label">{title}</div>
            {items.map(t => <TaskRow key={t.id} task={t} onEdit={onEdit} />)}
          </div>
        ))}
      </div>
      <div className="resize-handle" title="Drag to resize"
           onPointerDown={onResizePointerDown}
           onPointerMove={onResizePointerMove}
           onPointerUp={onResizePointerUp}>
        <Icon name="resize" size={9} />
      </div>
    </div>
  )
}
