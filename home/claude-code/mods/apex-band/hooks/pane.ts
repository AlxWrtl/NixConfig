// Pure layout of the APEX detail pane (/apex-pane, alias /task-board), in
// sections each opened by a `── Name ───` rule:
//   1 Action     what asks the user to act (only when something does)
//   2 Principal  the main loop's model · effort, its context gauge
//                (▰▱, percent, tokens/window, ⟲ compactions), the cost and
//                the rate-limit windows (percent, ↻ reset)
//   3 Run        the run's header and its phases with approximate tokens
//   4 Agents     the main loop's rail, then numbered cards or lanes over the
//                subagents at work and the listed ones ended (1-6, the
//                pane's hotkeys); the expanded one's task, last tools and
//                answer head below
//   5 Boucles    loops no agent list names (forks, workflow agents,
//                teammates), with their ⟲ step counts
//   6 Reçu       the turn under way (● live) or the last one: duration ·
//                agents · edits · errors · +$Δ
//   7 Journal    the last JOURNAL_ROWS entries, newest last, glyph and age
//   8 Shells en arrière-plan / Totaux / Vérif externe
// Finished agents, loops and shells past MAX_DONE fold into « +N terminés »
// unless `showAll`. Every line fits `cols` cells (hard cut otherwise); below
// NARROW the gauge shrinks to GAUGE_NARROW cells, the share bar goes, and
// the agents read as numbered rows (no model, no lanes).

import type { ThemeKey } from 'claude-code'

import type {
  ApexBandAlert,
  ApexBandGauge,
  ApexBandLimit,
  ApexBandLogEntry,
  ApexBandLogKind,
  ApexBandLoop,
  ApexBandLoopStatus,
  ApexBandPhases,
  ApexBandReceipt,
  ApexBandReceipts,
  ApexBandRun,
  ApexBandShell,
  ApexBandShellStatus,
  ApexBandVerdict,
} from '../types'
import { agentLabel, blockLoops, clockSeg, kTokens, layoutAgents, statusMark } from './agents.ts'
import {
  alertLine,
  cellWidth,
  hardCut,
  join,
  meta,
  stepLabel,
  stepMark,
  textCells,
  truncate,
  width,
} from './band.ts'
import type { Seg } from './band.ts'
import { clockText } from './elapsed.ts'
import { compactionCount } from './journal.ts'
import { MAIN, countedTotal, loopDuration, oneLine, pathTail, reasonStatus, shortModel, splitTotals } from './stats.ts'

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
  // The session's model ($.session.model()), null when unknown.
  model: string | null
  gauge: ApexBandGauge | null
  receipts: ApexBandReceipts
  log: readonly ApexBandLogEntry[]
  compactions: Record<string, number>
  // The agent whose block is expanded, or null.
  expanded: string | null
}

// Columns under which the gauge shrinks, the share bar goes and the agents
// read as numbered rows.
export const NARROW = 40
// Finished agents, loops and shells (each apart) shown before the fold.
export const MAX_DONE = 6
// Agents numbered for the pane's hotkeys (1-6).
export const MAX_HOTKEYS = 6
// Journal entries shown, newest last.
export const JOURNAL_ROWS = 8
// The context gauge's cells, and below NARROW.
export const GAUGE_CELLS = 10
export const GAUGE_NARROW = 5
// The expanded block: task rows, answer rows at most.
export const TASK_ROWS = 6
export const ANSWER_ROWS = 3
const BAR_CELLS = 10
const TOKEN_CELLS = 6
const MAX_LABEL = 12
// A cut label keeps at least this many cells before the detail shrinks.
const MIN_LABEL = 10
// The expanded block's indent and its label column.
const INDENT = '  '
const TAG_CELLS = 8

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

// A short age: 12s, 3m, 2h, 4j.
export function age(ms: number): string {
  const seconds = Math.floor(Math.max(0, ms) / 1000)
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  return hours < 24 ? `${hours}h` : `${Math.floor(hours / 24)}j`
}

