// Pure layout of the subagents block: the main loop's rail, then one of
// three shapes by the room left.
// Cards (n ≤ MAX_CARDS, each at least CARD_MIN cells, rail + CARD_ROWS rows):
//   ╭─ ● label ──────╮
//   │ type · model   │
//   │ ctx 45k · out 3.2k │
//   ╰─ 12 steps ─ 0:41 ─╯
// Lanes (two rows or more): `● label family ` then a time axis where each
// agent's ━ bar runs from its spawn to now (● head) or its end (✓ ✗ ■),
// then its clock; the last lane counts the agents left out (+k).
// A line (one row): `● 3 agents · opus×2 haiku×1`.
// Every meaning reads from a glyph or a word; the border's tone is the
// model family's. Clocks and the rail are live segments (see Seg.live).

import type { ApexBandLoop } from '../types'
import { family, familyTone, hardCut, textCells, truncate, width } from './band.ts'
import type { Seg } from './band.ts'
import { clockText } from './elapsed.ts'
import { railFrame } from './rail.ts'
import { MAIN, TEAMMATE, isWorking, loopDuration, oneLine, shortModel } from './stats.ts'

export const MAX_CARDS = 3
export const CARD_MIN = 24
export const CARD_MAX = 36
export const CARD_ROWS = 4

// A lane's label and family columns, in cells.
const LANE_LABEL = 14
const LANE_FAMILY = 6
// An axis narrower than this drops the family column, then the axis.
const AXIS_MIN = 6
const RAIL_HEAD = '◆ main '
const SEP = ' · '

export type AgentsInput = { loops: readonly ApexBandLoop[]; now: number }
export type AgentsOptions = { numbered: boolean; includeDone: boolean }
export type AgentsMode = 'cards' | 'lanes' | 'line'
export type AgentsBlock = { mode: AgentsMode; lines: Seg[][] }

// `text` cut to `cells` and padded with spaces to exactly that many.
function pad(text: string, cells: number): string {
  const cut = truncate(text, cells)
  return cut + ' '.repeat(Math.max(0, cells - textCells(cut)))
}

// A token count made short: 950, 3.2k, 45k, 1.2M.
export function kTokens(n: number): string {
  if (n < 1000) return String(Math.max(0, Math.round(n)))
  if (n < 10_000) return `${(n / 1000).toFixed(1)}k`
  if (n < 1_000_000) return `${Math.round(n / 1000)}k`
  return `${(n / 1_000_000).toFixed(1)}M`
}

// A loop's status glyph: ● at work, ✓ done, ✗ failed, ■ stopped.
export function statusMark(loop: ApexBandLoop): Seg {
  if (loop.status === 'running') return { text: '●', tone: 'warning' }
  if (loop.status === 'done') return { text: '✓', tone: 'success' }
  if (loop.status === 'failed') return { text: '✗', tone: 'error' }
  return { text: '■', dim: true }
}

// What a loop is called: its label, else its task's head, else its type.
export function agentLabel(loop: ApexBandLoop): string {
  if (loop.label !== undefined && loop.label !== '') return oneLine(loop.label)
  if (loop.task !== undefined && loop.task !== '') return oneLine(loop.task)
  return loop.type ?? loop.id
}

// The subagents the block draws, oldest first: those at work, plus the
// listed ones that ended when `includeDone`.
export function blockLoops(loops: readonly ApexBandLoop[], includeDone: boolean): ApexBandLoop[] {
  return loops
    .filter(
      l =>
        isWorking(l) ||
        (includeDone && l.id !== MAIN && l.listed === true && l.type !== TEAMMATE && l.status !== 'running'),
    )
    .sort((a, b) => a.startedAt - b.startedAt)
}

// A loop's clock as a live segment: its running time, counting on while it runs.
export function clockSeg(loop: ApexBandLoop, now: number, style: Omit<Seg, 'text' | 'live'> = { dim: true }): Seg {
  const ms = loopDuration(loop, now)
  const running = loop.status === 'running'
  return { text: clockText(ms), ...style, live: { kind: 'clock', key: `clock:${loop.id}`, ms, running } }
}

