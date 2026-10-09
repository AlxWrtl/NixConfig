// Pure bookkeeping of the pane's journal, turn receipts, compaction counts
// and context gauge. Every function returns the same reference when nothing
// changed, so a caller can skip the write.

import type {
  ApexBandGauge,
  ApexBandLimit,
  ApexBandLogEntry,
  ApexBandLogKind,
  ApexBandReceipt,
  ApexBandReceipts,
} from '../types'
import { cutText, oneLine } from './stats.ts'

// How many journal entries are kept (the oldest dropped first).
export const LOG_CAP = 50

// The longest journal line kept.
export const LOG_TEXT_CAP = 160

// An entry pushed on the journal, its text on one line and cut at
// LOG_TEXT_CAP; the last LOG_CAP kept, newest last. Empty text: unchanged.
export function pushLog(log: ApexBandLogEntry[], entry: { at: number; kind: ApexBandLogKind; text: string }): ApexBandLogEntry[] {
  const text = cutText(oneLine(entry.text), LOG_TEXT_CAP)
  if (text === '') return log
  return [...log, { at: entry.at, kind: entry.kind, text }].slice(-LOG_CAP)
}

// No turn under way, none ended yet.
export const NO_RECEIPTS: ApexBandReceipts = { current: null, last: null }

// A main-loop turn began: its receipt opened with the session's cost so far
// (null: unknown). The same turn again: unchanged. A turn still open is
// replaced (its end never came).
export function startReceipt(
  receipts: ApexBandReceipts,
  turn: { turnId: string; at: number; cost: number | null },
): ApexBandReceipts {
  if (receipts.current?.turnId === turn.turnId) return receipts
  const current: ApexBandReceipt = {
    turnId: turn.turnId,
    startedAt: turn.at,
    agents: [],
    edits: [],
    errors: 0,
    costAtStart: turn.cost,
  }
  return { ...receipts, current }
}

// The open receipt changed by `fn`; unchanged without one or when `fn`
// returns it as is.
function withCurrent(receipts: ApexBandReceipts, fn: (r: ApexBandReceipt) => ApexBandReceipt): ApexBandReceipts {
  const current = receipts.current
  if (current === null) return receipts
  const next = fn(current)
  return next === current ? receipts : { ...receipts, current: next }
}

// A subagent launched during the open turn, each id once.
export const receiptAgent = (receipts: ApexBandReceipts, agentId: string): ApexBandReceipts =>
  withCurrent(receipts, r => (agentId === '' || r.agents.includes(agentId) ? r : { ...r, agents: [...r.agents, agentId] }))

// A file edited during the open turn, each path once.
export const receiptEdit = (receipts: ApexBandReceipts, path: string): ApexBandReceipts =>
  withCurrent(receipts, r => (path === '' || r.edits.includes(path) ? r : { ...r, edits: [...r.edits, path] }))

// A tool call failed during the open turn.
export const receiptError = (receipts: ApexBandReceipts): ApexBandReceipts =>
  withCurrent(receipts, r => ({ ...r, errors: r.errors + 1 }))

// The open turn ended: its duration (the turn's own when given, else the
// clock's), its reason and the cost it added (both costs known) kept; it
// becomes the last receipt. No open turn: unchanged.
export function endReceipt(
  receipts: ApexBandReceipts,
  end: { at: number; durationMs?: number; reason: string; cost: number | null },
): ApexBandReceipts {
  const current = receipts.current
  if (current === null) return receipts
  const given = end.durationMs !== undefined && Number.isFinite(end.durationMs) && end.durationMs > 0
  const durationMs = given ? (end.durationMs ?? 0) : Math.max(0, end.at - current.startedAt)
  const delta = end.cost !== null && current.costAtStart !== null ? Math.max(0, end.cost - current.costAtStart) : undefined
  const last: ApexBandReceipt = {
    ...current,
    endedAt: end.at,
    durationMs,
    reason: end.reason,
    ...(delta === undefined ? {} : { costDelta: delta }),
  }
  return { current: null, last }
}

// The tools that write a file.
const EDIT_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit'])

export const isEditTool = (tool: string): boolean => EDIT_TOOLS.has(tool)

// The path an edit tool's input names (file_path, or a notebook's
// notebook_path); undefined for other tools or a malformed input.
export function editPath(tool: string, input: unknown): string | undefined {
  if (!isEditTool(tool) || typeof input !== 'object' || input === null) return undefined
  const value: unknown = Reflect.get(input, tool === 'NotebookEdit' ? 'notebook_path' : 'file_path')
  return typeof value === 'string' && value !== '' ? value : undefined
}

// The trigger session.compact fires for while precomputing a summary ahead
// of need: not a compaction the user sees.
const PRECOMPUTE = 'precompute'

// A compaction counted under its trigger; a precompute one: unchanged.
export function addCompaction(compactions: Record<string, number>, trigger: string): Record<string, number> {
  if (trigger === PRECOMPUTE || trigger === '') return compactions
  return { ...compactions, [trigger]: (compactions[trigger] ?? 0) + 1 }
}

// All compactions counted, triggers summed.
export const compactionCount = (compactions: Record<string, number>): number =>
  Object.values(compactions).reduce((sum, n) => sum + n, 0)

// What gaugeOf reads of session.usage.
export type UsageReading = {
  context: { tokens?: number; window: number; percent?: number }
  rateLimits: readonly { kind: string; percentUsed: number; resetsAt?: string }[]
}

const finite = (n: number | undefined): n is number => n !== undefined && Number.isFinite(n)

// Two gauges equal field by field.
function sameGauge(a: ApexBandGauge, b: ApexBandGauge): boolean {
  if (a.percent !== b.percent || a.tokens !== b.tokens || a.window !== b.window) return false
  if (a.limits.length !== b.limits.length) return false
  return a.limits.every((l, i) => {
    const o = b.limits[i]
    return o !== undefined && l.kind === o.kind && l.percent === o.percent && l.resetsAt === o.resetsAt
  })
}

// The gauge session.usage gives: context percent (its own, else tokens over
// window), tokens, window, and each rate-limit window with its reset parsed
// to ms (left out when unparsable). `prev` when equal to it.
export function gaugeOf(usage: UsageReading, prev: ApexBandGauge | null = null): ApexBandGauge {
  const { tokens, window, percent } = usage.context
  const size = finite(window) && window > 0 ? window : 0
  const used = finite(tokens) && tokens >= 0 ? tokens : null
  const pct = finite(percent) ? percent : used !== null && size > 0 ? Math.round((used / size) * 1000) / 10 : null
  const limits = usage.rateLimits
    .filter(l => l.kind !== '' && Number.isFinite(l.percentUsed))
    .map((l): ApexBandLimit => {
      const at = l.resetsAt === undefined ? Number.NaN : Date.parse(l.resetsAt)
      return Number.isFinite(at) ? { kind: l.kind, percent: l.percentUsed, resetsAt: at } : { kind: l.kind, percent: l.percentUsed }
    })
  const gauge: ApexBandGauge = { percent: pct, tokens: used, window: size, limits }
  return prev !== null && sameGauge(prev, gauge) ? prev : gauge
}
