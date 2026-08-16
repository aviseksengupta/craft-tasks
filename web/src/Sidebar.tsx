import { useRef, useState } from 'react'
import { Section, sectionEq, PinnedItem } from './types'
import { useStore } from './store'
import { Icon, useContextMenu } from './ui'
import { SidebarSettingsModal, NamePrompt } from './modals'

export interface NavDef { id: string; icon: string; label: string; section: Section; select: () => void }

export function Sidebar({ section, setSection, open, onNavigate, onClose, onOpenSettings, onAddTask }: {
  section: Section
  setSection: (s: Section) => void
  open: boolean
  onNavigate: () => void
  onClose: () => void
  onOpenSettings: () => void
  onAddTask: () => void
}) {
  const store = useStore()
  const [showSidebarSettings, setShowSidebarSettings] = useState(false)
  const [showMore, setShowMore] = useState(false)
  const [renaming, setRenaming] = useState<{ kind: 'view' | 'dashboard'; id: string; name: string } | null>(null)
  const [pinDropTarget, setPinDropTarget] = useState<string | null>(null)
  const draggedPin = useRef<{ kind: 'view' | 'dashboard'; id: string } | null>(null)
  const { openAt, menu } = useContextMenu()

  const navDefs: NavDef[] = [
    { id: 'home', icon: 'house', label: 'Home', section: { kind: 'home' }, select: () => setSection(store.navigateHome()) },
    { id: 'allTasks', icon: 'trayFull', label: 'All Tasks', section: { kind: 'allTasks' }, select: () => { store.selectAllTasks(); setSection({ kind: 'allTasks' }) } },
    { id: 'inbox', icon: 'tray', label: 'Inbox', section: { kind: 'inbox' }, select: () => { store.selectInbox(); setSection({ kind: 'inbox' }) } },
    { id: 'today', icon: 'sun', label: 'Today', section: { kind: 'today' }, select: () => { store.selectToday(); setSection({ kind: 'today' }) } },
    { id: 'thisWeek', icon: 'calendarClock', label: 'This Week', section: { kind: 'thisWeek' }, select: () => { store.selectThisWeek(); setSection({ kind: 'thisWeek' }) } },
    { id: 'documents', icon: 'doc', label: 'Documents', section: { kind: 'documents' }, select: () => setSection({ kind: 'documents' }) },
    { id: 'views', icon: 'listRect', label: 'Views', section: { kind: 'views' }, select: () => setSection({ kind: 'views' }) },
    { id: 'dashboards', icon: 'grid', label: 'Dashboards', section: { kind: 'dashboards' }, select: () => setSection({ kind: 'dashboards' }) },
  ]

  const visibility = (id: string) => store.itemVisibility[id] ?? 'Always shown'
  const homeIsActive = sectionEq(section, store.homeSection ?? { kind: 'home' })
  const isActive = (def: NavDef) => def.id === 'home' ? homeIsActive : sectionEq(section, def.section)

  const navRow = (def: NavDef) => (
    <button key={def.id}
            className={`sidebar-item${isActive(def) ? ' active' : ''}`}
            onClick={() => { def.select(); onNavigate() }}
            onContextMenu={def.id === 'home' ? undefined : e => openAt(e, [{
              label: store.isHomeTarget(def.section) ? 'Unset as Home' : 'Set as Home',
              action: () => store.setHomeTarget(def.section),
            }])}>
      <span className="glyph"><Icon name={def.icon} size={12} /></span>
      {def.label}
      {def.id !== 'home' && store.isHomeTarget(def.section) && <span className="home-mark"><Icon name="house" size={8} /></span>}
    </button>
  )

  const alwaysShown = navDefs.filter(d => visibility(d.id) === 'Always shown')
  const tucked = navDefs.filter(d => visibility(d.id) === 'Hidden')
  const pinnedItems = store.pinnedItems

  return (
    <>
      <div className={`sidebar${open ? ' open' : ''}`}>
        <div className="sidebar-head">
          <span className="sidebar-title"><Icon name="stack" size={13} /> Craft Tasks</span>
          <button className="icon-btn" onClick={() => setShowSidebarSettings(true)} title="Sidebar item settings">
            <Icon name="gear" size={12} />
          </button>
          <button className="icon-btn" onClick={onOpenSettings} title="App settings (Craft URL, sync)">
            <Icon name="refresh" size={12} />
          </button>
          <button className="icon-btn sidebar-close" onClick={onClose} title="Close menu">
            <Icon name="xmark" size={14} />
          </button>
        </div>

        <button className="new-task-btn" onClick={() => { onAddTask(); onNavigate() }}>
          <Icon name="plusCircle" size={13} weight={1.8} /> New Task
        </button>

        <div className="search-box">
          <Icon name="search" size={10} />
          <input placeholder="Search tasks & documents" value={store.searchText}
                 onChange={e => store.setSearchText(e.target.value)} />
          {store.searchText && (
            <button className="icon-btn" onClick={() => store.setSearchText('')}><Icon name="xmark" size={9} /></button>
          )}
        </div>

        {alwaysShown.map(navRow)}

        {tucked.length > 0 && (
          <>
            <button className="sidebar-item" onClick={() => setShowMore(m => !m)}>
              <span className="glyph" style={{ transform: showMore ? 'rotate(90deg)' : undefined, transition: 'transform 0.15s' }}>
                <Icon name="chevron" size={9} />
              </span>
              More
            </button>
            {showMore && tucked.map(navRow)}
          </>
        )}

        {pinnedItems.length > 0 && (
          <>
            <div className="sidebar-section-label">PINNED</div>
            {pinnedItems.map(item => {
              const ref = pinnedRef(item)
              const key = `${ref.kind}:${ref.id}`
              return (
                <PinnedRow key={key} item={item} section={section} setSection={setSection}
                           onNavigate={onNavigate} openAt={openAt} setRenaming={setRenaming}
                           isDropTarget={pinDropTarget === key}
                           onDragStart={() => { draggedPin.current = ref }}
                           onDragOver={() => setPinDropTarget(key)}
                           onDragLeave={() => setPinDropTarget(t => t === key ? null : t)}
                           onDrop={() => {
                             if (draggedPin.current && !(draggedPin.current.kind === ref.kind && draggedPin.current.id === ref.id)) {
                               store.movePinned(draggedPin.current, ref)
                             }
                             draggedPin.current = null
                             setPinDropTarget(null)
                           }} />
              )
            })}
          </>
        )}

        <SyncStatus />
      </div>

      {menu}
      {showSidebarSettings && <SidebarSettingsModal navDefs={navDefs} onClose={() => setShowSidebarSettings(false)} />}
      {renaming && (
        <NamePrompt title={renaming.kind === 'view' ? 'View name' : 'Dashboard name'} initial={renaming.name}
                    onClose={() => setRenaming(null)}
                    onSave={name => renaming.kind === 'view'
                      ? store.renameFilter(renaming.id, name)
                      : store.renameDashboard(renaming.id, name)} />
      )}
    </>
  )
}

