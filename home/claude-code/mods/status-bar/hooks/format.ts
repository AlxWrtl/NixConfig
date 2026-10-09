// Pure logic of the status bar: model name, bars, reset countdowns,
// thousands separators, git HEAD parsing and the one-or-two-line layout.
// Same figures, colours, thresholds and formats as the former command
// status line (statusline.sh). Widths are counted in terminal cells by an
// approximation (cellWidth): the bar's emoji count 2, the rest 1.

import type { Color } from 'claude-code'

import type { StatusBarLimit } from '../types'

// One run of text drawn with one style; index.tsx maps it to a Text.
export type Seg = { text: string; color?: Color; dim?: boolean }

// The script's ANSI colours as their xterm-256 hex, the same on every surface.
export const PALETTE = {
  red: '#ff5f5f',
  orange: '#ff8700',
  yellow: '#ffd75f',
  green: '#5fd75f',
  cyan: '#5fd7ff',
  grey: '#6c6c6c',
} as const

export const BAR_CELLS = 10
const FULL = '█'
const EMPTY = '░'
const SEP = ' | '
// Cells left free at the row's end before the bar breaks onto two lines.
const MARGIN = 4

// `claude-opus-5-5[1m]` → `Opus 5.5`, `claude-3-5-sonnet-20241022` →
// `Sonnet 3.5`, `opus` → `Opus`; a display name (`Opus 5.5 (1M context)`)
// loses its parenthesis. The family is the first word that is no number.
export function modelName(id: string): string {
  const bare = id
    .replace(/\[[^\]]*\]/g, '')
    .replace(/\s*\([^)]*\)/g, '')
    .trim()
  if (bare === '') return ''
  if (/\s/.test(bare)) return bare
  const words = bare
    .replace(/^claude-/i, '')
    .replace(/-\d{8}$/, '')
    .replace(/-latest$/i, '')
    .split('-')
    .filter(w => w !== '')
  const family = words.find(w => !/^\d+$/.test(w))
  const version = words.filter(w => /^\d+$/.test(w)).join('.')
  if (family === undefined) return bare
  const name = family.charAt(0).toUpperCase() + family.slice(1)
  return version === '' ? name : `${name} ${version}`
}

// The session's model as /model has it; an alias without a version
// (`opus[1m]`) takes the version of the API's model of the same family.
export function pickModel(session: string, step: string | undefined): string {
  const fromSession = modelName(session)
  if (step === undefined) return fromSession
  const fromStep = modelName(step)
  if (fromSession === '') return fromStep
  const isBare = !/\d/.test(fromSession)
  const sameFamily = fromStep.split(' ')[0]?.toLowerCase() === fromSession.toLowerCase()
  return isBare && sameFamily ? fromStep : fromSession
}

// A percentage as the script rounds it (jq round: half away from zero).
export function roundPct(value: number): number {
  return value < 0 ? -Math.round(-value) : Math.round(value)
}

// A 10-cell bar: filled cells from the whole tens of `pct` (clamped 0-100),
// green under 60, orange under 85, red from 85; empty cells grey.
export function bar(pct: number): Seg[] {
  const clamped = Math.min(100, Math.max(0, Math.trunc(pct)))
  const filled = Math.floor(clamped / 10)
  const color = clamped >= 85 ? PALETTE.red : clamped >= 60 ? PALETTE.orange : PALETTE.green
  const segs: Seg[] = []
  if (filled > 0) segs.push({ text: FULL.repeat(filled), color })
  if (filled < BAR_CELLS) segs.push({ text: EMPTY.repeat(BAR_CELLS - filled), color: PALETTE.grey })
  return segs
}

// Time left until `resetMs`: under an hour `42min`, under a day `5.07h`
// (the digits after the dot are minutes, 00-59), else `5j 0h`.
export function fmtReset(resetMs: number, nowMs: number): string {
  const seconds = Math.max(0, Math.floor((resetMs - nowMs) / 1000))
  const mins = Math.floor(seconds / 60)
  if (mins < 60) return `${mins}min`
  if (mins < 1440) return `${Math.floor(mins / 60)}.${String(mins % 60).padStart(2, '0')}h`
  return `${Math.floor(mins / 1440)}j ${Math.floor((mins % 1440) / 60)}h`
}

// 1234567 → `1,234,567` (the en_US grouping the script's printf used).
export function thousands(value: number): string {
  const whole = Math.trunc(value)
  const sign = whole < 0 ? '-' : ''
  return sign + String(Math.abs(whole)).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}

// The branch `.git/HEAD` names (`ref: refs/heads/feat/x` → `feat/x`); a
// detached HEAD names none, as `git branch --show-current` prints nothing.
export function parseHead(text: string): string | undefined {
  const name = /^ref:\s*refs\/heads\/(\S+)\s*$/.exec(text.trim())?.[1]
  return name === undefined || name === '' ? undefined : name
}

