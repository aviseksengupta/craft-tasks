import { useMemo, useRef, useState } from 'react'
import { Section, TaskFilter, Dashboard, scheduleDay, deadlineDay, startOfToday, stateLabel } from './types'
import { useStore, DocumentSummary } from './store'
import { Icon, useContextMenu, PageHeadSticky, Chip } from './ui'
import { CompletedToggle, BacklogToggle } from './TaskList'
import { NamePrompt, ViewPicker } from './modals'

function StatRow({ open, done, overdue }: { open: number; done: number; overdue: number }) {
  return (
    <div className="stat-row">
      <div className="stat-tile"><div className={`n${open > 0 ? ' bright' : ''}`}>{open}</div><div className="l">Open</div></div>
      <div className="stat-div" />
      <div className="stat-tile"><div className="n">{done}</div><div className="l">Done</div></div>
      <div className="stat-div" />
      <div className="stat-tile"><div className={`n${overdue > 0 ? ' bright' : ''}`}>{overdue}</div><div className="l">Overdue</div></div>
    </div>
  )
}

function ProgressBar({ progress, label }: { progress: number; label: string }) {
  return (
    <div>
      <div className="progress-track">
        <div className="progress-fill" style={{ width: `${Math.max(2, progress * 100)}%` }} />
      </div>
      <div className="progress-label">{label}</div>
    </div>
  )
}

// ---- Documents ----

export function DocumentsView({ setSection }: { setSection: (s: Section) => void }) {
  const store = useStore()
  const [renaming, setRenaming] = useState<DocumentSummary | null>(null)

  let docs = store.showCompleted ? store.documents : store.documents.filter(d => d.open > 0)
  if (store.searchText) {
    docs = docs.filter(d => d.title.toLowerCase().includes(store.searchText.toLowerCase()))
  }

  return (
    <>
      <PageHeadSticky>
        <div className="page-header">
          <h1 style={{ fontSize: 25 }}>Documents</h1>
          <span className="count">{docs.length} with tasks</span>
          <span className="spacer" />
          <CompletedToggle />
          <BacklogToggle />
        </div>
        <div className="hairline" />
      </PageHeadSticky>
      <div className="list-scroll" style={{ padding: 0 }}>
        <div className="cards-grid">
          {docs.map(doc => (
            <div key={doc.id} className="doc-card" role="button" tabIndex={0}
                 onClick={() => { store.openDocument(doc.id); setSection({ kind: 'allTasks' }) }}>
              <div className="doc-card-top">
                <div className="doc-icon"><Icon name={doc.id === 'inbox' ? 'tray' : 'doc'} size={13} /></div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                    <span className="doc-card-title">{doc.title}</span>
                    {doc.id !== 'inbox' && (
                      <button className="card-hover-btn" title="Rename in this app (Craft's own title is unaffected)"
                              onClick={e => { e.stopPropagation(); setRenaming(doc) }}>
                        <Icon name="pencil" size={11} />
                      </button>
                    )}
                  </div>
                  <div className="doc-card-sub">{doc.total} task{doc.total === 1 ? '' : 's'}</div>
                </div>
                <span className="card-hover-btn"><Icon name="arrowUpRight" size={10} /></span>
              </div>
              <StatRow open={doc.open} done={doc.done} overdue={doc.overdue} />
              <ProgressBar progress={doc.progress} label={`${Math.round(doc.progress * 100)}% complete`} />
            </div>
          ))}
        </div>
      </div>
      {renaming && (
        <NamePrompt title={`Display name${renaming.title !== renaming.craftTitle ? ` (Craft: ${renaming.craftTitle})` : ''}`}
                    initial={renaming.title}
                    onClose={() => setRenaming(null)}
                    onSave={name => store.setDisplayName(renaming.id, name)} />
      )}
    </>
  )
}

// ---- Views page ----

