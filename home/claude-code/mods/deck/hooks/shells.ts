// Pure reducer of the session's background shells: no `$`, no clock, no I/O.
// Every function returns the SAME array reference when nothing changed, so a
// caller can skip the state write (and the redraw it causes).

import type { DeckApexShell, DeckApexShellStatus } from '../types'

export type Shell = DeckApexShell

export const CAP = 50

// What a task-notification row carries (UserMessage `e.props.task`).
export type Notification = {
  id?: string
  toolUseId?: string
  status?: string
  durationMs?: number
}

// One agent of `$.agent.list()`, reduced to what the shells read.
export type OwnerSnap = { id: string; type: string; status: string }

const TEAMMATE = 'teammate'

// An ended status word, or undefined for anything else (still running, or a
// word this build does not name: the shell keeps `running`).
export type EndedStatus = Exclude<DeckApexShellStatus, 'running'>

function endedStatus(word: string | undefined): EndedStatus | undefined {
  if (word === 'completed' || word === 'failed' || word === 'killed') return word
  return undefined
}

// Running first (oldest first), then finished (most recent end first); past
// CAP the oldest finished go, then the oldest running.
function normalize(shells: Shell[]): Shell[] {
  const running = shells.filter(t => t.status === 'running').sort((a, b) => a.startedAt - b.startedAt)
  const done = shells
    .filter(t => t.status !== 'running')
    .sort((a, b) => (b.endedAt ?? b.startedAt) - (a.endedAt ?? a.startedAt))
  return [...running.slice(-CAP), ...done].slice(0, CAP)
}

export function addShell(
  shells: Shell[],
  shell: { id: string; label: string; startedAt: number; toolUseId?: string; ownerAgentId?: string },
): Shell[] {
  if (shells.some(t => t.id === shell.id)) return shells
  const row: Shell = {
    id: shell.id,
    label: shell.label,
    startedAt: shell.startedAt,
    status: 'running',
    ...(shell.toolUseId === undefined ? {} : { toolUseId: shell.toolUseId }),
    ...(shell.ownerAgentId === undefined ? {} : { ownerAgentId: shell.ownerAgentId }),
  }
  return normalize([...shells, row])
}

function replaceAt(shells: Shell[], index: number, shell: Shell): Shell[] {
  return normalize(shells.map((t, i) => (i === index ? shell : t)))
}

// A background shell's notification: matched by id, else by tool_use_id.
// Unknown shell, unknown status word, or a shell already ended: no change
// (a notification row is drawn again on every redraw and on a resume).
export function finishByNotification(shells: Shell[], note: Notification, now: number): Shell[] {
  const status = endedStatus(note.status)
  if (status === undefined) return shells
  let index = note.id === undefined ? -1 : shells.findIndex(t => t.id === note.id)
  if (index < 0 && note.toolUseId !== undefined) {
    index = shells.findIndex(t => t.toolUseId === note.toolUseId)
  }
  const shell = index < 0 ? undefined : shells[index]
  if (shell === undefined || shell.status !== 'running') return shells
  const endedAt = note.durationMs === undefined ? now : shell.startedAt + note.durationMs
  return replaceAt(shells, index, { ...shell, status, endedAt })
}

// A task-notification row's text, as a subagent's transcript keeps it:
// `<task-id>…</task-id>` and `<status>…</status>`. A missing id, or a status
// word that is not an end, reads as undefined.
export function parseTaskNotification(text: string): { id: string; status: EndedStatus } | undefined {
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

// A shell stopped by TaskStop: only a running shell closes, as killed; an
// agent id (TaskStop accepts both) or an unknown one is a no-op.
export function stopShell(shells: Shell[], id: string, now: number): Shell[] {
  const index = shells.findIndex(t => t.id === id)
  const shell = shells[index]
  if (shell === undefined || shell.status !== 'running') return shells
  return replaceAt(shells, index, { ...shell, status: 'killed', endedAt: now })
}

// A subagent's background shell notifies that subagent's loop, never the
// main one: once the owner ends killed or failed, or leaves the agent list,
// its still running shells are closed as `killed`. An owner that completed
// keeps them (it may resume on the shell's notification).
export function closeOrphanShells(shells: Shell[], ownerId: string, endedAt: number): Shell[] {
  const isOrphan = (t: Shell): boolean => t.status === 'running' && t.ownerAgentId === ownerId
  if (!shells.some(isOrphan)) return shells
  return normalize(shells.map(t => (isOrphan(t) ? { ...t, status: 'killed', endedAt } : t)))
}

// A `$.agent.list()` snapshot applied to the shells: a listed owner ended
// killed or failed (a teammate aside), or an owner among `known` (the
// subagent loops this session saw) gone from the list, closes its shells.
export function closeBySnapshot(
  shells: Shell[],
  agents: readonly OwnerSnap[],
  known: readonly string[],
  now: number,
): Shell[] {
  let out = shells
  for (const agent of agents) {
    const ended = endedStatus(agent.status)
    if ((ended === 'killed' || ended === 'failed') && agent.type !== TEAMMATE) out = closeOrphanShells(out, agent.id, now)
  }
  const listed = new Set(agents.map(a => a.id))
  for (const id of known) {
    if (!listed.has(id)) out = closeOrphanShells(out, id, now)
  }
  return out
}

export function runningShells(shells: readonly Shell[]): number {
  return shells.filter(t => t.status === 'running').length
}

// A subagent's turn ended with `reason`: unless it answered, its still running shells close as
// killed (their notification could only ever reach that loop). Any subagent, the architect too.
export function shellsAfterTurn(shells: Shell[], agentId: string, reason: string, at: number): Shell[] {
  return reason === 'answer' ? shells : closeOrphanShells(shells, agentId, at)
}
