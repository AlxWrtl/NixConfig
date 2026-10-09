// Pure layout of the APEX detail pane (/apex-pane, alias /task-board): what
// asks the user to act, the run's header and its phases with approximate
// token counts, one line per subagent, one line per background shell, the
// totals and the external verdict once there is one. Finished subagents and
// shells past MAX_DONE fold into a « +N terminés » line unless `showAll`.
// Every line fits `cols` cells (hard cut otherwise); below 40 columns the
// share bar and the subagent's model are dropped.

import type { ThemeKey } from 'claude-code'

import type {
  ApexBandAlert,
  ApexBandLoop,
  ApexBandLoopStatus,
  ApexBandPhases,
  ApexBandRun,
  ApexBandShell,
  ApexBandShellStatus,
  ApexBandVerdict,
} from '../types'
import { alertLine, hardCut, join, meta, stepLabel, stepMark, textCells, truncate, width } from './band.ts'
import type { Seg } from './band.ts'
import { MAIN, countedTotal, loopDuration, splitTotals } from './stats.ts'

export type PaneInput = {
  run: ApexBandRun | null
  loops: readonly ApexBandLoop[]
  phases: ApexBandPhases
  now: number
  cost: number | null
  verdict: ApexBandVerdict | null
  shells: readonly ApexBandShell[]
  alerts: readonly ApexBandAlert[]
  showAll: boolean
}

// Columns under which the bar and the subagent's model are dropped.
export const NARROW = 40
// Finished subagents (and, apart, finished shells) shown before the fold.
export const MAX_DONE = 6
const BAR_CELLS = 10
const TOKEN_CELLS = 6
const MAX_LABEL = 12
// A cut label keeps at least this many cells before the detail shrinks.
const MIN_LABEL = 10

const pad2 = (n: number): string => String(n).padStart(2, '0')

