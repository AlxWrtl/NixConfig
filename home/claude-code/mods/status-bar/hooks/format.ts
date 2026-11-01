// Pure logic of the status bar: model name, bars, reset countdowns,
// thousands separators, git HEAD parsing and the one-or-two-line layout.
// Same figures, colours, thresholds and formats as the former command
// status line (statusline.sh). Widths are counted in terminal cells by an
// approximation (cellWidth): the bar's emoji count 2, the rest 1.

import type { Color } from 'claude-code'

import type { StatusBarLimit } from '../types'

// What a bar shows, kept on each of its cells: a surface that draws SVG
// swaps those cells for one drawing (a pill when it carries a label).
export type Gauge = { pct: number; alt: string; label?: string }

// One run of text drawn with one style; index.tsx maps it to a Text.
export type Seg = { text: string; color?: Color; dim?: boolean; gauge?: Gauge }

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
// Length of each quota window, by the kind the engine names it with.
const WINDOW_MS: Readonly<Record<string, number>> = { five_hour: 5 * 3_600_000, seven_day: 7 * 86_400_000 }
// Short names of the quota windows, as the SVG gauges' alt text says them.
const WINDOW_LABEL: Readonly<Record<string, string>> = { five_hour: '5h', seven_day: '7d' }
// SVG sizes in CSS pixels: the quota gauge, the context pill.
const GAUGE_W = 48
const GAUGE_H = 6
const PILL_W = 84
const PILL_H = 16
// Empty-track colours: the quota gauge's (drawn faint), the context pill's.
const TRACK = '#8b8b8b'
const PILL_TRACK = '#3a3f47'

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

// The window context fill is measured against: CLAUDE_CODE_AUTO_COMPACT_WINDOW read as the
// engine reads it (leading integer, clamped to 100k–1M, capped at the model's window), else the
// model's window. Same text in the status-bar and deck mods: keep them in step.
export function compactWindow(modelWindow: number, raw: string | undefined): number {
  const set = raw === undefined ? Number.NaN : Number.parseInt(raw, 10)
  if (!Number.isFinite(set)) return modelWindow
  const clamped = Math.min(Math.max(set, 100_000), 1_000_000)
  return modelWindow > 0 ? Math.min(clamped, modelWindow) : clamped
}

// The context fill against that window, 0 to 100; the engine's own percent when no token count.
export function contextFill(
  context: { tokens?: number; window: number; percent?: number },
  raw: string | undefined,
): { window: number; pct: number | null } {
  const window = compactWindow(context.window, raw)
  if (context.tokens === undefined || window <= 0) return { window, pct: context.percent ?? null }
  return { window, pct: Math.min(100, (context.tokens / window) * 100) }
}

// A 10-cell bar: filled cells from the whole tens of `pct` (clamped 0-100),
// green under 60, orange under 85, red from 85; empty cells grey.
export function bar(pct: number): Seg[] {
  const clamped = Math.min(100, Math.max(0, Math.trunc(pct)))
  const filled = Math.floor(clamped / 10)
  const color = barColor(clamped)
  const segs: Seg[] = []
  if (filled > 0) segs.push({ text: FULL.repeat(filled), color })
  if (filled < BAR_CELLS) segs.push({ text: EMPTY.repeat(BAR_CELLS - filled), color: PALETTE.grey })
  return segs
}

// The bar's fill colour for a whole percentage: green, orange from 60, red from 85.
function barColor(clamped: number): Color {
  return clamped >= 85 ? PALETTE.red : clamped >= 60 ? PALETTE.orange : PALETTE.green
}

// `pct` clamped to 0-100, as a share of `width` pixels.
function fillWidth(pct: number, width: number): number {
  return Math.round((Math.min(100, Math.max(0, pct)) / 100) * width)
}

// Text made safe inside SVG markup.
function escapeXml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

// A quota bar as SVG: a rounded grey track, a rounded fill in bar()'s colour.
export function gaugeSvg(pct: number): string {
  const color = barColor(Math.min(100, Math.max(0, Math.trunc(pct))))
  const r = GAUGE_H / 2
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${GAUGE_W}" height="${GAUGE_H}" viewBox="0 0 ${GAUGE_W} ${GAUGE_H}"><rect width="${GAUGE_W}" height="${GAUGE_H}" rx="${r}" fill="${TRACK}" fill-opacity="0.25"/><rect width="${fillWidth(pct, GAUGE_W)}" height="${GAUGE_H}" rx="${r}" fill="${color}"/></svg>`
}