// Time left before a reset: 12m, 1h05, 3j04h.
export function countdown(ms: number): string {
  const minutes = Math.max(0, Math.ceil(ms / 60_000))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h${pad2(minutes % 60)}`
  return `${Math.floor(hours / 24)}j${pad2(hours % 24)}h`
}

const plural = (n: number, word: string): string => `${n} ${word}${n > 1 ? 's' : ''}`

const SEP: Seg = { text: ' · ', dim: true }

// A section's rule: `── Name ───…` across `cols` (the name bold).
export function rule(name: string, cols: number): Seg[] {
  const head: Seg[] = [{ text: '── ', dim: true }, { text: name, bold: true }, { text: ' ', dim: true }]
  const fill = cols - width(head)
  if (fill < 0) return hardCut(head, cols)
  return [...head, { text: '─'.repeat(fill), dim: true }]
}

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

// The journal glyph of each entry kind and its tone.
const LOG_MARKS: Record<ApexBandLogKind, Seg> = {
  prompt: { text: '›', tone: 'claude' },
  spawn: { text: '┬', tone: 'suggestion' },
  done: { text: '✓', tone: 'success' },
  edit: { text: '✎', tone: 'permission' },
  error: { text: '✗', tone: 'error' },
  compact: { text: '⟲', tone: 'warning' },
}

// A percent's tone: past 90 red, past 70 amber, else the brand's.
const pctTone = (pct: number): ThemeKey => (pct >= 90 ? 'error' : pct >= 70 ? 'warning' : 'claude')

// A percent as 34% or 7.5% (one decimal under 10).
const pctText = (pct: number): string => `${pct < 10 && !Number.isInteger(pct) ? pct.toFixed(1) : Math.round(pct)}%`

// `text` wrapped on words into rows of at most `cols` cells, at most `max`
// rows (the last ending … when cut); a word wider than a row is split.
export function wrap(text: string, cols: number, max: number): string[] {
  const w = Math.max(1, cols)
  const rows: string[] = []
  let line = ''
  let cells = 0
  const push = (): void => {
    rows.push(line)
    line = ''
    cells = 0
  }
  for (const word of oneLine(text).split(' ')) {
    if (word === '') continue
    const wordCells = textCells(word)
    if (cells > 0 && cells + 1 + wordCells <= w) {
      line += ` ${word}`
      cells += 1 + wordCells
      continue
    }
    if (cells > 0) push()
    if (wordCells <= w) {
      line = word
      cells = wordCells
      continue
    }
    // A word wider than a row: split on code points.
    for (const cp of Array.from(word)) {
      const c = cellWidth(cp.codePointAt(0) ?? 0)
      if (cells + c > w) push()
      line += cp
      cells += c
    }
  }
  if (cells > 0) push()
  if (rows.length <= max) return rows
  const kept = rows.slice(0, Math.max(1, max))
  const last = kept.length - 1
  kept[last] = truncate(`${kept[last] ?? ''} …`, w).replace(/ …$/, '…')
  return kept
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
  const label = oneLine(raw)
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

// ── 2 Principal ─────────────────────────────────────────────────────────

// The context gauge: `ctx ▰▰▰▱▱▱▱▱▱▱ 34% 68k/200k ⟲2`; `ctx –` unread.
function gaugeLine(gauge: ApexBandGauge | null, compactions: number, cols: number): Seg[] {
  const line: Seg[] = [{ text: 'ctx ', dim: true }]
  if (gauge === null || gauge.percent === null) line.push({ text: '–', dim: true })
  else {
    const cells = cols < NARROW ? GAUGE_NARROW : GAUGE_CELLS
    const pct = Math.max(0, gauge.percent)
    const filled = Math.max(0, Math.min(cells, Math.round((pct / 100) * cells)))
    const tone = pctTone(pct)
    line.push(
      { text: '▰'.repeat(filled), tone },
      { text: '▱'.repeat(cells - filled), dim: true },
      { text: ` ${pctText(pct)}`, tone },
    )
    if (gauge.tokens !== null && gauge.window > 0)
      line.push({ text: ` ${fmtTokens(gauge.tokens)}/${fmtTokens(gauge.window)}`, dim: true })
  }
  if (compactions > 0) line.push({ text: ` ⟲${compactions}`, tone: 'warning' })
  return line
}

// A rate-limit window's short name: five_hour → 5h, seven_day → 7j.
function limitName(kind: string): string {
  if (kind === 'five_hour') return '5h'
  if (kind === 'seven_day') return '7j'
  if (kind === 'spend_limit') return 'dépense'
  return kind.replace(/_/g, ' ')
}

// One window: `5h 42% ↻1h12` (no countdown when the reset is unknown or past).
function limitGroup(limit: ApexBandLimit, now: number): Seg[] {
  const group: Seg[] = [{ text: `${limitName(limit.kind)} `, dim: true }, { text: pctText(limit.percent), tone: pctTone(limit.percent) }]
  if (limit.resetsAt !== undefined && limit.resetsAt > now)
    group.push({ text: ` ↻${countdown(limit.resetsAt - now)}`, dim: true })
  return group
}

// Groups joined by ` · ` onto as few lines of `cols` as they fit.
function flow(groups: readonly Seg[][], cols: number): Seg[][] {
  const lines: Seg[][] = [[]]
  for (const group of groups) {
    const last = lines[lines.length - 1] ?? []
    const joined = join([last, group])
    if (last.length === 0 || width(joined) <= cols) lines[lines.length - 1] = joined
    else lines.push([...group])
  }
  return lines.filter(l => l.length > 0)
}

// The « Principal » section: model · effort · cost, the gauge, the limits;
// no section when nothing of it is known.
function principalRows(input: PaneInput, cols: number): Seg[][] {
  const main = input.loops.find(l => l.id === MAIN)
  const model = input.model ?? main?.model ?? null
  const head: Seg[][] = []
  if (model !== null && model !== '') head.push([{ text: '◆ ', tone: 'claude' }, { text: shortModel(model), bold: true }])
  if (main?.effort !== undefined && main.effort !== '') head.push([{ text: 'effort ', dim: true }, { text: main.effort }])
  if (input.cost !== null) head.push([{ text: `$${input.cost.toFixed(2)}` }])
  const count = compactionCount(input.compactions)
  if (head.length === 0 && input.gauge === null && count === 0) return []
  const limits = (input.gauge?.limits ?? []).map(l => limitGroup(l, input.now))
  return [...flow(head, cols), gaugeLine(input.gauge, count, cols), ...flow(limits, cols)]
}

// ── 3 Run ───────────────────────────────────────────────────────────────

function runRows(input: PaneInput, cols: number): Seg[][] {
  const { run } = input
  if (run === null) return [[{ text: 'Aucun run APEX en cours.', dim: true }]]
  const metaLine = join(meta(run).map(m => m.segs))
  const phases = phaseRows(run, input.phases, cols)
  return [[{ text: `APEX · ${run.title}`, bold: true }], ...(metaLine.length > 0 ? [metaLine] : []), ...phases]
}

// ── 4 Agents ────────────────────────────────────────────────────────────

// The agents the section draws, in their numbered order (oldest first):
// those at work, and the listed ones ended — the MAX_DONE most recent
// unless `showAll`; how many ended ones are left out.
function paneAgents(input: PaneInput): { list: ApexBandLoop[]; hidden: number } {
  const all = blockLoops(input.loops, true)
  const { shown, hidden } = folded(all, l => l.status === 'running', input.showAll)
  return { list: blockLoops(shown, true), hidden }
}

// The pane's digit hotkeys: the first MAX_HOTKEYS agents, numbered as drawn.
export function paneHotkeys(input: PaneInput): { n: number; id: string }[] {
  return paneAgents(input)
    .list.slice(0, MAX_HOTKEYS)
    .map((loop, i) => ({ n: i + 1, id: loop.id }))
}

// Below NARROW, one numbered row per agent: `1 ● label · 4.5k  1:05`.
function narrowAgent(loop: ApexBandLoop, n: number, now: number, cols: number): Seg[] {
  const tokens = countedTotal(loop.tally)
  const clock = clockSeg(loop, now)
  const tail: Seg[] = [...(tokens > 0 ? [{ text: ` · ${fmtTokens(tokens)}`, dim: true }] : []), { text: ' ' }, clock]
  const head: Seg[] = [{ text: `${n} `, bold: true }, statusMark(loop), { text: ' ' }]
  const room = cols - width(head) - width(tail)
  const label: Seg = { text: truncate(agentLabel(loop), room), ...(loop.status === 'running' ? { bold: true } : { dim: true }) }
  return room >= Math.min(MIN_LABEL, textCells(agentLabel(loop))) ? [...head, label, ...tail] : hardCut([...head, label], cols)
}

// A tagged block of the expanded agent: `  tâche   first row`, then the
// next rows under the first; the tag on its own row when too narrow.
function tagged(tag: string, rows: readonly string[], cols: number, style: Omit<Seg, 'text'> = {}): Seg[][] {
  if (rows.length === 0) return []
  const lead = textCells(INDENT) + TAG_CELLS
  return rows.map((text, i): Seg[] => [
    { text: i === 0 ? `${INDENT}${tag.padEnd(TAG_CELLS)}` : ' '.repeat(lead), dim: true },
    { text: truncate(text, cols - lead), ...style },
  ])
}

// The expanded agent: `▾ 2 label · type · model`, its task (≤ TASK_ROWS
// rows), its last tools, its answer head (≤ ANSWER_ROWS rows).
function expandedRows(loop: ApexBandLoop, n: number, cols: number): Seg[][] {
  const room = Math.max(1, cols - textCells(INDENT) - TAG_CELLS)
  const head: Seg[] = [
    { text: `▾ ${n} `, bold: true },
    { text: agentLabel(loop), bold: true },
    ...(loop.type === undefined ? [] : [SEP, { text: loop.type, dim: true }]),
    ...(loop.model === undefined || cols < NARROW ? [] : [SEP, { text: shortModel(loop.model), dim: true }]),
  ]
  const task = loop.task === undefined || loop.task === '' ? [] : wrap(loop.task, room, TASK_ROWS)
  const tools = (loop.recent ?? []).map(u => (u.target === undefined ? u.tool : `${u.tool} ${oneLine(u.target)}`))
  const answer = loop.answer === undefined || loop.answer === '' ? [] : wrap(loop.answer, room, ANSWER_ROWS)
  const body = [...tagged('tâche', task, cols), ...tagged('outils', tools, cols, { dim: true }), ...tagged('réponse', answer, cols)]
  return [head, ...(body.length > 0 ? body : [[{ text: `${INDENT}rien à détailler pour l’instant`, dim: true }]])]
}

function agentSection(input: PaneInput, cols: number): Seg[][] {
  const { list, hidden } = paneAgents(input)
  if (list.length === 0) return [[{ text: 'aucun pour l’instant', dim: true }]]
  const lines: Seg[][] =
    cols < NARROW
      ? list.map((loop, i) => narrowAgent(loop, i + 1, input.now, cols))
      : layoutAgents({ loops: list, now: input.now }, cols, Math.max(5, list.length + 1), {
          numbered: true,
          includeDone: true,
        }).lines
  if (hidden > 0) lines.push(foldLine(hidden))
  const at = input.expanded === null ? -1 : list.findIndex(l => l.id === input.expanded)
  const open = list[at]
  if (open !== undefined && at < MAX_HOTKEYS) lines.push(...expandedRows(open, at + 1, cols))
  return lines
}

// ── 5 Boucles ───────────────────────────────────────────────────────────

// Loops the agents section leaves out: no agent list names them (forks,
// workflow agents) or teammates. Each: mark label · ⟲ steps · tokens · time.
function loopSection(input: PaneInput, cols: number): Seg[][] {
  const named = new Set(blockLoops(input.loops, true).map(l => l.id))
  const others = input.loops.filter(l => l.id !== MAIN && !named.has(l.id))
  if (others.length === 0) return []
  const { shown, hidden } = folded(others, l => l.status === 'running', input.showAll)
  const rows = shown.map(loop => {
    const tokens = countedTotal(loop.tally)
    const details = [
      `⟲ ${loop.steps}`,
      ...(tokens > 0 ? [fmtTokens(tokens)] : []),
      formatDuration(loopDuration(loop, input.now)),
    ]
    return row(loopMark(loop.status), agentLabel(loop), loop.status === 'running', details, cols)
  })
  return hidden > 0 ? [...rows, foldLine(hidden)] : rows
}

// ── 6 Reçu ──────────────────────────────────────────────────────────────

// The turn under way (● and its live clock) or the last one (✓ ✗ ■ and its
// duration): agents · edits · errors · +$Δ; then the edited files' tails.
function receiptRows(receipts: ApexBandReceipts, now: number, cost: number | null, cols: number): Seg[][] {
  const live = receipts.current
  const r: ApexBandReceipt | null = live ?? receipts.last
  if (r === null) return []
  const head: Seg[] = []
  if (live !== null) {
    const ms = Math.max(0, now - live.startedAt)
    head.push(
      { text: '●', tone: 'warning' },
      { text: ' en cours ', bold: true },
      { text: clockText(ms), dim: true, live: { kind: 'clock', key: `clock:turn:${live.turnId}`, ms, running: true } },
    )
  } else {
    const status = reasonStatus(r.reason ?? 'answer')
    head.push(loopMark(status), { text: ' dernier tour ', bold: true }, { text: formatDuration(r.durationMs ?? 0), dim: true })
  }
  const delta =
    r.costDelta ?? (live !== null && cost !== null && live.costAtStart !== null ? Math.max(0, cost - live.costAtStart) : null)
  const groups: Seg[][] = [
    head,
    [{ text: plural(r.agents.length, 'agent'), dim: r.agents.length === 0 }],
    [{ text: plural(r.edits.length, 'édition'), dim: r.edits.length === 0 }],
    [{ text: plural(r.errors, 'erreur'), ...(r.errors > 0 ? { tone: 'error' as const } : { dim: true }) }],
    ...(delta === null ? [] : [[{ text: `+$${delta.toFixed(2)}` }]]),
  ]
  const lines = flow(groups, cols)
  if (r.edits.length > 0) {
    const tails = r.edits.slice(-3).map(pathTail).join(', ')
    const more = r.edits.length > 3 ? ` +${r.edits.length - 3}` : ''
    lines.push([{ text: '✎ ', tone: 'permission' }, { text: `${tails}${more}`, dim: true }])
  }
  return lines
}

// ── 7 Journal ───────────────────────────────────────────────────────────

// The last JOURNAL_ROWS entries, newest last: `  3m ┬ text`.
function journalRows(log: readonly ApexBandLogEntry[], now: number, cols: number): Seg[][] {
  return log.slice(-JOURNAL_ROWS).map((entry): Seg[] => {
    const head: Seg[] = [{ text: `${age(now - entry.at).padStart(3)} `, dim: true }, LOG_MARKS[entry.kind], { text: ' ' }]
    return [...head, { text: truncate(oneLine(entry.text), cols - width(head)) }]
  })
}

// ── 8 Shells / Totaux / Vérif externe ───────────────────────────────────

// A shell's row: label · time (frozen once it ended).
function shellRow(shell: ApexBandShell, now: number, cols: number): Seg[] {
  const time = formatDuration((shell.endedAt ?? now) - shell.startedAt)
  return row(shellMark(shell.status), shell.label, shell.status === 'running', [time], cols)
}

// The shells: the counts, then one line each.
function shellRows(shells: readonly ApexBandShell[], now: number, showAll: boolean, cols: number): Seg[][] {
  const rows: Seg[][] = [shellSummary(shells)]
  const { shown, hidden } = folded(shells, s => s.status === 'running', showAll)
  for (const shell of shown) rows.push(shellRow(shell, now, cols))
  if (hidden > 0) rows.push(foldLine(hidden))
  return rows
}

// Main loop vs subagents (counted tokens, cache reads excluded), the cache
// reads apart (dim, when there are some), then the session's cost; groups
// that do not fit `cols` wrap onto a next line.
function totals(loops: readonly ApexBandLoop[], cost: number | null, cols: number): Seg[][] {
  const { main, sub } = splitTotals(loops)
  const cache = main.cacheRead + sub.cacheRead
  const groups: Seg[][] = [
    [{ text: 'principal ', dim: true }, { text: fmtTokens(countedTotal(main)) }],
    [{ text: 'sous-agents ', dim: true }, { text: fmtTokens(countedTotal(sub)) }],
  ]
  if (cache > 0) groups.push([{ text: `cache ${fmtTokens(cache)}`, dim: true }])
  if (cost !== null) groups.push([{ text: `$${cost.toFixed(2)}` }])
  return flow(groups, cols)
}

// The verdict toned and its findings count; none until the run has one.
function verdictRows(verdict: ApexBandVerdict | null, run: ApexBandRun | null): Seg[][] {
  if (run === null || verdict === null || verdict.dir !== run.dir) return []
  const { glyph, tone } = verdictMark(verdict.verdict)
  return [[{ text: `${glyph} ${verdict.verdict}`, tone }, SEP, { text: plural(verdict.findings, 'constat'), dim: true }]]
}

// The pane as lines of segments, each within max(1, cols) cells: the
// sections that have something to show, in order, each under its rule.
// Nothing at all to show: the two-line empty state.
export function layoutPane(input: PaneInput, cols: number): Seg[][] {
  const w = Math.max(1, cols)
  const { run } = input
  const subs = input.loops.filter(l => l.id !== MAIN)
  const withAgents = run !== null || subs.length > 0
  const sections: [string, Seg[][]][] = [
    ['Action', input.alerts.map(a => alertLine(a, w))],
    ['Principal', principalRows(input, w)],
    ['Run', run !== null || withAgents ? runRows(input, w) : []],
    ['Agents', withAgents ? agentSection(input, w) : []],
    ['Boucles', loopSection(input, w)],
    ['Reçu', receiptRows(input.receipts, input.now, input.cost, w)],
    ['Journal', journalRows(input.log, input.now, w)],
    ['Shells en arrière-plan', input.shells.length > 0 ? shellRows(input.shells, input.now, input.showAll, w) : []],
    ['Totaux', withAgents ? totals(input.loops, input.cost, w) : []],
    ['Vérif externe', verdictRows(input.verdict, run)],
  ]
  const lines: Seg[][] = []
  for (const [name, rows] of sections) if (rows.length > 0) lines.push(rule(name, w), ...rows)
  if (lines.length === 0)
    return [
      [{ text: 'Aucun run APEX en cours.', dim: true }],
      [{ text: 'Lancez /apex ; le détail s’affiche ici.', dim: true }],
    ].map(line => hardCut(line, w))
  return lines.map(line => hardCut(line, w))
}
