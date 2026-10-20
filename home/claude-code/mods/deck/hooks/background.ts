// Pure helpers for the background agents panel: no `$`, no clock, no I/O. Each session is one
// ~/.claude/jobs/<id>/state.json, a format the engine does not document: parsed defensively, an
// entry that does not read is skipped rather than drawn wrong.
import type { DeckBgAgent, DeckBgEvent, DeckBgKind } from '../types'

import { redact } from './core'

export type { DeckBgKind }

/** Timeline steps an unfolded row shows. */
export const BG_TIMELINE = 5

/** A finished session older than this leaves the panel. */
export const BG_KEEP_MS = 24 * 60 * 60 * 1000

/** The panel's order: what waits on you first, what ended last. */
export const BG_ORDER: readonly DeckBgKind[] = ['needs-you', 'stalled', 'failed', 'working', 'other', 'stopped', 'done']

/**
 * The engine's state word as the panel groups it; a word it does not know is `other`. A `tempo`
 * of `active` (exact case) is `working` whatever the state: the session runs a turn now. A
 * `working` state whose `tempo` is `blocked`, both exact case as the claude-bg wrapper compares
 * them, is `needs-you` when it `asks` (a pending question: a non-empty `needs` or
 * `block.questions`), else `stalled`.
 */
export function bgKind(state: string, tempo = '', asks = false): DeckBgKind {
  if (tempo === 'active') return 'working'
  if (state === 'working' && tempo === 'blocked') return asks ? 'needs-you' : 'stalled'
  switch (state.toLowerCase()) {
    case 'working':
      return 'working'
    case 'blocked':
      return 'needs-you'
    case 'done':
    case 'completed':
      return 'done'
    case 'failed':
    case 'error':
      return 'failed'
    case 'stopped':
    case 'killed':
      return 'stopped'
    default:
      return 'other'
  }
}

const oneLine = (s: string) => s.replace(/\s+/g, ' ').trim()

/** A cwd's project: its last folder, a `<repo>/.claude/worktrees/<x>` read as `<repo>`. */
export function projectOf(cwd: string): string {
  const path = cwd.replace(/\/+$/, '')
  const repo = /^(.*)\/\.claude\/worktrees\/[^/]+$/.exec(path)?.[1] ?? path
  return repo.split('/').pop() || cwd
}

/** A cwd's repo root: the path without a trailing `/.claude/worktrees/<x>`. */
const rootOf = (cwd: string) => cwd.replace(/\/+$/, '').replace(/\/\.claude\/worktrees\/[^/]+$/, '')

/** The sessions of the project at `cwd`: same repo root, or a folder under it. */
export const inProject = (list: DeckBgAgent[], cwd: string): DeckBgAgent[] => {
  const root = rootOf(cwd)
  return list.filter(a => rootOf(a.cwd) === root || rootOf(a.cwd).startsWith(`${root}/`))
}

/** One state.json (its `tempo`, `needs` and `block.questions` read for `stalled` or `needs-you`), or null when it is no JSON object or lacks a string `state` or `cwd`. */
export function parseJobState(id: string, text: string): DeckBgAgent | null {
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    // Half-written or not JSON: skipped this poll.
    return null
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null
  const state: unknown = Reflect.get(value, 'state')
  const cwd: unknown = Reflect.get(value, 'cwd')
  if (typeof state !== 'string' || typeof cwd !== 'string') return null
  const name: unknown = Reflect.get(value, 'name')
  const detail: unknown = Reflect.get(value, 'detail')
  const updated: unknown = Reflect.get(value, 'updatedAt')
  const intent: unknown = Reflect.get(value, 'intent')
  const tokens: unknown = Reflect.get(value, 'tokens')
  const tempo: unknown = Reflect.get(value, 'tempo')
  const needs: unknown = Reflect.get(value, 'needs')
  const block: unknown = Reflect.get(value, 'block')
  const questions: unknown = typeof block === 'object' && block !== null ? Reflect.get(block, 'questions') : undefined
  const asks = (typeof needs === 'string' && needs !== '') || (Array.isArray(questions) && questions.length > 0)
  const at = typeof updated === 'string' ? Date.parse(updated) : Number.NaN
  return {
    id,
    name: typeof name === 'string' && oneLine(name) !== '' ? oneLine(name) : id,
    cwd,
    project: projectOf(cwd),
    state,
    kind: bgKind(state, typeof tempo === 'string' ? tempo : '', asks),
    detail: typeof detail === 'string' ? redact(oneLine(detail)) : '',
    intent: typeof intent === 'string' ? redact(oneLine(intent)) : '',
    tokens: typeof tokens === 'number' && Number.isFinite(tokens) ? tokens : null,
    updatedAt: Number.isFinite(at) ? at : 0,
  }
}

