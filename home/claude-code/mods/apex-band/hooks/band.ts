// Pure layout of the band: at most two lines of styled segments, each line
// fitting `cols` cells. Line 1 is the head (`APEX · <title>`) and the step
// bar; mode, branch and baseline follow it when they fit, else go to line 2.
// Widths are counted in code points: a wide glyph (CJK, emoji) in the title
// may overflow the line by its extra cell.

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

// Cuts `text` to `width` cells, the last one an ellipsis when cut.
export function truncate(text: string, width: number): string {
  if (width <= 0) return ''
  const cps = points(text)
  if (cps.length <= width) return text
  return width === 1 ? '…' : `${cps.slice(0, width - 1).join('')}…`
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
const width = (line: readonly Seg[]): number => line.reduce((n, seg) => n + points(seg.text).length, 0)

// Non-empty groups joined by a dim ` · `.
function join(groups: readonly (readonly Seg[])[]): Seg[] {
  const out: Seg[] = []
  for (const group of groups) {
    if (group.length === 0) continue
    if (out.length > 0) out.push({ text: SEP, dim: true })
    out.push(...group)
  }
  return out
}

// A line cut to `cols` cells, its last cell an ellipsis when cut.
function hardCut(line: readonly Seg[], cols: number): Seg[] {
  if (width(line) <= cols) return [...line]
  const out: Seg[] = []
  let room = cols - 1
  for (const seg of line) {
    if (room <= 0) break
    const cps = points(seg.text).slice(0, room)
    out.push({ ...seg, text: cps.join('') })
    room -= cps.length
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
  const minTitle = Math.min(MIN_TITLE, points(title).length)
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
function meta(run: ApexBandRun): Meta[] {
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
