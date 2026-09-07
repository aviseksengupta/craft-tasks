import { useCallback, useEffect, useMemo, useState } from 'react'
import { CraftTask, displayTitle, dayOf, sourceName } from './types'
import { useStore } from './store'
import { craftDeepLink } from './craft'
import { Icon, Modal, PageHeadSticky, MiniCalendar, TimePicker } from './ui'
import * as gcal from './gcal'

// ---- shared helpers ----

const pad = (n: number) => String(n).padStart(2, '0')

function combine(date: Date, time: string): Date {
  const [h, m] = time.split(':').map(Number)
  const d = new Date(date)
  d.setHours(h || 0, m || 0, 0, 0)
  return d
}
function timeOf(d: Date): string { return `${pad(d.getHours())}:${pad(d.getMinutes())}` }
function fmtTime(d: Date): string {
  return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
}
function mondayOf(d: Date): Date {
  const x = new Date(d); x.setHours(0, 0, 0, 0)
  const day = (x.getDay() + 6) % 7 // Mon=0
  x.setDate(x.getDate() - day)
  return x
}
function sameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

const REPEAT_OPTIONS: { value: gcal.RepeatKind; label: string }[] = [
  { value: 'none', label: 'Does not repeat' },
  { value: 'daily', label: 'Daily' },
  { value: 'weekly', label: 'Weekly' },
  { value: 'weekday', label: 'Every weekday (Mon–Fri)' },
  { value: 'monthly', label: 'Monthly' },
]

// ---- date + time + repeat sub-form, shared by both modals ----

