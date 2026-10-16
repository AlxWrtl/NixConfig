// The deck's second host command: `claude-bg open <id>` for any background row, by its absolute
// path and an argument vector (no shell). The wrapper opens a new Ghostty window running
// `claude attach <id>`, so the session can be answered without the agents view. The id is checked
// here again (eight lowercase hex digits) before it reaches the argv; the wrapper checks it once
// more and requires the job's state.json. One run per id at a time: a second press while the
// first runs does nothing.
import type { EngineInterface } from 'claude-code'

import { redact } from './core'

/** A background session id as ~/.claude/jobs names it: eight lowercase hex digits. */
const ID = /^[0123456789abcdef]{8}$/

/** The ids whose window is being opened. */
const inFlight = new Set<string>()

/** What the press came to, for the session log: `ok` when the wrapper exited 0. */
export type OpenOutcome = { ok: boolean; text: string }

/** The first non-empty line of the wrapper's stderr, redacted, at most 120 characters. */
const firstLine = (text: string): string => {
  const line = text.split('\n').find(l => l.trim() !== '') ?? ''
  const one = redact(line.replace(/\s+/g, ' ').trim())
  return one.length > 120 ? `${one.slice(0, 119)}…` : one
}

/**
 * Opens a Ghostty window attached to the background session `id` through the wrapper; null when
 * an open of the same id is already under way (nothing to log).
 */
export async function openBg($: EngineInterface, id: string): Promise<OpenOutcome | null> {
  if (!ID.test(id)) return { ok: false, text: 'id invalide' }
  if (inFlight.has(id)) return null
  inFlight.add(id)
  try {
    const r = await $.process.run(['/etc/profiles/per-user/alx/bin/claude-bg', 'open', id], { timeoutMs: 15000 })
    if (r.exitCode === 0) return { ok: true, text: 'ouvert' }
    const why = firstLine(r.stderr)
    return { ok: false, text: why === '' ? `exit ${r.exitCode}` : `exit ${r.exitCode} · ${why}` }
  } catch (e) {
    // Could not start, or still running at 15 s: the window may have opened all the same.
    const why = e instanceof Error ? firstLine(e.message) : ''
    return { ok: false, text: why === '' ? 'échec' : `échec · ${why}` }
  } finally {
    inFlight.delete(id)
  }
}