export function ViewsPage({ setSection }: { setSection: (s: Section) => void }) {
  const store = useStore()
  const [renaming, setRenaming] = useState<TaskFilter | null>(null)
  const [dropTarget, setDropTarget] = useState<string | null>(null)
  const draggedId = useRef<string | null>(null)
  const { openAt, menu } = useContextMenu()

  const visible = store.searchText
    ? store.savedFilters.filter(f => f.name.toLowerCase().includes(store.searchText.toLowerCase()))
    : store.savedFilters

  return (
    <>
      <PageHeadSticky>
        <div className="page-header">
          <h1 style={{ fontSize: 25 }}>Views</h1>
          <span className="count">{visible.length}</span>
          <span className="spacer" />
          <CompletedToggle />
          <BacklogToggle />
        </div>
        <div className="hairline" />
      </PageHeadSticky>
      {visible.length === 0 ? (
        <div className="empty-state">
          <div className="big"><Icon name="filterLines" size={28} /></div>
          {store.savedFilters.length === 0 ? 'Save a view from All Tasks to see it here' : 'No views match your search'}
        </div>
      ) : (
        <div className="list-scroll" style={{ padding: 0 }}>
          <div className="cards-grid">
            {visible.map(f => (
              <ViewCard key={f.id} filter={f} setSection={setSection}
                        onRename={() => setRenaming(f)} openAt={openAt}
                        isDropTarget={dropTarget === f.id}
                        onDragStart={() => { draggedId.current = f.id }}
                        onDragOver={() => setDropTarget(f.id)}
                        onDragLeave={() => setDropTarget(t => t === f.id ? null : t)}
                        onDrop={() => {
                          if (draggedId.current && draggedId.current !== f.id) {
                            store.moveView(draggedId.current, f.id)
                          }
                          draggedId.current = null
                          setDropTarget(null)
                        }} />
            ))}
          </div>
        </div>
      )}
      {menu}
      {renaming && (
        <NamePrompt title="View name" initial={renaming.name}
                    onClose={() => setRenaming(null)}
                    onSave={name => store.renameFilter(renaming.id, name)} />
      )}
    </>
  )
}

