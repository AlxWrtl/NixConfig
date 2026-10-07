// apex-band: a band above the prompt showing the live APEX run of the
// session's working directory (title, colored step bar, mode, branch,
// baseline), read from <cwd>/.claude/output/apex/*/00-context.md. Draws
// nothing of its own when no run is live, or when the run's branch is not
// the one checked out (<cwd>/.git/HEAD); the bands of the mods beneath are
// always kept. /apex-pane opens the detail pane: phases with approximate
// token counts, one card per subagent, totals and cost, external verdict.
// Observes only: turn.step, tool.call and turn.complete hooks return
// next(e)'s result unchanged. Read-only: it never writes a file.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TextProps, Timer } from 'claude-code'

import type { ApexBandLoop, ApexBandPhases, ApexBandRun, ApexBandVerdict } from '../types'
import { layoutBand } from './band.ts'
import type { Seg } from './band.ts'
import { headBranch, isLive, onBranch, parseContext } from './context.ts'
import { layoutPane } from './pane.ts'
import { addPhase, addStep, applySnapshot, endLoop, endTool, parseVerdict, startTool, syncPhases } from './stats.ts'
import type { Usage } from './stats.ts'

const POLL_MS = 5000
const TICK_MS = 1000
const PANE = 'apex'
const TITLE = 'APEX'

const run = atom({ plugin: 'apex-band', key: 'run' } as const, null)
const loops = atom({ plugin: 'apex-band', key: 'loops' } as const, [])
const phases = atom({ plugin: 'apex-band', key: 'phases' } as const, { dir: null, byStep: {} })
const now = atom({ plugin: 'apex-band', key: 'now' } as const, 0)
const cost = atom({ plugin: 'apex-band', key: 'cost' } as const, null)
const verdict = atom({ plugin: 'apex-band', key: 'verdict' } as const, null)

// Module-level: a hot reload drops the environment and its timers with it.
let timer: Timer | undefined
// The pane's per-second tick, alive only while the pane is open.
let fastTimer: Timer | undefined

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
  return onBranch(parsed, head) ? { ...parsed, dir: newest.dir } : null
}

// Applies a pure change to the loops, writing only when they changed (the
// state library reads and writes named atoms only: one helper per atom).
async function changeLoops($: EngineInterface, fn: (value: ApexBandLoop[]) => ApexBandLoop[]): Promise<void> {
  const current = await read($, loops)
  if (fn(current) === current) return
  await update($, loops, fn)
}

async function changePhases($: EngineInterface, fn: (value: ApexBandPhases) => ApexBandPhases): Promise<void> {
  const current = await read($, phases)
  if (fn(current) === current) return
  await update($, phases, fn)
}

// Writes the verdict unless it already holds an equal one.
async function putVerdict($: EngineInterface, value: ApexBandVerdict | null): Promise<void> {
  if (JSON.stringify(await read($, verdict)) === JSON.stringify(value)) return
  await update($, verdict, () => value)
}

async function putCost($: EngineInterface, value: number | null): Promise<void> {
  if ((await read($, cost)) === value) return
  await update($, cost, () => value)
}

async function putNow($: EngineInterface, value: number): Promise<void> {
  if ((await read($, now)) === value) return
  await update($, now, () => value)
}

// The run's external-verify.json, re-read only when its mtime moved.
async function refreshVerdict($: EngineInterface, found: ApexBandRun | null): Promise<void> {
  const dir = found?.dir
  if (dir === undefined) {
    await putVerdict($, null)
    return
  }
  const path = `${await $.session.cwd()}/.claude/output/apex/${dir}/external-verify.json`
  let mtimeMs: number
  try {
    mtimeMs = (await $.fs.stat(path)).mtimeMs
  } catch {
    // No external verification yet for this run.
    await putVerdict($, null)
    return
  }
  const current = await read($, verdict)
  if (current !== null && current.dir === dir && current.mtimeMs === mtimeMs) return
  let next: ApexBandVerdict | null = null
  try {
    const parsed = parseVerdict(await $.fs.read(path))
    if (parsed !== null) next = { dir, mtimeMs, ...parsed }
  } catch {
    // Vanished between stat and read, or over 4 MiB: shown as pending.
    next = null
  }
  await putVerdict($, next)
}

// The agent list applied to the known loops: labels, types, ends.
async function snapshot($: EngineInterface): Promise<void> {
  const at = await $.clock.now()
  const list = await $.agent.list()
  const agents = list.map(a => ({ id: a.id, description: a.description, type: a.type, status: a.status }))
  await changeLoops($, current => applySnapshot(current, agents, at))
}

// A segment's Text props: only the styles it sets, never an undefined prop.
function segProps(seg: Seg): TextProps {
  return {
    ...(seg.tone === undefined ? {} : { color: seg.tone }),
    ...(seg.dim === true ? { dimColor: true } : {}),
    ...(seg.bold === true ? { bold: true } : {}),
  }
}

async function refresh($: EngineInterface): Promise<void> {
  const found = await scan($)
  const current = await read($, run)
  if (JSON.stringify(current) !== JSON.stringify(found)) await update($, run, () => found)
  // Another run (or none): its buckets start over, never restored later.
  const dir = found?.dir ?? null
  await changePhases($, value => syncPhases(value, dir))
  await refreshVerdict($, found)
  await snapshot($)
}