// A duration as 45s, 3m 07s or 1h 05m.
export function formatDuration(ms: number): string {
  const seconds = Math.floor(Math.max(0, ms) / 1000)
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ${pad2(seconds % 60)}s`
  return `${Math.floor(minutes / 60)}h ${pad2(minutes % 60)}m`
}

// A token count as 950, 1.2k, 45k or 1.3M.
export function fmtTokens(n: number): string {
  const v = Math.max(0, Math.round(n))
  if (v < 1000) return String(v)
  // The unit is chosen after rounding: 9 999 → 10k, 999 999 → 1.0M.
  const tenths = (v / 1000).toFixed(1)
  if (Number(tenths) < 10) return `${tenths}k`
  const thousands = Math.round(v / 1000)
  if (thousands < 1000) return `${thousands}k`
  return `${(v / 1_000_000).toFixed(1)}M`
}

const plural = (n: number, word: string): string => `${n} ${word}${n > 1 ? 's' : ''}`

const SEP: Seg = { text: ' · ', dim: true }
const BLANK: Seg[] = [{ text: ' ' }]

// The glyph of a loop status and its tone.
export function loopMark(status: ApexBandLoopStatus): Seg {
  if (status === 'running') return { text: '●', tone: 'warning' }
  if (status === 'done') return { text: '✓', tone: 'success' }
  if (status === 'failed') return { text: '✗', tone: 'error' }
  return { text: '■', tone: 'inactive' }
}

// The glyph of a shell status and its tone: killed (■) apart from failed.
export function shellMark(status: ApexBandShellStatus): Seg {
  if (status === 'running') return { text: '●', tone: 'warning' }
  if (status === 'completed') return { text: '✓', tone: 'success' }
  if (status === 'failed') return { text: '✗', tone: 'error' }
  return { text: '■', tone: 'inactive' }
}

// The shells' counts by status, non-zero only, in a fixed order (« shell »
// is masculine: finis, échoués, arrêtés).
export function shellSummary(shells: readonly ApexBandShell[]): Seg[] {
  const n = (status: ApexBandShellStatus): number => shells.filter(s => s.status === status).length
  const parts: Seg[][] = []
  const running = n('running')
  if (running > 0) parts.push([{ text: `${running} en cours`, tone: 'warning', bold: true }])
  for (const [status, word] of [
    ['completed', 'fini'],
    ['failed', 'échoué'],
    ['killed', 'arrêté'],
  ] as const) {
    const count = n(status)
    if (count > 0) parts.push([{ text: plural(count, word), tone: shellMark(status).tone }])
  }
  return join(parts)
}

// The glyph and tone of an external verdict word.
function verdictMark(verdict: string): { glyph: string; tone: ThemeKey } {
  if (verdict === 'PASS') return { glyph: '✓', tone: 'success' }
  if (verdict === 'FAIL' || verdict === 'ERROR') return { glyph: '✗', tone: 'error' }
  if (verdict === 'BLOCKED') return { glyph: '■', tone: 'warning' }
  return { glyph: '·', tone: 'inactive' }
}

// A share of BAR_CELLS cells in the brand tone, at least one cell; the rest
// of the row is left empty (no track drawn).
function shareBar(share: number): Seg[] {
  const filled = Math.max(1, Math.min(BAR_CELLS, Math.round(share * BAR_CELLS)))
  return [{ text: '━'.repeat(filled), tone: 'claude' }]
}

// The « Phases ≈ » block: one row per step, its counted tokens (cache reads
// excluded; dim — when none) and, when wide enough and the step has
// tokens, its share of the run's counted tokens.
function phaseRows(run: ApexBandRun, phases: ApexBandPhases, cols: number): Seg[][] {
  if (run.steps.length === 0) return []
  const byStep = phases.dir !== null && phases.dir === run.dir ? phases.byStep : {}
  const totals = run.steps.map(s => {
    const tally = byStep[s.step]
    return tally === undefined ? 0 : countedTotal(tally)
  })
  const sum = totals.reduce((a, b) => a + b, 0)
  const labelCells = Math.min(MAX_LABEL, Math.max(...run.steps.map(s => Array.from(stepLabel(s.step)).length)))
  const rows: Seg[][] = [[{ text: 'Phases', bold: true }, { text: ' ≈ tokens', dim: true }]]
  run.steps.forEach((step, i) => {
    const n = totals[i] ?? 0
    const label = Array.from(stepLabel(step.step)).slice(0, labelCells).join('').padEnd(labelCells)
    const row: Seg[] = [stepMark(step.kind), { text: ` ${label} `, ...(step.kind === 'running' ? { bold: true } : {}) }]
    row.push(n > 0 ? { text: fmtTokens(n).padStart(TOKEN_CELLS) } : { text: '—'.padStart(TOKEN_CELLS), dim: true })
    if (cols >= NARROW && n > 0) row.push({ text: '  ' }, ...shareBar(n / sum))
    rows.push(row)
  })
  return rows
}

// One row: glyph, label (bold while running, dim once finished), then the
// dim ` · `-joined details; the label is cut first (down to MIN_LABEL
// cells), then the details are dropped from the first, then a hard cut.
function row(mark: Seg, raw: string, isRunning: boolean, details: readonly string[], cols: number): Seg[] {
  // One line: a multiline command or description collapsed before measuring.
  const label = raw.replace(/\s+/g, ' ').trim()
  const style = isRunning ? { bold: true } : { dim: true }
  const build = (text: string, kept: readonly string[]): Seg[] => [
    mark,
    { text: ` ${text}`, ...style },
    ...(kept.length > 0 ? [{ text: ` · ${kept.join(' · ')}`, dim: true }] : []),
  ]
  const minLabel = Math.min(MIN_LABEL, textCells(label))
  for (let drop = 0; drop <= details.length; drop++) {
    const kept = details.slice(drop)
    const room = cols - width(build('', kept))
    if (room >= minLabel) return build(truncate(label, room), kept)
  }
  return hardCut(build(label, []), cols)
}

// A subagent's row: label · model · tokens (counted, cache reads aside;
// none while 0) · time. Below NARROW the model is left out.
function agentRow(loop: ApexBandLoop, now: number, cols: number): Seg[] {
  const tokens = countedTotal(loop.tally)
  const details = [
    ...(cols >= NARROW && loop.model !== undefined && loop.model !== '' ? [loop.model] : []),
    ...(tokens > 0 ? [fmtTokens(tokens)] : []),
    formatDuration(loopDuration(loop, now)),
  ]
  return row(loopMark(loop.status), loop.label ?? loop.type ?? loop.id, loop.status === 'running', details, cols)
}

// A shell's row: label · time (frozen once it ended).
function shellRow(shell: ApexBandShell, now: number, cols: number): Seg[] {
  const time = formatDuration((shell.endedAt ?? now) - shell.startedAt)
  return row(shellMark(shell.status), shell.label, shell.status === 'running', [time], cols)
}

// Running items first (oldest first), then finished ones (most recent
// first), at most MAX_DONE of them unless `showAll`, the rest counted.
function folded<T extends { startedAt: number; endedAt?: number }>(
  items: readonly T[],
  isRunning: (item: T) => boolean,
  showAll: boolean,
): { shown: T[]; hidden: number } {
  const running = items.filter(isRunning).sort((a, b) => a.startedAt - b.startedAt)
  const done = items
    .filter(i => !isRunning(i))
    .sort((a, b) => (b.endedAt ?? b.startedAt) - (a.endedAt ?? a.startedAt))
  const keep = showAll ? done.length : MAX_DONE
  return { shown: [...running, ...done.slice(0, keep)], hidden: Math.max(0, done.length - keep) }
}

const foldLine = (hidden: number): Seg[] => [{ text: `+${hidden} terminés`, dim: true }]

// The « Sous-agents » block, one line each.
function agentRows(subs: readonly ApexBandLoop[], now: number, showAll: boolean, cols: number): Seg[][] {
  const rows: Seg[][] = [[{ text: 'Sous-agents', bold: true }]]
  if (subs.length === 0) return [...rows, [{ text: 'aucun pour l’instant', dim: true }]]
  const { shown, hidden } = folded(subs, l => l.status === 'running', showAll)
  for (const loop of shown) rows.push(agentRow(loop, now, cols))
  if (hidden > 0) rows.push(foldLine(hidden))
  return rows
}

// The « Shells en arrière-plan » block: the counts, then one line each.
function shellRows(shells: readonly ApexBandShell[], now: number, showAll: boolean, cols: number): Seg[][] {
  const rows: Seg[][] = [[{ text: 'Shells en arrière-plan', bold: true }], shellSummary(shells)]
  const { shown, hidden } = folded(shells, s => s.status === 'running', showAll)
  for (const shell of shown) rows.push(shellRow(shell, now, cols))
  if (hidden > 0) rows.push(foldLine(hidden))
  return rows
}

// The « Totaux » block: main loop vs subagents (counted tokens, cache reads
// excluded), the cache reads apart (dim, when there are some), then the
// session's cost; groups that do not fit `cols` wrap onto a next line.
function totals(loops: readonly ApexBandLoop[], cost: number | null, cols: number): Seg[][] {
  const { main, sub } = splitTotals(loops)
  const cache = main.cacheRead + sub.cacheRead
  const groups: Seg[][] = [
    [{ text: 'principal ', dim: true }, { text: fmtTokens(countedTotal(main)) }],
    [{ text: 'sous-agents ', dim: true }, { text: fmtTokens(countedTotal(sub)) }],
  ]
  if (cache > 0) groups.push([{ text: `cache ${fmtTokens(cache)}`, dim: true }])
  if (cost !== null) groups.push([{ text: `$${cost.toFixed(2)}` }])
  const lines: Seg[][] = [[]]
  for (const group of groups) {
    const last = lines[lines.length - 1] ?? []
    const joined = join([last, group])
    if (last.length === 0 || width(joined) <= cols) lines[lines.length - 1] = joined
    else lines.push([...group])
  }
  return [[{ text: 'Totaux', bold: true }], ...lines]
}

// The « Vérif externe » block: the verdict toned and its findings count;
// no block at all until the run has one.
function verdictRows(verdict: ApexBandVerdict | null, run: ApexBandRun): Seg[][] {
  if (verdict === null || verdict.dir !== run.dir) return []
  const { glyph, tone } = verdictMark(verdict.verdict)
  return [
    [{ text: 'Vérif externe', bold: true }],
    [{ text: `${glyph} ${verdict.verdict}`, tone }, SEP, { text: plural(verdict.findings, 'constat'), dim: true }],
  ]
}

// The pane as lines of segments, each within max(1, cols) cells. Sections:
// Action (alerts, when there are some) · the run or its absence ·
// Sous-agents (with a run, or once one was seen) · Shells en arrière-plan
// (once one was seen) · Totaux (as Sous-agents) · Vérif externe (once the run
// has one).
export function layoutPane(input: PaneInput, cols: number): Seg[][] {
  const w = Math.max(1, cols)
  const { run } = input
  const lines: Seg[][] = []
  if (input.alerts.length > 0) {
    lines.push([{ text: 'Action', bold: true }], ...input.alerts.map(a => alertLine(a, w)), BLANK)
  }
  if (run === null) {
    lines.push(
      [{ text: 'Aucun run APEX en cours.', dim: true }],
      [{ text: 'Lancez /apex ; le détail s’affiche ici.', dim: true }],
    )
  } else {
    const metaLine = join(meta(run).map(m => m.segs))
    lines.push([{ text: `APEX · ${run.title}`, bold: true }], ...(metaLine.length > 0 ? [metaLine] : []))
    const phases = phaseRows(run, input.phases, w)
    if (phases.length > 0) lines.push(BLANK, ...phases)
  }
  const subs = input.loops.filter(l => l.id !== MAIN)
  const withAgents = run !== null || subs.length > 0
  if (withAgents) lines.push(BLANK, ...agentRows(subs, input.now, input.showAll, w))
  if (input.shells.length > 0) lines.push(BLANK, ...shellRows(input.shells, input.now, input.showAll, w))
  if (withAgents) lines.push(BLANK, ...totals(input.loops, input.cost, w))
  const verdict = run === null ? [] : verdictRows(input.verdict, run)
  if (verdict.length > 0) lines.push(BLANK, ...verdict)
  return lines.map(line => hardCut(line, w))
}