// Identifies a pinned item independent of its underlying view/dashboard
// object, so drag state and drop-target comparisons don't need to unpack
// the PinnedItem union at every call site.
function pinnedRef(item: PinnedItem): { kind: 'view' | 'dashboard'; id: string } {
  return item.kind === 'view' ? { kind: 'view', id: item.filter.id } : { kind: 'dashboard', id: item.dashboard.id }
}

function PinnedRow({ item, section, setSection, onNavigate, openAt, setRenaming,
                     isDropTarget, onDragStart, onDragOver, onDragLeave, onDrop }: {
  item: PinnedItem
  section: Section
  setSection: (s: Section) => void
  onNavigate: () => void
  openAt: (e: React.MouseEvent, items: { label: string; danger?: boolean; action: () => void }[]) => void
  setRenaming: (r: { kind: 'view' | 'dashboard'; id: string; name: string } | null) => void
  isDropTarget: boolean
  onDragStart: () => void
  onDragOver: () => void
  onDragLeave: () => void
  onDrop: () => void
}) {
  const store = useStore()
  const target: Section = item.kind === 'view' ? { kind: 'saved', id: item.filter.id } : { kind: 'dashboard', id: item.dashboard.id }
  const name = item.kind === 'view' ? item.filter.name : item.dashboard.name
  const icon = item.kind === 'view' ? 'filterLines' : 'grid'

  const select = () => {
    if (item.kind === 'view') store.selectSaved(item.filter.id)
    setSection(target)
    onNavigate()
  }
  const unpin = () => item.kind === 'view' ? store.togglePinned(item.filter.id) : store.togglePinnedDashboard(item.dashboard.id)
  const del = () => {
    if (item.kind === 'view') {
      store.deleteFilter(item.filter.id)
    } else {
      const wasShowing = sectionEq(section, target)
      store.deleteDashboard(item.dashboard.id)
      if (wasShowing) setSection(store.navigateHome())
    }
  }

  return (
    <button className={`sidebar-item${sectionEq(section, target) ? ' active' : ''}${isDropTarget ? ' drop-target' : ''}`}
            draggable
            onClick={select}
            onDragStart={e => { e.dataTransfer.setData('text/plain', name); onDragStart() }}
            onDragOver={e => { e.preventDefault(); onDragOver() }}
            onDragLeave={onDragLeave}
            onDrop={e => { e.preventDefault(); onDrop() }}
            onContextMenu={e => openAt(e, [
              { label: 'Rename', action: () => setRenaming({ kind: item.kind, id: item.kind === 'view' ? item.filter.id : item.dashboard.id, name }) },
              {
                label: store.isHomeTarget(target) ? 'Unset as Home' : 'Set as Home',
                action: () => store.setHomeTarget(target),
              },
              { label: 'Unpin from Sidebar', action: unpin },
              { label: 'Delete', danger: true, action: del },
            ])}>
      <span className="glyph"><Icon name={icon} size={11} /></span>
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
      {store.isHomeTarget(target) && <span className="home-mark"><Icon name="house" size={8} /></span>}
    </button>
  )
}

function SyncStatus() {
  const store = useStore()
  return (
    <div className="sync-status">
      <div className="sync-row">
        {store.syncing ? <span>⟳ Syncing…</span> : (
          <>
            <button className="icon-btn" onClick={() => store.sync()} title="Sync now" style={{ padding: 0 }}>
              <Icon name="refresh" size={11} />
            </button>
            <span style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              {store.totalPendingCount > 0 && <span className="queued">{store.totalPendingCount} change(s) queued</span>}
              {store.syncError
                ? <span className="err">{store.syncError}</span>
                : <>
                    <span>{store.lastSyncSummary || 'Synced'}</span>
                    {store.lastSync && <span className="time">{store.lastSync.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}</span>}
                  </>}
              {store.gistStatus && <span className="time">{store.gistStatus}</span>}
            </span>
          </>
        )}
      </div>
    </div>
  )
}
