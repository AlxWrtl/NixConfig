// Pure reducer of the task list: no `$`, no clock, no I/O.
// Every function returns the SAME array reference when nothing changed, so
// a caller can skip the state write (and the redraw it causes).

import type { TaskBoardStatus, TaskBoardTask } from '../types'

export type Task = TaskBoardTask
export type Status = TaskBoardStatus

export const CAP = 50

// What a task-notification row carries (UserMessage `e.props.task`).
export type Notification = {
  id?: string
  toolUseId?: string
  status?: string
  durationMs?: number
}

// What `$.agent.list()` answers, reduced to the fields read here.
export type AgentSnapshot = {
  id: string
  description: string
  type: string
  status: string
}

export type TurnReason = 'answer' | 'aborted' | 'refusal' | 'error'

const TEAMMATE = 'teammate'

// An ended status word, or undefined for anything else (still running, or a
// word this build does not name: the task keeps `running`).
function endedStatus(word: string | undefined): Status | undefined {
  if (word === 'completed' || word === 'failed' || word === 'killed') return word
  return undefined
}

// Running first (oldest first), then finished (most recent end first); past
// CAP the oldest finished go, then the oldest running.
function normalize(tasks: Task[]): Task[] {
  const running = tasks.filter(t => t.status === 'running').sort((a, b) => a.startedAt - b.startedAt)
  const done = tasks
    .filter(t => t.status !== 'running')
    .sort((a, b) => (b.endedAt ?? b.startedAt) - (a.endedAt ?? a.startedAt))
  return [...running.slice(-CAP), ...done].slice(0, CAP)
}

export function addShell(
  tasks: Task[],
  shell: { id: string; label: string; startedAt: number; toolUseId?: string },
): Task[] {
  if (tasks.some(t => t.id === shell.id)) return tasks
  const task: Task = {
    id: shell.id,
    kind: 'shell',
    label: shell.label,
    startedAt: shell.startedAt,
    status: 'running',
    ...(shell.toolUseId === undefined ? {} : { toolUseId: shell.toolUseId }),
  }
  return normalize([...tasks, task])
}

export function addAgent(
  tasks: Task[],
  agent: { id: string; label: string; startedAt: number; agentType?: string; toolUseId?: string },
): Task[] {
  if (tasks.some(t => t.id === agent.id)) return tasks
  const task: Task = {
    id: agent.id,
    kind: 'agent',
    label: agent.label,
    startedAt: agent.startedAt,
    status: 'running',
    ...(agent.agentType === undefined ? {} : { agentType: agent.agentType }),
    ...(agent.toolUseId === undefined ? {} : { toolUseId: agent.toolUseId }),
  }
  return normalize([...tasks, task])
}

function replaceAt(tasks: Task[], index: number, task: Task): Task[] {
  return normalize(tasks.map((t, i) => (i === index ? task : t)))
}

// A background task's notification: matched by id, else by tool_use_id.
// Unknown task, unknown status word, or a task already ended: no change
// (a notification row is drawn again on every redraw and on a resume).
export function finishByNotification(tasks: Task[], note: Notification, now: number): Task[] {
  const status = endedStatus(note.status)
  if (status === undefined) return tasks
  let index = note.id === undefined ? -1 : tasks.findIndex(t => t.id === note.id)
  if (index < 0 && note.toolUseId !== undefined) {
    index = tasks.findIndex(t => t.toolUseId === note.toolUseId)
  }
  const task = index < 0 ? undefined : tasks[index]
  if (task === undefined || task.status !== 'running') return tasks
  const endedAt = note.durationMs === undefined ? now : task.startedAt + note.durationMs
  return replaceAt(tasks, index, { ...task, status, endedAt })
}

// A `$.agent.list()` snapshot: unknown agents are added; a known running
// agent the list reports ended is finished, except a teammate (it goes
// `idle` between turns and is never finished from here).
export function applyAgentSnapshot(tasks: Task[], list: readonly AgentSnapshot[], now: number): Task[] {
  let out = tasks
  for (const agent of list) {
    const index = out.findIndex(t => t.id === agent.id)
    const ended = endedStatus(agent.status)
    if (index < 0) {
      const added = addAgent(out, { id: agent.id, label: agent.description, startedAt: now, agentType: agent.type })
      const at = added.findIndex(t => t.id === agent.id)
      const task = added[at]
      out =
        ended === undefined || task === undefined || agent.type === TEAMMATE
          ? added
          : replaceAt(added, at, { ...task, status: ended, endedAt: now })
      continue
    }
    const task = out[index]
    if (task === undefined || ended === undefined || task.status !== 'running') continue
    if (task.agentType === TEAMMATE || agent.type === TEAMMATE) continue
    out = replaceAt(out, index, { ...task, status: ended, endedAt: now })
  }
  return out
}

// A subagent's `turn.complete`: answer → completed, aborted → killed,
// error | refusal → failed. A teammate is skipped (its turn ending is not
// the teammate ending).
export function finishAgentTurn(tasks: Task[], agentId: string, reason: TurnReason, now: number): Task[] {
  const index = tasks.findIndex(t => t.id === agentId && t.kind === 'agent')
  const task = tasks[index]
  if (task === undefined || task.status !== 'running' || task.agentType === TEAMMATE) return tasks
  const status: Status = reason === 'answer' ? 'completed' : reason === 'aborted' ? 'killed' : 'failed'
  return replaceAt(tasks, index, { ...task, status, endedAt: now })
}

export function clear(tasks: Task[]): Task[] {
  return tasks.length === 0 ? tasks : []
}

export function runningCount(tasks: readonly Task[]): number {
  return tasks.filter(t => t.status === 'running').length
}
