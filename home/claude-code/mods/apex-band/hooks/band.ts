// Pure layout of the band: at most three calm rows of styled segments, each
// fitting `cols` cells.
// L1, the run: `APEX · <title>  ●●●◐○  <phase> · <elapsed> · $<cost>`.
// L2, the work in flight, only while a subagent or a background shell runs:
// `◐ opus ×3  ◑ haiku ×2  ⧗ shell ×1  ✓ 9 terminés`.
// L3, what asks the user to act, only when something does (a failed step, a
// red external verification, a spent correction budget).
// Rows kept by priority L1 > L3 > L2, drawn in the order L1, L2, L3; on a
// single row an alert prefixes L1 with ⚠. Every meaning reads from a glyph
// or a word, never from the colour alone.
// Widths are counted in terminal cells by an approximation (cellWidth): CJK,
// pictographs and BMP default-emoji symbols (⌚ ✅ ⭐) count 2, joiners, VS16
// and combining accents 0, the rest 1. Still an approximation: a text symbol
// promoted to emoji by VS16 (☀️) counts 1, and a grapheme the table
// misjudges (rare scripts, flag pairs) may be off.

import type { ThemeKey } from 'claude-code'

import type {
  ApexBandAlert,
  ApexBandLoop,
  ApexBandRun,
  ApexBandShell,
  ApexBandStepKind,
} from '../types'
import { phaseBuckets } from './signals.ts'
import type { PhaseState } from './signals.ts'
import { MAIN, isWorking, shortModel } from './stats.ts'

// One run of text drawn with one style; index.tsx maps it to a Text.
export type Seg = { text: string; tone?: ThemeKey; dim?: boolean; bold?: boolean }

const SEP = ' · '
const HEAD = `APEX${SEP}`
const GAP = '  '
// A truncated title keeps at least this many cells before anything is dropped.
const MIN_TITLE = 8
// The spinner's four frames; each model group starts one frame further.
const SPIN = ['◐', '◓', '◑', '◒'] as const

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


type MetaKey = 'mode' | 'branch' | 'baseline'
type Meta = { key: MetaKey; segs: Seg[] }

// Mode, branch and `baseline <word>`, the fields the run has, in that order
// (the pane's second line).
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

export type BandInput = {
  run: ApexBandRun | null
  loops: readonly ApexBandLoop[]
  shells: readonly ApexBandShell[]
  now: number
  cost: number | null
  frame: number
  alerts: readonly ApexBandAlert[]
  // When this session first saw the run (its own start is not readable).
  seenAt: number | null
}

const pad2 = (n: number): string => String(n).padStart(2, '0')

// Minutes since the run was first seen: 12m, 1h05.
export function elapsed(ms: number): string {
  const minutes = Math.floor(Math.max(0, ms) / 60_000)
  if (minutes < 60) return `${minutes}m`
  return `${Math.floor(minutes / 60)}h${pad2(minutes % 60)}`
}

// A phase dot: ● done, ◐ running, ✗ failed, ○ waiting.
export function phaseDot(state: PhaseState): Seg {
  if (state === 'done') return { text: '●', tone: 'success' }
  if (state === 'running') return { text: '◐', tone: 'warning' }
  if (state === 'failed') return { text: '✗', tone: 'error' }
  return { text: '○', dim: true }
}

const head = (title: string): Seg => ({ text: `${HEAD}${title}`, dim: true })

type Tail = { phase: Seg[]; elapsed: Seg[]; cost: Seg[] }

// L1 with `title` and the tail groups kept, ` · ` between them.
function runLine(prefix: Seg[], title: string, dots: Seg[], tail: Tail): Seg[] {
  const line: Seg[] = [...prefix, head(title)]
  if (dots.length > 0) line.push({ text: GAP }, ...dots)
  const rest = join([tail.phase, tail.elapsed, tail.cost])
  if (rest.length > 0) line.push({ text: GAP }, ...rest)
  return line
}

// L1 within `cols`: the title cut down to MIN_TITLE cells, then elapsed,
// cost and the phase word dropped in that order, then a hard cut.
function fitRun(run: ApexBandRun, input: BandInput, prefix: Seg[], cols: number): Seg[] {
  const buckets = run.steps.length === 0 ? [] : phaseBuckets(run.steps)
  const dots = buckets.map(b => phaseDot(b.state))
  const current = buckets.find(b => b.isCurrent)
  const full: Tail = {
    phase:
      current === undefined
        ? []
        : [{ text: current.label, bold: true, ...(current.state === 'failed' ? { tone: 'error' as const } : {}) }],
    elapsed: input.seenAt === null ? [] : [{ text: elapsed(input.now - input.seenAt), dim: true }],
    cost: input.cost === null ? [] : [{ text: `$${input.cost.toFixed(2)}`, dim: true }],
  }
  const tails: Tail[] = [
    full,
    { ...full, elapsed: [] },
    { ...full, elapsed: [], cost: [] },
    { phase: [], elapsed: [], cost: [] },
  ]
  const minTitle = Math.min(MIN_TITLE, textCells(run.title))
  for (const tail of tails) {
    const room = cols - width(runLine(prefix, '', dots, tail))
    if (room >= minTitle) return runLine(prefix, truncate(run.title, room), dots, tail)
  }
  const last = tails[tails.length - 1] ?? full
  return hardCut(runLine(prefix, truncate(run.title, minTitle), dots, last), cols)
}

