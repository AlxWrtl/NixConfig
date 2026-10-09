// Pure bookkeeping of the band and pane: per-loop counters (steps, tool
// calls, token counts, running time), per-phase token buckets and the
// external verdict read from the run's verify file. Every function returns
// the same reference when nothing changed, so a caller can skip the write.

import type { ApexBandLoop, ApexBandLoopStatus, ApexBandPhases, ApexBandTally } from '../types'

// The loop id of the main conversation (events without an agentId).
export const MAIN = 'main'

// What a step's usage carries: ModelUsage's four counts and the model.
export type Usage = {
  input_tokens: number
  output_tokens: number
  cache_read_input_tokens: number
  cache_creation_input_tokens: number
  model?: string
}

// One agent of `$.agent.list()`, reduced to what the pane reads.
export type AgentSnap = { id: string; description: string; type: string; status: string }

export const ZERO: ApexBandTally = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }

// A model id made short: `claude-` and a date or `[1m]` suffix dropped, a
// trailing `-5-5` version read as `-5.5` (claude-opus-5-5[1m] → opus-5.5).
export function shortModel(model: string): string {
  const bare = model
    .replace(/\[[^\]]*\]$/, '')
    .replace(/^claude-/, '')
    .replace(/-\d{8}$/, '')
  return bare.replace(/-(\d+)-(\d+)$/, '-$1.$2')
}

// A finite non-negative count, else 0 (usage comes from the API).
const count = (n: number): number => (Number.isFinite(n) && n > 0 ? n : 0)

// A tally plus one response's usage.
export function addUsage(tally: ApexBandTally, usage: Usage): ApexBandTally {
  return {
    input: tally.input + count(usage.input_tokens),
    output: tally.output + count(usage.output_tokens),
    cacheRead: tally.cacheRead + count(usage.cache_read_input_tokens),
    cacheWrite: tally.cacheWrite + count(usage.cache_creation_input_tokens),
  }
}

// Two tallies summed.
export const sumTally = (a: ApexBandTally, b: ApexBandTally): ApexBandTally => ({
  input: a.input + b.input,
  output: a.output + b.output,
  cacheRead: a.cacheRead + b.cacheRead,
  cacheWrite: a.cacheWrite + b.cacheWrite,
})

// All four counts of a tally summed.
export const tallyTotal = (t: ApexBandTally): number => t.input + t.output + t.cacheRead + t.cacheWrite

// The counts the pane shows as a loop's or phase's work: input, output and
// cache writes; cache reads (the context re-read on every request) are left
// out and shown apart.
export const countedTotal = (t: ApexBandTally): number => t.input + t.output + t.cacheWrite

// A fresh loop, running from `at`.
function freshLoop(id: string, at: number): ApexBandLoop {
  return { id, status: 'running', steps: 0, calls: 0, tally: ZERO, startedAt: at, durationMs: 0, since: at }
}

// The list with loop `id` replaced by `fn` of it (created when missing).
function withLoop(
  loops: readonly ApexBandLoop[],
  id: string,
  at: number,
  fn: (loop: ApexBandLoop) => ApexBandLoop,
): ApexBandLoop[] {
  const i = loops.findIndex(l => l.id === id)
  const loop = loops[i]
  if (loop === undefined) return [...loops, fn(freshLoop(id, at))]
  const out = [...loops]
  out[i] = fn(loop)
  return out
}

// A loop seen at work again: running from `at` unless it already was.
function wake(loop: ApexBandLoop, at: number): ApexBandLoop {
  if (loop.status === 'running') return loop
  const { endedAt: _ended, endedBy: _by, ...rest } = loop
  return { ...rest, status: 'running', since: at }
}

