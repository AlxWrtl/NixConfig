// The deck's one host command: `claude-bg resume <id>` for a stalled background row, by its
// absolute path and an argument vector (no shell). The id is checked here again (eight lowercase
// hex digits) before it reaches the argv; the wrapper checks it once more, then reads the job's
// state.json itself. One run per id at a time: a second press while the first runs does nothing.
import type { EngineInterface } from 'claude-code'

import { redact } from './core'

/** A background session id as ~/.claude/jobs names it: eight lowercase hex digits. */
const ID = /^[0123456789abcdef]{8}$/

/** The ids whose resume is under way. */
const inFlight = new Set<string>()

/** What the press came to, for the session log: `ok` when the wrapper exited 0. */
export type ResumeOutcome = { ok: boolean; text: string }

/** The first non-empty line of the wrapper's stderr, redacted, at most 120 characters. */
const firstLine = (text: string): string => {
  const line = text.split('\n').find(l => l.trim() !== '') ?? ''
  const one = redact(line.replace(/\s+/g, ' ').trim())
  return one.length > 120 ? `${one.slice(0, 119)}…` : one
}

/**
 * Resumes the stalled background session `id` through the wrapper; null when a resume of the
 * same id is already under way (nothing to log).
 */
export async function resumeBg($: EngineInterface, id: string): Promise<ResumeOutcome | null> {
  if (!ID.test(id)) return { ok: false, text: 'id invalide' }
  if (inFlight.has(id)) return null
  inFlight.add(id)
  try {
    const r = await $.process.run(['/etc/profiles/per-user/alx/bin/claude-bg', 'resume', id], { timeoutMs: 60000 })
    if (r.exitCode === 0) return { ok: true, text: 'relancé' }
    const why = firstLine(r.stderr)
    return { ok: false, text: why === '' ? `exit ${r.exitCode}` : `exit ${r.exitCode} · ${why}` }
  } catch (e) {
    // Could not start, or still running at 60 s: the job may have resumed all the same.
    const why = e instanceof Error ? firstLine(e.message) : ''
    const text = 'échec ou pas de retour en 60 s — voir le panneau'
    return { ok: false, text: why === '' ? text : `${text} · ${why}` }
  } finally {
    inFlight.delete(id)
  }
}
