// Google Calendar integration.
//
// Design: Craft stays the source of truth for tasks (no time, no reminders).
// A dedicated secondary Google Calendar named "Craft Tasks" is a *separate*
// store for time-based reminders. "Send to Calendar" is a one-way, one-shot
// push — no sync, no linkage kept. The in-app Calendar view is a thin CRUD
// client over that one calendar.
//
// Auth is browser-only (GitHub Pages, no backend): Google Identity Services
// token flow. Access tokens last ~1h with silent renewal while the Google
// session is alive. Scope `calendar.app.created` means this app can only ever
// see and touch calendars it created itself — never the user's real calendars.

const GIS_SRC = 'https://accounts.google.com/gsi/client'
const API_BASE = 'https://www.googleapis.com/calendar/v3'
// Full calendar scope. `calendar.app.created` was cleaner in principle (app
// only sees calendars it made) but returns "insufficient permissions" for
// calendarList.list / calendars.insert unless the project is specially
// configured — not worth the friction for a personal, testing-mode app.
const SCOPE = 'https://www.googleapis.com/auth/calendar'
const CAL_SUMMARY = 'Craft Tasks'

// The OAuth client id is entered once in Settings (like the Craft URL), so it
// never needs a rebuild. A build-time default can still be baked in via Vite.
const BUILD_DEFAULT_CLIENT_ID = (import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined) ?? ''

export function getGoogleClientId(): string {
  return (localStorage.getItem('googleClientId') || BUILD_DEFAULT_CLIENT_ID).trim()
}
export function setGoogleClientId(id: string) {
  const v = id.trim()
  if (v === getGoogleClientId()) return
  if (v) localStorage.setItem('googleClientId', v)
  else localStorage.removeItem('googleClientId')
  // A different client invalidates any cached token/consent.
  disconnect()
}

// ---- GIS script + token client ----

interface TokenResponse { access_token?: string; expires_in?: number; error?: string; error_description?: string }
interface TokenClient { requestAccessToken(opts?: { prompt?: string }): void }

declare global {
  interface Window {
    google?: {
      accounts: {
        oauth2: {
          initTokenClient(cfg: {
            client_id: string; scope: string; prompt?: string
            callback: (r: TokenResponse) => void
            error_callback?: (e: { type?: string; message?: string }) => void
          }): TokenClient
          revoke(token: string, done?: () => void): void
        }
      }
    }
  }
}

let gisPromise: Promise<void> | null = null
function loadGis(): Promise<void> {
  if (window.google?.accounts?.oauth2) return Promise.resolve()
  if (gisPromise) return gisPromise
  gisPromise = new Promise((resolve, reject) => {
    const s = document.createElement('script')
    s.src = GIS_SRC
    s.async = true
    s.defer = true
    s.onload = () => resolve()
    s.onerror = () => { gisPromise = null; reject(new Error('Could not load Google sign-in')) }
    document.head.appendChild(s)
  })
  return gisPromise
}

// In-memory token, mirrored to sessionStorage so a reload within the hour
// doesn't re-prompt. `gcalConnected` in localStorage is the sticky "the user
// linked their account" flag that survives token expiry across reloads.
interface CachedToken { token: string; expiresAt: number; scope: string }
let cached: CachedToken | null = readSessionToken()

function readSessionToken(): CachedToken | null {
  try {
    const raw = sessionStorage.getItem('gcalToken')
    if (!raw) return null
    const t = JSON.parse(raw) as CachedToken
    // Discard a token minted under a different scope (e.g. after a scope change).
    if (t.scope !== SCOPE) return null
    return t.expiresAt > Date.now() + 30_000 ? t : null
  } catch { return null }
}
function writeSessionToken(t: CachedToken | null) {
  try {
    if (t) sessionStorage.setItem('gcalToken', JSON.stringify(t))
    else sessionStorage.removeItem('gcalToken')
  } catch { /* private mode */ }
}

export function isConnected(): boolean {
  return localStorage.getItem('gcalConnected') === '1' && !!getGoogleClientId()
}

