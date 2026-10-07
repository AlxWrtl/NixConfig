// Pure formatting of the board: duration, status glyph and tone, header
// counts, width fit of one row.

import type { ThemeKey } from 'claude-code'

import type { TaskBoardStatus, TaskBoardTask } from '../types'

const pad2 = (n: number): string => String(n).padStart(2, '0')

// Cells of the glyph column (glyph + gap) and of the kind column.
export const GLYPH_WIDTH = 2
export const KIND_WIDTH = 6
// Below this width the kind column is dropped to leave room for the label.
export const KIND_MIN_COLS = 40

// "Ns" under a minute, "Mm SSs" under an hour, "Hh MMm" past it.
export function formatDuration(ms: number): string {
  const seconds = Math.floor(Math.max(0, ms) / 1000)
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ${pad2(seconds % 60)}s`
  return `${Math.floor(minutes / 60)}h ${pad2(minutes % 60)}m`
}

// One narrow glyph per status; killed has its own, never the failure cross.
export function glyph(status: TaskBoardStatus): string {
  if (status === 'running') return '●'
  if (status === 'completed') return '✓'
  if (status === 'failed') return '✗'
  return '■'
}

// The theme color that goes with each status glyph.
export function tone(status: TaskBoardStatus): ThemeKey {
  if (status === 'running') return 'warning'
  if (status === 'completed') return 'success'
  if (status === 'failed') return 'error'
  return 'inactive'
}

export function truncate(text: string, width: number): string {
  if (width <= 0) return ''
  if (text.length <= width) return text
  return width === 1 ? '…' : `${text.slice(0, width - 1)}…`
}

export type SummaryPart = { text: string; tone: ThemeKey; bold: boolean }

const plural = (n: number, word: string): string => `${n} ${word}${n > 1 ? 's' : ''}`

// Header counts in a fixed order (en cours, finie(s), échouée(s),
// arrêtée(s)), zero counts left out; only the running count is bold.
export function summary(tasks: readonly TaskBoardTask[]): SummaryPart[] {
  const count = (status: TaskBoardStatus): number => tasks.filter(t => t.status === status).length
  const parts: SummaryPart[] = []
  const running = count('running')
  const completed = count('completed')
  const failed = count('failed')
  const killed = count('killed')
  if (running > 0) parts.push({ text: `${running} en cours`, tone: tone('running'), bold: true })
  if (completed > 0) parts.push({ text: plural(completed, 'finie'), tone: tone('completed'), bold: false })
  if (failed > 0) parts.push({ text: plural(failed, 'échouée'), tone: tone('failed'), bold: false })
  if (killed > 0) parts.push({ text: plural(killed, 'arrêtée'), tone: tone('killed'), bold: false })
  return parts
}

// True when the list holds both running and finished tasks: only then is
// the finished group introduced by its own label.
export function hasBothGroups(tasks: readonly TaskBoardTask[]): boolean {
  return tasks.some(t => t.status === 'running') && tasks.some(t => t.status !== 'running')
}

// "999", "1.2k", "10k", "1.0M": the unit is chosen after rounding
// (9 999 → 10k, 999 999 → 1.0M), as apex-band's pane counts.
export function fmtTokens(n: number): string {
  const v = Math.max(0, Math.round(n))
  if (v < 1000) return String(v)
  const tenths = (v / 1000).toFixed(1)
  if (Number(tenths) < 10) return `${tenths}k`
  const thousands = Math.round(v / 1000)
  if (thousands < 1000) return `${thousands}k`
  return `${(v / 1_000_000).toFixed(1)}M`
}

// Cells the label keeps before a row's dim detail is cut.
const MIN_NAME = 10

// `text` is the label; `detail` the dim " · tool · tokens" suffix of an agent
// (tool while running, tokens once counted), empty otherwise.
export type Row = { glyph: string; tone: ThemeKey; kind: string; text: string; detail: string; dur: string; isDone: boolean }

// One row laid out in `cols` cells: glyph column, kind column (empty below
// KIND_MIN_COLS, and for an agent whose type already prefixes the label),
// label then dim detail cut with "…" (the label keeps
// MIN_NAME cells first), one gap, duration; all fit.
export function layoutRow(task: TaskBoardTask, now: number, cols: number): Row {
  const dur = formatDuration((task.endedAt ?? now) - task.startedAt)
  const typedAgent = task.kind === 'agent' && task.agentType !== undefined
  const kind = cols >= KIND_MIN_COLS && !typedAgent ? task.kind : ''
  const base = task.label.replace(/\s+/g, ' ').trim()
  const name = typedAgent ? `${task.agentType} · ${base}` : base
  const room = cols - GLYPH_WIDTH - (kind === '' ? 0 : KIND_WIDTH) - 1 - dur.length
  const parts = [
    task.status === 'running' ? task.tool : undefined,
    task.tokens !== undefined && task.tokens > 0 ? fmtTokens(task.tokens) : undefined,
  ].filter((p): p is string => p !== undefined && p !== '')
  const suffix = parts.map(p => ` · ${p}`).join('')
  const nameRoom = Math.max(Math.min(name.length, room - suffix.length), Math.min(room, MIN_NAME))
  const text = truncate(name, nameRoom)
  return {
    glyph: glyph(task.status),
    tone: tone(task.status),
    kind,
    text,
    detail: truncate(suffix, room - text.length),
    dur,
    isDone: task.status !== 'running',
  }
}