// One model response of loop `agentId` (main when absent): a step more,
// its model and usage counted.
export function addStep(
  loops: readonly ApexBandLoop[],
  step: { agentId?: string; model: string; usage: Usage | null },
  at: number,
): ApexBandLoop[] {
  return withLoop(loops, step.agentId ?? MAIN, at, loop => {
    const woken = wake(loop, at)
    const model = shortModel(step.usage?.model ?? step.model)
    return {
      ...woken,
      steps: woken.steps + 1,
      ...(model === '' ? {} : { model }),
      tally: step.usage === null ? woken.tally : addUsage(woken.tally, step.usage),
    }
  })
}

// A tool call starting in loop `agentId`: a call more, shown as current.
export function startTool(
  loops: readonly ApexBandLoop[],
  call: { agentId?: string; tool: string; toolUseId?: string },
  at: number,
): ApexBandLoop[] {
  return withLoop(loops, call.agentId ?? MAIN, at, loop => {
    const { toolUseId: _old, ...woken } = wake(loop, at)
    return {
      ...woken,
      calls: woken.calls + 1,
      tool: call.tool,
      ...(call.toolUseId === undefined ? {} : { toolUseId: call.toolUseId }),
    }
  })
}

// A tool call ended: the current tool cleared when it is still that call.
export function endTool(loops: ApexBandLoop[], agentId: string | undefined, toolUseId: string | undefined): ApexBandLoop[] {
  const id = agentId ?? MAIN
  const i = loops.findIndex(l => l.id === id)
  const loop = loops[i]
  if (loop === undefined || loop.tool === undefined || loop.toolUseId !== toolUseId) return loops
  const { tool: _tool, toolUseId: _use, ...rest } = loop
  const out = [...loops]
  out[i] = rest
  return out
}

// A loop's turn ended (turn.complete reason, or an agent's last status):
// its status set, the turn's time added, its current tool cleared.
function finish(loop: ApexBandLoop, status: ApexBandLoopStatus, spentMs: number, at: number): ApexBandLoop {
  const { tool: _tool, toolUseId: _use, since: _since, ...rest } = loop
  return { ...rest, status, durationMs: loop.durationMs + Math.max(0, spentMs), endedAt: at }
}

// The status a turn.complete reason gives.
export function reasonStatus(reason: string): ApexBandLoopStatus {
  if (reason === 'answer') return 'done'
  if (reason === 'aborted') return 'stopped'
  return 'failed'
}

// The agent type of a teammate: it goes `idle` between turns, never ends here.
export const TEAMMATE = 'teammate'

// Loop `agentId`'s turn completed after `durationMs`. A running loop ends;
// a loop the agent snapshot ended first is reconciled once (the turn's
// duration and reason replace the snapshot's estimate); an unknown loop or
// a loop already ended by its turn is left alone.
export function endLoop(
  loops: ApexBandLoop[],
  agentId: string | undefined,
  reason: string,
  durationMs: number,
  at: number,
): ApexBandLoop[] {
  const id = agentId ?? MAIN
  const i = loops.findIndex(l => l.id === id)
  const loop = loops[i]
  if (loop === undefined) return loops
  const out = [...loops]
  // A teammate's turn ending is not the teammate ending: only its current
  // tool is cleared (it waits for its next message).
  if (loop.type === TEAMMATE) {
    if (loop.tool === undefined) return loops
    const { tool: _tool, toolUseId: _use, ...rest } = loop
    out[i] = rest
    return out
  }
  const given = Number.isFinite(durationMs) && durationMs > 0
  if (loop.status === 'running') {
    const spent = given ? durationMs : at - (loop.since ?? at)
    out[i] = { ...finish(loop, reasonStatus(reason), spent, at), endedBy: 'turn' }
    return out
  }
  if (loop.endedBy !== 'snapshot') return loops
  // The snapshot added endedAt - since; the turn's own duration replaces it.
  const ended = loop.endedAt ?? at
  const estimate = Math.max(0, ended - (loop.since ?? ended))
  const { since: _since, ...rest } = loop
  const base = loop.durationMs - estimate
  out[i] = { ...rest, status: reasonStatus(reason), durationMs: base + (given ? durationMs : estimate), endedBy: 'turn' }
  return out
}

