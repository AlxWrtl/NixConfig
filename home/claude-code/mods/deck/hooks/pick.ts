// The deck's one host command: `agent-pane pick <name>` for a background row, by its absolute
// path and an argument vector (no shell): the agent screen's top pane then shows that abduco
// session. The name is checked here again (claude-dispatch's rule) before it reaches the argv;
// agent-pane checks it once more. One run per name at a time: a second press while the first
// runs does nothing.
import type { EngineInterface } from 'claude-code'

import { SESSION_NAME } from './background'
import { redact } from './core'

/** The names whose pick is under way. */
const inFlight = new Set<string>()

/** What the press came to, for the session log: `ok` when agent-pane exited 0. */
export type PickOutcome = { ok: boolean; text: string }

/** The first non-empty line of agent-pane's stderr, redacted, at most 120 characters. */
const firstLine = (text: string): string => {
  const line = text.split('\n').find(l => l.trim() !== '') ?? ''
  const one = redact(line.replace(/\s+/g, ' ').trim())
  return one.length > 120 ? `${one.slice(0, 119)}…` : one
}

/**
 * Shows the session `name` in the agent screen's top pane; null when a pick of the same name is
 * already under way (nothing to log).
 */
export async function pickSession($: EngineInterface, name: string): Promise<PickOutcome | null> {
  if (!SESSION_NAME.test(name)) return { ok: false, text: 'nom invalide' }
  if (inFlight.has(name)) return null
  inFlight.add(name)
  try {
    const r = await $.process.run(['/etc/profiles/per-user/alx/bin/agent-pane', 'pick', name], { timeoutMs: 5000 })
    if (r.exitCode === 0) return { ok: true, text: 'affichée en haut' }
    const why = firstLine(r.stderr)
    return { ok: false, text: why === '' ? `exit ${r.exitCode}` : `exit ${r.exitCode} · ${why}` }
  } catch (e) {
    // Could not start, or still running at 5 s: the pane may have switched all the same.
    const why = e instanceof Error ? firstLine(e.message) : ''
    const text = 'échec ou pas de retour en 5 s'
    return { ok: false, text: why === '' ? text : `${text} · ${why}` }
  } finally {
    inFlight.delete(name)
  }
}
