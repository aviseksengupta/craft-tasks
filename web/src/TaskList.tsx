import { useMemo, useState } from 'react'
import {
  CraftTask, Section, TaskFilter, TaskState, stateLabel, dateScopes, dateFields, groupBys,
  filterIsEmpty, newFilter,
} from './types'
import { useStore } from './store'
import { Chip, MenuChip, MenuItem, Icon, PageHeadSticky } from './ui'
import { TaskRow } from './TaskRow'
import { EditTaskModal, NamePrompt } from './modals'

export function CompletedToggle() {
  const store = useStore()
  return (
    <Chip text="Completed" small
          icon={store.showCompleted ? 'eye' : 'eyeSlash'}
          active={!store.showCompleted}
          onClick={() => store.setShowCompleted(!store.showCompleted)}
          title={store.showCompleted ? 'Completed & canceled tasks shown — click to hide' : 'Completed & canceled tasks hidden — click to show'} />
  )
}

export function BacklogToggle() {
  const store = useStore()
  return (
    <Chip text="Backlog" small
          icon={store.showBacklog ? 'eye' : 'eyeSlash'}
          active={!store.showBacklog}
          onClick={() => store.setShowBacklog(!store.showBacklog)}
          title={store.showBacklog
            ? `Backlog tasks (tagged #${store.backlogTag}) shown — click to hide`
            : `Backlog tasks (tagged #${store.backlogTag}) hidden — click to show`} />
  )
}