// The pane's second: agents, cost, and the clock while a loop runs.
async function fastTick($: EngineInterface): Promise<void> {
  const at = await $.clock.now()
  await snapshot($)
  const usage = await $.session.usage()
  await putCost($, usage.cost?.usd ?? null)
  if ((await read($, loops)).some(l => l.status === 'running')) await putNow($, at)
}

function onFastTick($: EngineInterface): void {
  fastTick($).catch(() => {
    // Agent list or usage refused: the pane keeps its figures; the next
    // tick (TICK_MS later) tries again.
  })
}

// Runs `write`; a refused state write leaves the counters as they were (an
// observer never fails the event it watches).
async function record(write: () => Promise<void>): Promise<void> {
  try {
    await write()
  } catch {
    // Counters only: the next step, call or poll writes again.
  }
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
    try {
      await $.command.register({
        name: 'apex-pane',
        description: 'Ouvre le détail du run APEX (phases, sous-agents, tokens, vérif externe)',
        immediate: true,
      })
    } catch {
      // Refused registration: no /apex-pane this session, the band still runs.
    }
    return next(e)
  })

  on('command.run', { command: 'apex-pane' }, async $ => {
    ensurePolling($)
    const at = await $.clock.now()
    await update($, now, () => at)
    // Opened first: a refused open throws before any 1 s tick is armed. An
    // unplaced pane is still open (seated once a surface places it): ticked.
    await $.ui.open({ id: PANE, title: TITLE })
    onFastTick($)
    fastTimer ??= $.clock.every(TICK_MS, () => onFastTick($))
    return { text: 'Détail du run APEX ouvert.' }
  })

  // The tick stops once the close went through: a hook beneath that keeps
  // the pane open (answering, or throwing) keeps its figures live.
  on('ui.close', async ($, e, next) => {
    const closed = await next(e)
    if (e.id === PANE) {
      fastTimer?.cancel()
      fastTimer = undefined
    }
    return closed
  }).catch(($, e, next) => next(e))

  // Each model response: a step and its usage for its loop, and the usage
  // for the run's current step (approximate: the step as last polled).
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const usage: Usage | null = result.usage
    await record(async () => {
      const at = await $.clock.now()
      await changeLoops($, current => addStep(current, { agentId: e.agentId, model: e.model, usage }, at))
      const live = await read($, run)
      const dir = live?.dir
      if (dir !== undefined) await changePhases($, current => addPhase(current, dir, live?.currentStep, usage))
    })
    return result
  }).catch(async function* ($, e, next) {
    return yield* next(e)
  })

  // Each tool call: counted and shown as its loop's current tool while it runs.
  on('tool.call', async ($, e, next) => {
    const { agentId, tool, tool_use_id: toolUseId } = e
    await record(async () => {
      const at = await $.clock.now()
      await changeLoops($, current => startTool(current, { agentId, tool, toolUseId }, at))
    })
    const ran = await next(e)
    await record(() => changeLoops($, current => endTool(current, agentId, toolUseId)))
    return ran
  }).catch(($, e, next) => next(e))

  // A loop's turn ended: its status and the turn's duration.
  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    await record(async () => {
      const at = await $.clock.now()
      await changeLoops($, current => endLoop(current, e.agentId, e.reason, e.durationMs, at))
    })
    return done
  }).catch(($, e, next) => next(e))

  on('prompt.submit', ($, e, next) => {
    ensurePolling($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      // A /clear starts the counting over; the timers are kept for it.
      await update($, loops, () => [])
      await update($, phases, () => ({ dir: null, byStep: {} }))
      await update($, verdict, () => null)
      await update($, cost, () => null)
    } else {
      // No session.start follows a /clear: the timer is kept for it.
      timer?.cancel()
      timer = undefined
      fastTimer?.cancel()
      fastTimer = undefined
    }
    return next(e)
  })

  // The pane: reads state only, every line within the body's columns.
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const lines = layoutPane(
      {
        run: await read($, run),
        loops: await read($, loops),
        phases: await read($, phases),
        now: await read($, now),
        cost: await read($, cost),
        verdict: await read($, verdict),
      },
      e.props.bodyColumns,
    )
    return (
      <Box flexDirection="column">
        {lines.map(line => (
          <Box flexDirection="row">
            {line.map(seg => (
              <Text {...segProps(seg)} wrap="truncate-end">
                {seg.text}
              </Text>
            ))}
          </Box>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, run)
    if (current === null || e.props.hasSurvey) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const lines = layoutBand(current, e.props.bodyColumns, e.props.maxRows)
    // The later mods' band, kept under ours (a tree replaces it otherwise).
    const theirs = await next(e)
    return (
      <Box flexDirection="column">
        {lines.map(line => (
          <Box flexDirection="row">
            {line.map(seg => (
              <Text {...segProps(seg)} wrap="truncate-end">
                {seg.text}
              </Text>
            ))}
          </Box>
        ))}
        {theirs}
      </Box>
    )
  })
}