// A model's family: the first word of its short id (opus-5.5 → opus).
export function family(model: string | undefined): string {
  const word = shortModel(model ?? '').split('-')[0] ?? ''
  return word === '' ? 'agent' : word
}

// The spinner's tone per family; a background shell is drawn inactive.
export function familyTone(name: string): ThemeKey {
  if (name === 'opus') return 'claude'
  if (name === 'sonnet') return 'suggestion'
  if (name === 'haiku') return 'planMode'
  return 'text'
}

type Group = { label: string; count: number; glyph: string; tone: ThemeKey }

// The running subagents (teammates aside, see isWorking) grouped by model
// family (first seen first), then the running shells; each group's spinner one frame ahead of the previous.
function groups(input: BandInput): Group[] {
  const running = input.loops
    .filter(isWorking)
    .sort((a, b) => a.startedAt - b.startedAt)
  const counts = new Map<string, number>()
  for (const loop of running) {
    const name = family(loop.model)
    counts.set(name, (counts.get(name) ?? 0) + 1)
  }
  const out: Group[] = [...counts].map(([label, count], i) => ({
    label,
    count,
    glyph: SPIN[(((input.frame + i) % SPIN.length) + SPIN.length) % SPIN.length] ?? '◐',
    tone: familyTone(label),
  }))
  const shells = input.shells.filter(s => s.status === 'running').length
  if (shells > 0) out.push({ label: 'shell', count: shells, glyph: '⧗', tone: 'inactive' })
  return out
}

// True while a subagent (teammates aside) or a background shell works.
export function isBusy(loops: readonly ApexBandLoop[], shells: readonly ApexBandShell[]): boolean {
  return loops.some(isWorking) || shells.some(s => s.status === 'running')
}

// L2 within `cols`: the « terminés » count dropped, then the spacing
// tightened, then a hard cut.
function fitActivity(input: BandInput, cols: number): Seg[] {
  const list = groups(input)
  const done =
    input.loops.filter(l => l.id !== MAIN && l.status !== 'running').length +
    input.shells.filter(s => s.status !== 'running').length
  const spaced = (gap: string, inner: string): Seg[] =>
    list.flatMap((g, i): Seg[] => [
      ...(i > 0 ? [{ text: gap }] : []),
      { text: g.glyph, tone: g.tone },
      { text: ` ${g.label}${inner}×${g.count}` },
    ])
  const full = spaced(GAP, ' ')
  if (done > 0) {
    const withDone = [...full, { text: GAP }, { text: `✓ ${done} ${done > 1 ? 'terminés' : 'terminé'}`, dim: true }]
    if (width(withDone) <= cols) return withDone
  }
  if (width(full) <= cols) return full
  return hardCut(spaced(' ', ''), cols)
}

const plural = (n: number, word: string): string => `${n} ${word}${n > 1 ? 's' : ''}`

const BUDGET_LONG = 'Budget de correction épuisé — tape « apex: +1 tour » ou livre avec les résiduels'
const BUDGET_SHORT = 'Budget épuisé — « apex: +1 tour »'

// One alert as a line within `cols`: its glyph (✗ or ⚠, toned) and words;
// the budget's long wording when it fits, else its short one; then a hard
// cut. `more` alerts left unshown add a dim ` (+k)`.
export function alertLine(alert: ApexBandAlert, cols: number, more = 0): Seg[] {
  const suffix: Seg[] = more > 0 ? [{ text: ` (+${more})`, dim: true }] : []
  const words: string[] =
    alert.kind === 'step'
      ? [`Étape ${stepLabel(alert.step)} en échec`]
      : alert.kind === 'verify'
        ? [`Vérif externe ${alert.verdict}${SEP}${plural(alert.findings, 'constat')}`]
        : [BUDGET_LONG, BUDGET_SHORT]
  const mark: Seg = alert.kind === 'budget' ? { text: '⚠', tone: 'warning' } : { text: '✗', tone: 'error' }
  const lines = words.map(w => [mark, { text: ` ${w}` }, ...suffix])
  const fits = lines.find(l => width(l) <= cols)
  return fits ?? hardCut(lines[lines.length - 1] ?? [mark], cols)
}

// The band as at most min(3, maxRows) lines (at least one when anything is
// drawn), each within max(1, cols) cells; no line at all when no run is
// live and nothing runs.
export function layoutBand(input: BandInput, cols: number, maxRows: number): Seg[][] {
  const w = Math.max(1, cols)
  const rows = Math.max(1, Math.min(3, maxRows))
  const busy = isBusy(input.loops, input.shells)
  const { run } = input
  if (run === null) return busy ? [fitActivity(input, w)] : []
  const alert = input.alerts[0]
  if (rows === 1) {
    const prefix: Seg[] = alert === undefined ? [] : [{ text: '⚠ ', tone: 'warning' }]
    return [fitRun(run, input, prefix, w)]
  }
  const showAlert = alert !== undefined
  const showActivity = busy && (rows >= 3 || !showAlert)
  const lines: Seg[][] = [fitRun(run, input, [], w)]
  if (showActivity) lines.push(fitActivity(input, w))
  if (alert !== undefined) lines.push(alertLine(alert, w, input.alerts.length - 1))
  return lines
}
