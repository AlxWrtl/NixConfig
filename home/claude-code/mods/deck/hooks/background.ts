// Pure helpers for the background agents panel: no `$`, no clock, no I/O. Each session is one
// ~/.claude/jobs/<id>/state.json, a format the engine does not document: parsed defensively, an
// entry that does not read is skipped rather than drawn wrong.
import type { DeckBgAgent, DeckBgKind } from '../types'

import { redact } from './core'

export type { DeckBgKind }

/** A finished session older than this leaves the panel. */
export const BG_KEEP_MS = 24 * 60 * 60 * 1000

/** The panel's order: what waits on you first, what ended last. */
export const BG_ORDER: readonly DeckBgKind[] = ['needs-you', 'failed', 'working', 'other', 'stopped', 'done']

/** The engine's state word as the panel groups it; a word it does not know is `other`. */
export function bgKind(state: string): DeckBgKind {
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

/** One state.json, or null when it is no JSON object or lacks a string `state` or `cwd`. */
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
  const at = typeof updated === 'string' ? Date.parse(updated) : Number.NaN
  return {
    id,
    name: typeof name === 'string' && oneLine(name) !== '' ? oneLine(name) : id,
    cwd,
    project: projectOf(cwd),
    state,
    kind: bgKind(state),
    detail: typeof detail === 'string' ? redact(oneLine(detail)) : '',
    updatedAt: Number.isFinite(at) ? at : 0,
  }
}

/** Without the finished sessions (done, stopped) last updated over BG_KEEP_MS ago. */
export const recentBg = (list: DeckBgAgent[], now: number): DeckBgAgent[] =>
  list.filter(a => !((a.kind === 'done' || a.kind === 'stopped') && now - a.updatedAt > BG_KEEP_MS))

/** In BG_ORDER, newest update first within a kind. */
export const sortBg = (list: DeckBgAgent[]): DeckBgAgent[] =>
  [...list].sort((a, b) => BG_ORDER.indexOf(a.kind) - BG_ORDER.indexOf(b.kind) || b.updatedAt - a.updatedAt)

/** How many sessions of each kind. */
export function bgCounts(list: DeckBgAgent[]): Record<DeckBgKind, number> {
  const counts: Record<DeckBgKind, number> = { 'needs-you': 0, working: 0, failed: 0, done: 0, stopped: 0, other: 0 }
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