// The context bar as SVG: a rounded pill filled in bar()'s colour, `label` centered inside.
export function pillSvg(pct: number, label: string): string {
  const color = barColor(Math.min(100, Math.max(0, Math.trunc(pct))))
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${PILL_W}" height="${PILL_H}" viewBox="0 0 ${PILL_W} ${PILL_H}"><defs><clipPath id="p"><rect width="${PILL_W}" height="${PILL_H}" rx="${PILL_H / 2}"/></clipPath></defs><g clip-path="url(#p)"><rect width="${PILL_W}" height="${PILL_H}" fill="${PILL_TRACK}"/><rect width="${fillWidth(pct, PILL_W)}" height="${PILL_H}" fill="${color}"/></g><text x="${PILL_W / 2}" y="11.5" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, system-ui, sans-serif" font-size="10.5" font-weight="700" fill="#ffffff" stroke="#000000" stroke-opacity="0.45" stroke-width="2" paint-order="stroke">${escapeXml(label)}</text></svg>`
}

// The drawing that stands for a gauge's cells on a surface that draws SVG.
export function gaugeSource(gauge: Gauge): string {
  return gauge.label === undefined ? gaugeSvg(gauge.pct) : pillSvg(gauge.pct, gauge.label)
}

// Ahead (+) or behind (-) of an even spend: the share of the window elapsed
// less the share used, in points; null when its reset or length is unknown.
export function pace(limit: StatusBarLimit, now: number): number | null {
  const windowMs = WINDOW_MS[limit.kind]
  const resetMs = limit.resetsAt === null ? Number.NaN : Date.parse(limit.resetsAt)
  if (windowMs === undefined || !Number.isFinite(resetMs)) return null
  const elapsed = Math.min(100, Math.max(0, ((windowMs - (resetMs - now)) / windowMs) * 100))
  return elapsed - limit.percentUsed
}

// Green when on or ahead of pace, yellow less than 10 points behind, else red.
export function paceColor(points: number): Color {
  return points >= 0 ? PALETTE.green : points > -10 ? PALETTE.yellow : PALETTE.red
}

// A pace as `+24.5%` / `-5.0%`: sign, one decimal.
export function fmtPace(points: number): string {
  return `${points >= 0 ? '+' : ''}${points.toFixed(1)}%`
}

// A token count as `84k` from a thousand up (rounded), else as it is.
export function fmtTokens(count: number): string {
  return count >= 1000 ? `${Math.round(count / 1000)}k` : String(count)
}

// Each cell of `segs` tagged with the one gauge they draw.
function tag(segs: readonly Seg[], gauge: Gauge): Seg[] {
  return segs.map(seg => ({ ...seg, gauge }))
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
  // The context's tokens and the window they fill, for the SVG pill's label.
  contextTokens?: number | null
  contextWindow?: number | null
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

// One quota window: glyph, bar, percentage, pace and the time to its reset.
function limitSegs(glyph: string, limit: StatusBarLimit, now: number): Seg[] {
  const pct = roundPct(limit.percentUsed)
  const gauge: Gauge = { pct, alt: `${WINDOW_LABEL[limit.kind] ?? limit.kind} ${pct}%` }
  const segs: Seg[] = [sep(), { text: `${glyph} ` }, ...tag(bar(pct), gauge), { text: ` ${pct}%`, color: PALETTE.cyan }]
  const ahead = pace(limit, now)
  if (ahead !== null) segs.push({ text: ` ${fmtPace(ahead)}`, color: paceColor(ahead) })
  const resetMs = limit.resetsAt === null ? Number.NaN : Date.parse(limit.resetsAt)
  if (Number.isFinite(resetMs)) segs.push({ text: ` · ${fmtReset(resetMs, now)}`, color: PALETTE.cyan })
  return segs
}

// The context pill's label: `84k/200k` when both figures are known, else the percentage.
function contextLabel(data: StatusData, pct: number): string {
  const tokens = data.contextTokens ?? null
  const window = data.contextWindow ?? null
  return tokens === null || window === null || window <= 0 ? `${pct}%` : `${fmtTokens(tokens)}/${fmtTokens(window)}`
}

// Group 2: context bar, then the 5h and 7d windows that have a reading.
export function usageGroup(data: StatusData): Seg[] {
  const ctx = roundPct(data.contextPercent)
  const label = contextLabel(data, ctx)
  const gauge: Gauge = { pct: ctx, alt: `context ${label} (${ctx}%)`, label }
  const segs: Seg[] = [{ text: '🧠 ' }, ...tag(bar(ctx), gauge), { text: ` ${ctx}%`, color: PALETTE.cyan }]
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
