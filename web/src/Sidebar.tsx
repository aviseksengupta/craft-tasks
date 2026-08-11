import { useState } from 'react'
import { Section, sectionEq } from './types'
import { useStore } from './store'
import { Icon, useContextMenu } from './ui'
import { SidebarSettingsModal, ViewPicker, NamePrompt } from './modals'

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
  const [showNewDashboard, setShowNewDashboard] = useState(false)
  const [showMore, setShowMore] = useState(false)
  const [renaming, setRenaming] = useState<{ id: string; name: string } | null>(null)
  const { openAt, menu } = useContextMenu()

  const navDefs: NavDef[] = [
    { id: 'home', icon: 'house', label: 'Home', section: { kind: 'home' }, select: () => setSection(store.navigateHome()) },
    { id: 'allTasks', icon: 'trayFull', label: 'All Tasks', section: { kind: 'allTasks' }, select: () => { store.selectAllTasks(); setSection({ kind: 'allTasks' }) } },
    { id: 'inbox', icon: 'tray', label: 'Inbox', section: { kind: 'inbox' }, select: () => { store.selectInbox(); setSection({ kind: 'inbox' }) } },
    { id: 'today', icon: 'sun', label: 'Today', section: { kind: 'today' }, select: () => { store.selectToday(); setSection({ kind: 'today' }) } },
    { id: 'thisWeek', icon: 'calendarClock', label: 'This Week', section: { kind: 'thisWeek' }, select: () => { store.selectThisWeek(); setSection({ kind: 'thisWeek' }) } },
    { id: 'documents', icon: 'doc', label: 'Documents', section: { kind: 'documents' }, select: () => setSection({ kind: 'documents' }) },
    { id: 'views', icon: 'listRect', label: 'Views', section: { kind: 'views' }, select: () => setSection({ kind: 'views' }) },
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
  const pinnedFilters = store.savedFilters.filter(f => f.pinned)

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

        {pinnedFilters.length > 0 && (
          <>
            <div className="sidebar-section-label">PINNED VIEWS</div>
            {pinnedFilters.map(f => (
              <button key={f.id}
                      className={`sidebar-item${sectionEq(section, { kind: 'saved', id: f.id }) ? ' active' : ''}`}
                      onClick={() => { store.selectSaved(f.id); setSection({ kind: 'saved', id: f.id }); onNavigate() }}
                      onContextMenu={e => openAt(e, [
                        { label: 'Rename', action: () => setRenaming({ id: f.id, name: f.name }) },
                        {
                          label: store.isHomeTarget({ kind: 'saved', id: f.id }) ? 'Unset as Home' : 'Set as Home',
                          action: () => store.setHomeTarget({ kind: 'saved', id: f.id }),
                        },
                        { label: 'Unpin from Sidebar', action: () => store.togglePinned(f.id) },
                        { label: 'Delete', danger: true, action: () => store.deleteFilter(f.id) },
                      ])}>
                <span className="glyph"><Icon name="filterLines" size={11} /></span>
                <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{f.name}</span>
                {store.isHomeTarget({ kind: 'saved', id: f.id }) && <span className="home-mark"><Icon name="house" size={8} /></span>}
              </button>
            ))}
          </>
        )}

        <div className="sidebar-section-label">
          DASHBOARDS
          <button className="plus" onClick={() => setShowNewDashboard(true)}
                  disabled={store.savedFilters.length === 0}
                  title={store.savedFilters.length === 0 ? 'Save a view first' : 'New dashboard'}>
            <Icon name="plus" size={9} />
          </button>
        </div>
        {store.dashboards.map(d => (
          <button key={d.id}
                  className={`sidebar-item${sectionEq(section, { kind: 'dashboard', id: d.id }) ? ' active' : ''}`}
                  onClick={() => { setSection({ kind: 'dashboard', id: d.id }); onNavigate() }}
                  onContextMenu={e => openAt(e, [
                    {
                      label: store.isHomeTarget({ kind: 'dashboard', id: d.id }) ? 'Unset as Home' : 'Set as Home',
                      action: () => store.setHomeTarget({ kind: 'dashboard', id: d.id }),
                    },
                    {
                      label: 'Delete', danger: true,
                      action: () => {
                        const wasShowing = sectionEq(section, { kind: 'dashboard', id: d.id })
                        store.deleteDashboard(d.id)
                        if (wasShowing) setSection(store.navigateHome())
                      },
                    },
                  ])}>
          <span className="glyph"><Icon name="grid" size={11} /></span>
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{d.name}</span>
          {store.isHomeTarget({ kind: 'dashboard', id: d.id }) && <span className="home-mark"><Icon name="house" size={8} /></span>}
        </button>
        ))}

        <SyncStatus />
      </div>

      {menu}
      {showSidebarSettings && <SidebarSettingsModal navDefs={navDefs} onClose={() => setShowSidebarSettings(false)} />}
      {showNewDashboard && (
        <ViewPicker title="New Dashboard" cta="Create" requireName
                    views={store.savedFilters.map(f => ({ id: f.id, name: f.name }))}
                    onClose={() => setShowNewDashboard(false)}
                    onDone={(name, ids) => {
                      const d = store.saveDashboard(name, ids)
                      setSection({ kind: 'dashboard', id: d.id })
                    }} />
      )}
      {renaming && (
        <NamePrompt title="View name" initial={renaming.name}
                    onClose={() => setRenaming(null)}
                    onSave={name => store.renameFilter(renaming.id, name)} />
      )}
    </>
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