function ViewCard({ filter, setSection, onRename, openAt, isDropTarget, onDragStart, onDragOver, onDragLeave, onDrop }: {
  filter: TaskFilter
  setSection: (s: Section) => void
  onRename: () => void
  openAt: (e: React.MouseEvent, items: { label: string; danger?: boolean; action: () => void }[]) => void
  isDropTarget: boolean
  onDragStart: () => void
  onDragOver: () => void
  onDragLeave: () => void
  onDrop: () => void
}) {
  const store = useStore()
  const isHome = store.isHomeTarget({ kind: 'saved', id: filter.id })
  const pinned = !!filter.pinned

  const stats = useMemo(() => {
    const matched = store.apply(filter)
    const today = startOfToday()
    const open = matched.filter(t => t.state === 'todo').length
    const done = matched.filter(t => t.state === 'done').length
    const overdue = matched.filter(t => {
      const d = scheduleDay(t) ?? deadlineDay(t)
      return t.state === 'todo' && d !== null && d < today
    }).length
    return { total: matched.length, open, done, overdue }
  }, [store, filter])
  const progress = stats.total === 0 ? 0 : (stats.total - stats.open) / stats.total

  const criteria = useMemo(() => {
    const parts: string[] = []
    if (filter.states.length) parts.push(filter.states.map(s => stateLabel[s]).sort().join('/'))
    if (filter.dateScope !== 'Any') parts.push(filter.dateScope)
    if (filter.documentIds.length) parts.push(`${filter.documentIds.length} doc${filter.documentIds.length === 1 ? '' : 's'}`)
    if (filter.tags.length) parts.push(`${filter.tags.length} tag${filter.tags.length === 1 ? '' : 's'}`)
    if (filter.excludedTags.length) parts.push(`−${filter.excludedTags.length} tag${filter.excludedTags.length === 1 ? '' : 's'}`)
    return parts.length ? parts.join(' · ') : 'All tasks'
  }, [filter])

  return (
    <div className={`doc-card${isDropTarget ? ' drop-target' : ''}`} role="button" tabIndex={0}
         onClick={() => { store.selectSaved(filter.id); setSection({ kind: 'saved', id: filter.id }) }}
         onDragOver={e => { e.preventDefault(); onDragOver() }}
         onDragLeave={onDragLeave}
         onDrop={e => { e.preventDefault(); onDrop() }}
         onContextMenu={e => openAt(e, [
           { label: 'Rename', action: onRename },
           { label: isHome ? 'Unset as Home' : 'Set as Home', action: () => store.setHomeTarget({ kind: 'saved', id: filter.id }) },
           { label: pinned ? 'Unpin from Sidebar' : 'Pin to Sidebar', action: () => store.togglePinned(filter.id) },
           { label: 'Delete', danger: true, action: () => store.deleteFilter(filter.id) },
         ])}>
      <div className="doc-card-top">
        <span className="doc-card-grip" draggable
              onDragStart={e => { e.dataTransfer.setData('text/plain', filter.id); onDragStart() }}
              onClick={e => e.stopPropagation()}
              title="Drag to reorder">
          <Icon name="gripLines" size={11} />
        </span>
        <div className="doc-icon"><Icon name="filterLines" size={13} /></div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            <span className="doc-card-title">{filter.name}</span>
            {isHome && <Icon name="house" size={9} />}
            <button className="card-hover-btn" title="Rename this view"
                    onClick={e => { e.stopPropagation(); onRename() }}>
              <Icon name="pencil" size={11} />
            </button>
          </div>
          <div className="doc-card-sub">{criteria}</div>
        </div>
        <button className={`card-hover-btn${pinned ? ' pinned' : ''}`}
                title={pinned ? 'Unpin from sidebar' : 'Pin to sidebar'}
                onClick={e => { e.stopPropagation(); store.togglePinned(filter.id) }}>
          <Icon name="pin" size={11} />
        </button>
      </div>
      <StatRow open={stats.open} done={stats.done} overdue={stats.overdue} />
      <ProgressBar progress={progress}
                   label={stats.total === 0 ? 'No matching tasks' : `${Math.round(progress * 100)}% complete`} />
    </div>
  )
}

// ---- Dashboards page ----

export function DashboardsPage({ setSection }: { setSection: (s: Section) => void }) {
  const store = useStore()
  const [renaming, setRenaming] = useState<Dashboard | null>(null)
  const [showNewDashboard, setShowNewDashboard] = useState(false)
  const [dropTarget, setDropTarget] = useState<string | null>(null)
  const draggedId = useRef<string | null>(null)
  const { openAt, menu } = useContextMenu()

  const visible = store.searchText
    ? store.dashboards.filter(d => d.name.toLowerCase().includes(store.searchText.toLowerCase()))
    : store.dashboards

  return (
    <>
      <PageHeadSticky>
        <div className="page-header">
          <h1 style={{ fontSize: 25 }}>Dashboards</h1>
          <span className="count">{visible.length}</span>
          <span className="spacer" />
          <Chip text="New dashboard" icon="plus" onClick={() => setShowNewDashboard(true)} />
        </div>
        <div className="hairline" />
      </PageHeadSticky>
      {visible.length === 0 ? (
        <div className="empty-state">
          <div className="big"><Icon name="grid" size={28} /></div>
          {store.dashboards.length === 0 ? 'Create a dashboard to see it here' : 'No dashboards match your search'}
        </div>
      ) : (
        <div className="list-scroll" style={{ padding: 0 }}>
          <div className="cards-grid">
            {visible.map(d => (
              <DashboardCard key={d.id} dashboard={d} setSection={setSection}
                             onRename={() => setRenaming(d)} openAt={openAt}
                             isDropTarget={dropTarget === d.id}
                             onDragStart={() => { draggedId.current = d.id }}
                             onDragOver={() => setDropTarget(d.id)}
                             onDragLeave={() => setDropTarget(t => t === d.id ? null : t)}
                             onDrop={() => {
                               if (draggedId.current && draggedId.current !== d.id) {
                                 store.moveDashboard(draggedId.current, d.id)
                               }
                               draggedId.current = null
                               setDropTarget(null)
                             }} />
            ))}
          </div>
        </div>
      )}
      {menu}
      {renaming && (
        <NamePrompt title="Dashboard name" initial={renaming.name}
                    onClose={() => setRenaming(null)}
                    onSave={name => store.renameDashboard(renaming.id, name)} />
      )}
      {showNewDashboard && (
        <ViewPicker title="New Dashboard" cta="Create" requireName
                    views={store.savedFilters.map(f => ({ id: f.id, name: f.name }))}
                    onClose={() => setShowNewDashboard(false)}
                    onDone={(name, ids) => {
                      const d = store.saveDashboard(name, ids)
                      setSection({ kind: 'dashboard', id: d.id })
                    }} />
      )}
    </>
  )
}

