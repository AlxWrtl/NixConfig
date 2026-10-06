// Pure formatting of one board row: duration, French state word, width fit.

import type { TaskBoardStatus, TaskBoardTask } from '../types'

const pad2 = (n: number): string => String(n).padStart(2, '0')

// "Ns" under a minute, "Mm SSs" under an hour, "Hh MMm" past it.
export function formatDuration(ms: number): string {
  const seconds = Math.floor(Math.max(0, ms) / 1000)
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ${pad2(seconds % 60)}s`
  return `${Math.floor(minutes / 60)}h ${pad2(minutes % 60)}m`
}

export function label(status: TaskBoardStatus): string {
  if (status === 'running') return 'en cours'
  if (status === 'completed') return 'fini'
  return 'échoué'
}

export function truncate(text: string, width: number): string {
  if (width <= 0) return ''
  if (text.length <= width) return text
  return width === 1 ? '…' : `${text.slice(0, width - 1)}…`
}

const STATE_WIDTH = 'en cours'.length

export type Row = { state: string; text: string; dur: string }

// One row laid out in `cols` cells: "<state> <text> <dur>", the text cut
// with "…" so the three fit; state padded to one column width.
export function layoutRow(task: TaskBoardTask, now: number, cols: number): Row {
  const state = label(task.status).padEnd(STATE_WIDTH)
  const dur = formatDuration((task.endedAt ?? now) - task.startedAt)
  const prefix = task.kind === 'shell' ? '$ ' : '@ '
  const room = cols - state.length - dur.length - 2
  const text = truncate(`${prefix}${task.label.replace(/\s+/g, ' ').trim()}`, room)
  return { state, text, dur }
}