export function TaskListView({ section }: { section: Section }) {
  const store = useStore()
  const [showSaveSheet, setShowSaveSheet] = useState(false)
  const [editing, setEditing] = useState<CraftTask | null>(null)

  const heading = useMemo(() => {
    switch (section.kind) {
      case 'home': return 'Home'
      case 'allTasks': return 'All Tasks'
      case 'inbox': return 'Inbox'
      case 'today': return 'Today'
      case 'thisWeek': return 'This Week'
      case 'saved': return store.savedFilters.find(f => f.id === section.id)?.name ?? 'View'
      default: return ''
    }
  }, [section, store.savedFilters])

  const editableViewId = section.kind === 'saved' ? section.id : null
  const hasUnsavedViewChanges = useMemo(() => {
    if (!editableViewId) return false
    const saved = store.savedFilters.find(f => f.id === editableViewId)
    if (!saved) return false
    const current: TaskFilter = { ...store.filter, id: saved.id, name: saved.name, pinned: saved.pinned }
    return JSON.stringify({ ...current, tags: [...current.tags].sort(), excludedTags: [...current.excludedTags].sort(), documentIds: [...current.documentIds].sort(), states: [...current.states].sort() })
      !== JSON.stringify({ ...saved, tags: [...saved.tags].sort(), excludedTags: [...saved.excludedTags].sort(), documentIds: [...saved.documentIds].sort(), states: [...saved.states].sort() })
  }, [editableViewId, store.filter, store.savedFilters])

  const groups = store.group(store.filtered, store.filter.groupBy)
  const isKanban = store.filter.layout === 'Kanban'

  return (
    <>
      <PageHeadSticky>
        <div className="page-header">
          <h1>{heading}</h1>
          <span className="count">{store.filtered.length}</span>
          <span className="spacer" />
          <CompletedToggle />
          <BacklogToggle />
          {editableViewId && hasUnsavedViewChanges && (
            <Chip text="Update view" icon="refresh" onClick={() => store.updateSavedFilter(editableViewId)} />
          )}
          {!editableViewId && section.kind === 'allTasks' && !filterIsEmpty(store.filter) && (
            <Chip text="Save view" icon="plus" onClick={() => setShowSaveSheet(true)} />
          )}
        </div>
        <FilterBar />
        <div className="hairline" />
      </PageHeadSticky>
      <div className="list-scroll">
        {store.filtered.length === 0 ? (
          <div className="empty-state">
            <div className="big"><Icon name="checkCircle" size={28} /></div>
            No tasks match this view
          </div>
        ) : isKanban ? (
          <div className="kanban-row">
            {groups.map(([title, items]) => (
              <div className="kanban-col" key={title}>
                <div className="group-head">
                  <span className="g-title" style={{ fontSize: 14 }}>{title}</span>
                  <span className="g-count">{items.length}</span>
                </div>
                <div className="group-card">
                  {items.map(t => <TaskRow key={t.id} task={t} onEdit={setEditing} />)}
                  {items.length === 0 && <div className="menu-note" style={{ padding: 14 }}>Nothing here</div>}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="group-stack">
            {groups.map(([title, items]) => <GroupBlock key={title} title={title} items={items} onEdit={setEditing} />)}
          </div>
        )}
      </div>
      {showSaveSheet && (
        <NamePrompt title="Save current filter as view"
                    onClose={() => setShowSaveSheet(false)}
                    onSave={name => store.saveCurrentFilter(name)} />
      )}
      {editing && <EditTaskModal task={editing} onClose={() => setEditing(null)} />}
    </>
  )
}

function GroupBlock({ title, items, onEdit }: {
  title: string; items: CraftTask[]; onEdit: (t: CraftTask) => void
}) {
  const [expanded, setExpanded] = useState(true)
  return (
    <div>
      <button className="group-head" onClick={() => setExpanded(e => !e)}>
        <span className={`chev${expanded ? ' open' : ''}`}><Icon name="chevron" size={10} /></span>
        <span className="g-title">{title}</span>
        <span className="g-count">{items.length}</span>
      </button>
      {expanded && (
        <div className="group-card">
          {items.map(t => <TaskRow key={t.id} task={t} onEdit={onEdit} />)}
        </div>
      )}
    </div>
  )
}

export function FilterBar() {
  const store = useStore()
  const f = store.filter
  const set = store.setFilter
  const toggleIn = <T,>(arr: T[], v: T): T[] => arr.includes(v) ? arr.filter(x => x !== v) : [...arr, v]

  const tagActiveCount = f.tags.length + f.excludedTags.length

  return (
    <div className="filter-bar">
      <MenuChip label={
        <Chip text={f.states.length === 0 ? 'Any' : f.states.map(s => stateLabel[s]).sort().join(', ')}
              icon="checkCircle"
              active={f.states.length > 0 && !(f.states.length === 1 && f.states[0] === 'todo')} />
      }>
        {() => (<>
          {(['todo', 'done', 'canceled'] as TaskState[]).map(s => (
            <MenuItem key={s} label={stateLabel[s]} checked={f.states.includes(s)}
                      onClick={() => set(p => ({ ...p, states: toggleIn(p.states, s) }))} />
          ))}
          <div className="menu-sep" />
          <MenuItem label="Any" onClick={() => set(p => ({ ...p, states: [] }))} />
        </>)}
      </MenuChip>

      <MenuChip label={
        <Chip text={f.dateField === 'Any date' ? 'Date' : f.dateField}
              icon={f.dateField === 'Deadline' ? 'flag' : 'calendar'}
              active={f.dateField !== 'Any date'} />
      }>
        {close => dateFields.map(d => (
          <MenuItem key={d} label={d} checked={f.dateField === d}
                    onClick={() => { set(p => ({ ...p, dateField: d })); close() }} />
        ))}
      </MenuChip>

      <MenuChip label={<Chip text={f.dateScope} active={f.dateScope !== 'Any'} />}>
        {close => dateScopes.map(d => (
          <MenuItem key={d} label={d} checked={f.dateScope === d}
                    onClick={() => { set(p => ({ ...p, dateScope: d })); close() }} />
        ))}
      </MenuChip>

      <MenuChip label={
        <Chip text={f.documentIds.length === 0 ? 'Docs: All' : `Docs: ${f.documentIds.length}`}
              icon="doc" active={f.documentIds.length > 0} />
      }>
        {() => (<>
          {store.documents.map(d => (
            <MenuItem key={d.id} label={d.title} checked={f.documentIds.includes(d.id)}
                      onClick={() => set(p => ({ ...p, documentIds: toggleIn(p.documentIds, d.id) }))} />
          ))}
          <div className="menu-sep" />
          <MenuItem label="Docs: All" onClick={() => set(p => ({ ...p, documentIds: [] }))} />
        </>)}
      </MenuChip>

      {/* Each tag cycles none → include → exclude → none */}
      <MenuChip label={
        <Chip text={tagActiveCount === 0 ? 'Tags: All' : `Tags: ${tagActiveCount}`}
              icon="pin" active={tagActiveCount > 0} />
      }>
        {() => (<>
          {store.allTags.map(tag => (
            <MenuItem key={tag} label={`#${tag}`}
                      checked={f.tags.includes(tag)} minus={f.excludedTags.includes(tag)}
                      onClick={() => set(p => {
                        if (p.tags.includes(tag)) return { ...p, tags: p.tags.filter(t => t !== tag), excludedTags: [...p.excludedTags, tag] }
                        if (p.excludedTags.includes(tag)) return { ...p, excludedTags: p.excludedTags.filter(t => t !== tag) }
                        return { ...p, tags: [...p.tags, tag] }
                      })} />
          ))}
          {store.allTags.length === 0 && <div className="menu-note">No tags yet</div>}
          <div className="menu-sep" />
          <MenuItem label="Tags: All" onClick={() => set(p => ({ ...p, tags: [], excludedTags: [] }))} />
        </>)}
      </MenuChip>

      <MenuChip label={
        <Chip text={`By: ${f.groupBy}`} icon="stack" active={f.groupBy !== 'Document'} />
      }>
        {close => groupBys.map(g => (
          <MenuItem key={g} label={g} checked={f.groupBy === g}
                    onClick={() => { set(p => ({ ...p, groupBy: g })); close() }} />
        ))}
      </MenuChip>

      <Chip text={f.layout} icon={f.layout === 'Kanban' ? 'grid' : 'listRect'}
            active={f.layout === 'Kanban'}
            onClick={() => set(p => ({ ...p, layout: p.layout === 'Stacked' ? 'Kanban' : 'Stacked' }))}
            title="Switch between stacked groups and side-by-side kanban columns" />

      <span className="spacer" style={{ flex: 1 }} />
      {!filterIsEmpty(f) && (
        <Chip text="Clear" icon="xmark" onClick={() => set(newFilter())} />
      )}
    </div>
  )
}
