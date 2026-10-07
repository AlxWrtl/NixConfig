// Pure layout of the band: at most two lines of styled segments, each line
// fitting `cols` cells. Line 1 is the head (`APEX · <title>`) and the step
// bar; mode, branch and baseline follow it when they fit, else go to line 2.
// Widths are counted in terminal cells by an approximation (cellWidth): CJK,
// pictographs and BMP default-emoji symbols (⌚ ✅ ⭐) count 2, joiners, VS16
// and combining accents 0, the rest 1. Still an approximation: a text symbol
// promoted to emoji by VS16 (☀️) counts 1, and a grapheme the table
// misjudges (rare scripts, flag pairs) may be off.

import type { ThemeKey } from 'claude-code'

import type { ApexBandRun, ApexBandStep, ApexBandStepKind } from '../types'

// One run of text drawn with one style; index.tsx maps it to a Text.
export type Seg = { text: string; tone?: ThemeKey; dim?: boolean; bold?: boolean }

const SEP = ' · '
const HEAD = `APEX${SEP}`
// A truncated title keeps at least this many cells before the bar shrinks.
const MIN_TITLE = 8

// Code points of `text`, so a surrogate pair is never split.
const points = (text: string): string[] => Array.from(text)

// Code point ranges drawn two cells wide: Hangul Jamo, CJK and Yi, Hangul
// syllables, CJK compatibility, vertical and full-width forms, BMP symbols
// with default emoji presentation (Emoji_Presentation=Yes), the emoji of
// the 1F000–1F2FF blocks, emoji and pictographs, CJK extensions B and beyond.
// The band's own glyphs (✓ ✗ ● ○ ■ – › · █ ░ …) stay outside, one cell.
const WIDE: readonly (readonly [number, number])[] = [
  [0x1100, 0x115f],
  [0x231a, 0x231b],
  [0x23e9, 0x23ec],
  [0x23f0, 0x23f0],
  [0x23f3, 0x23f3],
  [0x25fd, 0x25fe],
  [0x2614, 0x2615],
  [0x2648, 0x2653],
  [0x267f, 0x267f],
  [0x2693, 0x2693],
  [0x26a1, 0x26a1],
  [0x26aa, 0x26ab],
  [0x26bd, 0x26be],
  [0x26c4, 0x26c5],
  [0x26ce, 0x26ce],
  [0x26d4, 0x26d4],
  [0x26ea, 0x26ea],
  [0x26f2, 0x26f3],
  [0x26f5, 0x26f5],
  [0x26fa, 0x26fa],
  [0x26fd, 0x26fd],
  [0x2705, 0x2705],
  [0x270a, 0x270b],
  [0x2728, 0x2728],
  [0x274c, 0x274c],
  [0x274e, 0x274e],
  [0x2753, 0x2755],
  [0x2757, 0x2757],
  [0x2795, 0x2797],
  [0x27b0, 0x27b0],
  [0x27bf, 0x27bf],
  [0x2b1b, 0x2b1c],
  [0x2b50, 0x2b50],
  [0x2b55, 0x2b55],
  [0x2e80, 0xa4cf],
  [0xac00, 0xd7a3],
  [0xf900, 0xfaff],
  [0xfe30, 0xfe4f],
  [0xff00, 0xff60],
  [0xffe0, 0xffe6],
  [0x1f004, 0x1f004],
  [0x1f0cf, 0x1f0cf],
  [0x1f18e, 0x1f18e],
  [0x1f191, 0x1f19a],
  [0x1f200, 0x1f2ff],
  [0x1f300, 0x1faff],
  [0x20000, 0x3fffd],
]

// The cells a code point takes (approximation): 0 for the zero-width
// joiner, VS16 and combining accents, 2 for the WIDE ranges, else 1.
export function cellWidth(cp: number): number {
  if (cp === 0x200d || cp === 0xfe0f || (cp >= 0x300 && cp <= 0x36f)) return 0
  return WIDE.some(([lo, hi]) => cp >= lo && cp <= hi) ? 2 : 1
}

const cpCells = (cp: string): number => cellWidth(cp.codePointAt(0) ?? 0)

// Cells of a text.
export const textCells = (text: string): number => points(text).reduce((n, cp) => n + cpCells(cp), 0)

