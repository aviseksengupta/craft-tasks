/* eslint-disable react-refresh/only-export-components */
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, ReactNode } from 'react'
import {
  CraftTask, TaskFilter, Dashboard, DashboardWidget, Section, ConfigFile, ItemVisibility,
  TaskState, GroupBy, PendingUpdate, PendingCreate,
  newFilter, filterMatches, sectionEq, emptyConfig, taskTitle, taskTags, displayTitle,
  scheduleDay, deadlineDay, completedDay, sourceName, startOfToday, markdownParts, rebuiltMarkdown,
} from './types'
import * as craft from './craft'
import { loadFromGist, saveToGist, getGistToken } from './gist'

export interface DocumentSummary {
  id: string; title: string; craftTitle: string
  open: number; done: number; canceled: number; overdue: number
  total: number; progress: number
}

// ---- localStorage helpers ----
function loadJson<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key)
    return raw ? JSON.parse(raw) as T : fallback
  } catch { return fallback }
}
function saveJson(key: string, value: unknown) {
  localStorage.setItem(key, JSON.stringify(value))
}

interface StoreValue {
  tasks: CraftTask[]
  filter: TaskFilter
  setFilter: (f: TaskFilter | ((prev: TaskFilter) => TaskFilter)) => void
  savedFilters: TaskFilter[]
  dashboards: Dashboard[]
  homeSection: Section | null
  itemVisibility: Record<string, ItemVisibility>
  documentDisplayNames: Record<string, string>
  showCompleted: boolean
  setShowCompleted: (b: boolean) => void
  searchText: string
  setSearchText: (s: string) => void
  syncing: boolean
  lastSync: Date | null
  lastSyncSummary: string
  syncError: string | null
  totalPendingCount: number
  gistStatus: string | null
  configured: boolean

  allTags: string[]
  documents: DocumentSummary[]
  filtered: CraftTask[]
  apply: (f: TaskFilter) => CraftTask[]
  group: (tasks: CraftTask[], by: GroupBy) => [string, CraftTask[]][]
  displayName: (id: string, craftTitle: string) => string
  setDisplayName: (id: string, name: string | null) => void

  sync: () => Promise<void>
  cycleState: (t: CraftTask) => void
  applyEdit: (t: CraftTask, body: string, state: TaskState, scheduleDate: string | null,
              deadlineDate: string | null, destination?: { kind: 'unchanged' } | { kind: 'inbox' } | { kind: 'document'; id: string }) => void
  createTask: (title: string, tags: string[], scheduleDate: string | null,
               deadlineDate: string | null, documentId: string | null) => void

  navigateHome: () => Section
  selectAllTasks: () => void
  selectInbox: () => void
  selectToday: () => void
  selectThisWeek: () => void
  selectSaved: (id: string) => void
  openDocument: (id: string) => void

  saveCurrentFilter: (name: string) => void
  updateSavedFilter: (id: string) => void
  togglePinned: (id: string) => void
  renameFilter: (id: string, name: string) => void
  deleteFilter: (id: string) => void
  setHomeTarget: (s: Section) => void
  isHomeTarget: (s: Section) => boolean
  setItemVisibility: (id: string, v: ItemVisibility) => void

  saveDashboard: (name: string, viewIds: string[]) => Dashboard
  deleteDashboard: (id: string) => void
  addWidgets: (viewIds: string[], dashboardId: string) => void
  removeWidget: (widgetId: string, dashboardId: string) => void
  setWidgetDimensions: (widgetId: string, w: number, h: number, dashboardId: string) => void
  moveWidget: (draggedId: string, targetId: string, dashboardId: string) => void

  todayFilter: TaskFilter
  thisWeekFilter: TaskFilter
  inboxFilter: TaskFilter
}

const StoreContext = createContext<StoreValue | null>(null)

export function useStore(): StoreValue {
  const v = useContext(StoreContext)
  if (!v) throw new Error('useStore outside provider')
  return v
}

