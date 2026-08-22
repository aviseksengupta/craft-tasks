import { ReactNode, useEffect, useRef, useState, MouseEvent as ReactMouseEvent } from 'react'

// ---- Icons: minimal inline SVG strokes in the SF Symbols spirit ----
const paths: Record<string, ReactNode> = {
  house: <path d="M2 8.5 8 3l6 5.5M3.5 7.5V13h9V7.5" />,
  trayFull: <><path d="M2 9h3.5l1 1.5h3L10.5 9H14v4H2z" fill="currentColor" stroke="none" /><path d="M2 9h3.5l1 1.5h3L10.5 9H14M2 9v4h12V9M4 6.5h8M5 4h6" /></>,
  tray: <path d="M2 9h3.5l1 1.5h3L10.5 9H14M2 9v4h12V9M2 9l1.5-5h9L14 9" />,
  sun: <><circle cx="8" cy="8" r="3" /><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4" /></>,
  calendarClock: <><rect x="2" y="3" width="12" height="11" rx="2" /><path d="M2 6.5h12M5 1.5v3M11 1.5v3M8 9v2l1.5 1" /></>,
  calendar: <><rect x="2" y="3" width="12" height="11" rx="2" /><path d="M2 6.5h12M5 1.5v3M11 1.5v3" /></>,
  doc: <><path d="M4 1.5h5.5L13 5v9.5H4z" /><path d="M9.5 1.5V5H13M6 8h4M6 10.5h4" /></>,
  listRect: <><rect x="1.5" y="3" width="13" height="10" rx="2" /><path d="M4.5 6h1M7 6h4.5M4.5 8h1M7 8h4.5M4.5 10h1M7 10h4.5" /></>,
  grid: <><rect x="2" y="2" width="5" height="5" rx="1" /><rect x="9" y="2" width="5" height="5" rx="1" /><rect x="2" y="9" width="5" height="5" rx="1" /><rect x="9" y="9" width="5" height="5" rx="1" /></>,
  stack: <path d="M8 2 14 5 8 8 2 5zM2 8l6 3 6-3M2 11l6 3 6-3" />,
  filterLines: <path d="M3 5h10M5 8h6M6.5 11h3" />,
  plus: <path d="M8 3v10M3 8h10" />,
  plusCircle: <><circle cx="8" cy="8" r="6.5" /><path d="M8 5v6M5 8h6" /></>,
  search: <><circle cx="7" cy="7" r="4.5" /><path d="m10.5 10.5 3 3" /></>,
  gear: <><circle cx="8" cy="8" r="2.2" /><path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M12.4 3.6 11 5M5 11l-1.4 1.4" /></>,
  chevron: <path d="m6 3 5 5-5 5" />,
  check: <path d="m3 8.5 3.5 3.5L13 4.5" />,
  xmark: <path d="m4 4 8 8M12 4l-8 8" />,
  flag: <path d="M4 14V2.5M4 2.5c3-1.5 5 1.5 8 0V9c-3 1.5-5-1.5-8 0" />,
  pencil: <path d="m10 3 3 3-7.5 7.5L2 14l.5-3.5z" />,
  pin: <path d="M9.5 2 14 6.5l-3 1-2 4-1.5-1.5L3 14.5 1.5 13l4.5-4.5L4.5 7l4-2z" />,
  refresh: <path d="M13 8a5 5 0 1 1-1.5-3.5M11.5 1.5v3h3" />,
  gripLines: <path d="M3 6h10M3 10h10" />,
  eye: <><path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z" /><circle cx="8" cy="8" r="2" /></>,
  eyeSlash: <><path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z" /><circle cx="8" cy="8" r="2" /><path d="m2.5 2.5 11 11" /></>,
  resize: <path d="M13 3 3 13M13 3h-4M13 3v4M3 13h4M3 13V9" />,
  arrowUpRight: <path d="M4 12 12 4M6 4h6v6" />,
  menuBars: <path d="M2.5 4.5h11M2.5 8h11M2.5 11.5h11" />,
  checkCircle: <><circle cx="8" cy="8" r="6.5" /><path d="m5 8.3 2 2 4-4.3" /></>,
  bolt: <path d="M8.5 1.5 3 9h4l-.5 5.5L13 7H9z" fill="currentColor" stroke="none" />,
  clock: <><circle cx="8" cy="8" r="6.5" /><path d="M8 4.5V8l3 1.8" /></>,
}

