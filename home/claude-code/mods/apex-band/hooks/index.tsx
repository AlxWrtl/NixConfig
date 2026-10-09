// apex-band: one detail pane on demand, fed by observers.
// /apex-pane (and its alias /task-board) opens the pane; it never opens by
// itself. It shows the live APEX run of the session's working directory
// (title, phases, cost), read from <cwd>/.claude/output/apex/*/00-context.md;
// the main loop and its subagents; the background shells; the receipt, the
// journal and the gauge; what asks the user to act (a failed step, a red
// external verification, a spent correction budget). Nothing is drawn above
// the prompt: that band belongs to another mod.
// Motion: the rail's head and the agents' clocks are surface modules
// (./rail.ts, ./elapsed.ts) drawn as Clients where the surface has them
// (terminal, desktop), each on its own timer; elsewhere, or once a Client
// failed (ui.fault), the same frame as static text.
// Observes only: every hook but the commands and the renders returns
// next(e)'s result unchanged. Read-only: it never writes a file.
// Calm: the 1 s tick (agent list) runs only while a subagent or a shell
// works or the pane is open; the host clock moves only while the pane is
// open (each second); the 5 s poll writes nothing that did not change.

import { atom, read, update } from 'claude-code'
import type { Elements, EngineInterface, Register, RenderNode, RenderSurface, TextProps, Timer } from 'claude-code'

import type {
  ApexBandBudget,
  ApexBandGauge,
  ApexBandLogEntry,
  ApexBandLoop,
  ApexBandPhases,
  ApexBandReceipts,
  ApexBandRun,
  ApexBandShell,
  ApexBandVerdict,
} from '../types'
import { blockLoops } from './agents.ts'
import { clientProps, textCells } from './band.ts'
import type { Seg } from './band.ts'
import { headBranch, isLive, onBranch, parseContext } from './context.ts'
import {
  NO_RECEIPTS,
  addCompaction,
  editPath,
  endReceipt,
  gaugeOf,
  isEditTool,
  pushLog,
  receiptAgent,
  receiptEdit,
  receiptError,
  startReceipt,
} from './journal.ts'
import type { UsageReading } from './journal.ts'
import { MAX_DONE, layoutPane, paneHotkeys } from './pane.ts'
import type { PaneInput } from './pane.ts'
import {
  addShell,
  closeBySnapshot,
  closeOrphanShells,
  finishByNotification,
  parseTaskNotifications,
  runningShells,
  stopShell,
} from './shells.ts'
import type { Notification } from './shells.ts'
import { alertsOf, budgetOf, pickVerdict } from './signals.ts'
import {
  MAIN,
  addPhase,
  addStep,
  applySnapshot,
  endLoop,
  endTool,
  endedOwners,
  launchLoop,
  listedIds,
  noteAnswer,
  noteSpawn,
  parseVerdict,
  pathTail,
  reasonStatus,
  startTool,
  subagentsRunning,
  syncPhases,
  toolTarget,
} from './stats.ts'
import type { Usage } from './stats.ts'

const POLL_MS = 5000
const TICK_MS = 1000
const PANE = 'apex'
const TITLE = 'APEX'
// What the pane asks for: rows inline, columns docked (requests only).
const PANE_ROWS = 30
const PANE_COLUMNS = 100
// The two names the external verification is written under, in a run dir.
const VERIFY_NAMES = ['04-external-verify.json', 'external-verify.json']