// The status an agent's terminal status gives; undefined while it works.
function snapStatus(status: string): ApexBandLoopStatus | undefined {
  if (status === 'completed') return 'done'
  if (status === 'failed') return 'failed'
  if (status === 'killed') return 'stopped'
  return undefined
}

// A listed loop's idle mark as the agent list reads it (a teammate's never
// set: it is never counted at work anyway).
function withIdle(loop: ApexBandLoop, status: string): ApexBandLoop {
  const idle = status === 'idle' && loop.type !== TEAMMATE
  if (idle === (loop.idle === true)) return loop
  if (idle) return { ...loop, idle: true }
  const { idle: _idle, ...rest } = loop
  return rest
}

// The agent list applied to the loops: each listed loop marked listed (and
// idle while the list reads it so), description and type filled in, a
// running loop whose agent ended is ended (never a teammate's: it goes idle
// between turns). A listed agent not known yet is added: running while at
// work (idle: marked so), with its final status when already ended (a
// teammate always running). Never reopens a loop.
export function applySnapshot(loops: ApexBandLoop[], agents: readonly AgentSnap[], at: number): ApexBandLoop[] {
  let out: ApexBandLoop[] | undefined
  loops.forEach((loop, i) => {
    const agent = agents.find(a => a.id === loop.id)
    if (agent === undefined) return
    let next = loop.listed === true ? loop : { ...loop, listed: true }
    if (next.label === undefined && agent.description !== '') next = { ...next, label: agent.description }
    if (next.type === undefined && agent.type !== '') next = { ...next, type: agent.type }
    next = withIdle(next, agent.status)
    const ended = snapStatus(agent.status)
    const isMate = next.type === TEAMMATE || agent.type === TEAMMATE
    if (ended !== undefined && next.status === 'running' && !isMate) {
      // Kept: `since` lets the turn's own end replace this estimate (endLoop).
      const since = next.since
      next = { ...finish(next, ended, at - (since ?? at), at), ...(since === undefined ? {} : { since }), endedBy: 'snapshot' }
    }
    if (next === loop) return
    out ??= [...loops]
    out[i] = next
  })
  for (const agent of agents) {
    if (agent.id === MAIN || (out ?? loops).some(l => l.id === agent.id)) continue
    const fresh = withIdle({ ...named(freshLoop(agent.id, at), agent.description, agent.type), listed: true }, agent.status)
    const ended = snapStatus(agent.status)
    const added =
      ended === undefined || fresh.type === TEAMMATE ? fresh : { ...finish(fresh, ended, 0, at), since: at, endedBy: 'snapshot' as const }
    out = [...(out ?? loops), added]
  }
  return out ?? loops
}

// The subagent loops the agent list named or an Agent call launched: the
// owners whose leaving the list orphans their shells (closeBySnapshot).
export function listedIds(loops: readonly ApexBandLoop[]): string[] {
  return loops.filter(l => l.id !== MAIN && l.listed === true).map(l => l.id)
}

// A loop with its label and type filled in where it has none yet.
function named(loop: ApexBandLoop, label: string | undefined, type: string | undefined): ApexBandLoop {
  let next = loop
  if (next.label === undefined && label !== undefined && label !== '') next = { ...next, label }
  if (next.type === undefined && type !== undefined && type !== '') next = { ...next, type }
  return next
}

// A background subagent launched (Agent answered async_launched): its loop
// added as running and listed, or named when its first step came first.
// The model asked at launch is shown until a step reports the one it ran.
export function launchLoop(
  loops: ApexBandLoop[],
  agent: { id: string; label?: string; type?: string; model?: string },
  at: number,
): ApexBandLoop[] {
  const asked = agent.model === undefined ? '' : shortModel(agent.model)
  const mark = (loop: ApexBandLoop): ApexBandLoop => {
    const withNames = named(loop, agent.label, agent.type)
    const listed = withNames.listed === true ? withNames : { ...withNames, listed: true }
    return listed.model === undefined && asked !== '' ? { ...listed, model: asked } : listed
  }
  const i = loops.findIndex(l => l.id === agent.id)
  const loop = loops[i]
  if (loop === undefined) return [...loops, mark(freshLoop(agent.id, at))]
  const next = mark(loop)
  if (next === loop) return loops
  const out = [...loops]
  out[i] = next
  return out
}

