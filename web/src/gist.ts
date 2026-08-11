// Config sync to a private GitHub Gist. The PAT (classic, `gist` scope, or
// fine-grained with Gists read/write) lives in localStorage; the gist id is
// discovered by filename or created on first save.

import { ConfigFile } from './types'

const GIST_FILENAME = 'craft-tasks-config.json'

export function getGistToken(): string | null { return localStorage.getItem('gistToken') }
export function setGistToken(t: string) {
  if (t.trim()) localStorage.setItem('gistToken', t.trim())
  else localStorage.removeItem('gistToken')
}
export function getGistId(): string | null { return localStorage.getItem('gistId') }
function setGistId(id: string) { localStorage.setItem('gistId', id) }

function headers(token: string) {
  return {
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'Content-Type': 'application/json',
  }
}

async function findGist(token: string): Promise<string | null> {
  const resp = await fetch('https://api.github.com/gists?per_page=100', { headers: headers(token) })
  if (!resp.ok) throw new Error(`GitHub API ${resp.status}`)
  const gists = await resp.json() as { id: string; files: Record<string, unknown> }[]
  return gists.find(g => GIST_FILENAME in g.files)?.id ?? null
}

/** Load config from the gist, resolving the gist id if unknown. Returns null when no gist exists yet. */
export async function loadFromGist(): Promise<ConfigFile | null> {
  const token = getGistToken()
  if (!token) return null
  let id = getGistId()
  if (!id) {
    id = await findGist(token)
    if (!id) return null
    setGistId(id)
  }
  const resp = await fetch(`https://api.github.com/gists/${id}`, { headers: headers(token) })
  if (resp.status === 404) { localStorage.removeItem('gistId'); return null }
  if (!resp.ok) throw new Error(`GitHub API ${resp.status}`)
  const gist = await resp.json() as { files: Record<string, { content?: string; truncated?: boolean; raw_url?: string }> }
  const file = gist.files[GIST_FILENAME]
  if (!file) return null
  let content = file.content ?? ''
  if (file.truncated && file.raw_url) {
    content = await (await fetch(file.raw_url)).text()
  }
  try { return JSON.parse(content) as ConfigFile } catch { return null }
}

/** Save config to the gist, creating it (private) on first save. */
export async function saveToGist(config: ConfigFile): Promise<void> {
  const token = getGistToken()
  if (!token) return
  const body = { files: { [GIST_FILENAME]: { content: JSON.stringify(config, null, 2) } } }
  const id = getGistId() ?? await findGist(token)
  if (id) {
    setGistId(id)
    const resp = await fetch(`https://api.github.com/gists/${id}`, {
      method: 'PATCH', headers: headers(token), body: JSON.stringify(body),
    })
    if (resp.status === 404) { localStorage.removeItem('gistId'); return saveToGist(config) }
    if (!resp.ok) throw new Error(`GitHub API ${resp.status}`)
  } else {
    const resp = await fetch('https://api.github.com/gists', {
      method: 'POST', headers: headers(token),
      body: JSON.stringify({ description: 'Craft Tasks web config', public: false, ...body }),
    })
    if (!resp.ok) throw new Error(`GitHub API ${resp.status}`)
    const created = await resp.json() as { id: string }
    setGistId(created.id)
  }
}
