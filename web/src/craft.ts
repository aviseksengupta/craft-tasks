import { CraftTask, TaskState, computeHash } from './types'

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
  get isLikelyTransient() { return this.status >= 500 || this.status === 0 }
}

export function getApiBase(): string | null {
  const url = localStorage.getItem('craftApiUrl')
  if (!url) return null
  return url.replace(/\/+$/, '')
}

export function setApiBase(url: string) {
  localStorage.setItem('craftApiUrl', url.trim())
}

export function getSpaceId(): string | null {
  return localStorage.getItem('craftSpaceId')
}

/** GET /connection returns the space id and a ready-made craftdocs:// URL template
 * ({blockId} placeholder) — fetched once after the API URL is (re)configured and cached. */
export async function refreshSpaceId(): Promise<void> {
  const root = await call('/connection') as { space?: { id?: string } }
  const id = root.space?.id
  if (id) localStorage.setItem('craftSpaceId', id)
}

/** Deep link to open a task's own block in the Craft app, via the craftdocs://
 * URL scheme — lands on the task itself (including inside a nested subpage),
 * not just the top of its containing document. Needs the space id cached by
 * refreshSpaceId(); null for inbox tasks (no addressable location). */
export function craftDeepLink(task: CraftTask): string | null {
  const spaceId = getSpaceId()
  if (task.locationType === 'inbox' || !spaceId) return null
  return `craftdocs://open?spaceId=${encodeURIComponent(spaceId)}&blockId=${encodeURIComponent(task.id)}`
}

async function call(path: string, init?: RequestInit): Promise<unknown> {
  const base = getApiBase()
  if (!base) throw new ApiError(0, 'Craft link URL not configured')
  let resp: Response
  try {
    resp = await fetch(`${base}${path}`, {
      ...init,
      headers: init?.body ? { 'Content-Type': 'application/json' } : undefined,
    })
  } catch (e) {
    throw new ApiError(0, e instanceof Error ? e.message : 'Network error')
  }
  const text = await resp.text()
  let json: unknown = null
  try { json = text ? JSON.parse(text) : null } catch { /* not json */ }
  if (!resp.ok) {
    const obj = json as { errors?: { message?: string }[] } | null
    const msg = obj?.errors?.[0]?.message ?? `Craft API returned HTTP ${resp.status}`
    throw new ApiError(resp.status, msg)
  }
  return json
}

interface RawTask {
  id: string
  markdown?: string
  completedAt?: string
  taskInfo?: { state?: string; scheduleDate?: string; deadlineDate?: string }
  location?: { type?: string; documentId?: string; title?: string }
}

async function parseTask(raw: RawTask): Promise<CraftTask> {
  const ti = raw.taskInfo ?? {}
  const loc = raw.location ?? {}
  return {
    id: raw.id,
    markdown: raw.markdown ?? '',
    state: (ti.state as TaskState) ?? 'todo',
    scheduleDate: ti.scheduleDate ?? null,
    deadlineDate: ti.deadlineDate ?? null,
    locationType: loc.type ?? 'document',
    documentId: loc.documentId ?? null,
    documentTitle: loc.title ?? null,
    completedAt: raw.completedAt ?? null,
    hash: await computeHash(raw),
  }
}

export async function fetchAllTasks(): Promise<CraftTask[]> {
  const root = await call('/tasks?scope=all') as { items?: RawTask[] }
  const items = root.items ?? []
  return Promise.all(items.map(parseTask))
}

export async function pushUpdates(payloads: Record<string, unknown>[]): Promise<void> {
  if (payloads.length === 0) return
  await call('/tasks', { method: 'PUT', body: JSON.stringify({ tasksToUpdate: payloads }) })
}

export async function createTask(payload: Record<string, unknown>): Promise<CraftTask> {
  const root = await call('/tasks', { method: 'POST', body: JSON.stringify({ tasks: [payload] }) }) as { items?: RawTask[] }
  const raw = root.items?.[0]
  if (!raw?.id) throw new ApiError(200, 'Craft returned an unexpected response')
  return parseTask(raw)
}

export async function deleteTask(taskId: string): Promise<void> {
  await call('/blocks', { method: 'DELETE', body: JSON.stringify({ blockIds: [taskId] }) })
}

export interface TaskDescription { blockIds: string[]; text: string }

export async function fetchDescription(taskId: string): Promise<TaskDescription> {
  const root = await call(`/blocks?id=${encodeURIComponent(taskId)}&maxDepth=1`) as
    { content?: { id?: string; markdown?: string }[] }
  const content = root.content ?? []
  return {
    blockIds: content.map(b => b.id).filter((x): x is string => !!x),
    text: content.map(b => b.markdown).filter(Boolean).join('\n'),
  }
}

export async function pushDescription(taskId: string, existingBlockIds: string[], newText: string): Promise<void> {
  const trimmed = newText.trim()
  if (existingBlockIds.length > 0) {
    await call('/blocks', { method: 'DELETE', body: JSON.stringify({ blockIds: existingBlockIds }) })
  }
  if (!trimmed) return
  await call('/blocks', {
    method: 'POST',
    body: JSON.stringify({
      blocks: [{ type: 'text', markdown: trimmed }],
      position: { position: 'start', pageId: taskId },
    }),
  })
}