export function disconnect() {
  const tok = cached?.token
  cached = null
  writeSessionToken(null)
  localStorage.removeItem('gcalConnected')
  localStorage.removeItem('craftCalendarId')
  if (tok && window.google?.accounts?.oauth2) {
    try { window.google.accounts.oauth2.revoke(tok) } catch { /* ignore */ }
  }
}

let tokenClient: TokenClient | null = null
let tokenClientId = ''
let pending: { resolve: (t: string) => void; reject: (e: Error) => void } | null = null

function getTokenClient(): TokenClient {
  const clientId = getGoogleClientId()
  if (!clientId) throw new Error('Google OAuth Client ID not set — add it in Settings')
  if (tokenClient && tokenClientId === clientId) return tokenClient
  tokenClientId = clientId
  tokenClient = window.google!.accounts.oauth2.initTokenClient({
    client_id: clientId,
    scope: SCOPE,
    callback: (r) => {
      const p = pending; pending = null
      if (!p) return
      if (r.error || !r.access_token) {
        p.reject(new Error(r.error_description || r.error || 'Authorization failed'))
        return
      }
      cached = { token: r.access_token, expiresAt: Date.now() + (r.expires_in ?? 3600) * 1000, scope: SCOPE }
      writeSessionToken(cached)
      localStorage.setItem('gcalConnected', '1')
      p.resolve(r.access_token)
    },
    error_callback: (e) => {
      const p = pending; pending = null
      p?.reject(new Error(e.message || 'Authorization was cancelled'))
    },
  })
  return tokenClient
}

/** Get a usable access token. `interactive` shows the Google popup; when false,
 * only a cached or silently-refreshable token is used (throws otherwise). */
async function getToken(interactive: boolean): Promise<string> {
  if (cached && cached.expiresAt > Date.now() + 30_000) return cached.token
  await loadGis()
  const client = getTokenClient()
  return new Promise<string>((resolve, reject) => {
    if (pending) { reject(new Error('Another sign-in is already in progress')); return }
    pending = { resolve, reject }
    try {
      client.requestAccessToken({ prompt: interactive ? 'consent' : '' })
    } catch (e) {
      pending = null
      reject(e instanceof Error ? e : new Error('Authorization failed'))
    }
  })
}

/** Interactive sign-in, triggered by the "Connect" button. */
export async function connect(): Promise<void> {
  await getToken(true)
}

// ---- REST helpers ----

async function api<T>(path: string, init?: RequestInit & { interactive?: boolean }): Promise<T> {
  const doFetch = async (token: string) => fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
    },
  })

  let token = await getToken(init?.interactive ?? false)
  let resp = await doFetch(token)
  if (resp.status === 401) {
    // token rejected — force a fresh one and retry once
    cached = null; writeSessionToken(null)
    token = await getToken(init?.interactive ?? false)
    resp = await doFetch(token)
  }
  if (!resp.ok) {
    let msg = `Google Calendar API ${resp.status}`
    try {
      const j = await resp.json() as { error?: { message?: string } }
      if (j.error?.message) msg = j.error.message
    } catch { /* ignore */ }
    throw new Error(msg)
  }
  if (resp.status === 204) return undefined as T
  return resp.json() as Promise<T>
}

// ---- Calendar resolution ----

interface CalendarListEntry { id: string; summary?: string }

/** Resolve the dedicated "Craft Tasks" calendar id, creating it only if none
 * exists. `known` is the id remembered in synced config, tried first. Guards
 * against multiple devices each creating their own copy: always scans the
 * calendar list by name, and after a create re-scans and collapses duplicates
 * to the deterministically-first id (deleting empty extras, best effort). */