function EventForm({ value, onChange }: {
  value: EventFormState
  onChange: (v: EventFormState) => void
}) {
  const [calOpen, setCalOpen] = useState(false)
  const [untilOpen, setUntilOpen] = useState(false)
  const set = (patch: Partial<EventFormState>) => onChange({ ...value, ...patch })

  return (
    <>
      <div>
        <div className="form-label">TITLE</div>
        <input type="text" value={value.title} onChange={e => set({ title: e.target.value })}
               placeholder="Event title" />
      </div>

      <div className="flow-row" style={{ gap: 14, alignItems: 'flex-start' }}>
        <div style={{ position: 'relative' }}>
          <div className="form-label">DATE</div>
          <button className="btn" onClick={() => setCalOpen(o => !o)}>
            <Icon name="calendar" size={12} />{' '}
            {value.date.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' })}
          </button>
          {calOpen && (
            <div style={{ position: 'absolute', zIndex: 30, top: '100%', left: 0 }}>
              <MiniCalendar date={value.date} onChange={d => { if (d) set({ date: d }); setCalOpen(false) }} />
            </div>
          )}
        </div>
        <div>
          <div className="form-label">TIME</div>
          <TimePicker value={value.time} onChange={t => set({ time: t })} />
        </div>
      </div>

      {value.canRepeat ? (
        <div className="flow-row" style={{ gap: 14, alignItems: 'flex-start' }}>
          <div>
            <div className="form-label">REPEAT</div>
            <select value={value.repeat} onChange={e => set({ repeat: e.target.value as gcal.RepeatKind })}>
              {REPEAT_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
            </select>
          </div>
          {value.repeat !== 'none' && (
            <div style={{ position: 'relative' }}>
              <div className="form-label">UNTIL (OPTIONAL)</div>
              <button className="btn" onClick={() => setUntilOpen(o => !o)}>
                {value.until
                  ? value.until.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
                  : 'No end'}
              </button>
              {value.until && (
                <button className="btn" style={{ marginLeft: 6 }} onClick={() => set({ until: null })}>×</button>
              )}
              {untilOpen && (
                <div style={{ position: 'absolute', zIndex: 30, top: '100%', left: 0 }}>
                  <MiniCalendar date={value.until} onChange={d => { set({ until: d }); setUntilOpen(false) }} />
                </div>
              )}
            </div>
          )}
        </div>
      ) : (
        <div className="hint-text"><Icon name="refresh" size={11} /> Part of a repeating series — changes here apply to this occurrence only.</div>
      )}
    </>
  )
}

interface EventFormState {
  title: string
  date: Date
  time: string
  repeat: gcal.RepeatKind
  until: Date | null
  canRepeat: boolean
}

// ---- Send to Calendar (from a task) ----

export function SendToCalendarModal({ task, onClose }: { task: CraftTask; onClose: () => void }) {
  const store = useStore()
  const initialDate = dayOf(task.scheduleDate) ?? dayOf(task.deadlineDate) ?? new Date()
  const [form, setForm] = useState<EventFormState>({
    title: displayTitle(task),
    date: (() => { const d = new Date(initialDate); d.setHours(0, 0, 0, 0); return d })(),
    time: '09:00',
    repeat: 'none',
    until: null,
    canRepeat: true,
  })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  const connected = gcal.isConnected()

  const send = async () => {
    setBusy(true); setError(null)
    try {
      const calId = await gcal.ensureCalendar(store.craftCalendarId)
      store.setCraftCalendarId(calId)
      const link = craftDeepLink(task)
      await gcal.createEvent(calId, {
        title: form.title.trim() || 'Untitled',
        start: combine(form.date, form.time),
        repeat: form.repeat,
        repeatUntil: form.until,
        craftTaskId: task.id,
        description: [`From Craft Tasks · ${sourceName(task)}`, link].filter(Boolean).join('\n'),
      })
      setDone(true)
      setTimeout(onClose, 900)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal onClose={onClose} narrow>
      <h2><Icon name="calendarClock" size={15} /> Send to Calendar</h2>
      {!connected ? (
        <div className="hint-text" style={{ marginTop: 8 }}>
          Connect a Google account under <b>Settings → Calendar</b> first. Events are pushed to a
          dedicated “Craft Tasks” calendar.
        </div>
      ) : done ? (
        <div className="hint-text" style={{ marginTop: 8 }}><Icon name="check" size={12} /> Added to your Craft Tasks calendar.</div>
      ) : (
        <>
          <EventForm value={form} onChange={setForm} />
          <div className="hint-text">
            One-way push — the event is independent of the task afterwards. Manage it in the Calendar view.
          </div>
          {error && <div className="error-text">{error}</div>}
        </>
      )}
      <div className="modal-actions">
        <button className="btn" onClick={onClose} disabled={busy}>{done ? 'Close' : 'Cancel'}</button>
        {connected && !done && (
          <button className="btn primary" onClick={send} disabled={busy || !form.title.trim()}>
            {busy ? 'Sending…' : 'Send to Calendar'}
          </button>
        )}
      </div>
    </Modal>
  )
}

// ---- Event editor (inside the Calendar view) ----

function EventEditModal({ calId, event, onClose, onChanged }: {
  calId: string
  event: gcal.GCalEvent
  onClose: () => void
  onChanged: () => void
}) {
  const isRecurringInstance = !!event.recurringEventId
  const start = gcal.eventStart(event)
  const rec = gcal.parseRecurrence(event.recurrence)
  const [form, setForm] = useState<EventFormState>({
    title: event.summary ?? '',
    date: (() => { const d = new Date(start); d.setHours(0, 0, 0, 0); return d })(),
    time: timeOf(start),
    repeat: rec.kind,
    until: rec.until,
    canRepeat: !isRecurringInstance,
  })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmDelete, setConfirmDelete] = useState(false)

  const save = async () => {
    setBusy(true); setError(null)
    try {
      const input: gcal.EventInput = {
        title: form.title.trim() || 'Untitled',
        start: combine(form.date, form.time),
        repeat: form.canRepeat ? form.repeat : 'none',
        repeatUntil: form.until,
      }
      await gcal.updateEvent(calId, event.id, input)
      onChanged(); onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally { setBusy(false) }
  }

  const remove = async (which: 'instance' | 'series') => {
    setBusy(true); setError(null)
    try {
      await gcal.deleteEvent(calId, which === 'series' ? (event.recurringEventId ?? event.id) : event.id)
      onChanged(); onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally { setBusy(false) }
  }

  return (
    <Modal onClose={onClose} narrow>
      <h2><Icon name="calendarClock" size={15} /> Edit event</h2>
      <EventForm value={form} onChange={setForm} />
      {error && <div className="error-text">{error}</div>}
      <div className="modal-actions split">
        <div>
          {!confirmDelete && (
            <button className="btn btn-delete" onClick={() => setConfirmDelete(true)} disabled={busy}>Delete</button>
          )}
          {confirmDelete && !isRecurringInstance && (
            <button className="btn btn-delete" onClick={() => remove('series')} disabled={busy}>Confirm delete</button>
          )}
          {confirmDelete && isRecurringInstance && (
            <span className="flow-row">
              <button className="btn btn-delete" onClick={() => remove('instance')} disabled={busy}>This event</button>
              <button className="btn btn-delete" onClick={() => remove('series')} disabled={busy}>Whole series</button>
            </span>
          )}
        </div>
        <div className="modal-actions">
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" onClick={save} disabled={busy || !form.title.trim()}>
            {busy ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </Modal>
  )
}

// ---- Weekly agenda view ----

export function CalendarView() {
  const store = useStore()
  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()))
  const [events, setEvents] = useState<gcal.AgendaEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [connecting, setConnecting] = useState(false)
  const [editing, setEditing] = useState<gcal.GCalEvent | null>(null)
  const [calId, setCalId] = useState<string | null>(store.craftCalendarId)

  const connected = gcal.isConnected()
  const weekEnd = useMemo(() => { const d = new Date(weekStart); d.setDate(d.getDate() + 7); return d }, [weekStart])

  const load = useCallback(async () => {
    if (!gcal.isConnected()) return
    setLoading(true); setError(null)
    try {
      const id = await gcal.ensureCalendar(store.craftCalendarId)
      if (id !== store.craftCalendarId) store.setCraftCalendarId(id)
      setCalId(id)
      setEvents(await gcal.listAgenda(id, weekStart, weekEnd))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally { setLoading(false) }
  }, [store, weekStart, weekEnd])

  useEffect(() => { void load() }, [load])

  const connect = async () => {
    setConnecting(true); setError(null)
    try {
      await gcal.connect()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally { setConnecting(false) }
  }

  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart); d.setDate(d.getDate() + i); return d
  })
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const eventsForDay = (d: Date) => events
    .filter(a => sameDay(gcal.eventStart(a.event), d))
    .sort((a, b) => gcal.eventStart(a.event).getTime() - gcal.eventStart(b.event).getTime())

  const weekLabel = `${weekStart.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })} – ${
    new Date(weekEnd.getTime() - 1).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}`

  return (
    <>
      <PageHeadSticky>
        <div className="page-header">
          <h1>Calendar</h1>
          <span className="spacer" />
          {connected && (
            <>
              <button className="btn" onClick={() => setWeekStart(mondayOf(new Date()))}>Today</button>
              <button className="btn" onClick={() => setWeekStart(d => { const x = new Date(d); x.setDate(x.getDate() - 7); return x })}>‹</button>
              <button className="btn" onClick={() => setWeekStart(d => { const x = new Date(d); x.setDate(x.getDate() + 7); return x })}>›</button>
              <button className="btn" onClick={() => void load()} title="Refresh"><Icon name="refresh" size={12} /></button>
            </>
          )}
        </div>
        {connected && <div className="cal-week-label">{weekLabel}{loading && ' · loading…'}</div>}
      </PageHeadSticky>

      <div className="list-scroll">
        {!connected ? (
          <div className="cal-empty">
            <p>Connect a Google account to push tasks to a dedicated <b>Craft Tasks</b> calendar and manage those events here.</p>
            <button className="btn primary" onClick={connect} disabled={connecting || !gcal.getGoogleClientId()}>
              {connecting ? 'Connecting…' : 'Connect Google Calendar'}
            </button>
            {!gcal.getGoogleClientId() && (
              <div className="hint-text">Add your Google OAuth Client ID in Settings → Calendar first.</div>
            )}
            {error && <div className="error-text">{error}</div>}
          </div>
        ) : (
          <>
            {error && <div className="error-text" style={{ margin: '8px 16px' }}>{error}</div>}
            <div className="agenda">
              {days.map(d => {
                const list = eventsForDay(d)
                const isToday = sameDay(d, today)
                return (
                  <div key={d.toISOString()} className={`agenda-day${isToday ? ' today' : ''}`}>
                    <div className="agenda-date">
                      <span className="dow">{d.toLocaleDateString(undefined, { weekday: 'short' })}</span>
                      <span className="dnum">{d.getDate()}</span>
                    </div>
                    <div className="agenda-events">
                      {list.map(({ event: e, editable, calendarName, color }) => (
                        <button key={e.id}
                                className={`agenda-event${editable ? '' : ' readonly'}`}
                                onClick={editable ? () => setEditing(e) : undefined}
                                title={editable ? undefined : calendarName}>
                          <span className="ae-dot" style={color ? { background: color } : undefined} />
                          <span className="ae-time">{gcal.isAllDay(e) ? 'all day' : fmtTime(gcal.eventStart(e))}</span>
                          <span className="ae-title">{e.summary || '(no title)'}</span>
                          {(e.recurringEventId || e.recurrence) && <span className="ae-rep"><Icon name="refresh" size={9} /></span>}
                        </button>
                      ))}
                    </div>
                  </div>
                )
              })}
            </div>
          </>
        )}
      </div>

      {editing && calId && (
        <EventEditModal
          calId={calId}
          event={editing}
          onClose={() => setEditing(null)}
          onChanged={load}
        />
      )}
    </>
  )
}
