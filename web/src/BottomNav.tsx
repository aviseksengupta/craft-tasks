import { Section, sectionEq } from './types'
import { useStore } from './store'
import { Icon } from './ui'

/// Mobile-only bottom tab bar — the primary nav surface for the 90% of
/// usage that's on a phone. Covers the four most common destinations plus
/// "Menu" for everything else (Inbox, This Week, Views, Dashboards,
/// search, settings), which opens the full-screen sidebar.
export function BottomNav({ section, setSection, onOpenMenu }: {
  section: Section
  setSection: (s: Section) => void
  onOpenMenu: () => void
}) {
  const store = useStore()

  const homeIsActive = sectionEq(section, store.homeSection ?? { kind: 'home' })
  const tabs = [
    { id: 'home', icon: 'house', label: 'Home', active: homeIsActive, action: () => setSection(store.navigateHome()) },
    { id: 'allTasks', icon: 'trayFull', label: 'Tasks', active: sectionEq(section, { kind: 'allTasks' }), action: () => { store.selectAllTasks(); setSection({ kind: 'allTasks' }) } },
    { id: 'today', icon: 'sun', label: 'Today', active: sectionEq(section, { kind: 'today' }), action: () => { store.selectToday(); setSection({ kind: 'today' }) } },
    { id: 'documents', icon: 'doc', label: 'Docs', active: sectionEq(section, { kind: 'documents' }), action: () => setSection({ kind: 'documents' }) },
  ]

  const menuActive = ['inbox', 'thisWeek', 'views', 'dashboard'].includes(section.kind)

  return (
    <nav className="bottom-nav">
      {tabs.map(t => (
        <button key={t.id} className={`bn-tab${t.active ? ' active' : ''}`} onClick={t.action}>
          <Icon name={t.icon} size={19} weight={t.active ? 1.8 : 1.4} />
          <span>{t.label}</span>
        </button>
      ))}
      <button className={`bn-tab${menuActive ? ' active' : ''}`} onClick={onOpenMenu}>
        <Icon name="menuBars" size={18} weight={menuActive ? 1.8 : 1.4} />
        <span>Menu</span>
      </button>
    </nav>
  )
}
