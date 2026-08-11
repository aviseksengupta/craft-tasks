import { useMemo, useState } from 'react'
import { Section, TaskFilter, scheduleDay, deadlineDay, startOfToday, stateLabel } from './types'
import { useStore, DocumentSummary } from './store'
import { Icon, useContextMenu } from './ui'
import { CompletedToggle } from './TaskList'
import { NamePrompt } from './modals'

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
      <div className="page-header">
        <h1 style={{ fontSize: 25 }}>Documents</h1>
        <span className="count">{docs.length} with tasks</span>
        <span className="spacer" />
        <CompletedToggle />
      </div>
      <div className="hairline" />
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
  const { openAt, menu } = useContextMenu()

  const visible = store.searchText
    ? store.savedFilters.filter(f => f.name.toLowerCase().includes(store.searchText.toLowerCase()))
    : store.savedFilters

  return (
    <>
      <div className="page-header">
        <h1 style={{ fontSize: 25 }}>Views</h1>
        <span className="count">{visible.length}</span>
        <span className="spacer" />
        <CompletedToggle />
      </div>
      <div className="hairline" />
      {visible.length === 0 ? (
        <div className="empty-state">
          <div className="big"><Icon name="filterLines" size={28} /></div>
          {store.savedFilters.length === 0 ? 'Save a view from All Tasks to see it here' : 'No views match your search'}
        </div>
      ) : (
        <div className="list-scroll" style={{ padding: 0 }}>
          <div className="cards-grid">
            {visible.map(f => <ViewCard key={f.id} filter={f} setSection={setSection}
                                        onRename={() => setRenaming(f)} openAt={openAt} />)}
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

function ViewCard({ filter, setSection, onRename, openAt }: {
  filter: TaskFilter
  setSection: (s: Section) => void
  onRename: () => void
  openAt: (e: React.MouseEvent, items: { label: string; danger?: boolean; action: () => void }[]) => void
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
    <div className="doc-card" role="button" tabIndex={0}
         onClick={() => { store.selectSaved(filter.id); setSection({ kind: 'saved', id: filter.id }) }}
         onContextMenu={e => openAt(e, [
           { label: 'Rename', action: onRename },
           { label: isHome ? 'Unset as Home' : 'Set as Home', action: () => store.setHomeTarget({ kind: 'saved', id: filter.id }) },
           { label: pinned ? 'Unpin from Sidebar' : 'Pin to Sidebar', action: () => store.togglePinned(filter.id) },
           { label: 'Delete', danger: true, action: () => store.deleteFilter(filter.id) },
         ])}>
      <div className="doc-card-top">
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