export function Icon({ name, size = 14, weight = 1.4 }: { name: string; size?: number; weight?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none"
         stroke="currentColor" strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round"
         style={{ flexShrink: 0 }}>
      {paths[name] ?? <circle cx="8" cy="8" r="5" />}
    </svg>
  )
}

export function Chip({ text, icon, active, onClick, title }: {
  text: string; icon?: string; active?: boolean; onClick?: () => void; title?: string
}) {
  return (
    <button className={`chip${active ? ' active' : ''}`} onClick={onClick} title={title}>
      {icon && <span className="chip-icon"><Icon name={icon} size={10} /></span>}
      {text}
    </button>
  )
}

/** Chip that opens a dropdown menu; closes on outside click. Positioned
 * fixed from the trigger's measured rect rather than absolute-within-flow,
 * so it isn't clipped by a scrolling ancestor (e.g. the horizontally
 * scrollable mobile filter bar) and always lands in the right place
 * regardless of that ancestor's own scroll offset. */
export function MenuChip({ label, children }: {
  label: ReactNode; children: (close: () => void) => ReactNode
}) {
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null)
  const ref = useRef<HTMLSpanElement>(null)
  const open = pos !== null
  useEffect(() => {
    if (!open) return
    const close = () => setPos(null)
    document.addEventListener('mousedown', close)
    window.addEventListener('resize', close)
    window.addEventListener('scroll', close, true)
    return () => {
      document.removeEventListener('mousedown', close)
      window.removeEventListener('resize', close)
      window.removeEventListener('scroll', close, true)
    }
  }, [open])
  const toggle = (e: ReactMouseEvent) => {
    e.stopPropagation()
    if (open) { setPos(null); return }
    const r = ref.current!.getBoundingClientRect()
    setPos({ top: r.bottom + 4, left: Math.min(r.left, window.innerWidth - 180) })
  }
  return (
    <div className="menu-wrap">
      <span ref={ref} onClick={toggle}>{label}</span>
      {open && (
        <div className="menu" style={{ top: pos.top, left: pos.left }} onMouseDown={e => e.stopPropagation()}>
          {children(() => setPos(null))}
        </div>
      )}
    </div>
  )
}

export function MenuItem({ label, checked, minus, danger, onClick }: {
  label: string; checked?: boolean; minus?: boolean; danger?: boolean; onClick: () => void
}) {
  return (
    <button className={`menu-item${danger ? ' danger' : ''}`} onClick={onClick}>
      {label}
      {checked && <span className="check"><Icon name="check" size={10} /></span>}
      {minus && <span className="check">−</span>}
    </button>
  )
}

/** Floating context menu opened at pointer position (right-click / long-press "…"). */
export function useContextMenu() {
  const [state, setState] = useState<{ x: number; y: number; items: ContextItem[] } | null>(null)
  const openAt = (e: { preventDefault(): void; clientX: number; clientY: number }, items: ContextItem[]) => {
    e.preventDefault()
    setState({ x: e.clientX, y: e.clientY, items })
  }
  const menu = state ? <ContextMenuOverlay state={state} close={() => setState(null)} /> : null
  return { openAt, menu }
}

export interface ContextItem { label: string; danger?: boolean; action: () => void }

function ContextMenuOverlay({ state, close }: {
  state: { x: number; y: number; items: ContextItem[] }; close: () => void
}) {
  const style: React.CSSProperties = {
    position: 'fixed',
    left: Math.min(state.x, window.innerWidth - 180),
    top: Math.min(state.y, window.innerHeight - state.items.length * 34 - 16),
    zIndex: 200,
  }
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 199 }} onClick={close} onContextMenu={e => { e.preventDefault(); close() }}>
      <div className="menu" style={style}>
        {state.items.map((it, i) => (
          <button key={i} className={`menu-item${it.danger ? ' danger' : ''}`}
                  onClick={e => { e.stopPropagation(); it.action(); close() }}>
            {it.label}
          </button>
        ))}
      </div>
    </div>
  )
}

/** Wraps a view's header (+ filter bar, where present) so it can stay
 * pinned via CSS position:sticky while the content below it scrolls past
 * — a plain div on desktop (no effect there, the sidebar shell handles
 * scrolling its own way), sticky only under the mobile breakpoint. See
 * the .page-head-sticky rule in styles.css for why. */
