import { useEffect, useState } from 'react'
import { Section } from './types'
import { StoreProvider, useStore } from './store'
import { Sidebar } from './Sidebar'
import { BottomNav } from './BottomNav'
import { TaskListView } from './TaskList'
import { DocumentsView, ViewsPage, DashboardsPage } from './Cards'
import { DashboardView } from './DashboardView'
import { CalendarView } from './CalendarView'
import { SettingsModal, AddTaskModal, QuickOpenModal } from './modals'
import { Icon } from './ui'

function Root() {
  const store = useStore()
  const [section, setSection] = useState<Section>({ kind: 'home' })
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [showAddTask, setShowAddTask] = useState(false)
  const [showQuickOpen, setShowQuickOpen] = useState(false)
  const [booted, setBooted] = useState(false)

  // ---- keyboard shortcuts: ⌘F search · ⌘K quick-open · ⌘0 Home · ⌘1–⌘9 pinned ----
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || e.altKey || e.shiftKey) return
      const k = e.key.toLowerCase()
      if (k === 'f') {
        e.preventDefault()
        setSidebarOpen(true)
        const focusSearch = () => (document.getElementById('sidebarSearch') as HTMLInputElement | null)?.focus()
        focusSearch()               // desktop: sidebar is always mounted
        setTimeout(focusSearch, 0)  // mobile: after the drawer opens
      } else if (k === 'k') {
        e.preventDefault()
        setShowQuickOpen(true)
      } else if (/^[0-9]$/.test(e.key)) {
        e.preventDefault()
        if (e.key === '0') { setSection(store.navigateHome()); return }
        const item = store.pinnedItems[Number(e.key) - 1]
        if (!item) return
        if (item.kind === 'view') { store.selectSaved(item.filter.id); setSection({ kind: 'saved', id: item.filter.id }) }
        else setSection({ kind: 'dashboard', id: item.dashboard.id })
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [store])

  useEffect(() => {
    if (!booted && store.configured) {
      setSection(store.navigateHome())
      setBooted(true)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booted, store.configured])

  const content = () => {
    switch (section.kind) {
      case 'documents': return <DocumentsView setSection={setSection} />
      case 'views': return <ViewsPage setSection={setSection} />
      case 'dashboards': return <DashboardsPage setSection={setSection} />
      case 'dashboard': return <DashboardView dashboardId={section.id} />
      case 'calendar': return <CalendarView />
      default: return <TaskListView section={section} />
    }
  }

  return (
    <div className="app">
      <Sidebar section={section} setSection={setSection}
               open={sidebarOpen}
               onNavigate={() => setSidebarOpen(false)}
               onClose={() => setSidebarOpen(false)}
               onOpenSettings={() => { setShowSettings(true); setSidebarOpen(false) }}
               onAddTask={() => setShowAddTask(true)} />
      <div className="main">
        {content()}
      </div>
      <button className="fab" onClick={() => setShowAddTask(true)} title="New Task">
        <Icon name="plus" size={20} weight={2} />
      </button>
      <BottomNav section={section} setSection={setSection} onOpenMenu={() => setSidebarOpen(true)} />
      {(showSettings || !store.configured) && (
        <SettingsModal forced={!store.configured} onClose={() => setShowSettings(false)} />
      )}
      {showAddTask && <AddTaskModal onClose={() => setShowAddTask(false)} />}
      {showQuickOpen && (
        <QuickOpenModal
          onOpen={id => { store.openDocument(id); setSection({ kind: 'allTasks' }) }}
          onClose={() => setShowQuickOpen(false)} />
      )}
    </div>
  )
}

export default function App() {
  return (
    <StoreProvider>
      <Root />
    </StoreProvider>
  )
}
