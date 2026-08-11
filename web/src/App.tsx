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

const HEIGHT_OFFSET_KEY = 'appHeightOffsetPx'
export function getHeightOffset(): number {
  return Number(localStorage.getItem(HEIGHT_OFFSET_KEY) ?? 0)
}

/** Sets --app-height from a JS-measured window.innerHeight, kept fresh on
 * resize/orientation/pageshow. A standalone (home-screen-launched) iOS PWA
 * can report viewport metrics to CSS (100vh/dvh, and even position:fixed's
 * own inset:0 sizing) that don't match the real screen — a well-known
 * WebKit quirk specific to that launch mode, distinct from and on top of
 * ordinary browser-tab rendering (which is what a desktop browser or a
 * regular Safari tab actually exercises, so it can look fine there and
 * still be wrong once added to the home screen). window.innerHeight is a
 * plain runtime measurement, not a CSS calculation, so it sidesteps
 * whatever's wrong with the CSS side specifically — but on some devices
 * even that measurement itself is short by a device-specific amount,
 * hence `offsetPx`: a manual per-device fudge factor set from Settings,
 * since this can't be reproduced or tuned from outside a real standalone
 * PWA launch.
 */
function useAppHeight(offsetPx: number) {
  useEffect(() => {
    const set = () => {
      const h = window.visualViewport?.height ?? window.innerHeight
      document.documentElement.style.setProperty('--app-height', `${h + offsetPx}px`)
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
  }, [offsetPx])
}

function Root() {
  const store = useStore()
  const [section, setSection] = useState<Section>({ kind: 'home' })
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [showAddTask, setShowAddTask] = useState(false)
  const [booted, setBooted] = useState(false)
  const [heightOffset, setHeightOffset] = useState(getHeightOffset)
  useAppHeight(heightOffset)
  const adjustHeightOffset = (delta: number) => {
    setHeightOffset(v => {
      const next = v + delta
      localStorage.setItem(HEIGHT_OFFSET_KEY, String(next))
      return next
    })
  }

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
        <SettingsModal forced={!store.configured} onClose={() => setShowSettings(false)}
                       heightOffset={heightOffset} onAdjustHeightOffset={adjustHeightOffset} />
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
