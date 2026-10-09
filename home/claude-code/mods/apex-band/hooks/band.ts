// Shared segment helpers of the pane and the agents block (pane.ts,
// agents.ts): styled segments, cell widths, cuts, step and alert lines.
// Every meaning reads from a glyph or a word, never from the colour alone.
// Widths are counted in terminal cells by an approximation (cellWidth): CJK,
// pictographs and BMP default-emoji symbols (⌚ ✅ ⭐) count 2, joiners, VS16
// and combining accents 0, the rest 1. Still an approximation: a text symbol
// promoted to emoji by VS16 (☀️) counts 1, and a grapheme the table
// misjudges (rare scripts, flag pairs) may be off.

import type { ThemeKey } from 'claude-code'

import type { ApexBandAlert, ApexBandRun, ApexBandStepKind } from '../types'
import type { ElapsedProps } from './elapsed.ts'
import type { RailProps } from './rail.ts'
import { shortModel } from './stats.ts'

// What a live segment's Client draws in place of its static text: a clock
// counting on from `ms`, or the main loop's rail.
export type Live =
  | { kind: 'clock'; key: string; ms: number; running: boolean }
  | { kind: 'rail'; key: string; cells: number; drops: number[]; active: boolean; tone: ThemeKey }

// One run of text drawn with one style; index.tsx maps it to a Text, or a
// live one to a Client as wide as its text (the text, the static fallback).
export type Seg = { text: string; tone?: ThemeKey; dim?: boolean; bold?: boolean; live?: Live }

// A live segment's Client props (./elapsed.ts or ./rail.ts), null when static.
export function clientProps(seg: Seg): ElapsedProps | RailProps | null {
  const live = seg.live
  if (live === undefined) return null
  if (live.kind === 'rail') return { cells: live.cells, drops: live.drops, active: live.active, tone: live.tone }
  return { ms: live.ms, running: live.running, tone: seg.tone ?? null, dim: seg.dim === true }
}

const SEP = ' · '

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
    // A cut live segment keeps its text only: its Client would draw it whole.
    const { live: _live, ...style } = seg
    out.push(head.whole ? { ...seg, text: head.text } : { ...style, text: head.text })
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

// A model's family: the first word of its short id (opus-5.5 → opus).
export function family(model: string | undefined): string {
  const word = shortModel(model ?? '').split('-')[0] ?? ''
  return word === '' ? 'agent' : word
}

// A model family's tone; anything else the plain text tone.
export function familyTone(name: string): ThemeKey {
  if (name === 'opus') return 'claude'
  if (name === 'sonnet') return 'suggestion'
  if (name === 'haiku') return 'planMode'
  return 'text'
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

