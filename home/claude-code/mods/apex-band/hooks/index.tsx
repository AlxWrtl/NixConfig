// apex-band: a band above the prompt showing the live APEX run of the
// session's working directory (title, mode, current step, branch,
// baseline), read from <cwd>/.claude/output/apex/*/00-context.md. Draws
// nothing when no run is live, or when the run's branch is not the one
// checked out (<cwd>/.git/HEAD). Read-only: it never writes a file.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { ApexBandRun } from '../types'
import { layoutBand } from './band.ts'
import { headBranch, isLive, onBranch, parseContext } from './context.ts'

const POLL_MS = 5000

const run = atom({ plugin: 'apex-band', key: 'run' } as const, null)

// Module-level: a hot reload drops the environment and its timers with it.
let timer: Timer | undefined

// The newest run's context file and its mtime, or undefined.
async function newestContext(
  $: EngineInterface,
  root: string,
): Promise<{ path: string; dir: string; mtimeMs: number } | undefined> {
  let entries
  try {
    entries = await $.fs.list(root)
  } catch {
    // No .claude/output/apex here (or unreadable): no run to show.
    return undefined
  }
  let best: { path: string; dir: string; mtimeMs: number } | undefined
  for (const entry of entries) {
    if (entry.kind !== 'dir') continue
    const path = `${root}/${entry.name}/00-context.md`
    try {
      const stat = await $.fs.stat(path)
      if (best === undefined || stat.mtimeMs > best.mtimeMs) best = { path, dir: entry.name, mtimeMs: stat.mtimeMs }
    } catch {
      // A run directory without its context file is not a run: skipped.
    }
  }
  return best
}

async function scan($: EngineInterface): Promise<ApexBandRun | null> {
  const cwd = await $.session.cwd()
  const newest = await newestContext($, `${cwd}/.claude/output/apex`)
  if (newest === undefined) return null
  let text: string
  try {
    text = await $.fs.read(newest.path)
  } catch {
    // Vanished between stat and read, or over 4 MiB: nothing shown this round.
    return null
  }
  const parsed = parseContext(text, newest.dir)
  if (!isLive(parsed, newest.mtimeMs, await $.clock.now())) return null
  let head: string | undefined
  try {
    head = headBranch(await $.fs.read(`${cwd}/.git/HEAD`))
  } catch {
    // No repo here, or a worktree whose .git is a file: branch unknown, shown.
    head = undefined
  }
  return onBranch(parsed, head) ? parsed : null
}

async function refresh($: EngineInterface): Promise<void> {
  const found = await scan($)
  const current = await read($, run)
  if (JSON.stringify(current) === JSON.stringify(found)) return
  await update($, run, () => found)
}

function onTick($: EngineInterface): void {
  refresh($).catch(() => {
    // A failed scan or a refused write leaves the band as it was; the next
    // tick (POLL_MS later) tries again.
  })
}

// Started from session.start and lazily from prompt.submit: session.start
// does not fire again after a hot reload.
function ensurePolling($: EngineInterface): void {
  if (timer !== undefined) return
  timer = $.clock.every(POLL_MS, () => onTick($))
  $.clock.after(0, () => onTick($))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    ensurePolling($)
    return next(e)
  })

  on('prompt.submit', ($, e, next) => {
    ensurePolling($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.end', async ($, e, next) => {
    if (e.reason !== 'clear') {
      // No session.start follows a /clear: the timer is kept for it.
      timer?.cancel()
      timer = undefined
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, run)
    if (current === null || e.props.hasSurvey) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const lines = layoutBand(current, e.props.bodyColumns, e.props.maxRows)
    return (
      <Box flexDirection="column">
        {lines.map(line => (
          <Text dimColor wrap="truncate-end">
            {line}
          </Text>
        ))}
      </Box>
    )
  })
}
