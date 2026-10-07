// Pure layout of the /apex-pane pane: the run's header, its phases with
// approximate token counts, one three-line card per subagent, the totals and
// the external verdict once there is one. Every line fits `cols` cells (hard
// cut otherwise); below 40 columns the share bar and the card's type and
// model are dropped.

import type { ThemeKey } from 'claude-code'

import type { ApexBandLoop, ApexBandLoopStatus, ApexBandPhases, ApexBandRun, ApexBandVerdict } from '../types'
import { hardCut, join, meta, stepLabel, stepMark, width } from './band.ts'
import type { Seg } from './band.ts'
import { MAIN, countedTotal, loopDuration, splitTotals } from './stats.ts'

export type PaneInput = {
  run: ApexBandRun | null
  loops: readonly ApexBandLoop[]
  phases: ApexBandPhases
  now: number
  cost: number | null
  verdict: ApexBandVerdict | null
}

// Columns under which the bar and the card's type and model are dropped.
export const NARROW = 40
// Finished cards shown before the « +N terminés » line.
export const MAX_DONE = 6
const BAR_CELLS = 10
const TOKEN_CELLS = 6
const MAX_LABEL = 12

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

// A card's detail lines. From NARROW: line A model · duration · in X · out Y
// (in = input + cache writes), line B type · tool · N appels · cache X (when
// any cache read); below NARROW one line tool · duration.
function cardDetail(loop: ApexBandLoop, now: number, cols: number): string[] {
  const dur = formatDuration(loopDuration(loop, now))
  const parts = (list: readonly (string | undefined)[]): string =>
    list.filter((p): p is string => p !== undefined && p !== '').join(' · ')
  if (cols < NARROW) return [parts([loop.tool, dur])]
  const { input, output, cacheRead, cacheWrite } = loop.tally
  return [
    parts([loop.model, dur, `in ${fmtTokens(input + cacheWrite)}`, `out ${fmtTokens(output)}`]),
    parts([loop.type, loop.tool, plural(loop.calls, 'appel'), cacheRead > 0 ? `cache ${fmtTokens(cacheRead)}` : undefined]),
  ]
}

// One subagent's card: glyph and label (bold while running), then its dim
// detail lines; a finished card is dim throughout.
function card(loop: ApexBandLoop, now: number, cols: number): Seg[][] {
  const running = loop.status === 'running'
  const label = loop.label ?? loop.type ?? loop.id
  const head: Seg[] = [loopMark(loop.status), running ? { text: ` ${label}`, bold: true } : { text: ` ${label}`, dim: true }]
  return [head, ...cardDetail(loop, now, cols).map(detail => [{ text: `  ${detail}`, dim: true }])]
}

// The « Sous-agents » block: running cards (oldest first), then finished
// ones (most recent first), at most MAX_DONE of them, the rest counted.
function cards(loops: readonly ApexBandLoop[], now: number, cols: number): Seg[][] {
  const subs = loops.filter(l => l.id !== MAIN)
  const rows: Seg[][] = [[{ text: 'Sous-agents', bold: true }]]
  if (subs.length === 0) return [...rows, [{ text: 'aucun pour l’instant', dim: true }]]
  const running = subs.filter(l => l.status === 'running').sort((a, b) => a.startedAt - b.startedAt)
  const done = subs
    .filter(l => l.status !== 'running')
    .sort((a, b) => (b.endedAt ?? b.startedAt) - (a.endedAt ?? a.startedAt))
  for (const loop of running) rows.push(...card(loop, now, cols))
  for (const loop of done.slice(0, MAX_DONE)) rows.push(...card(loop, now, cols))
  if (done.length > MAX_DONE) rows.push([{ text: `+${done.length - MAX_DONE} terminés`, dim: true }])
  return rows
}

// The « Totaux » block: main loop vs subagents (counted tokens, cache reads
// excluded), the cache reads apart (dim, when any), then the session's cost;
// groups that do not fit `cols` wrap onto a next line.
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

// The pane as lines of segments, each within max(1, cols) cells.
export function layoutPane(input: PaneInput, cols: number): Seg[][] {
  const w = Math.max(1, cols)
  const { run } = input
  if (run === null) {
    return [
      [{ text: 'Aucun run APEX en cours.', dim: true }],
      [{ text: 'Lancez /apex ; le détail s’affiche ici.', dim: true }],
    ].map(line => hardCut(line, w))
  }
  const metaLine = join(meta(run).map(m => m.segs))
  const lines: Seg[][] = [
    [{ text: `APEX · ${run.title}`, bold: true }],
    ...(metaLine.length > 0 ? [metaLine] : []),
  ]
  const phases = phaseRows(run, input.phases, w)
  if (phases.length > 0) lines.push(BLANK, ...phases)
  lines.push(BLANK, ...cards(input.loops, input.now, w))
  lines.push(BLANK, ...totals(input.loops, input.cost, w))
  const verdict = verdictRows(input.verdict, run)
  if (verdict.length > 0) lines.push(BLANK, ...verdict)
  return lines.map(line => hardCut(line, w))
}