// The longest head of `text` within `room` cells, whole code points only (a
// wide glyph that does not fit is dropped, never halved), and its cells.
function fit(text: string, room: number): { text: string; cells: number; whole: boolean } {
  const cps = points(text)
  let cells = 0
  let n = 0
  for (const cp of cps) {
    const w = cpCells(cp)
    if (cells + w > room) break
    cells += w
    n += 1
  }
  return { text: cps.slice(0, n).join(''), cells, whole: n === cps.length }
}

// Cuts `text` to `width` cells, the last one an ellipsis when cut.
export function truncate(text: string, width: number): string {
  if (width <= 0) return ''
  if (textCells(text) <= width) return text
  return width === 1 ? '…' : `${fit(text, width - 1).text}…`
}

// skipped → ignorée, a red word → rouge, a green word → vert, else the raw
// text cut to 30 characters.
export function baselineWord(baseline: string): string {
  const s = baseline.toLowerCase()
  if (/skip|ignor/.test(s)) return 'ignorée'
  if (/\bred\b|rouge|fail|échec|✘|❌/.test(s)) return 'rouge'
  if (/green|vert|✅|\bpass/.test(s)) return 'vert'
  return truncate(baseline, 30)
}

// A step's short label: the `NN-` / `NNx-` prefix stripped, execute → exec,
// validate → valid.
export function stepLabel(step: string): string {
  const bare = step.replace(/^\d+[a-z]?-/i, '')
  if (bare === 'execute') return 'exec'
  if (bare === 'validate') return 'valid'
  return bare
}

// The glyph of a step kind and its style: a theme tone, or dim.
export function stepMark(kind: ApexBandStepKind): Seg {
  if (kind === 'done') return { text: '✓', tone: 'success' }
  if (kind === 'running') return { text: '●', tone: 'warning' }
  if (kind === 'failed') return { text: '✗', tone: 'error' }
  if (kind === 'pending') return { text: '○', dim: true }
  if (kind === 'skipped') return { text: '–', dim: true }
  return { text: '·', dim: true }
}

// The style of a baseline word: vert green, rouge red, anything else dim.
function baselineStyle(word: string): Omit<Seg, 'text'> {
  if (word === 'vert') return { tone: 'success' }
  if (word === 'rouge') return { tone: 'error' }
  return { dim: true }
}

// Total cells of a line.
export const width = (line: readonly Seg[]): number => line.reduce((n, seg) => n + textCells(seg.text), 0)

// Non-empty groups joined by a dim ` · `.
export function join(groups: readonly (readonly Seg[])[]): Seg[] {
  const out: Seg[] = []
  for (const group of groups) {
    if (group.length === 0) continue
    if (out.length > 0) out.push({ text: SEP, dim: true })
    out.push(...group)
  }
  return out
}

// A line cut to `cols` cells, its last cell an ellipsis when cut.
export function hardCut(line: readonly Seg[], cols: number): Seg[] {
  if (width(line) <= cols) return [...line]
  const out: Seg[] = []
  let room = cols - 1
  for (const seg of line) {
    if (room <= 0) break
    const head = fit(seg.text, room)
    out.push({ ...seg, text: head.text })
    room -= head.cells
    // A cut segment ends the line: nothing narrower slips in after it.
    if (!head.whole) break
  }
  const last = out[out.length - 1]
  if (last === undefined) return [{ text: '…', dim: true }]
  out[out.length - 1] = { ...last, text: `${last.text}…` }
  return out
}

// One chip: the glyph, then the label (bold while running, plain when
// failed, dim otherwise) unless `withLabel` is false.
function chip(step: ApexBandStep, withLabel: boolean): Seg[] {
  const mark = stepMark(step.kind)
  if (!withLabel) return [mark]
  const text = ` ${stepLabel(step.step)}`
  if (step.kind === 'running') return [mark, { text, bold: true }]
  if (step.kind === 'failed') return [mark, { text }]
  return [mark, { text, dim: true }]
}

// The step bar at a degradation level: 0 every label, 1 done chips
// glyph-only, 2 only running/failed chips keep a label, 3 as 2 with the
// ` › ` separators turned to single spaces.
function bar(steps: readonly ApexBandStep[], level: 0 | 1 | 2 | 3): Seg[] {
  const out: Seg[] = []
  steps.forEach((step, i) => {
    if (i > 0) out.push({ text: level >= 3 ? ' ' : ' › ', dim: true })
    const live = step.kind === 'running' || step.kind === 'failed'
    const withLabel = level === 0 || live || (level === 1 && step.kind !== 'done')
    out.push(...chip(step, withLabel))
  })
  return out
}

