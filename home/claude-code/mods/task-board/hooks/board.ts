// Pure reducer of the task list: no `$`, no clock, no I/O.
// Every function returns the SAME array reference when nothing changed, so
// a caller can skip the state write (and the redraw it causes).

import type { TaskBoardStatus, TaskBoardTask } from '../types'

export type Task = TaskBoardTask
export type Status = TaskBoardStatus

export const CAP = 50
// A task finished less than RECENT_MS ago is always shown; past it, at most
// MAX_DONE finished tasks are shown unless the pane shows them all.
export const RECENT_MS = 30_000
export const MAX_DONE = 5

// A model step's usage, reduced to the fields counted here.
export type StepUsage = {
  input_tokens: number
  output_tokens: number
  cache_creation_input_tokens: number
}

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
type EndedStatus = Exclude<Status, 'running'>

function endedStatus(word: string | undefined): EndedStatus | undefined {
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
  shell: { id: string; label: string; startedAt: number; toolUseId?: string; ownerAgentId?: string },
): Task[] {
  if (tasks.some(t => t.id === shell.id)) return tasks
  const task: Task = {
    id: shell.id,
    kind: 'shell',
    label: shell.label,
    startedAt: shell.startedAt,
    status: 'running',
    ...(shell.toolUseId === undefined ? {} : { toolUseId: shell.toolUseId }),
    ...(shell.ownerAgentId === undefined ? {} : { ownerAgentId: shell.ownerAgentId }),
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

// A task-notification row's text, as a subagent's transcript keeps it:
// `<task-id>…</task-id>` and `<status>…</status>`. A missing id, or a status
// word that is not an end, reads as undefined.
export function parseTaskNotification(
  text: string,
): { id: string; status: EndedStatus } | undefined {
  const id = /<task-id>([^<]*)<\/task-id>/.exec(text)?.[1]?.trim()
  const status = endedStatus(/<status>([^<]*)<\/status>/.exec(text)?.[1]?.trim())
  if (id === undefined || id === '' || status === undefined) return undefined
  return { id, status }
}

// Every `<task-notification>…</task-notification>` block of a row: a row
// delivered while the loop was busy may batch several. A malformed block is
// skipped.
export function parseTaskNotifications(text: string): Array<{ id: string; status: EndedStatus }> {
  const notes: Array<{ id: string; status: EndedStatus }> = []
  for (const block of text.matchAll(/<task-notification>([\s\S]*?)<\/task-notification>/g)) {
    const note = parseTaskNotification(block[1] ?? '')
    if (note !== undefined) notes.push(note)
  }
  return notes
}

// A shell stopped by TaskStop: only a running shell row closes, as killed;
// an agent id (TaskStop accepts both) or an unknown one is a no-op.
export function stopShell(tasks: Task[], id: string, now: number): Task[] {
  const index = tasks.findIndex(t => t.id === id && t.kind === 'shell')
  const task = tasks[index]
  if (task === undefined || task.status !== 'running') return tasks
  return replaceAt(tasks, index, { ...task, status: 'killed', endedAt: now })
}

// A subagent's background shell notifies that subagent's loop, never the
// main one: once the owner ends killed or failed, or leaves the agent list,
// its still running shells are closed as `killed`. An owner that completed
// keeps them (it may resume on the shell's notification).
export function closeOrphanShells(tasks: Task[], ownerId: string, endedAt: number): Task[] {
  const isOrphan = (t: Task): boolean => t.kind === 'shell' && t.status === 'running' && t.ownerAgentId === ownerId
  if (!tasks.some(isOrphan)) return tasks
  return normalize(tasks.map(t => (isOrphan(t) ? { ...t, status: 'killed', endedAt } : t)))
}

// A `$.agent.list()` snapshot: unknown agents are added; a known running
// agent the list reports ended is finished, except a teammate (it goes
// `idle` between turns and is never finished from here).
export function applyAgentSnapshot(tasks: Task[], list: readonly AgentSnapshot[], now: number): Task[] {
  let out = tasks
  for (const agent of list) {
    const ended = endedStatus(agent.status)
    if ((ended === 'killed' || ended === 'failed') && agent.type !== TEAMMATE) out = closeOrphanShells(out, agent.id, now)
  }
  const listed = new Set(list.map(a => a.id))
  for (const t of tasks) {
    if (t.kind === 'agent' && !listed.has(t.id)) out = closeOrphanShells(out, t.id, now)
  }
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
  if (task === undefined || task.status !== 'running') return tasks
  // A teammate's turn ending only clears its current tool.
  if (task.agentType === TEAMMATE) return task.tool === undefined ? tasks : replaceAt(tasks, index, withoutTool(task))
  const status: Status = reason === 'answer' ? 'completed' : reason === 'aborted' ? 'killed' : 'failed'
  const out = replaceAt(tasks, index, { ...withoutTool(task), status, endedAt: now })
  return status === 'completed' ? out : closeOrphanShells(out, agentId, now)
}

// The task without its current tool (the same object when it has none).
function withoutTool(task: Task): Task {
  if (task.tool === undefined) return task
  const copy: Task = { ...task }
  delete copy.tool
  return copy
}

// A model step of subagent `agentId`: its input, output and cache-write
// tokens are added to that agent's row (cache reads excluded: with a large
// context they dwarf the rest). A main-loop step, an unknown agent, a null
// usage or a zero count: no change.
export function noteStep(tasks: Task[], agentId: string | undefined, usage: StepUsage | null): Task[] {
  if (agentId === undefined || usage === null) return tasks
  const count = usage.input_tokens + usage.output_tokens + usage.cache_creation_input_tokens
  const index = tasks.findIndex(t => t.id === agentId && t.kind === 'agent')
  const task = tasks[index]
  if (task === undefined || !(count > 0)) return tasks
  return tasks.map((t, i) => (i === index ? { ...task, tokens: (task.tokens ?? 0) + count } : t))
}

// A tool call in subagent `agentId`'s loop: shown as that running agent's
// current tool. Main loop, unknown or finished agent, same tool: no change.
export function noteTool(tasks: Task[], agentId: string | undefined, tool: string): Task[] {
  if (agentId === undefined || tool === '') return tasks
  const index = tasks.findIndex(t => t.id === agentId && t.kind === 'agent')
  const task = tasks[index]
  if (task === undefined || task.status !== 'running' || task.tool === tool) return tasks
  return tasks.map((t, i) => (i === index ? { ...task, tool } : t))
}

// Every finished task removed; running ones kept.
export function clearDone(tasks: Task[]): Task[] {
  return tasks.some(t => t.status !== 'running') ? tasks.filter(t => t.status === 'running') : tasks
}

// True while a finished task is still inside the RECENT_MS window at `now`:
// the pane's clock must keep ticking for it to fold once the window ends.
export function hasRecentDone(tasks: readonly Task[], now: number): boolean {
  return tasks.some(t => t.status !== 'running' && now - (t.endedAt ?? t.startedAt) < RECENT_MS)
}

// The rows the pane draws: every running task, then the finished ones (most
// recent first) that are recent, among the first MAX_DONE, or all of them
// when `showAll`; `hidden` counts the finished tasks left out.
export function visible(tasks: readonly Task[], now: number, showAll: boolean): { rows: Task[]; hidden: number } {
  const rows: Task[] = []
  let done = 0
  let hidden = 0
  for (const t of tasks) {
    if (t.status === 'running') {
      rows.push(t)
      continue
    }
    const isRecent = now - (t.endedAt ?? t.startedAt) < RECENT_MS
    if (showAll || isRecent || done < MAX_DONE) rows.push(t)
    else hidden += 1
    done += 1
  }
  return { rows, hidden }
}

export function clear(tasks: Task[]): Task[] {
  return tasks.length === 0 ? tasks : []
}

export function runningCount(tasks: readonly Task[]): number {
  return tasks.filter(t => t.status === 'running').length
}