const run = atom({ plugin: 'apex-band', key: 'run' } as const, null)
const loops = atom({ plugin: 'apex-band', key: 'loops' } as const, [])
const phases = atom({ plugin: 'apex-band', key: 'phases' } as const, { dir: null, byStep: {} })
const now = atom({ plugin: 'apex-band', key: 'now' } as const, 0)
const cost = atom({ plugin: 'apex-band', key: 'cost' } as const, null)
const verdict = atom({ plugin: 'apex-band', key: 'verdict' } as const, null)
const shells = atom({ plugin: 'apex-band', key: 'shells' } as const, [])
const budget = atom({ plugin: 'apex-band', key: 'budget' } as const, null)
const log = atom({ plugin: 'apex-band', key: 'log' } as const, [])
const receipts = atom({ plugin: 'apex-band', key: 'receipts' } as const, NO_RECEIPTS)
const gauge = atom({ plugin: 'apex-band', key: 'gauge' } as const, null)
const compactions = atom({ plugin: 'apex-band', key: 'compactions' } as const, {})
const expanded = atom({ plugin: 'apex-band', key: 'expanded' } as const, null)
const isOpen = atom({ plugin: 'apex-band', key: 'isOpen' } as const, false)
const showAll = atom({ plugin: 'apex-band', key: 'showAll' } as const, false)

// Module-level: a hot reload drops the environment and its timers with it.
let timer: Timer | undefined
// The 1 s tick, alive only while something runs or the pane is open.
let fastTimer: Timer | undefined
// Set once a Client of ours failed (ui.fault): static text from then on.
let clientsOff = false

// The element table of one surface, as $.ui.resolve(e) hands it.
type Table = Elements[keyof Elements]

// Reads a field of an engine record whose shape varies per tool; a value
// that is not a non-empty string reads as undefined.
function stringField(record: unknown, key: string): string | undefined {
  if (typeof record !== 'object' || record === null) return undefined
  const value: unknown = Reflect.get(record, key)
  return typeof value === 'string' && value !== '' ? value : undefined
}