export async function ensureCalendar(known: string | null | undefined): Promise<string> {
  if (known) {
    try {
      await api(`/calendars/${encodeURIComponent(known)}`)
      return known
    } catch { /* gone — fall through to re-resolve */ }
  }

  const found = await findCraftCalendars()
  if (found.length > 0) return found[0]

  await api('/calendars', { method: 'POST', body: JSON.stringify({ summary: CAL_SUMMARY }) })

  // Re-scan to catch a race where another device created one at the same time.
  const after = await findCraftCalendars()
  const winner = after[0]
  for (const extra of after.slice(1)) {
    if (await calendarIsEmpty(extra)) {
      try { await api(`/calendars/${encodeURIComponent(extra)}`, { method: 'DELETE' }) } catch { /* ignore */ }
    }
  }
  return winner
}

async function findCraftCalendars(): Promise<string[]> {
  const list = await api<{ items?: CalendarListEntry[] }>('/users/me/calendarList?showHidden=true&maxResults=250')
  return (list.items ?? [])
    .filter(c => (c.summary ?? '').trim() === CAL_SUMMARY)
    .map(c => c.id)
    .sort()
}

async function calendarIsEmpty(calId: string): Promise<boolean> {
  try {
    const r = await api<{ items?: unknown[] }>(`/calendars/${encodeURIComponent(calId)}/events?maxResults=1`)
    return (r.items ?? []).length === 0
  } catch { return false }
}

// ---- Events ----

export interface GCalEvent {
  id: string
  summary: string
  description?: string
  htmlLink?: string
  start: { dateTime?: string; date?: string; timeZone?: string }
  end: { dateTime?: string; date?: string; timeZone?: string }
  recurrence?: string[]
  recurringEventId?: string
  status?: string
  extendedProperties?: { private?: Record<string, string> }
}

export type RepeatKind = 'none' | 'daily' | 'weekly' | 'weekday' | 'monthly'

const BYDAY = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']

/** Build an RRULE array for the Google event, or undefined for a one-off.
 * `date` anchors weekly-by-weekday and monthly-by-monthday. */
export function buildRecurrence(kind: RepeatKind, date: Date, until: Date | null): string[] | undefined {
  if (kind === 'none') return undefined
  let rule: string
  switch (kind) {
    case 'daily': rule = 'FREQ=DAILY'; break
    case 'weekly': rule = `FREQ=WEEKLY;BYDAY=${BYDAY[date.getDay()]}`; break
    case 'weekday': rule = 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'; break
    case 'monthly': rule = `FREQ=MONTHLY;BYMONTHDAY=${date.getDate()}`; break
  }
  if (until) {
    const u = new Date(until); u.setHours(23, 59, 59, 0)
    rule += `;UNTIL=${u.getUTCFullYear()}${pad(u.getUTCMonth() + 1)}${pad(u.getUTCDate())}T${pad(u.getUTCHours())}${pad(u.getUTCMinutes())}${pad(u.getUTCSeconds())}Z`
  }
  return [`RRULE:${rule}`]
}

/** Read the RRULE back into our simple RepeatKind (best effort, for editing). */
export function parseRecurrence(recurrence: string[] | undefined): { kind: RepeatKind; until: Date | null } {
  const rrule = (recurrence ?? []).find(r => r.startsWith('RRULE:'))
  if (!rrule) return { kind: 'none', until: null }
  const body = rrule.slice(6)
  const parts = Object.fromEntries(body.split(';').map(p => p.split('=') as [string, string]))
  let until: Date | null = null
  if (parts.UNTIL) {
    const m = parts.UNTIL.match(/^(\d{4})(\d{2})(\d{2})/)
    if (m) until = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  }
  let kind: RepeatKind = 'none'
  if (parts.FREQ === 'DAILY') kind = 'daily'
  else if (parts.FREQ === 'MONTHLY') kind = 'monthly'
  else if (parts.FREQ === 'WEEKLY') kind = parts.BYDAY === 'MO,TU,WE,TH,FR' ? 'weekday' : 'weekly'
  return { kind, until }
}

const pad = (n: number) => String(n).padStart(2, '0')
const localTz = Intl.DateTimeFormat().resolvedOptions().timeZone