// The git directory a `.git` file points at (`gitdir: ../.git/worktrees/x`),
// made absolute against the folder holding that file.
export function resolveGitdir(text: string, dir: string): string | undefined {
  const target = /^gitdir:\s*(.+?)\s*$/m.exec(text)?.[1]
  if (target === undefined || target === '') return undefined
  if (target.startsWith('/')) return target
  return `${dir === '/' ? '' : dir}/${target}`
}

// The folder above `dir`; the root is its own parent.
export function parentDir(dir: string): string {
  const trimmed = dir.replace(/\/+$/, '')
  const cut = trimmed.lastIndexOf('/')
  return cut <= 0 ? '/' : trimmed.slice(0, cut)
}

// The last path component, trailing slashes ignored; the root reads `/`.
export function basename(path: string): string {
  const trimmed = path.replace(/\/+$/, '')
  const name = trimmed.slice(trimmed.lastIndexOf('/') + 1)
  return name === '' ? '/' : name
}

// Cells a code point takes: 2 for emoji and CJK, 0 for joiners, variation
// selectors and combining marks, 1 otherwise.
function pointWidth(code: number): number {
  if (code === 0x200d || (code >= 0xfe00 && code <= 0xfe0f) || (code >= 0x0300 && code <= 0x036f)) return 0
  if (
    code === 0x23f3 ||
    (code >= 0x1100 && code <= 0x115f) ||
    (code >= 0x2e80 && code <= 0xa4cf) ||
    (code >= 0xac00 && code <= 0xd7a3) ||
    (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0xff00 && code <= 0xff60) ||
    (code >= 0x1f300 && code <= 0x1faff) ||
    (code >= 0x20000 && code <= 0x3fffd)
  ) {
    return 2
  }
  return 1
}

export function cellWidth(text: string): number {
  let width = 0
  for (const point of text) width += pointWidth(point.codePointAt(0) ?? 0)
  return width
}

const lineWidth = (line: readonly Seg[]): number => line.reduce((sum, seg) => sum + cellWidth(seg.text), 0)

export type StatusData = {
  model: string
  cwd: string
  branch: string | null
  tokensIn: number
  tokensOut: number
  contextPercent: number
  limits: readonly StatusBarLimit[]
  now: number
}

const sep = (): Seg => ({ text: SEP, dim: true })

// Group 1: model, folder, branch (when known), tokens in/out.
export function sessionGroup(data: StatusData): Seg[] {
  const segs: Seg[] = [
    { text: `🤖 ${data.model === '' ? '?' : data.model}`, color: PALETTE.red },
    sep(),
    { text: `📁 ${basename(data.cwd)}`, color: PALETTE.orange },
  ]
  if (data.branch !== null && data.branch !== '') segs.push(sep(), { text: `⎇ ${data.branch}`, color: PALETTE.yellow })
  segs.push(sep(), { text: `📊 ${thousands(data.tokensIn)}/${thousands(data.tokensOut)}`, color: PALETTE.green })
  return segs
}

// One quota window: glyph, bar, percentage and the time to its reset.
function limitSegs(glyph: string, limit: StatusBarLimit, now: number): Seg[] {
  const pct = roundPct(limit.percentUsed)
  const resetMs = limit.resetsAt === null ? Number.NaN : Date.parse(limit.resetsAt)
  const reset = Number.isFinite(resetMs) ? ` · ${fmtReset(resetMs, now)}` : ''
  return [sep(), { text: `${glyph} ` }, ...bar(pct), { text: ` ${pct}%${reset}`, color: PALETTE.cyan }]
}

// Group 2: context bar, then the 5h and 7d windows that have a reading.
export function usageGroup(data: StatusData): Seg[] {
  const ctx = roundPct(data.contextPercent)
  const segs: Seg[] = [{ text: '🧠 ' }, ...bar(ctx), { text: ` ${ctx}%`, color: PALETTE.cyan }]
  const five = data.limits.find(l => l.kind === 'five_hour')
  const seven = data.limits.find(l => l.kind === 'seven_day')
  if (five !== undefined) segs.push(...limitSegs('⏳', five, data.now))
  if (seven !== undefined) segs.push(...limitSegs('📆', seven, data.now))
  return segs
}

// One line when it fits `cols` (less a margin), else group 1 over group 2;
// one line too when the width is unknown.
export function layout(data: StatusData, cols: number | undefined): Seg[][] {
  const first = sessionGroup(data)
  const second = usageGroup(data)
  const one = [...first, sep(), ...second]
  if (cols === undefined || lineWidth(one) <= cols - MARGIN) return [one]
  return [first, second]
}