function numberField(record: unknown, key: string): number | undefined {
  if (typeof record !== 'object' || record === null) return undefined
  const value: unknown = Reflect.get(record, key)
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

// A row's text: a string as is, else its text blocks joined (every other
// block skipped); a value of another shape reads as empty.
function rowText(content: unknown): string {
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  const parts: string[] = []
  for (const block of content) {
    const text = stringField(block, 'type') === 'text' ? stringField(block, 'text') : undefined
    if (text !== undefined) parts.push(text)
  }
  return parts.join('\n')
}

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

// Applies a pure change, writing only when it changed (the state library
// reads and writes named atoms only: one helper per atom).
async function changeLoops($: EngineInterface, fn: (value: ApexBandLoop[]) => ApexBandLoop[]): Promise<void> {
  const current = await read($, loops)
  if (fn(current) === current) return
  await update($, loops, fn)
}

async function changeShells($: EngineInterface, fn: (value: ApexBandShell[]) => ApexBandShell[]): Promise<void> {
  const current = await read($, shells)
  if (fn(current) === current) return
  await update($, shells, fn)
}

async function changePhases($: EngineInterface, fn: (value: ApexBandPhases) => ApexBandPhases): Promise<void> {
  const current = await read($, phases)
  if (fn(current) === current) return
  await update($, phases, fn)
}

async function changeLog($: EngineInterface, fn: (value: ApexBandLogEntry[]) => ApexBandLogEntry[]): Promise<void> {
  const current = await read($, log)
  if (fn(current) === current) return
  await update($, log, fn)
}

async function changeReceipts($: EngineInterface, fn: (value: ApexBandReceipts) => ApexBandReceipts): Promise<void> {
  const current = await read($, receipts)
  if (fn(current) === current) return
  await update($, receipts, fn)
}

async function changeCompactions(
  $: EngineInterface,
  fn: (value: Record<string, number>) => Record<string, number>,
): Promise<void> {
  const current = await read($, compactions)
  if (fn(current) === current) return
  await update($, compactions, fn)
}

// Writes each value unless the atom already holds an equal one.
async function putRun($: EngineInterface, value: ApexBandRun | null): Promise<void> {
  if (JSON.stringify(await read($, run)) === JSON.stringify(value)) return
  await update($, run, () => value)
}

async function putVerdict($: EngineInterface, value: ApexBandVerdict | null): Promise<void> {
  if (JSON.stringify(await read($, verdict)) === JSON.stringify(value)) return
  await update($, verdict, () => value)
}

async function putBudget($: EngineInterface, value: ApexBandBudget | null): Promise<void> {
  if (JSON.stringify(await read($, budget)) === JSON.stringify(value)) return
  await update($, budget, () => value)
}

async function putCost($: EngineInterface, value: number | null): Promise<void> {
  if ((await read($, cost)) === value) return
  await update($, cost, () => value)
}

async function putNow($: EngineInterface, value: number): Promise<void> {
  if ((await read($, now)) === value) return
  await update($, now, () => value)
}

// The gauge session.usage gives, written only when gaugeOf hands a new one.
async function putGauge($: EngineInterface, usage: UsageReading): Promise<void> {
  const prev: ApexBandGauge | null = await read($, gauge)
  const next = gaugeOf(usage, prev)
  if (next === prev) return
  await update($, gauge, () => next)
}

// The session's cost and gauge, one usage read.
async function refreshUsage($: EngineInterface): Promise<void> {
  const usage = await $.session.usage()
  await putCost($, usage.cost?.usd ?? null)
  await putGauge($, usage)
}

// The session's cost so far, null when unread.
async function costNow($: EngineInterface): Promise<number | null> {
  const usage = await $.session.usage()
  return usage.cost?.usd ?? null
}

// The run's external verification, from whichever of its two names was
// written last; re-read only when that file's mtime moved.
async function refreshVerdict($: EngineInterface, found: ApexBandRun | null): Promise<void> {
  const dir = found?.dir
  if (dir === undefined) {
    await putVerdict($, null)
    return
  }
  const runDir = `${await $.session.cwd()}/.claude/output/apex/${dir}`
  let newest: { name: string; mtimeMs: number } | null = null
  try {
    for (const entry of await $.fs.list(runDir)) {
      if (entry.kind !== 'file' || !VERIFY_NAMES.includes(entry.name)) continue
      newest = pickVerdict(newest, { name: entry.name, mtimeMs: entry.mtimeMs })
    }
  } catch {
    // The run directory vanished: no verification to show.
    newest = null
  }
  if (newest === null) {
    await putVerdict($, null)
    return
  }
  const current = await read($, verdict)
  if (current !== null && current.dir === dir && current.mtimeMs === newest.mtimeMs) return
  let next: ApexBandVerdict | null = null
  try {
    const parsed = parseVerdict(await $.fs.read(`${runDir}/${newest.name}`))
    if (parsed !== null) next = { dir, mtimeMs: newest.mtimeMs, ...parsed }
  } catch {
    // Vanished between list and read, or over 4 MiB: shown as pending.
    next = null
  }
  await putVerdict($, next)
}

// The run's correction budget, from the names in
// ~/.claude/apex-correction-budget (one file per round used or granted).
async function refreshBudget($: EngineInterface, found: ApexBandRun | null): Promise<void> {
  const dir = found?.dir
  const home = await $.env.get('HOME')
  if (dir === undefined || home === undefined || home === '') {
    await putBudget($, null)
    return
  }
  let names: string[]
  try {
    names = (await $.fs.list(`${home}/.claude/apex-correction-budget`)).map(entry => entry.name)
  } catch {
    // No round was ever claimed on this machine: no budget to show.
    names = []
  }
  await putBudget($, budgetOf(names, dir))
}

// The agent list applied to the loops (labels, types, ends, unknown agents
// at work) and to the shells (an owner killed, failed or gone closes them).
async function snapshot($: EngineInterface, at: number): Promise<void> {
  const list = await $.agent.list()
  const agents = list.map(a => ({ id: a.id, description: a.description, type: a.type, status: a.status }))
  const before = await read($, loops)
  const after = applySnapshot(before, agents, at)
  if (after !== before) await update($, loops, () => after)
  const ended = endedOwners(before, after)
  // Only the owners the list named or an Agent call launched: a fork or a
  // workflow agent is never listed, its leaving the list means nothing.
  const known = listedIds(after)
  await changeShells($, current =>
    ended.reduce((list2, id) => closeOrphanShells(list2, id, at), closeBySnapshot(current, agents, known, at)),
  )
}

// True while a subagent or a background shell works: the 1 s tick runs.
async function isBusy($: EngineInterface): Promise<boolean> {
  return subagentsRunning(await read($, loops)) || runningShells(await read($, shells)) > 0
}

// A segment's Text props: only the styles it sets, never an undefined prop.
function segProps(seg: Seg): TextProps {
  return {
    ...(seg.tone === undefined ? {} : { color: seg.tone }),
    ...(seg.dim === true ? { dimColor: true } : {}),
    ...(seg.bold === true ? { bold: true } : {}),
  }
}

// True where the surface draws Clients (terminal, desktop) and none of
// ours failed yet.
const drawsClients = (surface: RenderSurface): boolean => !clientsOff && (surface === 'terminal' || surface === 'desktop')

// One segment: a live one as its Client (as wide as its static text) where
// `clients` holds, else its text.
function drawSeg(seg: Seg, table: Table, clients: boolean): RenderNode {
  const live = seg.live
  const props = clientProps(seg)
  if (live !== undefined && props !== null && clients && 'Client' in table) {
    const { Client } = table
    const cells = textCells(seg.text)
    return live.kind === 'rail' ? (
      <Client key={live.key} module="./rail.ts" width={cells} props={props} />
    ) : (
      <Client key={live.key} module="./elapsed.ts" width={cells} props={props} />
    )
  }
  const { Text } = table
  return (
    <Text {...segProps(seg)} wrap="truncate-end">
      {seg.text}
    </Text>
  )
}

function drawLines(lines: readonly Seg[][], table: Table, clients: boolean): RenderNode[] {
  const { Box } = table
  return lines.map(line => <Box flexDirection="row">{line.map(seg => drawSeg(seg, table, clients))}</Box>)
}

// The 5 s poll: run, phases, verdict, budget, agents, cost, gauge. Arms the
// 1 s tick when something runs. The clock is the pane's: never written here.
async function refresh($: EngineInterface): Promise<void> {
  const at = await $.clock.now()
  const found = await scan($)
  await putRun($, found)
  const dir = found?.dir ?? null
  // Another run (or none): its buckets start over, never restored later.
  await changePhases($, value => syncPhases(value, dir))
  await refreshVerdict($, found)
  await refreshBudget($, found)
  await snapshot($, at)
  await refreshUsage($)
  if (await isBusy($)) armFast($)
}

// The 1 s tick: agents; the clock, the cost and the gauge while the pane is
// open. Cancels itself once idle and closed.
async function fastTick($: EngineInterface): Promise<void> {
  const at = await $.clock.now()
  await snapshot($, at)
  const busy = await isBusy($)
  const open = await read($, isOpen)
  if (open) await putNow($, at)
  if (open) await refreshUsage($)
  if (!busy && !open) {
    fastTimer?.cancel()
    fastTimer = undefined
  }
}

function onFastTick($: EngineInterface): void {
  fastTick($).catch(() => {
    // Agent list, usage or state refused: the figures stay as they were; the
    // next tick (TICK_MS later) tries again.
  })
}

function armFast($: EngineInterface): void {
  if (fastTimer !== undefined) return
  fastTimer = $.clock.every(TICK_MS, () => onFastTick($))
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
    // A failed scan or a refused write leaves the figures as they were; the next
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

// /apex-pane and /task-board: the one detail pane, opened on demand only.
async function openPane($: EngineInterface): Promise<{ text: string }> {
  ensurePolling($)
  const at = await $.clock.now()
  await update($, now, () => at)
  // Opened first: a refused open throws before a tick is armed. An
  // unplaced pane is still open (seated once a surface places it): ticked.
  await $.ui.open({ id: PANE, title: TITLE, rows: PANE_ROWS, columns: PANE_COLUMNS })
  await update($, isOpen, () => true)
  onFastTick($)
  armFast($)
  return { text: 'Détail du run APEX ouvert.' }
}

// The session's model, null when unreadable.
async function sessionModel($: EngineInterface): Promise<string | null> {
  try {
    const model = await $.session.model()
    return model === '' ? null : model
  } catch {
    // Unreadable here: the pane falls back to the main loop's last model.
    return null
  }
}

// Everything the pane reads, from state (and the session's model).
async function paneInput($: EngineInterface): Promise<PaneInput> {
  const live = await read($, run)
  const found = await read($, verdict)
  return {
    run: live,
    loops: await read($, loops),
    phases: await read($, phases),
    now: await read($, now),
    cost: await read($, cost),
    verdict: found,
    shells: await read($, shells),
    alerts: alertsOf(live, found, await read($, budget)),
    showAll: await read($, showAll),
    model: await sessionModel($),
    gauge: await read($, gauge),
    receipts: await read($, receipts),
    log: await read($, log),
    compactions: await read($, compactions),
    expanded: await read($, expanded),
  }
}

// True when a section folds finished items away (or shows them all):
// the agents, the other loops and the shells, each past MAX_DONE.
function canFold(input: PaneInput): boolean {
  if (input.showAll) return true
  const agents = blockLoops(input.loops, true)
  const named = new Set(agents.map(l => l.id))
  const doneAgents = agents.filter(l => l.status !== 'running').length
  const doneOthers = input.loops.filter(l => l.id !== MAIN && !named.has(l.id) && l.status !== 'running').length
  const doneShells = input.shells.filter(s => s.status !== 'running').length
  return doneAgents > MAX_DONE || doneOthers > MAX_DONE || doneShells > MAX_DONE
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    ensurePolling($)
    try {
      await $.command.register({
        name: 'apex-pane',
        description: 'Ouvre le détail du run APEX (phases, sous-agents, shells, tokens, vérif externe)',
        immediate: true,
      })
      await $.command.register({
        name: 'task-board',
        description: 'Ouvre le détail APEX : sous-agents et shells en arrière-plan (alias de /apex-pane)',
        immediate: true,
      })
    } catch {
      // Refused registration: no command this session, the observers still run.
    }
    return next(e)
  })

  on('command.run', { command: 'apex-pane' }, async $ => openPane($))
  on('command.run', { command: 'task-board' }, async $ => openPane($))

  // Marked closed once the close went through: a hook beneath that keeps
  // the pane open (answering, or throwing) keeps its figures live. The tick
  // stops by itself once nothing runs.
  on('ui.close', async ($, e, next) => {
    const closed = await next(e)
    if (e.id === PANE) {
      await record(async () => {
        await update($, isOpen, () => false)
      })
    }
    return closed
  }).catch(($, e, next) => next(e))

  // A Client of ours failed on a surface: static text from now on, every
  // site drawn again.
  on('ui.fault', ($, e, next) => {
    clientsOff = true
    $.ui.invalidate('ui.render')
    return next(e)
  })

  // A main-loop turn begins: the prompt in the journal, its receipt opened
  // with the session's cost so far.
  on('turn.start', async ($, e, next) => {
    const started = await next(e)
    await record(async () => {
      const at = await $.clock.now()
      const spent = await costNow($)
      await changeLog($, current => pushLog(current, { at, kind: 'prompt', text: e.text }))
      await changeReceipts($, current => startReceipt(current, { turnId: e.turnId, at, cost: spent }))
    })
    return started
  }).catch(($, e, next) => next(e))

  // A subagent started (foreground, background, fork or workflow): its
  // label, type, model and task kept, never marked at work by this alone.
  on('agent.spawn', async ($, e, next) => {
    const spawned = await next(e)
    const id = spawned.agentId
    if (id !== undefined && id !== '') {
      await record(async () => {
        const at = await $.clock.now()
        const label = e.description === '' ? undefined : e.description
        const model = spawned.model !== '' ? spawned.model : e.model
        await changeLoops($, current =>
          noteSpawn(
            current,
            {
              id,
              ...(label === undefined ? {} : { label }),
              ...(e.subagentType === '' ? {} : { type: e.subagentType }),
              ...(model === undefined || model === '' ? {} : { model }),
              task: e.prompt,
            },
            at,
          ),
        )
        await changeLog($, current => pushLog(current, { at, kind: 'spawn', text: label ?? e.subagentType }))
        await changeReceipts($, current => receiptAgent(current, id))
      })
    }
    return spawned
  }).catch(($, e, next) => next(e))

  // A compaction that stood (not skipped, not a precompute): counted under
  // its trigger, its sizes in the journal.
  on('session.compact', async ($, e, next) => {
    const compacted = await next(e)
    if (compacted.skip === undefined && e.trigger !== 'precompute') {
      await record(async () => {
        const at = await $.clock.now()
        const before = compacted.tokensBefore
        const after = compacted.tokensAfter
        const sizes =
          before === undefined ? '' : ` · ${Math.round(before / 1000)}k${after === undefined ? '' : ` → ${Math.round(after / 1000)}k`}`
        await changeCompactions($, current => addCompaction(current, e.trigger))
        await changeLog($, current => pushLog(current, { at, kind: 'compact', text: `compaction ${e.trigger}${sizes}` }))
      })
    }
    return compacted
  }).catch(($, e, next) => next(e))

  // Each model response: a step, its usage and effort for its loop, and the
  // usage for the run's current step (approximate: the step as last polled).
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const usage: Usage | null = result.usage
    await record(async () => {
      const at = await $.clock.now()
      const step = {
        ...(e.agentId === undefined ? {} : { agentId: e.agentId }),
        model: e.model,
        usage,
        ...(e.effort === undefined ? {} : { effort: e.effort }),
      }
      await changeLoops($, current => addStep(current, step, at))
      const live = await read($, run)
      const dir = live?.dir
      if (dir !== undefined) await changePhases($, current => addPhase(current, dir, live?.currentStep, usage))
    })
    if (e.agentId !== undefined) armFast($)
    return result
  }).catch(async function* ($, e, next) {
    return yield* next(e)
  })

  // Each tool call: counted and shown as its loop's current tool (and what
  // it aims at) while it runs; an edit or a failure goes on the receipt and
  // in the journal.
  on('tool.call', async ($, e, next) => {
    const { agentId, tool, tool_use_id: toolUseId } = e
    const target = toolTarget(tool, e)
    await record(async () => {
      const at = await $.clock.now()
      await changeLoops($, current =>
        startTool(current, { agentId, tool, toolUseId, ...(target === undefined ? {} : { target }) }, at),
      )
    })
    if (agentId !== undefined) armFast($)
    const ran = await next(e)
    await record(async () => {
      await changeLoops($, current => endTool(current, agentId, toolUseId))
      const at = await $.clock.now()
      if (ran.isError === true) {
        await changeReceipts($, current => receiptError(current))
        await changeLog($, current =>
          pushLog(current, { at, kind: 'error', text: target === undefined ? tool : `${tool} · ${target}` }),
        )
        return
      }
      const path = isEditTool(tool) ? editPath(tool, e) : undefined
      if (path !== undefined) {
        await changeReceipts($, current => receiptEdit(current, path))
        await changeLog($, current => pushLog(current, { at, kind: 'edit', text: pathTail(path) }))
      }
    })
    return ran
  }).catch(($, e, next) => next(e))

  // Background shell: run_in_background, or ctrl+B / auto-background, all
  // answer a backgroundTaskId.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    const id = stringField(ran.result, 'backgroundTaskId')
    if (id !== undefined) {
      await record(async () => {
        const startedAt = await $.clock.now()
        const label = stringField(e, 'description') ?? stringField(e, 'command') ?? 'shell'
        const toolUseId = stringField(e, 'tool_use_id')
        // Set only inside a subagent loop: its shells close with it (shells.ts).
        const ownerAgentId = stringField(e, 'agentId')
        await changeShells($, current =>
          addShell(current, {
            id,
            label,
            startedAt,
            ...(toolUseId === undefined ? {} : { toolUseId }),
            ...(ownerAgentId === undefined ? {} : { ownerAgentId }),
          }),
        )
      })
      armFast($)
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A subagent: a background one answers async_launched + agentId (its
  // label known at once); a foreground one shows up in the agent list, read
  // each second from here on.
  on('tool.call', { tool: 'Agent' }, async ($, e, next) => {
    armFast($)
    const ran = await next(e)
    const id = stringField(ran.result, 'agentId')
    if (stringField(ran.result, 'status') === 'async_launched' && id !== undefined) {
      await record(async () => {
        const at = await $.clock.now()
        const label = stringField(ran.result, 'description') ?? stringField(e, 'description')
        const type = stringField(e, 'subagent_type')
        // The model asked for (shown until the first step reports its own).
        const model = stringField(e, 'model')
        await changeLoops($, current =>
          launchLoop(
            current,
            {
              id,
              ...(label === undefined ? {} : { label }),
              ...(type === undefined ? {} : { type }),
              ...(model === undefined ? {} : { model }),
            },
            at,
          ),
        )
      })
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A shell stopped by TaskStop gets no notification row: close it as
  // killed. TaskStop also stops agents; stopShell leaves those to the agent
  // snapshot.
  on('tool.call', { tool: 'TaskStop' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.isError !== true && ran.result !== undefined) {
      const id = stringField(ran.result, 'task_id') ?? stringField(e, 'task_id') ?? stringField(e, 'shell_id')
      if (id !== undefined) {
        await record(async () => {
          const at = await $.clock.now()
          await changeShells($, current => stopShell(current, id, at))
        })
      }
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A background shell's notification row: the one completion signal a
  // shell has. A render hook never writes state, so the write is deferred to
  // a timer; the row itself is drawn unchanged.
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'task-notification' } } }, ($, e, next) => {
    const task: unknown = e.props.task
    const note: Notification = {}
    const id = stringField(task, 'id')
    const toolUseId = stringField(task, 'toolUseId')
    const status = stringField(task, 'status')
    const durationMs = numberField(task, 'durationMs')
    if (id !== undefined) note.id = id
    if (toolUseId !== undefined) note.toolUseId = toolUseId
    if (status !== undefined) note.status = status
    if (durationMs !== undefined) note.durationMs = durationMs
    if (note.status !== undefined) {
      $.clock.after(0, () => {
        $.clock
          .now()
          .then(at => changeShells($, current => finishByNotification(current, note, at)))
          .catch(() => {
            // State refused: the shell stays "en cours" until its owner's end
            // or a later redraw of the row retries it.
          })
      })
    }
    return next(e)
  })

  // A subagent's shell notifies that subagent's loop only: its row never
  // reaches the main transcript (nor the ui.render path above). Read before
  // next: the row is relayed unchanged.
  on('session.append', async ($, e, next) => {
    const agentId = e.agentId
    if (agentId !== undefined && agentId !== '' && e.origin.kind === 'task-notification') {
      const notes = parseTaskNotifications(rowText(e.message.content))
      if (notes.length > 0) {
        await record(async () => {
          const at = await $.clock.now()
          await changeShells($, current => notes.reduce((list, note) => finishByNotification(list, note, at), current))
        })
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A loop's turn ended: its status, the turn's duration and the head of
  // its answer; a subagent ended failed or stopped closes its still running
  // shells; the main loop's end closes its receipt with the cost it added.
  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    await record(async () => {
      const at = await $.clock.now()
      const before = await read($, loops)
      const ended = endLoop(before, e.agentId, e.reason, e.durationMs, at)
      const after = noteAnswer(ended, e.agentId, e.answer)
      if (after !== before) await update($, loops, () => after)
      const gone = endedOwners(before, after)
      await changeShells($, current => gone.reduce((list, id) => closeOrphanShells(list, id, at), current))
      const kind = reasonStatus(e.reason) === 'failed' ? 'error' : 'done'
      const isMain = e.agentId === undefined || e.agentId === MAIN
      const label = isMain ? 'fin du tour' : (after.find(l => l.id === e.agentId)?.label ?? e.agentId ?? '')
      // The reason is said only for a failure (a plain answer is the norm).
      const text = kind === 'error' ? `${label} · ${e.reason}` : label
      await changeLog($, current => pushLog(current, { at, kind, text }))
      if (isMain) {
        const spent = await costNow($)
        await changeReceipts($, current =>
          endReceipt(current, { at, durationMs: e.durationMs, reason: e.reason, cost: spent }),
        )
      }
    })
    return done
  }).catch(($, e, next) => next(e))

  on('prompt.submit', ($, e, next) => {
    ensurePolling($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      // A /clear starts every figure over; the timers are kept for it. The
      // pane's open state is the surface's, not a figure: left as it is.
      await update($, run, () => null)
      await update($, loops, () => [])
      await update($, phases, () => ({ dir: null, byStep: {} }))
      await update($, now, () => 0)
      await update($, cost, () => null)
      await update($, verdict, () => null)
      await update($, shells, () => [])
      await update($, budget, () => null)
      await update($, log, () => [])
      await update($, receipts, () => NO_RECEIPTS)
      await update($, gauge, () => null)
      await update($, compactions, () => ({}))
      await update($, expanded, () => null)
      await update($, showAll, () => false)
    } else {
      // No session.start follows a /clear: the timers are kept for it.
      timer?.cancel()
      timer = undefined
      fastTimer?.cancel()
      fastTimer = undefined
    }
    return next(e)
  })

  // The pane: reads state only, every line within the body's columns;
  // [1]-[6] expand an agent's block (or fold it again); [t] shows every
  // finished agent, loop and shell, or folds them again.
  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const table = $.ui.resolve(e)
    const { Box, Button } = table
    const input = await paneInput($)
    const lines = layoutPane(input, e.props.bodyColumns)
    const toggle = (): void => {
      update($, showAll, value => !value).catch(() => {
        // State refused: the pane stays as drawn; a later press retries.
      })
    }
    const expand = (id: string): void => {
      update($, expanded, value => (value === id ? null : id)).catch(() => {
        // State refused: the block stays as drawn; a later press retries.
      })
    }
    const keys = paneHotkeys(input).map(({ n, id }) => (
      <Button
        key={`agent-${n}`}
        hotkey={String(n)}
        label={input.expanded === id ? `replier ${n}` : `détail ${n}`}
        plain
        dimColor
        onPress={() => expand(id)}
      />
    ))
    const fold = canFold(input)
      ? [<Button key="toggle" hotkey="t" label={input.showAll ? 'replier' : 'tout afficher'} plain dimColor onPress={toggle} />]
      : []
    const buttons = [...keys, ...fold]
    return (
      <Box flexDirection="column">
        {drawLines(lines, table, drawsClients(e.surface))}
        {buttons.length > 0 ? [
          <Box key="keys" flexDirection="row" flexWrap="wrap" columnGap={2}>
            {buttons}
          </Box>,
        ] : []}
      </Box>
    )
  })
}
