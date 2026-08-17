import { CraftTask, displayTitle, taskTags, scheduleDay, deadlineDay, completedDay, startOfToday } from './types'
import { useStore } from './store'
import { Icon } from './ui'
import { craftDeepLink } from './craft'

export function TaskRow({ task, onEdit }: { task: CraftTask; onEdit: (t: CraftTask) => void }) {
  const store = useStore()
  const isPending = task.id.startsWith('local-')
  const deepLink = craftDeepLink(task)
  const tags = taskTags(task)
  const firstColoredTag = tags.find(t => store.tagColors[t])
  const tagColor = firstColoredTag ? store.tagColors[firstColoredTag] : null

  const today = startOfToday()
  const d = scheduleDay(task) ?? deadlineDay(task)
  let badge: { text: string; overdue: boolean } | null = null
  if (d) {
    const overdue = d < today && task.state === 'todo'
    const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate() + 1)
    const text = d.getTime() === today.getTime() ? 'Today'
      : d.getTime() === tomorrow.getTime() ? 'Tomorrow'
      : d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
    badge = { text, overdue }
  }
  const cd = task.state === 'done' ? completedDay(task) : null

  return (
    <div className={`task-row${isPending ? ' pending' : ''}`}
         style={tagColor ? { borderLeftColor: tagColor, borderLeftWidth: '4px', borderLeftStyle: 'solid', paddingLeft: '12px' } : {}}
         data-tag-color={tagColor}
         onClick={() => { if (!isPending) onEdit(task) }}
         title={isPending ? 'Still syncing to Craft — editing available once confirmed' : undefined}>
      <button className={`checkbox ${task.state}`}
              onClick={e => { e.stopPropagation(); if (!isPending) store.cycleState(task) }}
              title="Click to cycle state">
        {task.state === 'done' && <Icon name="check" size={9} weight={2.5} />}
        {task.state === 'canceled' && <Icon name="xmark" size={8} weight={2.5} />}
      </button>
      <div className="task-main">
        <div className={`task-title${task.state !== 'todo' ? ' closed' : ''}`}>{displayTitle(task)}</div>
        <div className="task-meta">
          {isPending && <span className="done-note">syncing…</span>}
          {taskTags(task).map(tag => <span key={tag} className="task-tag">#{tag}</span>)}
          {badge && (
            <span className={`date-badge${badge.overdue ? ' overdue' : ''}`}>
              <Icon name={task.deadlineDate && !task.scheduleDate ? 'flag' : 'calendar'} size={8} />
              {badge.text}
            </span>
          )}
          {cd && <span className="done-note">done {cd.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}</span>}
        </div>
      </div>
      {deepLink && (
        <a className="open-in-craft" href={deepLink} onClick={e => e.stopPropagation()} title="Open in Craft">
          <Icon name="stack" size={12} weight={1.6} />
        </a>
      )}
    </div>
  )
}