// The rail row within `cols`: `◆ main ` then the rail, a ┬ under each drop
// column (absolute, 0 at the line's left edge); moving while `active`.
export function railLine(cols: number, drops: readonly number[], active: boolean): Seg[] {
  const head: Seg = { text: RAIL_HEAD, tone: 'claude' }
  const lead = textCells(RAIL_HEAD)
  const cells = cols - lead
  if (cells < 1) return hardCut([head], cols)
  const rel = drops.map(d => d - lead).filter(d => d >= 0 && d < cells)
  return [
    head,
    {
      text: railFrame(cells, rel, -1),
      tone: 'claude',
      live: { kind: 'rail', key: 'rail', cells, drops: rel, active, tone: 'claude' },
    },
  ]
}

// The card width for n cards in `cols`, or null when they do not fit.
export function cardWidth(n: number, cols: number): number | null {
  if (n < 1 || n > MAX_CARDS || n * CARD_MIN + (n - 1) > cols) return null
  return Math.min(CARD_MAX, Math.max(CARD_MIN, Math.floor((cols - (n - 1)) / n)))
}

// One card's four rows, each exactly `cw` cells.
function card(loop: ApexBandLoop, index: number, cw: number, now: number, numbered: boolean): Seg[][] {
  const tone = familyTone(family(loop.model))
  const inner = cw - 2
  const mark = statusMark(loop)
  // Top: ╭─ ● label ─…╮, at least one ─ before the corner.
  const titleRoom = cw - 8
  const title = truncate(`${numbered ? `${index + 1} ` : ''}${agentLabel(loop)}`, titleRoom)
  const topFill = cw - 7 - textCells(title)
  const top: Seg[] = [
    { text: '╭─ ', tone },
    mark,
    { text: ' ' },
    { text: title, bold: true },
    { text: ` ${'─'.repeat(Math.max(0, topFill))}╮`, tone },
  ]
  const body = (text: string, dim: boolean): Seg[] => [
    { text: '│ ', tone },
    { text: pad(text, inner - 2), ...(dim ? { dim: true } : {}) },
    { text: ' │', tone },
  ]
  const model = loop.model === undefined ? '' : `${SEP}${shortModel(loop.model)}`
  const ctx = loop.context === undefined ? 'ctx –' : `ctx ${kTokens(loop.context)}`
  // Bottom: ╰─ 12 steps ─…─ 0:41 ─╯.
  const clock = clockSeg(loop, now, { tone })
  const steps = truncate(`${loop.steps} step${loop.steps > 1 ? 's' : ''}`, Math.max(0, cw - 14))
  const botFill = cw - 13 - textCells(steps)
  const bottom: Seg[] = [
    { text: '╰─ ', tone },
    { text: steps, dim: true },
    { text: ` ${'─'.repeat(Math.max(0, botFill))} `, tone },
    clock,
    { text: ' ─╯', tone },
  ]
  return [top, body(`${loop.type ?? 'agent'}${model}`, true), body(`${ctx}${SEP}out ${kTokens(loop.tally.output)}`, false), bottom]
}

// Cards side by side, one space apart; the rail's drops at their centres.
function cards(list: readonly ApexBandLoop[], cw: number, cols: number, now: number, opts: AgentsOptions): Seg[][] {
  const rows: Seg[][] = [[], [], [], []]
  list.forEach((loop, i) => {
    card(loop, i, cw, now, opts.numbered).forEach((segs, r) => {
      const row = rows[r]
      if (row === undefined) return
      if (i > 0) row.push({ text: ' ' })
      row.push(...segs)
    })
  })
  const drops = list.map((_, i) => i * (cw + 1) + Math.floor(cw / 2))
  return [railLine(cols, drops, list.some(isWorking)), ...rows]
}

// The lanes' shared time axis: from the oldest spawn to now.
type Axis = { t0: number; span: number; w: number }

// A lane's bar over the axis: blank before its spawn, ━ while it lived, its
// status glyph at its last cell; `from` is its first cell.
function bar(loop: ApexBandLoop, axis: Axis, now: number): { segs: Seg[]; from: number } {
  const { t0, span, w } = axis
  const from = Math.min(w - 1, Math.max(0, Math.floor(((Math.max(loop.startedAt, t0) - t0) / span) * w)))
  const end = loop.status === 'running' ? now : (loop.endedAt ?? now)
  const to = Math.min(w, Math.max(from + 1, Math.ceil(((end - t0) / span) * w)))
  const tone = familyTone(family(loop.model))
  const mark = statusMark(loop)
  const segs: Seg[] = []
  if (from > 0) segs.push({ text: ' '.repeat(from) })
  if (to - from > 1) segs.push({ text: '━'.repeat(to - from - 1), tone })
  segs.push(mark)
  if (w - to > 0) segs.push({ text: ' '.repeat(w - to) })
  return { segs, from }
}

