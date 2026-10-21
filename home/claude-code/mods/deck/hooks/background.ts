// Pure helpers for the background agents panel: no `$`, no clock, no I/O. Each session is one
// ~/.claude/session-state/<name>.json, written by hooks/session-state.js for an abduco session
// that claude-dispatch named: parsed defensively, an entry that does not read is skipped rather
// than drawn wrong.
import type { DeckBgAgent, DeckBgKind } from '../types'

import { redact } from './core'

export type { DeckBgKind }

/** A session name as claude-dispatch gives it and session-state.js checks it. */
export const SESSION_NAME = /^[a-z0-9][a-z0-9-]{0,47}$/

/** A session silent this long leaves the panel, a finished one included. */
export const BG_KEEP_MS = 24 * 60 * 60 * 1000

/** The panel's order: what waits on you first, what ended last. */
export const BG_ORDER: readonly DeckBgKind[] = ['needs-you', 'waiting', 'idle', 'working', 'other', 'done']

/**
 * The state word as session-state.js writes it (exact case): Notification `needs-you`, Stop
 * `waiting`, SessionStart `idle`, UserPromptSubmit `working`, SessionEnd `done`; any other word
 * is `other`.
 */
export function sessionKind(state: string): DeckBgKind {
  switch (state) {
    case 'needs-you':
    case 'waiting':
    case 'idle':
    case 'working':
    case 'done':
      return state
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

/**
 * One `<name>.json` (`name` its file stem), or null when the stem is no session name, the text
 * no JSON object, `state` or `cwd` no string, or its own `name` another than the stem.
 */
export function parseSessionState(name: string, text: string): DeckBgAgent | null {
  if (!SESSION_NAME.test(name)) return null
  let value: unknown
  try {
    value = JSON.parse(text)
  } catch {
    // Not JSON (the writer renames whole files, so never half a file): skipped this poll.
    return null
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null
  const state: unknown = Reflect.get(value, 'state')
  const cwd: unknown = Reflect.get(value, 'cwd')
  if (typeof state !== 'string' || typeof cwd !== 'string') return null
  if (Reflect.get(value, 'name') !== name) return null
  const notice: unknown = Reflect.get(value, 'notice')
  const intent: unknown = Reflect.get(value, 'intent')
  const updated: unknown = Reflect.get(value, 'updatedAt')
  const at = typeof updated === 'string' ? Date.parse(updated) : Number.NaN
  return {
    id: name,
    name,
    cwd,
    project: projectOf(cwd),
    state,
    kind: sessionKind(state),
    detail: typeof notice === 'string' ? redact(oneLine(notice)) : '',
    intent: typeof intent === 'string' ? redact(oneLine(intent)) : '',
    updatedAt: Number.isFinite(at) ? at : 0,
  }
}

/**
 * Without the sessions silent over BG_KEEP_MS: a finished one, or one whose session died without
 * its SessionEnd (the deck does not ask abduco).
 */
export const recentBg = (list: DeckBgAgent[], now: number): DeckBgAgent[] => list.filter(a => now - a.updatedAt <= BG_KEEP_MS)

/** In BG_ORDER, newest update first within a kind. */
export const sortBg = (list: DeckBgAgent[]): DeckBgAgent[] =>
  [...list].sort((a, b) => BG_ORDER.indexOf(a.kind) - BG_ORDER.indexOf(b.kind) || b.updatedAt - a.updatedAt)

/** How many sessions of each kind. */
export function bgCounts(list: DeckBgAgent[]): Record<DeckBgKind, number> {
  const counts: Record<DeckBgKind, number> = { 'needs-you': 0, waiting: 0, idle: 0, working: 0, other: 0, done: 0 }
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
