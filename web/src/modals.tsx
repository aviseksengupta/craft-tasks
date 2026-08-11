import { useEffect, useMemo, useRef, useState } from 'react'
import {
  CraftTask, TaskState, ymd, dayOf, markdownParts,
} from './types'
import { useStore, DocumentSummary } from './store'
import * as craft from './craft'
import { getGistToken, setGistToken } from './gist'
import { Modal, Icon, DateChip, StateCycle, MenuChip, MenuItem } from './ui'

// ---- Add Task ----

export function AddTaskModal({ onClose }: { onClose: () => void }) {
  const store = useStore()
  const [rawText, setRawText] = useState('')
  const [tags, setTags] = useState<string[]>([])
  const [scheduleDate, setScheduleDate] = useState<Date | null>(null)
  const [deadlineDate, setDeadlineDate] = useState<Date | null>(null)
  const [selectedDoc, setSelectedDoc] = useState<DocumentSummary | null>(null)
  const [mentionQuery, setMentionQuery] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  useEffect(() => inputRef.current?.focus(), [])

  const mentionMatches = useMemo(() => {
    if (mentionQuery === null) return []
    const pool = store.documents.filter(d => d.id !== 'inbox')
    const q = mentionQuery.toLowerCase()
    return (q === '' ? pool : pool.filter(d => d.title.toLowerCase().includes(q))).slice(0, 6)
  }, [mentionQuery, store.documents])

  // A completed #tag (ended with a space) becomes a chip; a trailing @query
  // opens the live document picker. Trailing in-progress tokens stay put.
  const processInput = (value: string) => {
    const m = value.match(/[#@][\w/\-]*$/)
    const liveToken = m?.[0] ?? null
    let committed = liveToken ? value.slice(0, value.length - liveToken.length) : value
    setMentionQuery(liveToken?.startsWith('@') ? liveToken.slice(1) : null)
    const found = [...committed.matchAll(/#([\w/\-]+)/g)].map(x => x[1].toLowerCase())
    if (found.length) {
      setTags(prev => [...prev, ...found.filter(t => !prev.includes(t))])
      committed = committed.replace(/#[\w/\-]+/g, '').replace(/[ \t]{2,}/g, ' ')
    }
    setRawText(committed + (liveToken ?? ''))
  }

  const chooseMention = (doc: DocumentSummary) => {
    setRawText(t => t.replace(/@[\w/\-]*$/, '').trim())
    setSelectedDoc(doc)
    setMentionQuery(null)
    inputRef.current?.focus()
  }

  const save = () => {
    const title = rawText.trim()
    if (!title) return
    store.createTask(title, tags,
      scheduleDate ? ymd(scheduleDate) : null,
      deadlineDate ? ymd(deadlineDate) : null,
      selectedDoc?.id ?? null)
    onClose()
  }

  return (
    <Modal onClose={onClose}>
      <h2><Icon name="plusCircle" size={15} /> New Task</h2>
      <div>
        <div className="form-label">TITLE</div>
        <input ref={inputRef} type="text" placeholder="What needs doing? Try #tag or @document"
               value={rawText}
               onChange={e => processInput(e.target.value)}
               onKeyDown={e => {
                 if (e.key === 'Enter') {
                   if (mentionMatches.length > 0) chooseMention(mentionMatches[0])
                   else save()
                 }
               }} />
        {mentionMatches.length > 0 && (
          <div className="mention-list">
            {mentionMatches.map(doc => (
              <button key={doc.id} className="mention-item" onClick={() => chooseMention(doc)}>
                <Icon name="doc" size={10} /> {doc.title}
              </button>
            ))}
          </div>
        )}
      </div>
      <div className="dest-row">
        <Icon name={selectedDoc ? 'doc' : 'tray'} size={10} />
        {selectedDoc?.title ?? 'Inbox'}
        {selectedDoc && <button className="icon-btn" onClick={() => setSelectedDoc(null)}><Icon name="xmark" size={8} /></button>}
      </div>
      {tags.length > 0 && (
        <div>
          <div className="form-label">TAGS</div>
          <div className="flow-row">
            {tags.map(tag => (
              <button key={tag} className="tag-chip-lg" onClick={() => setTags(ts => ts.filter(t => t !== tag))}>
                #{tag} <span className="x"><Icon name="xmark" size={9} weight={2.5} /></span>
              </button>
            ))}
          </div>
        </div>
      )}
      <div className="flow-row" style={{ gap: 14 }}>
        <DateChip title="Scheduled" icon="calendar" date={scheduleDate} onChange={setScheduleDate} />
        <DateChip title="Deadline" icon="flag" date={deadlineDate} onChange={setDeadlineDate} />
      </div>
      <div className="modal-actions">
        <button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={save} disabled={rawText.trim() === ''}>Add Task</button>
      </div>
    </Modal>
  )
}

// ---- Edit Task ----

export function EditTaskModal({ task, onClose }: { task: CraftTask; onClose: () => void }) {
  const store = useStore()
  const parts = useMemo(() => markdownParts(task.markdown), [task.markdown])
  const [body, setBody] = useState(parts.body)
  const [state, setState] = useState<TaskState>(task.state)
  const [scheduleDate, setScheduleDate] = useState<Date | null>(dayOf(task.scheduleDate))
  const [deadlineDate, setDeadlineDate] = useState<Date | null>(dayOf(task.deadlineDate))
  const [newTag, setNewTag] = useState('')
  const [selectedDocumentId, setSelectedDocumentId] = useState<string | null>(
    task.locationType === 'inbox' ? null : task.documentId)
  const [description, setDescription] = useState('')
  const [originalDescription, setOriginalDescription] = useState('')
  const [descriptionBlockIds, setDescriptionBlockIds] = useState<string[]>([])
  const [loadingDescription, setLoadingDescription] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    craft.fetchDescription(task.id).then(d => {
      if (!alive) return
      setDescription(d.text); setOriginalDescription(d.text); setDescriptionBlockIds(d.blockIds)
      setLoadingDescription(false)
    }).catch(e => {
      if (!alive) return
      setSaveError(`Couldn't load description: ${e instanceof Error ? e.message : e}`)
      setLoadingDescription(false)
    })
    return () => { alive = false }
  }, [task.id])

  const currentTags = useMemo(() => [...body.matchAll(/#([\w/\-]+)/g)].map(m => m[1]), [body])
  const addTag = () => {
    const t = newTag.trim().replace(/#/g, '')
    if (!t) return
    setBody(b => b.trim() + ` #${t}`)
    setNewTag('')
  }
  const removeTag = (tag: string) => {
    setBody(b => b.replace(new RegExp(`\\s*#${tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`), ''))
  }

  const cycle = () => setState(s => s === 'todo' ? 'done' : s === 'done' ? 'canceled' : 'todo')

  const docLabel = selectedDocumentId
    ? store.documents.find(d => d.id === selectedDocumentId)?.title ?? 'Document'
    : 'Inbox'

  const save = async () => {
    const originalId = task.locationType === 'inbox' ? null : task.documentId
    const destination = selectedDocumentId === originalId
      ? { kind: 'unchanged' as const }
      : selectedDocumentId ? { kind: 'document' as const, id: selectedDocumentId } : { kind: 'inbox' as const }
    store.applyEdit(task, body.trim(), state,
      scheduleDate ? ymd(scheduleDate) : null,
      deadlineDate ? ymd(deadlineDate) : null,
      destination)
    if (description !== originalDescription) {
      setSaving(true); setSaveError(null)
      try {
        await craft.pushDescription(task.id, descriptionBlockIds, description)
      } catch (e) {
        setSaving(false)
        setSaveError(`Task saved, but description failed to sync: ${e instanceof Error ? e.message : e}. Try again.`)
        return
      }
      setSaving(false)
    }
    onClose()
  }

  return (
    <Modal onClose={onClose}>
      <h2 style={{ justifyContent: 'space-between' }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <StateCycle state={state} onCycle={cycle} />
          Edit Task
        </span>
        <MenuChip label={
          <button className="dest-row" style={{ fontWeight: 400, fontSize: 11, color: 'var(--text-faint)' }}
                  title="Move this task to a different document">
            <Icon name={selectedDocumentId ? 'doc' : 'tray'} size={9} /> {docLabel}
          </button>
        }>
          {close => (<>
            <MenuItem label="Inbox" checked={selectedDocumentId === null}
                      onClick={() => { setSelectedDocumentId(null); close() }} />
            <div className="menu-sep" />
            {store.documents.filter(d => d.id !== 'inbox').map(doc => (
              <MenuItem key={doc.id} label={doc.title} checked={selectedDocumentId === doc.id}
                        onClick={() => { setSelectedDocumentId(doc.id); close() }} />
            ))}
          </>)}
        </MenuChip>
      </h2>
      <div>
        <div className="form-label">TASK</div>
        <textarea value={body} onChange={e => setBody(e.target.value)} rows={3} />
      </div>
      <div>
        <div className="form-label">TAGS</div>
        <div className="flow-row">
          {currentTags.map(tag => (
            <button key={tag} className="tag-chip-lg" onClick={() => removeTag(tag)} title={`Remove #${tag}`}>
              #{tag} <span className="x"><Icon name="xmark" size={9} weight={2.5} /></span>
            </button>
          ))}
          <span className="tag-add">
            <span style={{ color: 'var(--text-faint)', fontSize: 12 }}>#</span>
            <input value={newTag} onChange={e => setNewTag(e.target.value)}
                   onKeyDown={e => { if (e.key === 'Enter') addTag() }} placeholder="add tag" />
          </span>
        </div>
      </div>
      <div>
        <div className="form-label">DESCRIPTION {loadingDescription && <span>…</span>}</div>
        <textarea value={description} onChange={e => setDescription(e.target.value)} rows={3}
                  disabled={loadingDescription} style={{ opacity: loadingDescription ? 0.4 : 1, fontSize: 12 }} />
      </div>
      <div className="flow-row" style={{ gap: 14 }}>
        <DateChip title="Scheduled" icon="calendar" date={scheduleDate} onChange={setScheduleDate} />
        <DateChip title="Deadline" icon="flag" date={deadlineDate} onChange={setDeadlineDate} />
      </div>
      {saveError && <div className="error-text">{saveError}</div>}
      <div className="modal-actions">
        <button className="btn" onClick={onClose} disabled={saving}>Cancel</button>
        <button className="btn primary" onClick={save} disabled={body.trim() === '' || saving}>
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
    </Modal>
  )
}

// ---- Settings (Craft URL + Gist token) ----

/** Unregisters the service worker and clears its caches before reloading —
 * a plain reload can still be served the old cached app shell by a
 * service worker that hasn't finished checking for an update yet. This
 * guarantees the next load is genuinely fresh, which matters because
 * there's no easy manual "clear cache" gesture for an installed iOS PWA. */
async function forceRefresh() {
  try {
    const regs = await navigator.serviceWorker?.getRegistrations?.() ?? []
    await Promise.all(regs.map(r => r.unregister()))
    const cacheNames = await caches?.keys?.() ?? []
    await Promise.all(cacheNames.map(n => caches.delete(n)))
  } catch {
    // best-effort — still reload even if SW/cache APIs are unavailable
  }
  window.location.reload()
}

export function SettingsModal({ onClose, forced, heightOffset, onAdjustHeightOffset }: {
  onClose: () => void; forced?: boolean
  heightOffset?: number; onAdjustHeightOffset?: (delta: number) => void
}) {
  const [url, setUrl] = useState(craft.getApiBase() ?? '')
  const [token, setToken] = useState(getGistToken() ?? '')
  const [refreshing, setRefreshing] = useState(false)

  const save = () => {
    const trimmed = url.trim()
    if (!trimmed) return
    craft.setApiBase(trimmed)
    setGistToken(token)
    setRefreshing(true)
    forceRefresh()
  }

  return (
    <Modal onClose={forced ? () => {} : onClose}>
      <h2><Icon name="gear" size={15} /> Settings</h2>
      <div>
        <div className="form-label">CRAFT LINK API URL</div>
        <input type="text" value={url} onChange={e => setUrl(e.target.value)}
               placeholder="https://connect.craft.do/links/…/api/v1" />
        <div className="hint-text" style={{ marginTop: 6 }}>
          The API base of a Craft share link with task access, e.g.
          https://connect.craft.do/links/XXXX/api/v1. Stored only in this browser.
        </div>
      </div>
      <div>
        <div className="form-label">GITHUB TOKEN (OPTIONAL — SYNCS VIEWS &amp; DASHBOARDS)</div>
        <input type="password" value={token} onChange={e => setToken(e.target.value)}
               placeholder="github_pat_… with Gist read/write" />
        <div className="hint-text" style={{ marginTop: 6 }}>
          A GitHub personal access token with the <b>gist</b> scope. Saved views, dashboards and
          other configs sync to a private Gist so they follow you across devices. Leave empty to
          keep configs in this browser only.
        </div>
      </div>
      {onAdjustHeightOffset && (
        <div>
          <div className="form-label">HOME SCREEN FIT (IOS STANDALONE ONLY)</div>
          <div className="flow-row" style={{ gap: 10 }}>
            <button className="btn" onClick={() => onAdjustHeightOffset(-5)}>− 5px</button>
            <span style={{ fontSize: 13, minWidth: 60, textAlign: 'center' }}>{heightOffset ?? 0}px</span>
            <button className="btn" onClick={() => onAdjustHeightOffset(5)}>+ 5px</button>
            {heightOffset !== 0 && (
              <button className="btn" onClick={() => onAdjustHeightOffset(-(heightOffset ?? 0))}>Reset</button>
            )}
          </div>
          <div className="hint-text" style={{ marginTop: 6 }}>
            If there's a gap below the bottom bar when this is added to your home screen, nudge
            this up a few px at a time until the gap disappears — applies and saves immediately,
            no need to hit Save below for this one.
          </div>
        </div>
      )}
      <div className="hint-text">
        Save clears the cached app and reloads — the reliable way to force this installed PWA
        onto the latest version, since there's no manual "clear cache" gesture on iOS.
      </div>
      <div className="modal-actions">
        {!forced && <button className="btn" onClick={onClose} disabled={refreshing}>Cancel</button>}
        <button className="btn primary" onClick={save} disabled={url.trim() === '' || refreshing}>
          {refreshing ? 'Refreshing…' : 'Save'}
        </button>
      </div>
    </Modal>
  )
}

// ---- Small name-prompt modal (save view / rename / new dashboard name) ----

export function NamePrompt({ title, initial = '', cta = 'Save', onClose, onSave }: {
  title: string; initial?: string; cta?: string; onClose: () => void; onSave: (name: string) => void
}) {
  const [name, setName] = useState(initial)
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => ref.current?.focus(), [])
  const save = () => { if (name.trim()) { onSave(name.trim()); onClose() } }
  return (
    <Modal onClose={onClose} narrow>
      <h2>{title}</h2>
      <input ref={ref} type="text" value={name} onChange={e => setName(e.target.value)}
             onKeyDown={e => { if (e.key === 'Enter') save() }} placeholder="Name" />
      <div className="modal-actions">
        <button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" onClick={save} disabled={name.trim() === ''}>{cta}</button>
      </div>
    </Modal>
  )
}

// ---- View-picker modals (new dashboard / add widgets) ----

export function ViewPicker({ title, cta, views, requireName, onClose, onDone }: {
  title: string; cta: string; views: { id: string; name: string }[]
  requireName?: boolean; onClose: () => void
  onDone: (name: string, selected: string[]) => void
}) {
  const [name, setName] = useState('')
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const toggle = (id: string) => setSelected(s => {
    const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n
  })
  const disabled = selected.size === 0 || (requireName && name.trim() === '')
  return (
    <Modal onClose={onClose} narrow>
      <h2>{title}</h2>
      {requireName && <input type="text" value={name} onChange={e => setName(e.target.value)} placeholder="Dashboard name" />}
      <div>
        <div className="form-label">COMBINE VIEWS</div>
        {views.length === 0 && <div className="hint-text">All your saved views are already on this dashboard.</div>}
        {views.map(v => (
          <button key={v.id} className="check-row" onClick={() => toggle(v.id)}>
            <span className={`box${selected.has(v.id) ? ' on' : ''}`}>
              <Icon name={selected.has(v.id) ? 'checkCircle' : 'plusCircle'} size={13} />
            </span>
            {v.name}
          </button>
        ))}
      </div>
      <div className="modal-actions">
        <button className="btn" onClick={onClose}>Cancel</button>
        <button className="btn primary" disabled={disabled}
                onClick={() => { onDone(name.trim(), [...selected]); onClose() }}>{cta}</button>
      </div>
    </Modal>
  )
}

// ---- Sidebar item visibility settings ----

export function SidebarSettingsModal({ navDefs, onClose }: {
  navDefs: { id: string; icon: string; label: string }[]; onClose: () => void
}) {
  const store = useStore()
  return (
    <Modal onClose={onClose}>
      <h2>Sidebar Items</h2>
      <div className="hint-text">Choose how each item behaves in the sidebar.</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {navDefs.map(def => {
          const v = store.itemVisibility[def.id] ?? 'Always shown'
          return (
            <div key={def.id} className="vis-row">
              <span className="v-label"><Icon name={def.icon} size={11} /> {def.label}</span>
              <span className="seg">
                {(['Always shown', 'Hidden', 'Invisible'] as const).map(opt => (
                  <button key={opt} className={v === opt ? 'on' : ''}
                          onClick={() => store.setItemVisibility(def.id, opt)}>{opt}</button>
                ))}
              </span>
            </div>
          )
        })}
      </div>
      <div className="modal-actions">
        <button className="btn primary" onClick={onClose}>Done</button>
      </div>
    </Modal>
  )
}