/**
 * A timeline.jsonl's last `max` steps, oldest first: a line that does not read, has no ISO `at` or
 * no non-empty `detail` is skipped; a detail repeated on the next line folds into its first.
 */
export function parseTimeline(text: string, max: number): DeckBgEvent[] {
  const events: DeckBgEvent[] = []
  for (const line of text.split('\n')) {
    if (line.trim() === '') continue
    let value: unknown
    try {
      value = JSON.parse(line)
    } catch {
      // Half-written last line or not JSON: skipped.
      continue
    }
    if (typeof value !== 'object' || value === null || Array.isArray(value)) continue
    const rawAt: unknown = Reflect.get(value, 'at')
    const rawDetail: unknown = Reflect.get(value, 'detail')
    const rawState: unknown = Reflect.get(value, 'state')
    const at = typeof rawAt === 'string' ? Date.parse(rawAt) : Number.NaN
    const detail = typeof rawDetail === 'string' ? redact(oneLine(rawDetail)) : ''
    if (!Number.isFinite(at) || detail === '') continue
    if (events[events.length - 1]?.detail === detail) continue
    events.push({ at, state: typeof rawState === 'string' ? oneLine(rawState) : '', detail })
  }
  return max > 0 ? events.slice(-max) : []
}

/**
 * What a needs-you session waits on, from its timeline.jsonl: the last paragraph (parts split on a
 * blank line) of the last line with a non-empty `text` (an agent reply), one line and redacted.
 * Without a reply, `detail` (already one line and redacted), unless it equals the `detail` of a
 * line without `text` (a user prompt): a prompt echo gives ''. A line that does not read is skipped.
 */
export function waitingText(timeline: string, detail: string): string {
  let reply = ''
  const prompts = new Set<string>()
  for (const line of timeline.split('\n')) {
    if (line.trim() === '') continue
    let value: unknown
    try {
      value = JSON.parse(line)
    } catch {
      // Half-written last line or not JSON: skipped.
      continue
    }
    if (typeof value !== 'object' || value === null || Array.isArray(value)) continue
    const rawText: unknown = Reflect.get(value, 'text')
    const text = typeof rawText === 'string' ? rawText.trim() : ''
    if (text !== '') {
      reply = text
      continue
    }
    const rawDetail: unknown = Reflect.get(value, 'detail')
    if (typeof rawDetail === 'string') prompts.add(redact(oneLine(rawDetail)))
  }
  const last = redact(oneLine(reply.split(/\n[ \t]*\n/).filter(p => p.trim() !== '').pop() ?? ''))
  if (last !== '') return last
  return prompts.has(detail) ? '' : detail
}

/** Without the finished sessions (done, stopped) last updated over BG_KEEP_MS ago. */
export const recentBg = (list: DeckBgAgent[], now: number): DeckBgAgent[] =>
  list.filter(a => !((a.kind === 'done' || a.kind === 'stopped') && now - a.updatedAt > BG_KEEP_MS))

/** In BG_ORDER, newest update first within a kind. */
export const sortBg = (list: DeckBgAgent[]): DeckBgAgent[] =>
  [...list].sort((a, b) => BG_ORDER.indexOf(a.kind) - BG_ORDER.indexOf(b.kind) || b.updatedAt - a.updatedAt)

/** How many sessions of each kind. */
export function bgCounts(list: DeckBgAgent[]): Record<DeckBgKind, number> {
  const counts: Record<DeckBgKind, number> = { 'needs-you': 0, stalled: 0, working: 0, failed: 0, done: 0, stopped: 0, other: 0 }
  for (const a of list) counts[a.kind] += 1
  return counts
}

/** The word a row shows: `needs you`, the kind, or an unknown state's own word. */
export const bgWord = (a: Pick<DeckBgAgent, 'kind' | 'state'>) => (a.kind === 'needs-you' ? 'needs you' : a.kind === 'other' ? a.state : a.kind)

/** The one-line summary's parts, in BG_ORDER, kinds with none left out: `1 needs you`, `2 working`. */
export const bgSummary = (list: DeckBgAgent[]): { kind: DeckBgKind; text: string }[] => {
  const counts = bgCounts(list)
  return BG_ORDER.filter(k => counts[k] > 0).map(k => ({ kind: k, text: `${counts[k]} ${k === 'needs-you' ? 'needs you' : k}` }))
}