export function StoreProvider({ children }: { children: ReactNode }) {
  const [tasks, setTasks] = useState<CraftTask[]>(() => loadJson('tasks', []))
  const [filter, setFilter] = useState<TaskFilter>(() => newFilter())
  const [config, setConfig] = useState<ConfigFile>(() => loadJson('config', emptyConfig))
  const [showCompleted, setShowCompletedState] = useState<boolean>(() => loadJson('showCompleted', true))
  const [searchText, setSearchText] = useState('')
  const [syncing, setSyncing] = useState(false)
  const [lastSync, setLastSync] = useState<Date | null>(() => {
    const s = localStorage.getItem('lastSync'); return s ? new Date(s) : null
  })
  const [lastSyncSummary, setLastSyncSummary] = useState('')
  const [syncError, setSyncError] = useState<string | null>(null)
  const [pending, setPending] = useState<PendingUpdate[]>(() => loadJson('pendingUpdates', []))
  const [pendingCreates, setPendingCreates] = useState<PendingCreate[]>(() => loadJson('pendingCreates', []))
  const [gistStatus, setGistStatus] = useState<string | null>(null)
  // Settings changes always reload the page (see SettingsModal's forceRefresh),
  // so this only needs to reflect what's true at mount — no version counter
  // to force a re-check, unlike an in-place settings update would need.
  const configured = !!craft.getApiBase()

  // refs so async flows always see current values
  const tasksRef = useRef(tasks); tasksRef.current = tasks
  const pendingRef = useRef(pending); pendingRef.current = pending
  const pendingCreatesRef = useRef(pendingCreates); pendingCreatesRef.current = pendingCreates
  const syncingRef = useRef(false)

  const persistTasks = useCallback((ts: CraftTask[]) => {
    setTasks(ts); saveJson('tasks', ts)
  }, [])
  const persistPending = useCallback((p: PendingUpdate[]) => {
    setPending(p); pendingRef.current = p; saveJson('pendingUpdates', p)
  }, [])
  const persistPendingCreates = useCallback((p: PendingCreate[]) => {
    setPendingCreates(p); pendingCreatesRef.current = p; saveJson('pendingCreates', p)
  }, [])

  // ---- config persistence: localStorage always, gist debounced ----
  const gistTimer = useRef<number | null>(null)
  const skipNextGistPush = useRef(false)
  const updateConfig = useCallback((fn: (c: ConfigFile) => ConfigFile) => {
    setConfig(prev => {
      const next = fn(prev)
      saveJson('config', next)
      if (getGistToken() && !skipNextGistPush.current) {
        if (gistTimer.current) window.clearTimeout(gistTimer.current)
        gistTimer.current = window.setTimeout(() => {
          saveToGist(next)
            .then(() => setGistStatus('Config synced to Gist'))
            .catch(e => setGistStatus(`Gist sync failed: ${e instanceof Error ? e.message : e}`))
        }, 1500)
      }
      skipNextGistPush.current = false
      return next
    })
  }, [])

  // Pull config from gist on startup (remote wins — it's the cross-device source of truth).
  useEffect(() => {
    if (!getGistToken()) return
    loadFromGist().then(remote => {
      if (remote) {
        skipNextGistPush.current = true
        setConfig(remote)
        saveJson('config', remote)
        setGistStatus('Config loaded from Gist')
      }
    }).catch(e => setGistStatus(`Gist load failed: ${e instanceof Error ? e.message : e}`))
  }, [])

  const setShowCompleted = useCallback((b: boolean) => {
    setShowCompletedState(b); saveJson('showCompleted', b)
  }, [])

  // ---- outbox flush ----
  const flushPending = useCallback(async () => {
    const p = pendingRef.current
    if (p.length === 0) return
    try {
      await craft.pushUpdates(p.map(x => x.payload))
      persistPending([])
      setSyncError(null)
    } catch (e) {
      const err = e as craft.ApiError
      setSyncError(err.isLikelyTransient === false
        ? `${p.length} change(s) can't sync: ${err.message}`
        : `Offline — ${p.length} change(s) queued`)
    }
  }, [persistPending])

  const flushPendingCreates = useCallback(async () => {
    const items = pendingCreatesRef.current
    if (items.length === 0) return
    for (const item of [...items]) {
      try {
        const created = await craft.createTask(item.payload)
        persistTasks([...tasksRef.current.filter(t => t.id !== item.localId), created])
        persistPendingCreates(pendingCreatesRef.current.filter(x => x.localId !== item.localId))
      } catch (e) {
        const err = e as craft.ApiError
        if (err.isLikelyTransient === false) {
          setSyncError(`New task can't sync: ${err.message}`)
          // Permanent rejection: drop from queue and remove the optimistic row.
          persistTasks(tasksRef.current.filter(t => t.id !== item.localId))
          persistPendingCreates(pendingCreatesRef.current.filter(x => x.localId !== item.localId))
        }
      }
    }
  }, [persistTasks, persistPendingCreates])

  // ---- sync ----
  const sync = useCallback(async () => {
    if (syncingRef.current || !craft.getApiBase()) return
    syncingRef.current = true
    setSyncing(true)
    setSyncError(null)
    try {
      await flushPending()
      await flushPendingCreates()
      const remote = await craft.fetchAllTasks()
      const pendingIds = new Set([
        ...pendingRef.current.map(x => x.taskId),
        ...pendingCreatesRef.current.map(x => x.localId),
      ])
      const local = new Map(tasksRef.current.map(t => [t.id, t]))
      let added = 0, updated = 0
      const next: CraftTask[] = []
      const seen = new Set<string>()
      for (const r of remote) {
        seen.add(r.id)
        if (pendingIds.has(r.id)) { const l = local.get(r.id); if (l) next.push(l); continue }
        const l = local.get(r.id)
        if (!l) added++
        else if (l.hash !== r.hash) updated++
        next.push(r)
      }
      // keep local rows that are still pending (e.g. offline-created)
      for (const t of tasksRef.current) {
        if (!seen.has(t.id) && pendingIds.has(t.id)) next.push(t)
      }
      const removed = tasksRef.current.filter(t => !seen.has(t.id) && !pendingIds.has(t.id)).length
      if (added || updated || removed) persistTasks(next)
      const now = new Date()
      setLastSync(now)
      localStorage.setItem('lastSync', now.toISOString())
      setLastSyncSummary(added === 0 && updated === 0 && removed === 0
        ? `Up to date · ${remote.length} tasks`
        : `+${added} · ~${updated} · −${removed} · ${remote.length} tasks`)
    } catch (e) {
      setSyncError(e instanceof Error ? e.message : String(e))
    } finally {
      syncingRef.current = false
      setSyncing(false)
    }
  }, [flushPending, flushPendingCreates, persistTasks])

  // startup + every 5 minutes + on regaining connectivity
  useEffect(() => {
    sync()
    const t = window.setInterval(sync, 300_000)
    const onOnline = () => sync()
    window.addEventListener('online', onOnline)
    return () => { window.clearInterval(t); window.removeEventListener('online', onOnline) }
  }, [sync])

  // ---- edits ----
  const applyEdit = useCallback((task: CraftTask, body: string, state: TaskState,
                                 scheduleDate: string | null, deadlineDate: string | null,
                                 destination: { kind: 'unchanged' } | { kind: 'inbox' } | { kind: 'document'; id: string } = { kind: 'unchanged' }) => {
    const newMarkdown = rebuiltMarkdown(markdownParts(task.markdown), body, state)
    let { locationType, documentId, documentTitle } = task
    let locationPayload: Record<string, unknown> | undefined
    if (destination.kind === 'inbox') {
      locationType = 'inbox'; documentId = null; documentTitle = null
      locationPayload = { type: 'inbox' }
    } else if (destination.kind === 'document') {
      locationType = 'document'; documentId = destination.id
      const doc = tasksRef.current.find(t => t.documentId === destination.id)
      documentTitle = doc?.documentTitle ?? documentTitle
      locationPayload = { type: 'document', documentId: destination.id }
    }
    const updatedTask: CraftTask = {
      ...task, markdown: newMarkdown, state, scheduleDate, deadlineDate,
      locationType, documentId, documentTitle,
      completedAt: state === 'todo' ? null : task.completedAt,
      hash: 'dirty',
    }
    persistTasks(tasksRef.current.map(t => t.id === task.id ? updatedTask : t))
    const payload: Record<string, unknown> = {
      id: task.id, markdown: newMarkdown,
      taskInfo: { state, scheduleDate, deadlineDate },
    }
    if (locationPayload) payload.location = locationPayload
    persistPending([...pendingRef.current.filter(x => x.taskId !== task.id), { taskId: task.id, payload }])
    flushPending()
  }, [persistTasks, persistPending, flushPending])

  const cycleState = useCallback((t: CraftTask) => {
    const next: TaskState = t.state === 'todo' ? 'done' : t.state === 'done' ? 'canceled' : 'todo'
    applyEdit(t, markdownParts(t.markdown).body, next, t.scheduleDate, t.deadlineDate)
  }, [applyEdit])

  const documentsForCreate = useRef<DocumentSummary[]>([])

  const createTask = useCallback((title: string, tags: string[], scheduleDate: string | null,
                                  deadlineDate: string | null, documentId: string | null) => {
    const tagSuffix = tags.length ? ' ' + tags.map(t => `#${t}`).join(' ') : ''
    const markdown = '- [ ] ' + title.trim() + tagSuffix
    const location = documentId ? { type: 'document', documentId } : { type: 'inbox' }
    const localId = `local-${crypto.randomUUID()}`
    const optimistic: CraftTask = {
      id: localId, markdown, state: 'todo', scheduleDate, deadlineDate,
      locationType: documentId ? 'document' : 'inbox', documentId,
      documentTitle: documentId ? documentsForCreate.current.find(d => d.id === documentId)?.title ?? null : null,
      completedAt: null, hash: 'pending-create',
    }
    persistTasks([...tasksRef.current, optimistic])
    const payload: Record<string, unknown> = { markdown, location }
    const taskInfo: Record<string, unknown> = {}
    if (scheduleDate) taskInfo.scheduleDate = scheduleDate
    if (deadlineDate) taskInfo.deadlineDate = deadlineDate
    if (Object.keys(taskInfo).length) payload.taskInfo = taskInfo
    persistPendingCreates([...pendingCreatesRef.current, { localId, payload }])
    flushPendingCreates()
  }, [persistTasks, persistPendingCreates, flushPendingCreates])

  // ---- derived ----
  const allTags = useMemo(() => {
    const counts = new Map<string, number>()
    for (const t of tasks) for (const tag of taskTags(t)) counts.set(tag, (counts.get(tag) ?? 0) + 1)
    return [...counts.entries()]
      .sort((a, b) => a[1] === b[1] ? a[0].localeCompare(b[0]) : b[1] - a[1])
      .map(([k]) => k)
  }, [tasks])

  const displayName = useCallback((id: string, craftTitle: string) =>
    config.documentDisplayNames[id] ?? craftTitle, [config.documentDisplayNames])

  const documents = useMemo<DocumentSummary[]>(() => {
    const groups = new Map<string, { title: string; tasks: CraftTask[] }>()
    const today = startOfToday()
    for (const t of tasks) {
      const key = t.locationType === 'inbox' ? 'inbox' : (t.documentId ?? 'unknown')
      if (!groups.has(key)) groups.set(key, { title: sourceName(t), tasks: [] })
      groups.get(key)!.tasks.push(t)
    }
    const list = [...groups.entries()].map(([key, g]) => {
      const open = g.tasks.filter(t => t.state === 'todo').length
      const done = g.tasks.filter(t => t.state === 'done').length
      const canceled = g.tasks.filter(t => t.state === 'canceled').length
      const overdue = g.tasks.filter(t => {
        const d = scheduleDay(t) ?? deadlineDay(t)
        return t.state === 'todo' && d !== null && d < today
      }).length
      const total = open + done + canceled
      return {
        id: key, title: displayName(key, g.title), craftTitle: g.title,
        open, done, canceled, overdue, total,
        progress: total === 0 ? 0 : (done + canceled) / total,
      }
    })
    list.sort((a, b) => a.open === b.open ? a.title.localeCompare(b.title) : b.open - a.open)
    return list
  }, [tasks, displayName])
  documentsForCreate.current = documents

  const taskSort = useCallback((a: CraftTask, b: CraftTask): number => {
    if (a.state !== b.state) return a.state === 'todo' ? -1 : b.state === 'todo' ? 1 : 0
    const da = scheduleDay(a) ?? deadlineDay(a)
    const db = scheduleDay(b) ?? deadlineDay(b)
    if (da && db) { if (da.getTime() !== db.getTime()) return da.getTime() - db.getTime() }
    else if (da && !db) return -1
    else if (!da && db) return 1
    if (a.state === 'done') {
      const ca = completedDay(a), cb = completedDay(b)
      if (ca && cb && ca.getTime() !== cb.getTime()) return cb.getTime() - ca.getTime()
    }
    return displayTitle(a).localeCompare(displayTitle(b))
  }, [])

  const apply = useCallback((f: TaskFilter) =>
    tasks.filter(t =>
      filterMatches(f, t) && (showCompleted || t.state === 'todo')
        && (searchText === '' || taskTitle(t).toLowerCase().includes(searchText.toLowerCase()))
    ).sort(taskSort), [tasks, showCompleted, searchText, taskSort])

  const filtered = useMemo(() => apply(filter), [apply, filter])

  const group = useCallback((ts: CraftTask[], g: GroupBy): [string, CraftTask[]][] => {
    const today = startOfToday()
    const dateBucket = (d: Date | null, isOpen: boolean): string => {
      if (!d) return 'No date'
      if (d < today) return isOpen ? 'Overdue' : 'Earlier'
      if (d.getTime() === today.getTime()) return 'Today'
      const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1)
      if (d.getTime() === tomorrow.getTime()) return 'Tomorrow'
      const end = new Date(today); end.setDate(end.getDate() + 7)
      if (d <= end) return 'Next 7 days'
      return 'Later'
    }
    const bucketOrder = ['Overdue', 'Earlier', 'Today', 'Tomorrow', 'Next 7 days', 'Later', 'No date']
    const order: string[] = []
    const map = new Map<string, CraftTask[]>()
    for (const t of ts) {
      let key: string
      switch (g) {
        case 'Document': {
          const docKey = t.locationType === 'inbox' ? 'inbox' : (t.documentId ?? 'unknown')
          key = displayName(docKey, sourceName(t)); break
        }
        case 'Tag': {
          const tags = taskTags(t).sort()
          key = tags.length === 0 ? 'No tags' : tags.map(x => `#${x}`).join('  '); break
        }
        case 'Scheduled': key = dateBucket(scheduleDay(t), t.state === 'todo'); break
        case 'Deadline': key = dateBucket(deadlineDay(t), t.state === 'todo'); break
        case 'State': key = t.state === 'todo' ? 'Open' : t.state === 'done' ? 'Done' : 'Canceled'; break
      }
      if (!map.has(key)) { order.push(key); map.set(key, []) }
      map.get(key)!.push(t)
    }
    if (g === 'Scheduled' || g === 'Deadline') {
      order.sort((a, b) => (bucketOrder.indexOf(a) + 100 || 99) - (bucketOrder.indexOf(b) + 100 || 99))
      order.sort((a, b) => {
        const ia = bucketOrder.indexOf(a), ib = bucketOrder.indexOf(b)
        return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
      })
    } else if (g === 'Tag') {
      order.sort((a, b) => a === 'No tags' ? 1 : b === 'No tags' ? -1 : a.localeCompare(b))
    } else if (g === 'State') {
      const so = ['Open', 'Done', 'Canceled']
      order.sort((a, b) => so.indexOf(a) - so.indexOf(b))
    }
    return order.map(k => [k, map.get(k)!])
  }, [displayName])

  // ---- built-in filters ----
  const todayFilter = useMemo(() => newFilter({ name: 'Today', dateScope: 'Today' }), [])
  const thisWeekFilter = useMemo(() => newFilter({ name: 'This Week', dateScope: 'Next 7 days' }), [])
  const inboxFilter = useMemo(() => newFilter({ name: 'Inbox', documentIds: ['inbox'] }), [])

  // ---- navigation ----
  const selectAllTasks = useCallback(() => setFilter(newFilter({ states: [] })), [])
  const selectInbox = useCallback(() => setFilter({ ...inboxFilter }), [inboxFilter])
  const selectToday = useCallback(() => setFilter({ ...todayFilter }), [todayFilter])
  const selectThisWeek = useCallback(() => setFilter({ ...thisWeekFilter }), [thisWeekFilter])
  const selectSaved = useCallback((id: string) => {
    const f = config.filters.find(x => x.id === id)
    if (f) setFilter({ ...f })
  }, [config.filters])
  const openDocument = useCallback((id: string) => {
    setFilter(newFilter({ states: [], documentIds: [id] }))
  }, [])

  const navigateHome = useCallback((): Section => {
    const hs = config.homeSection
    switch (hs?.kind) {
      case 'saved': {
        const f = config.filters.find(x => x.id === hs.id)
        if (!f) { setFilter(newFilter()); return { kind: 'home' } }
        setFilter({ ...f })
        return hs
      }
      case 'dashboard':
        if (!config.dashboards.some(d => d.id === hs.id)) { setFilter(newFilter()); return { kind: 'home' } }
        return hs
      case 'allTasks': selectAllTasks(); return hs
      case 'inbox': selectInbox(); return hs
      case 'today': selectToday(); return hs
      case 'thisWeek': selectThisWeek(); return hs
      case 'documents': case 'views': return hs
      default: setFilter(newFilter()); return { kind: 'home' }
    }
  }, [config, selectAllTasks, selectInbox, selectToday, selectThisWeek])

  // ---- saved filters / dashboards / home ----
  const saveCurrentFilter = useCallback((name: string) => {
    const f = { ...filter, id: crypto.randomUUID(), name }
    updateConfig(c => ({ ...c, filters: [...c.filters, f] }))
  }, [filter, updateConfig])

  const updateSavedFilter = useCallback((id: string) => {
    updateConfig(c => ({
      ...c,
      filters: c.filters.map(x => x.id === id
        ? { ...filter, id, name: x.name, pinned: x.pinned } : x),
    }))
  }, [filter, updateConfig])

  const togglePinned = useCallback((id: string) => {
    updateConfig(c => ({ ...c, filters: c.filters.map(x => x.id === id ? { ...x, pinned: !x.pinned } : x) }))
  }, [updateConfig])

  const renameFilter = useCallback((id: string, name: string) => {
    const trimmed = name.trim()
    if (!trimmed) return
    updateConfig(c => ({ ...c, filters: c.filters.map(x => x.id === id ? { ...x, name: trimmed } : x) }))
  }, [updateConfig])

  const deleteFilter = useCallback((id: string) => {
    updateConfig(c => ({
      ...c,
      filters: c.filters.filter(x => x.id !== id),
      dashboards: c.dashboards.map(d => ({ ...d, widgets: d.widgets.filter(w => w.viewId !== id) })),
      homeSection: sectionEq(c.homeSection, { kind: 'saved', id }) ? null : c.homeSection,
    }))
  }, [updateConfig])

  const setHomeTarget = useCallback((s: Section) => {
    updateConfig(c => ({ ...c, homeSection: sectionEq(c.homeSection, s) ? null : s }))
  }, [updateConfig])

  const isHomeTarget = useCallback((s: Section) => sectionEq(config.homeSection, s), [config.homeSection])

  const setItemVisibility = useCallback((id: string, v: ItemVisibility) => {
    updateConfig(c => ({ ...c, itemVisibility: { ...c.itemVisibility, [id]: v } }))
  }, [updateConfig])

  const setDisplayName = useCallback((id: string, name: string | null) => {
    updateConfig(c => {
      const names = { ...c.documentDisplayNames }
      const trimmed = name?.trim()
      if (trimmed) names[id] = trimmed
      else delete names[id]
      return { ...c, documentDisplayNames: names }
    })
  }, [updateConfig])

  const saveDashboard = useCallback((name: string, viewIds: string[]): Dashboard => {
    const d: Dashboard = {
      id: crypto.randomUUID(), name,
      widgets: viewIds.map(viewId => ({ id: crypto.randomUUID(), viewId, widthUnits: 4, heightUnits: 2 })),
    }
    updateConfig(c => ({ ...c, dashboards: [...c.dashboards, d] }))
    return d
  }, [updateConfig])

  const deleteDashboard = useCallback((id: string) => {
    updateConfig(c => ({
      ...c,
      dashboards: c.dashboards.filter(d => d.id !== id),
      homeSection: sectionEq(c.homeSection, { kind: 'dashboard', id }) ? null : c.homeSection,
    }))
  }, [updateConfig])

  const addWidgets = useCallback((viewIds: string[], dashboardId: string) => {
    updateConfig(c => ({
      ...c,
      dashboards: c.dashboards.map(d => {
        if (d.id !== dashboardId) return d
        const existing = new Set(d.widgets.map(w => w.viewId))
        const toAdd: DashboardWidget[] = viewIds.filter(v => !existing.has(v))
          .map(viewId => ({ id: crypto.randomUUID(), viewId, widthUnits: 4, heightUnits: 2 }))
        return { ...d, widgets: [...d.widgets, ...toAdd] }
      }),
    }))
  }, [updateConfig])

  const removeWidget = useCallback((widgetId: string, dashboardId: string) => {
    updateConfig(c => ({
      ...c,
      dashboards: c.dashboards.map(d => d.id === dashboardId
        ? { ...d, widgets: d.widgets.filter(w => w.id !== widgetId) } : d),
    }))
  }, [updateConfig])

  const setWidgetDimensions = useCallback((widgetId: string, w: number, h: number, dashboardId: string) => {
    updateConfig(c => ({
      ...c,
      dashboards: c.dashboards.map(d => d.id === dashboardId
        ? { ...d, widgets: d.widgets.map(x => x.id === widgetId ? { ...x, widthUnits: w, heightUnits: h } : x) } : d),
    }))
  }, [updateConfig])

  const moveWidget = useCallback((draggedId: string, targetId: string, dashboardId: string) => {
    updateConfig(c => ({
      ...c,
      dashboards: c.dashboards.map(d => {
        if (d.id !== dashboardId) return d
        const from = d.widgets.findIndex(w => w.id === draggedId)
        const to = d.widgets.findIndex(w => w.id === targetId)
        if (from < 0 || to < 0 || from === to) return d
        const widgets = [...d.widgets]
        const [item] = widgets.splice(from, 1)
        widgets.splice(to, 0, item)
        return { ...d, widgets }
      }),
    }))
  }, [updateConfig])

  const value: StoreValue = {
    tasks, filter, setFilter,
    savedFilters: config.filters, dashboards: config.dashboards,
    homeSection: config.homeSection, itemVisibility: config.itemVisibility,
    documentDisplayNames: config.documentDisplayNames,
    showCompleted, setShowCompleted, searchText, setSearchText,
    syncing, lastSync, lastSyncSummary, syncError,
    totalPendingCount: pending.length + pendingCreates.length,
    gistStatus, configured,
    allTags, documents, filtered, apply, group, displayName, setDisplayName,
    sync, cycleState, applyEdit, createTask,
    navigateHome, selectAllTasks, selectInbox, selectToday, selectThisWeek, selectSaved, openDocument,
    saveCurrentFilter, updateSavedFilter, togglePinned, renameFilter, deleteFilter,
    setHomeTarget, isHomeTarget, setItemVisibility,
    saveDashboard, deleteDashboard, addWidgets, removeWidget, setWidgetDimensions, moveWidget,
    todayFilter, thisWeekFilter, inboxFilter,
  }

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>
}