// The compact bar: one chip with its dim `k/n` position, the running step
// (else the last failed one, else the next pending one); a ✓ and `n/n`
// when none of these is left.
function compactBar(steps: readonly ApexBandStep[]): Seg[] {
  let at = steps.findIndex(s => s.kind === 'running')
  if (at < 0) {
    for (let i = 0; i < steps.length; i++) if (steps[i]?.kind === 'failed') at = i
  }
  if (at < 0) at = steps.findIndex(s => s.kind === 'pending')
  const step = steps[at]
  const n = steps.length
  if (step === undefined) return [stepMark('done'), { text: ` ${n}/${n}`, dim: true }]
  return [...chip(step, true), { text: ` ${at + 1}/${n}`, dim: true }]
}

// The head, one dim segment so it reads as a single Text.
const head = (title: string): Seg[] => [{ text: `${HEAD}${title}`, dim: true }]

// Head and bar within `cols`: labels dropped (done, then the rest), then
// separators to spaces, then the title truncated (≥ MIN_TITLE cells), then
// the compact bar when narrower than the spaced bar, then a hard cut of the
// narrowest of the two.
function fitBar(run: ApexBandRun, cols: number): Seg[] {
  const { steps, title } = run
  const bars = steps.length === 0 ? [[]] : [bar(steps, 0), bar(steps, 1), bar(steps, 2), bar(steps, 3)]
  for (const b of bars) {
    const line = join([head(title), b])
    if (width(line) <= cols) return line
  }
  const minTitle = Math.min(MIN_TITLE, textCells(title))
  const last: Seg[][] = steps.length === 0 ? [[]] : [bar(steps, 3)]
  if (steps.length > 0) {
    // With few steps the compact bar can be wider than the spaced one.
    const compact = compactBar(steps)
    if (width(compact) < width(bar(steps, 3))) last.push(compact)
  }
  for (const b of last) {
    const room = cols - width(join([head(''), b]))
    if (room >= minTitle) return join([head(truncate(title, room)), b])
  }
  const narrowest = last[last.length - 1] ?? []
  return hardCut(join([head(truncate(title, minTitle)), narrowest]), cols)
}

type MetaKey = 'mode' | 'branch' | 'baseline'
type Meta = { key: MetaKey; segs: Seg[] }

// Mode, branch and `baseline <word>`, the fields the run has, in that order.
export function meta(run: ApexBandRun): Meta[] {
  const items: Meta[] = []
  if (run.mode !== undefined && run.mode !== '') items.push({ key: 'mode', segs: [{ text: run.mode, dim: true }] })
  if (run.branch !== undefined && run.branch !== '')
    items.push({ key: 'branch', segs: [{ text: run.branch, dim: true }] })
  if (run.baseline !== undefined) {
    const word = baselineWord(run.baseline)
    items.push({ key: 'baseline', segs: [{ text: 'baseline ', dim: true }, { text: word, ...baselineStyle(word) }] })
  }
  return items
}

// Line 2 within `cols`: branch dropped, then mode, then a hard cut.
function fitMeta(items: readonly Meta[], cols: number): Seg[] {
  let kept = [...items]
  for (const drop of ['branch', 'mode'] as const) {
    const line = join(kept.map(m => m.segs))
    if (width(line) <= cols) return line
    if (kept.length > 1) kept = kept.filter(m => m.key !== drop)
  }
  return hardCut(join(kept.map(m => m.segs)), cols)
}

// The band as at most min(2, maxRows) lines (at least one), each fitting
// max(1, cols) cells. One line when all fits; else meta on line 2 when two
// rows are free; else one line dropping branch, mode, baseline before the
// bar degrades.
export function layoutBand(run: ApexBandRun, cols: number, maxRows: number): Seg[][] {
  const w = Math.max(1, cols)
  const full = run.steps.length === 0 ? [] : bar(run.steps, 0)
  let items = meta(run)
  const whole = join([head(run.title), full, ...items.map(m => m.segs)])
  if (width(whole) <= w) return [whole]
  if (maxRows >= 2 && items.length > 0) return [fitBar(run, w), fitMeta(items, w)]
  for (const drop of ['branch', 'mode', 'baseline'] as const) {
    items = items.filter(m => m.key !== drop)
    const line = join([head(run.title), full, ...items.map(m => m.segs)])
    if (width(line) <= w) return [line]
  }
  return [fitBar(run, w)]
}
