import { useEffect, useMemo, useRef, useState } from 'react'
import {
  CraftTask, TaskState, ymd, dayOf, markdownParts,
} from './types'
import { useStore, DocumentSummary, buildBackup, applyBackup, defaultBackup, AppBackup } from './store'
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
  const [confirmingDelete, setConfirmingDelete] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)

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
  const deepLink = craft.craftDeepLink(task)

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

  const handleDelete = async () => {
    if (!confirmingDelete) { setConfirmingDelete(true); return }
    setDeleting(true); setDeleteError(null)
    try {
      await store.deleteTask(task)
      onClose()
    } catch (e) {
      setDeleting(false)
      setDeleteError(`Couldn't delete: ${e instanceof Error ? e.message : e}`)
    }
  }

  return (
    <Modal onClose={onClose}>
      <h2 style={{ justifyContent: 'space-between' }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <StateCycle state={state} onCycle={cycle} />
          Edit Task
        </span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {deepLink && (
          <a className="open-in-craft" href={deepLink} title="Open the source document in Craft">
            <Icon name="stack" size={12} weight={1.6} />
          </a>
        )}
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
        </span>
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
      {deleteError && <div className="error-text">{deleteError}</div>}
      <div className="modal-actions split">
        <button className="btn btn-delete" onClick={handleDelete} disabled={saving || deleting}>
          {deleting ? 'Deleting…' : confirmingDelete ? 'Confirm delete?' : 'Delete'}
        </button>
        <div className="modal-actions">
          <button className="btn" onClick={onClose} disabled={saving || deleting}>Cancel</button>
          <button className="btn primary" onClick={save} disabled={body.trim() === '' || saving || deleting}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
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

export function SettingsModal({ onClose, forced }: { onClose: () => void; forced?: boolean }) {
  const store = useStore()
  const [url, setUrl] = useState(craft.getApiBase() ?? '')
  const [token, setToken] = useState(getGistToken() ?? '')
  const [refreshing, setRefreshing] = useState(false)

  const save = () => {
    const trimmed = url.trim()
    if (!trimmed) return
    craft.setApiBase(trimmed)
    setGistToken(token)
    setRefreshing(true)
    craft.refreshSpaceId().finally(forceRefresh)
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
      <div>
        <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
          <input type="checkbox" checked={store.todayIncludesOverdue}
                 onChange={e => store.setTodayIncludesOverdue(e.target.checked)} />
          <span className="form-label" style={{ margin: 0 }}>TODAY INCLUDES OVERDUE</span>
        </label>
        <div className="hint-text" style={{ marginTop: 6 }}>
          When enabled, the Today view also shows overdue tasks. When disabled, Today shows only
          tasks due today.
        </div>
      </div>
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
      {!forced && <BackupRestoreSection />}
    </Modal>
  )
}

// ---- Backup & Restore: export the current config as JSON, or restore from
// a previously exported (or default) JSON. Lets you get back to the same
// state after redeploying the PWA or clearing browser storage. ----

function BackupRestoreSection() {
  const [json, setJson] = useState<string | null>(null)
  const [importText, setImportText] = useState('')
  const [status, setStatus] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const showExport = () => setJson(JSON.stringify(buildBackup(), null, 2))

  const download = () => {
    const data = json ?? JSON.stringify(buildBackup(), null, 2)
    const blob = new Blob([data], { type: 'application/json' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `craft-tasks-config-${new Date().toISOString().slice(0, 10)}.json`
    a.click()
    URL.revokeObjectURL(a.href)
  }

  const copy = async () => {
    await navigator.clipboard.writeText(json ?? JSON.stringify(buildBackup(), null, 2))
    setStatus('Copied to clipboard')
  }

  const restore = (text: string) => {
    try {
      const parsed = JSON.parse(text) as AppBackup
      if (!parsed || typeof parsed !== 'object' || !parsed.config) throw new Error('Missing "config" field')
      applyBackup(parsed)
      setStatus('Config restored — reloading…')
      forceRefresh()
    } catch (e) {
      setStatus(`Restore failed: ${e instanceof Error ? e.message : String(e)}`)
    }
  }

  const restoreDefault = () => {
    if (!window.confirm('Reset to the default configuration? This replaces your saved views, dashboards, and renamed documents.')) return
    restore(JSON.stringify(defaultBackup))
  }

  const onFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    file.text().then(restore)
    e.target.value = ''
  }

  return (
    <div style={{ marginTop: 20, paddingTop: 16, borderTop: '1px solid var(--border)' }}>
      <div className="form-label">BACKUP &amp; RESTORE</div>
      <div className="hint-text" style={{ marginTop: 6, marginBottom: 10 }}>
        Export your saved views, dashboards, pinned items and renamed documents as JSON — useful
        after redeploying the app or reinstalling the PWA, since this is otherwise only stored
        locally on this device.
      </div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <button className="btn" onClick={showExport}>Show config JSON</button>
        <button className="btn" onClick={download}>Download JSON</button>
        {json && <button className="btn" onClick={copy}>Copy</button>}
        <button className="btn" onClick={() => fileRef.current?.click()}>Import JSON…</button>
        <button className="btn" onClick={restoreDefault}>Reset to default</button>
      </div>
      <input ref={fileRef} type="file" accept="application/json" style={{ display: 'none' }} onChange={onFile} />
      {json && (
        <textarea readOnly value={json} rows={8}
                  style={{ marginTop: 10, width: '100%', fontFamily: 'monospace', fontSize: 12 }}
                  onFocus={e => e.target.select()} />
      )}
      <div style={{ marginTop: 10 }}>
        <div className="form-label">OR PASTE JSON TO RESTORE</div>
        <textarea value={importText} onChange={e => setImportText(e.target.value)} rows={4}
                  placeholder="Paste exported config JSON here"
                  style={{ width: '100%', fontFamily: 'monospace', fontSize: 12, marginTop: 6 }} />
        <button className="btn" style={{ marginTop: 6 }} disabled={importText.trim() === ''}
                onClick={() => restore(importText)}>Restore from pasted JSON</button>
      </div>
      {status && <div className="hint-text" style={{ marginTop: 8 }}>{status}</div>}
    </div>
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