// The listed subagents that went from running (or unknown) to failed or
// stopped between `before` and `after`, teammates aside: their background
// shells can no longer notify anyone (shells.ts closeOrphanShells). A loop
// never listed is left out: its type (a teammate?) is not known yet.
export function endedOwners(before: readonly ApexBandLoop[], after: readonly ApexBandLoop[]): string[] {
  const ids: string[] = []
  for (const loop of after) {
    if (loop.id === MAIN || loop.listed !== true || loop.type === TEAMMATE) continue
    if (loop.status !== 'failed' && loop.status !== 'stopped') continue
    const was = before.find(l => l.id === loop.id)
    if (was === undefined || was.status === 'running') ids.push(loop.id)
  }
  return ids
}

// A subagent loop at work: listed (a fork or a workflow agent seen by its
// steps alone is not one), not idle, running; the main loop aside, and a
// teammate aside (it is never ended here, so it would read as running for as
// long as it lives; the pane still lists it).
export const isWorking = (loop: ApexBandLoop): boolean =>
  loop.id !== MAIN && loop.listed === true && loop.idle !== true && loop.type !== TEAMMATE && loop.status === 'running'

// True while a subagent loop works (see isWorking).
export const subagentsRunning = (loops: readonly ApexBandLoop[]): boolean => loops.some(isWorking)

// The buckets kept for run `dir` (null: no live run), started over when the
// polled run's directory is another one; the same reference when equal.
export function syncPhases(phases: ApexBandPhases, dir: string | null): ApexBandPhases {
  return phases.dir === dir ? phases : { dir, byStep: {} }
}

// One response's usage added to `step`'s bucket of run `dir`; the buckets
// start over when the run's directory changed.
export function addPhase(phases: ApexBandPhases, dir: string, step: string | undefined, usage: Usage | null): ApexBandPhases {
  const base = phases.dir === dir ? phases : { dir, byStep: {} }
  if (step === undefined || usage === null) return base
  return { dir, byStep: { ...base.byStep, [step]: addUsage(base.byStep[step] ?? ZERO, usage) } }
}

// The main loop's tally and the subagents' summed.
export function splitTotals(loops: readonly ApexBandLoop[]): { main: ApexBandTally; sub: ApexBandTally } {
  let main = ZERO
  let sub = ZERO
  for (const loop of loops) {
    if (loop.id === MAIN) main = sumTally(main, loop.tally)
    else sub = sumTally(sub, loop.tally)
  }
  return { main, sub }
}

// A loop's running time at `now`: its finished turns plus the live one.
export function loopDuration(loop: ApexBandLoop, now: number): number {
  const live = loop.status === 'running' && loop.since !== undefined ? Math.max(0, now - loop.since) : 0
  return loop.durationMs + live
}

const VERDICTS = new Set(['PASS', 'FAIL', 'BLOCKED', 'ERROR'])

// The verdict word and findings count of an external-verify.json text, or
// null when it is not one (bad JSON, unknown verdict, findings not a list).
export function parseVerdict(text: string): { verdict: string; findings: number } | null {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    // Not JSON (half-written, or another file): no verdict to show.
    return null
  }
  if (typeof data !== 'object' || data === null) return null
  const word: unknown = Reflect.get(data, 'verdict')
  const findings: unknown = Reflect.get(data, 'findings')
  if (typeof word !== 'string' || !VERDICTS.has(word)) return null
  return { verdict: word, findings: Array.isArray(findings) ? findings.length : 0 }
}