export function PageHeadSticky({ children }: { children: ReactNode }) {
  return <div className="page-head-sticky">{children}</div>
}

export function Modal({ children, onClose, narrow }: {
  children: ReactNode; onClose: () => void; narrow?: boolean
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="modal-backdrop" onMouseDown={e => { if (e.target === e.currentTarget) onClose() }}>
      <div className={`modal${narrow ? ' narrow' : ''}`}>{children}</div>
    </div>
  )
}

// ---- Calendar ----

function sameDay(a: Date, b: Date) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

export function MiniCalendar({ date, onChange }: {
  date: Date | null; onChange: (d: Date | null) => void
}) {
  const [month, setMonth] = useState(() => {
    const d = date ?? new Date()
    return new Date(d.getFullYear(), d.getMonth(), 1)
  })
  const today = new Date()
  const first = new Date(month.getFullYear(), month.getMonth(), 1)
  const leading = first.getDay() // Sunday-first
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
  const cells: (Date | null)[] = [
    ...Array<null>(leading).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => new Date(month.getFullYear(), month.getMonth(), i + 1)),
  ]
  while (cells.length % 7 !== 0) cells.push(null)
  const monthTitle = month.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
  const shift = (delta: number) => setMonth(m => new Date(m.getFullYear(), m.getMonth() + delta, 1))
  return (
    <div className="calendar-pop" onMouseDown={e => e.stopPropagation()}>
      <div className="cal-head">
        <button className="cal-step" onClick={() => shift(-1)}>‹</button>
        <span className="m-title">{monthTitle}</span>
        <button className="cal-step" onClick={() => shift(1)}>›</button>
      </div>
      <div className="cal-week">
        {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((s, i) => <span key={i}>{s}</span>)}
      </div>
      <div className="cal-grid">
        {cells.map((d, i) => d ? (
          <button key={i}
                  className={`cal-day${date && sameDay(d, date) ? ' selected' : ''}${sameDay(d, today) ? ' today' : ''}`}
                  onClick={() => onChange(d)}>
            {d.getDate()}
          </button>
        ) : <span key={i} />)}
      </div>
      <div className="cal-quick">
        <button className="qbtn" onClick={() => { const d = new Date(); d.setHours(0,0,0,0); onChange(d); setMonth(new Date(d.getFullYear(), d.getMonth(), 1)) }}>Today</button>
        <button className="qbtn" onClick={() => { const d = new Date(); d.setHours(0,0,0,0); d.setDate(d.getDate()+1); onChange(d); setMonth(new Date(d.getFullYear(), d.getMonth(), 1)) }}>Tomorrow</button>
        {date && <button className="clear" onClick={() => onChange(null)}>Clear</button>}
      </div>
    </div>
  )
}

export function DateChip({ title, icon, date, onChange }: {
  title: string; icon: string; date: Date | null; onChange: (d: Date | null) => void
}) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDown)
    return () => document.removeEventListener('mousedown', onDown)
  }, [open])
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1)
  const display = !date ? title
    : sameDay(date, today) ? 'Today'
    : sameDay(date, tomorrow) ? 'Tomorrow'
    : date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
  return (
    <div className={`date-chip${date ? ' set' : ''}`} ref={ref}>
      <button className="main-btn" onClick={() => setOpen(o => !o)}>
        <Icon name={date ? icon : 'plus'} size={11} />
        <span>
          {date && <div className="sub">{title.toUpperCase()}</div>}
          <div className="val">{display}</div>
        </span>
      </button>
      {date && <button className="clear-btn" onClick={() => onChange(null)} title={`Clear ${title.toLowerCase()}`}>×</button>}
      {open && <MiniCalendar date={date} onChange={d => { onChange(d); setOpen(false) }} />}
    </div>
  )
}

export function StateCycle({ state, onCycle, size = 24, ringColor }: {
  state: 'todo' | 'done' | 'canceled'; onCycle: () => void; size?: number; ringColor?: string | null
}) {
  return (
    <button className={`state-cycle ${state}`}
            style={{ width: size, height: size, ...(state === 'todo' && ringColor ? { borderColor: ringColor, borderWidth: '2px' } : {}) }}
            onClick={onCycle} title="Click to cycle: open → done → canceled">
      {state === 'done' && <Icon name="check" size={12} weight={2.5} />}
      {state === 'canceled' && <Icon name="xmark" size={10} weight={2.5} />}
    </button>
  )
}
