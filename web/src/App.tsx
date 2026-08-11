import { useEffect, useState } from 'react'
import { Section } from './types'
import { StoreProvider, useStore } from './store'
import { Sidebar } from './Sidebar'
import { BottomNav } from './BottomNav'
import { TaskListView } from './TaskList'
import { DocumentsView, ViewsPage } from './Cards'
import { DashboardView } from './DashboardView'
import { SettingsModal, AddTaskModal } from './modals'
import { Icon } from './ui'

/** Sets --app-height from a JS-measured window.innerHeight, kept fresh on
 * resize/orientation/pageshow. A standalone (home-screen-launched) iOS PWA
 * can report viewport metrics to CSS (100vh/dvh, and even position:fixed's
 * own inset:0 sizing) that don't match the real screen — a well-known
 * WebKit quirk specific to that launch mode, distinct from and on top of
 * ordinary browser-tab rendering (which is what a desktop browser or a
 * regular Safari tab actually exercises, so it can look fine there and
 * still be wrong once added to the home screen). window.innerHeight is a
 * plain runtime measurement, not a CSS calculation, so it sidesteps
 * whatever's wrong with the CSS side specifically. */
function useAppHeight() {
  useEffect(() => {
    const set = () => {
      const h = window.visualViewport?.height ?? window.innerHeight
      document.documentElement.style.setProperty('--app-height', `${h}px`)
    }
    set()
    window.addEventListener('resize', set)
    window.addEventListener('orientationchange', set)
    window.addEventListener('pageshow', set)
    window.visualViewport?.addEventListener('resize', set)
    return () => {
      window.removeEventListener('resize', set)
      window.removeEventListener('orientationchange', set)
      window.removeEventListener('pageshow', set)
      window.visualViewport?.removeEventListener('resize', set)
    }
  }, [])
}

function Root() {
  const store = useStore()
  const [section, setSection] = useState<Section>({ kind: 'home' })
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [showAddTask, setShowAddTask] = useState(false)
  const [booted, setBooted] = useState(false)
  useAppHeight()

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
      case 'dashboard': return <DashboardView dashboardId={section.id} />
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
