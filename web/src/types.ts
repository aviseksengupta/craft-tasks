export type TaskState = 'todo' | 'done' | 'canceled'

export const stateLabel: Record<TaskState, string> = {
  todo: 'Open', done: 'Done', canceled: 'Canceled',
}

export interface CraftTask {
  id: string
  markdown: string
  state: TaskState
  scheduleDate: string | null   // yyyy-MM-dd
  deadlineDate: string | null
  locationType: string          // document | inbox | dailyNote
  documentId: string | null
  documentTitle: string | null
  completedAt: string | null    // ISO8601
  hash: string
}

const TAG_RE = /#([\w/\-]+)/g

export function taskTitle(t: CraftTask): string {
  return t.markdown
    .replace(/<[^>]+>/g, '')
    .replace(/^\s*-\s*\[[ xX-]?\]\s*/, '')
    .trim()
}

export function displayTitle(t: CraftTask): string {
  const title = taskTitle(t)
  const s = title.replace(/\s*#[\w/\-]+/g, '').trim()
  return s === '' ? title : s
}

export function taskTags(t: CraftTask): string[] {
  return [...taskTitle(t).matchAll(TAG_RE)].map(m => m[1].toLowerCase())
}

export const DEFAULT_BACKLOG_TAG = 'later'

/// Whether a task carries the configured backlog/"later" tag, e.g. #later.
export function isBacklogTask(t: CraftTask, backlogTag: string): boolean {
  const tag = backlogTag.trim().toLowerCase()
  return tag !== '' && taskTags(t).includes(tag)
}

/// Tag autocomplete: prefix matches first (alphabetical), then substring
/// matches (alphabetical) — used by both the "add tag" field and the
/// live #tag token while typing a new task's title.
export function matchTags(query: string, allTags: string[], exclude: string[] = [], limit = 8): string[] {
  const q = query.toLowerCase()
  const pool = allTags.filter(t => !exclude.includes(t.toLowerCase()))
  if (!q) return pool.slice(0, limit)
  const prefix = pool.filter(t => t.toLowerCase().startsWith(q)).sort()
  const substring = pool.filter(t => !t.toLowerCase().startsWith(q) && t.toLowerCase().includes(q)).sort()
  return [...prefix, ...substring].slice(0, limit)
}

export function sourceName(t: CraftTask): string {
  if (t.locationType === 'inbox') return 'Inbox'
  return t.documentTitle ?? 'Untitled'
}

export function dayOf(s: string | null | undefined): Date | null {
  if (!s) return null
  const [y, m, d] = s.split('-').map(Number)
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

export function scheduleDay(t: CraftTask) { return dayOf(t.scheduleDate) }
export function deadlineDay(t: CraftTask) { return dayOf(t.deadlineDate) }
export function completedDay(t: CraftTask): Date | null {
  return t.completedAt ? new Date(t.completedAt) : null
}
export function effectiveDay(t: CraftTask): Date | null {
  return scheduleDay(t) ?? deadlineDay(t)
}

export function ymd(d: Date): string {
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

export function startOfToday(): Date {
  const d = new Date(); d.setHours(0, 0, 0, 0); return d
}

/// Split raw markdown into wrapper prefix, checkbox prefix, editable body,
/// wrapper suffix — so edits rewrite the body while preserving Craft's tags.
export interface MarkdownParts { pre: string; check: string; body: string; post: string }

export function markdownParts(md: string): MarkdownParts {
  const m = md.match(/^((?:<[^>]+>\s*)*)(-\s*\[[ xX-]?\]\s*)?([\s\S]*?)((?:\s*<\/[^>]+>)*)$/)
  if (!m) return { pre: '', check: '', body: md, post: '' }
  return { pre: m[1] ?? '', check: m[2] ?? '', body: m[3] ?? '', post: m[4] ?? '' }
}

export function rebuiltMarkdown(parts: MarkdownParts, body: string, state: TaskState): string {
  let c = parts.check
  if (c) {
    const mark = state === 'done' ? 'x' : state === 'canceled' ? '-' : ' '
    c = c.replace(/\[[ xX-]?\]/, `[${mark}]`)
  }
  return parts.pre + c + body + parts.post
}

// Stable JSON stringify with sorted keys, matching the Swift app's hashing basis.
function sortedJson(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v)
  if (Array.isArray(v)) return '[' + v.map(sortedJson).join(',') + ']'
  const o = v as Record<string, unknown>
  return '{' + Object.keys(o).sort().map(k => JSON.stringify(k) + ':' + sortedJson(o[k])).join(',') + '}'
}

export async function computeHash(json: unknown): Promise<string> {
  const data = new TextEncoder().encode(sortedJson(json))
  const buf = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
}

// ---- Filters ----

export type DateScope = 'Any' | 'Today' | 'Overdue' | 'Next 7 days' | 'This month' | 'No date'
export const dateScopes: DateScope[] = ['Any', 'Today', 'Overdue', 'Next 7 days', 'This month', 'No date']

export type DateField = 'Any date' | 'Scheduled' | 'Deadline'
export const dateFields: DateField[] = ['Any date', 'Scheduled', 'Deadline']

export type ViewLayout = 'Stacked' | 'Kanban'

export type GroupBy = 'Document' | 'Tag' | 'Scheduled' | 'Deadline' | 'State'
export const groupBys: GroupBy[] = ['Document', 'Tag', 'Scheduled', 'Deadline', 'State']

export type ItemVisibility = 'Always shown' | 'Hidden' | 'Invisible'
export const itemVisibilities: ItemVisibility[] = ['Always shown', 'Hidden', 'Invisible']

export interface TaskFilter {
  id: string
  name: string
  tags: string[]
  excludedTags: string[]
  documentIds: string[]        // "inbox" sentinel allowed
  states: TaskState[]
  dateField: DateField
  dateScope: DateScope
  groupBy: GroupBy
  layout: ViewLayout
  pinned?: boolean
  order?: number
  pinnedOrder?: number          // separate scale from `order` — pinned section mixes views+dashboards
  sectionId?: string | null    // reserved for future section grouping; unused for now
}

export function newFilter(partial: Partial<TaskFilter> = {}): TaskFilter {
  return {
    id: crypto.randomUUID(), name: '', tags: [], excludedTags: [], documentIds: [],
    states: ['todo'], dateField: 'Any date', dateScope: 'Any',
    groupBy: 'Document', layout: 'Stacked', order: 0,
    ...partial,
  }
}

export function filterIsEmpty(f: TaskFilter): boolean {
  return f.tags.length === 0 && f.excludedTags.length === 0 && f.documentIds.length === 0
    && f.states.length === 1 && f.states[0] === 'todo'
    && f.dateField === 'Any date' && f.dateScope === 'Any' && f.groupBy === 'Document'
}

export function filterMatches(f: TaskFilter, t: CraftTask, todayIncludesOverdue = false): boolean {
  if (f.states.length > 0 && !f.states.includes(t.state)) return false
  const tags = taskTags(t)
  if (f.tags.length > 0 && !f.tags.some(x => tags.includes(x))) return false
  if (f.excludedTags.length > 0 && f.excludedTags.some(x => tags.includes(x))) return false
  if (f.documentIds.length > 0) {
    const key = t.locationType === 'inbox' ? 'inbox' : (t.documentId ?? '')
    if (!f.documentIds.includes(key)) return false
  }
  const today = startOfToday()
  let date: Date | null
  switch (f.dateField) {
    case 'Any date': date = effectiveDay(t); break
    case 'Scheduled': date = scheduleDay(t); break
    case 'Deadline': date = deadlineDay(t); break
  }
  switch (f.dateScope) {
    case 'Any': break
    case 'No date': if (date) return false; break
    case 'Today':
      if (!date) return false
      if (date.getTime() !== today.getTime()) {
        if (!(todayIncludesOverdue && date < today && t.state === 'todo')) return false
      }
      break
    case 'Overdue':
      if (!date || !(date < today && t.state === 'todo')) return false; break
    case 'Next 7 days': {
      if (!date) return false
      const end = new Date(today); end.setDate(end.getDate() + 7)
      if (!(date >= today && date <= end)) return false; break
    }
    case 'This month':
      if (!date || date.getFullYear() !== today.getFullYear() || date.getMonth() !== today.getMonth()) return false
      break
  }
  return true
}

// ---- Dashboards ----

export interface DashboardWidget {
  id: string
  viewId: string
  widthUnits: number
  heightUnits: number
}

export interface Dashboard {
  id: string
  name: string
  widgets: DashboardWidget[]
  pinned?: boolean
  order?: number
  pinnedOrder?: number          // separate scale from `order` — pinned section mixes views+dashboards
  sectionId?: string | null    // reserved for future section grouping; unused for now
}

export type PinnedItem =
  | { kind: 'view'; filter: TaskFilter }
  | { kind: 'dashboard'; dashboard: Dashboard }

// ---- Navigation ----

export type Section =
  | { kind: 'home' } | { kind: 'allTasks' } | { kind: 'inbox' } | { kind: 'today' }
  | { kind: 'thisWeek' } | { kind: 'documents' } | { kind: 'views' } | { kind: 'dashboards' }
  | { kind: 'saved', id: string } | { kind: 'dashboard', id: string }

export function sectionEq(a: Section | null | undefined, b: Section | null | undefined): boolean {
  if (!a || !b) return false
  if (a.kind !== b.kind) return false
  if ('id' in a && 'id' in b) return a.id === b.id
  return true
}

// ---- Persisted config (synced to Gist) ----

export interface ConfigFile {
  filters: TaskFilter[]
  homeSection: Section | null
  dashboards: Dashboard[]
  documentDisplayNames: Record<string, string>
  itemVisibility: Record<string, ItemVisibility>
  tagColors: Record<string, string>  // tag → hex color (e.g. "#FF5733"), used for the card's left border
  tagCheckboxColors: Record<string, string>  // tag → hex color, used for the checkbox ring on open tasks
  backlogTag: string  // tag (without '#') marking a task as backlog/later, e.g. "later"
}

export const emptyConfig: ConfigFile = {
  filters: [], homeSection: null, dashboards: [], documentDisplayNames: {}, itemVisibility: {}, tagColors: {}, tagCheckboxColors: {},
  backlogTag: DEFAULT_BACKLOG_TAG,
}

// ---- Outbox ----

export interface PendingUpdate { taskId: string; payload: Record<string, unknown> }
export interface PendingCreate { localId: string; payload: Record<string, unknown>; description?: string }