function DashboardCard({ dashboard, setSection, onRename, openAt, isDropTarget, onDragStart, onDragOver, onDragLeave, onDrop }: {
  dashboard: Dashboard
  setSection: (s: Section) => void
  onRename: () => void
  openAt: (e: React.MouseEvent, items: { label: string; danger?: boolean; action: () => void }[]) => void
  isDropTarget: boolean
  onDragStart: () => void
  onDragOver: () => void
  onDragLeave: () => void
  onDrop: () => void
}) {
  const store = useStore()
  const isHome = store.isHomeTarget({ kind: 'dashboard', id: dashboard.id })
  const pinned = !!dashboard.pinned

  return (
    <div className={`doc-card${isDropTarget ? ' drop-target' : ''}`} role="button" tabIndex={0}
         onClick={() => setSection({ kind: 'dashboard', id: dashboard.id })}
         onDragOver={e => { e.preventDefault(); onDragOver() }}
         onDragLeave={onDragLeave}
         onDrop={e => { e.preventDefault(); onDrop() }}
         onContextMenu={e => openAt(e, [
           { label: 'Rename', action: onRename },
           { label: isHome ? 'Unset as Home' : 'Set as Home', action: () => store.setHomeTarget({ kind: 'dashboard', id: dashboard.id }) },
           { label: pinned ? 'Unpin from Sidebar' : 'Pin to Sidebar', action: () => store.togglePinnedDashboard(dashboard.id) },
           {
             label: 'Delete', danger: true,
             action: () => {
               store.deleteDashboard(dashboard.id)
             },
           },
         ])}>
      <div className="doc-card-top">
        <span className="doc-card-grip" draggable
              onDragStart={e => { e.dataTransfer.setData('text/plain', dashboard.id); onDragStart() }}
              onClick={e => e.stopPropagation()}
              title="Drag to reorder">
          <Icon name="gripLines" size={11} />
        </span>
        <div className="doc-icon"><Icon name="grid" size={13} /></div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            <span className="doc-card-title">{dashboard.name}</span>
            {isHome && <Icon name="house" size={9} />}
            <button className="card-hover-btn" title="Rename this dashboard"
                    onClick={e => { e.stopPropagation(); onRename() }}>
              <Icon name="pencil" size={11} />
            </button>
          </div>
          <div className="doc-card-sub">{dashboard.widgets.length} widget{dashboard.widgets.length === 1 ? '' : 's'}</div>
        </div>
        <button className={`card-hover-btn${pinned ? ' pinned' : ''}`}
                title={pinned ? 'Unpin from sidebar' : 'Pin to sidebar'}
                onClick={e => { e.stopPropagation(); store.togglePinnedDashboard(dashboard.id) }}>
          <Icon name="pin" size={11} />
        </button>
      </div>
    </div>
  )
}