// Lanes in `rows` rows (the rail one of them): the first rows − 1 agents,
// the last lane drawn counting the others (+k).
function lanes(list: readonly ApexBandLoop[], cols: number, rows: number, now: number, opts: AgentsOptions): Seg[][] {
  const shown = list.slice(0, Math.max(1, rows - 1))
  const left = list.length - shown.length
  const t0 = Math.min(...list.map(l => l.startedAt))
  const tEnd = Math.max(now, ...list.map(l => (l.status === 'running' ? now : (l.endedAt ?? now))))
  const num = opts.numbered ? 2 : 0
  const more = left > 0 ? ` +${left}` : ''
  // Head: [n ]● label(14) [family(6) ]; tail: ` 0:41` [+k].
  const tail = 1 + 5 + more.length
  let showFamily = true
  let w = cols - (num + 2 + LANE_LABEL + 1 + LANE_FAMILY + 1) - tail
  if (w < AXIS_MIN) {
    showFamily = false
    w = cols - (num + 2 + LANE_LABEL + 1) - tail
  }
  const showAxis = w >= AXIS_MIN
  const axis: Axis = { t0, span: Math.max(1, tEnd - t0), w: Math.max(1, w) }
  const lead = num + 2 + LANE_LABEL + 1 + (showFamily ? LANE_FAMILY + 1 : 0)
  const drops: number[] = []
  const out = shown.map((loop, i): Seg[] => {
    const name = family(loop.model)
    const line: Seg[] = []
    if (opts.numbered) line.push({ text: `${i + 1} `, bold: true })
    line.push(statusMark(loop), { text: ' ' }, { text: `${pad(agentLabel(loop), LANE_LABEL)} ` })
    if (showFamily) line.push({ text: `${pad(name, LANE_FAMILY)} `, tone: familyTone(name) })
    if (showAxis) {
      const drawn = bar(loop, axis, now)
      drops.push(lead + drawn.from)
      line.push(...drawn.segs)
    }
    line.push({ text: ' ' }, clockSeg(loop, now))
    if (i === shown.length - 1 && more !== '') line.push({ text: more, dim: true })
    return width(line) <= cols ? line : hardCut(line, cols)
  })
  return [railLine(cols, drops, list.some(isWorking)), ...out]
}

// One line: `● 3 agents · opus×2 haiku×1`, the families dropped when it is
// too wide, then a hard cut.
export function agentsLine(list: readonly ApexBandLoop[], cols: number): Seg[] {
  if (list.length === 0) return []
  const counts = new Map<string, number>()
  for (const loop of list) {
    const name = family(loop.model)
    counts.set(name, (counts.get(name) ?? 0) + 1)
  }
  const head: Seg[] = [
    { text: '●', tone: list.some(isWorking) ? 'warning' : 'success' },
    { text: ` ${list.length} agent${list.length > 1 ? 's' : ''}` },
  ]
  const fams = [...counts].flatMap(([name, n], i): Seg[] => [
    ...(i > 0 ? [{ text: ' ' }] : []),
    { text: `${name}×${n}`, tone: familyTone(name) },
  ])
  const full: Seg[] = [...head, { text: SEP, dim: true }, ...fams]
  if (width(full) <= cols) return full
  return width(head) <= cols ? head : hardCut(head, cols)
}

// The block within `cols` and `rows`: cards when they fit (rail + 4 rows),
// else lanes (two rows or more), else one line; no line without an agent.
export function layoutAgents(input: AgentsInput, cols: number, rows: number, opts: AgentsOptions): AgentsBlock {
  const list = blockLoops(input.loops, opts.includeDone)
  const w = Math.max(1, cols)
  if (list.length === 0 || rows < 1) return { mode: 'line', lines: [] }
  const cw = cardWidth(list.length, w)
  if (cw !== null && rows >= 1 + CARD_ROWS) return { mode: 'cards', lines: cards(list, cw, w, input.now, opts) }
  if (rows >= 2) return { mode: 'lanes', lines: lanes(list, w, rows, input.now, opts) }
  return { mode: 'line', lines: [agentsLine(list, w)] }
}