function toLocalIso(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:00`
}

export interface EventInput {
  title: string
  start: Date          // local time
  durationMin?: number // default 30
  repeat?: RepeatKind
  repeatUntil?: Date | null
  description?: string
  craftTaskId?: string
}

function eventBody(input: EventInput): Record<string, unknown> {
  const end = new Date(input.start.getTime() + (input.durationMin ?? 30) * 60_000)
  const body: Record<string, unknown> = {
    summary: input.title,
    start: { dateTime: toLocalIso(input.start), timeZone: localTz },
    end: { dateTime: toLocalIso(end), timeZone: localTz },
  }
  const rec = buildRecurrence(input.repeat ?? 'none', input.start, input.repeatUntil ?? null)
  if (rec) body.recurrence = rec
  if (input.description) body.description = input.description
  if (input.craftTaskId) body.extendedProperties = { private: { craftTaskId: input.craftTaskId } }
  return body
}

export async function createEvent(calId: string, input: EventInput): Promise<GCalEvent> {
  return api<GCalEvent>(`/calendars/${encodeURIComponent(calId)}/events`, {
    method: 'POST', body: JSON.stringify(eventBody(input)), interactive: true,
  })
}

/** Patch an existing event. For a recurring series pass the master event id. */
export async function updateEvent(calId: string, eventId: string, input: EventInput): Promise<GCalEvent> {
  return api<GCalEvent>(`/calendars/${encodeURIComponent(calId)}/events/${encodeURIComponent(eventId)}`, {
    method: 'PATCH', body: JSON.stringify(eventBody(input)),
  })
}

export async function deleteEvent(calId: string, eventId: string): Promise<void> {
  await api(`/calendars/${encodeURIComponent(calId)}/events/${encodeURIComponent(eventId)}`, { method: 'DELETE' })
}

/** List single event instances (recurring events expanded) within [from, to). */
export async function listEvents(calId: string, from: Date, to: Date): Promise<GCalEvent[]> {
  const params = new URLSearchParams({
    singleEvents: 'true',
    orderBy: 'startTime',
    timeMin: from.toISOString(),
    timeMax: to.toISOString(),
    maxResults: '250',
  })
  const r = await api<{ items?: GCalEvent[] }>(`/calendars/${encodeURIComponent(calId)}/events?${params}`)
  return (r.items ?? []).filter(e => e.status !== 'cancelled')
}

export function eventStart(e: GCalEvent): Date {
  return new Date(e.start.dateTime ?? `${e.start.date}T00:00:00`)
}
export function isAllDay(e: GCalEvent): boolean {
  return !e.start.dateTime && !!e.start.date
}

// ---- Multi-calendar agenda (Craft Tasks editable, everything else read-only) ----

interface CalListEntry {
  id: string
  summary?: string
  summaryOverride?: string
  backgroundColor?: string
  selected?: boolean
  accessRole?: string
}

export interface AgendaEvent {
  event: GCalEvent
  calendarId: string
  calendarName: string
  color?: string
  editable: boolean
}

/** Every event across the user's visible calendars for [from, to). Events on
 * the dedicated Craft Tasks calendar are `editable`; all others are read-only
 * context. Respects each calendar's "shown" checkbox in Google Calendar. */
export async function listAgenda(craftCalId: string, from: Date, to: Date): Promise<AgendaEvent[]> {
  const list = await api<{ items?: CalListEntry[] }>('/users/me/calendarList?maxResults=250')
  const cals = (list.items ?? []).filter(c =>
    c.selected !== false && c.accessRole !== 'freeBusyReader'
  )
  const per = await Promise.all(cals.map(async c => {
    try {
      const evs = await listEvents(c.id, from, to)
      const name = c.summaryOverride || c.summary || c.id
      return evs.map<AgendaEvent>(event => ({
        event, calendarId: c.id, calendarName: name,
        color: c.backgroundColor, editable: c.id === craftCalId,
      }))
    } catch { return [] as AgendaEvent[] }
  }))
  return per.flat()
}
