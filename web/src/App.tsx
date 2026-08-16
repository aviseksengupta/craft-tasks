import { useEffect, useState } from 'react'
import { Section } from './types'
import { StoreProvider, useStore } from './store'
import { Sidebar } from './Sidebar'
import { BottomNav } from './BottomNav'
import { TaskListView } from './TaskList'
import { DocumentsView, ViewsPage, DashboardsPage } from './Cards'
import { DashboardView } from './DashboardView'
import { SettingsModal, AddTaskModal } from './modals'
import { Icon } from './ui'

function Root() {
  const store = useStore()
  const [section, setSection] = useState<Section>({ kind: 'home' })
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [showAddTask, setShowAddTask] = useState(false)
  const [booted, setBooted] = useState(false)

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
