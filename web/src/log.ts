// Tiny append-only activity log for sync/push events, kept in localStorage
// (key `syncLog`). Deliberately small: only the last `MAX` lines are kept,
// trimmed on every write, so it never grows without bound and stays
// readable at a glance. The point is to answer "why aren't my changes
// syncing, and which task is to blame?" — so what's worth logging is
// queued edits/creates, push results, and rejections (with the offending
// task's title and id), not routine polls.

const KEY = 'syncLog'
const MAX = 120

function stamp(): string {
  const d = new Date()
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

function read(): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) ?? '[]')
    return Array.isArray(v) ? v as string[] : []
  } catch { return [] }
}

export function logLine(message: string): void {
  let lines = read()
  lines.push(`${stamp()}  ${message}`)
  if (lines.length > MAX) lines = lines.slice(lines.length - MAX)
  try { localStorage.setItem(KEY, JSON.stringify(lines)) } catch { /* quota — ignore */ }
}

/** The most recent `count` lines, oldest first. */
export function readLog(count = 50): string[] {
  return read().slice(-count)
}

export function clearLog(): void {
  localStorage.removeItem(KEY)
}

/** A short human label for a queued payload's markdown, for log lines —
 * strips the checkbox prefix, Craft wrapper tags, and collapses whitespace. */
export function logLabel(markdown: string | null | undefined): string {
  if (!markdown) return '(unknown task)'
  const s = markdown
    .replace(/<[^>]+>/g, '')
    .replace(/^\s*-\s*\[[ xX-]?\]\s*/, '')
    .replace(/\s+/g, ' ')
    .trim()
  return s.length > 60 ? s.slice(0, 60) + '…' : s
}
