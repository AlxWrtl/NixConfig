import { describe, expect, test } from 'claude-code/testing'

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
  loopDuration,
  parseVerdict,
  shortModel,
  splitTotals,
  startTool,
  syncPhases,
  tallyTotal,
  countedTotal,
  subagentsRunning,
} from '../hooks/stats.ts'
import type { Usage } from '../hooks/stats.ts'

const USAGE: Usage = {
  input_tokens: 10,
  output_tokens: 20,
  cache_read_input_tokens: 300,
  cache_creation_input_tokens: 4,
  model: 'claude-opus-5-5-20260901',
}

describe('shortModel', () => {
  test('drops the claude- prefix, the date and [1m], dots the version', () => {
    expect(shortModel('claude-opus-5-5[1m]')).toBe('opus-5.5')
    expect(shortModel('claude-haiku-4-5-20251001')).toBe('haiku-4.5')
    expect(shortModel('gpt-6-astra')).toBe('gpt-6-astra')
  })
})

describe('loops', () => {
  test('a step creates its loop, counts its usage and model', () => {
    const loops = addStep([], { agentId: 'a1', model: 'claude-sonnet-4-5', usage: USAGE }, 100)
    expect(loops).toHaveLength(1)
    const loop = loops[0]
    expect(loop?.id).toBe('a1')
    expect(loop?.steps).toBe(1)
    expect(loop?.model).toBe('opus-5.5')
    expect(loop?.tally).toEqual({ input: 10, output: 20, cacheRead: 300, cacheWrite: 4 })
    expect(loop?.status).toBe('running')
  })

  test('a step without usage counts the step and the requested model', () => {
    const loops = addStep([], { model: 'claude-sonnet-4-5', usage: null }, 0)
    expect(loops[0]?.id).toBe(MAIN)
    expect(loops[0]?.model).toBe('sonnet-4.5')
    expect(tallyTotal(loops[0]?.tally ?? { input: 1, output: 1, cacheRead: 1, cacheWrite: 1 })).toBe(0)
  })

  test('a tool call is counted and current until its own end', () => {
    let loops = startTool([], { agentId: 'a1', tool: 'Read', toolUseId: 'u1' }, 0)
    expect(loops[0]?.tool).toBe('Read')
    expect(loops[0]?.calls).toBe(1)
    const same = endTool(loops, 'a1', 'other')
    expect(same).toBe(loops)
    loops = endTool(loops, 'a1', 'u1')
    expect(loops[0]?.tool).toBeUndefined()
    expect(loops[0]?.calls).toBe(1)
  })

  test('a completed turn ends the loop with its duration, once', () => {
    let loops = addStep([], { agentId: 'a1', model: 'm', usage: null }, 0)
    loops = startTool(loops, { agentId: 'a1', tool: 'Bash' }, 10)
    loops = endLoop(loops, 'a1', 'answer', 5_000, 6_000)
    expect(loops[0]?.status).toBe('done')
    expect(loops[0]?.durationMs).toBe(5_000)
    expect(loops[0]?.tool).toBeUndefined()
    expect(endLoop(loops, 'a1', 'error', 1, 7_000)).toBe(loops)
    expect(endLoop(loops, 'nobody', 'answer', 1, 7_000)).toBe(loops)
    expect(endLoop(addStep([], { agentId: 'x', model: 'm', usage: null }, 0), 'x', 'aborted', 0, 10)[0]?.status).toBe(
      'stopped',
    )
    expect(endLoop(addStep([], { agentId: 'x', model: 'm', usage: null }, 0), 'x', 'refusal', 0, 10)[0]?.status).toBe(
      'failed',
    )
  })

  test('the running time grows with the clock and stops at the end', () => {
    let loops = addStep([], { agentId: 'a1', model: 'm', usage: null }, 1_000)
    const live = loops[0]
    expect(live === undefined ? -1 : loopDuration(live, 4_000)).toBe(3_000)
    loops = endLoop(loops, 'a1', 'answer', 0, 5_000)
    const ended = loops[0]
    expect(ended === undefined ? -1 : loopDuration(ended, 99_000)).toBe(4_000)
  })

  test('the agent snapshot fills label and type, ends a finished agent, never reopens', () => {
    const loops = addStep([], { agentId: 'a1', model: 'm', usage: null }, 0)
    const agent = { id: 'a1', description: 'scan types', type: 'Explore', status: 'running' }
    const snap = [agent]
    const named = applySnapshot(loops, snap, 1_000)
    expect(named[0]?.label).toBe('scan types')
    expect(named[0]?.type).toBe('Explore')
    expect(applySnapshot(named, snap, 2_000)).toBe(named)
    const ended = applySnapshot(named, [{ ...agent, status: 'killed' }], 3_000)
    expect(ended[0]?.status).toBe('stopped')
    expect(ended[0]?.durationMs).toBe(3_000)
    expect(applySnapshot(ended, snap, 4_000)).toBe(ended)
    expect(applySnapshot(loops, [], 1)).toBe(loops)
  })

  test('main and subagents are totalled apart', () => {
    let loops = addStep([], { model: 'm', usage: USAGE }, 0)
    loops = addStep(loops, { agentId: 'a1', model: 'm', usage: USAGE }, 0)
    loops = addStep(loops, { agentId: 'a2', model: 'm', usage: USAGE }, 0)
    const { main, sub } = splitTotals(loops)
    expect(tallyTotal(main)).toBe(334)
    expect(tallyTotal(sub)).toBe(668)
    // Counted totals leave the cache reads (300 per step) out.
    expect(countedTotal(main)).toBe(34)
    expect(countedTotal(sub)).toBe(68)
    expect(main.cacheRead + sub.cacheRead).toBe(900)
  })
})

describe('phases', () => {
  test('usage goes to the current step and resets on a new run dir', () => {
    let phases = addPhase({ dir: null, byStep: {} }, 'run-a', '03-execute', USAGE)
    phases = addPhase(phases, 'run-a', '03-execute', USAGE)
    expect(phases.byStep['03-execute']?.output).toBe(40)
    const same = addPhase(phases, 'run-a', undefined, USAGE)
    expect(same).toBe(phases)
    const fresh = addPhase(phases, 'run-b', '01-analyze', USAGE)
    expect(fresh.dir).toBe('run-b')
    expect(fresh.byStep['03-execute']).toBeUndefined()
    expect(fresh.byStep['01-analyze']?.input).toBe(10)
  })
})

describe('parseVerdict', () => {
  test('reads the verdict and counts findings; rejects anything else', () => {
    expect(parseVerdict('{"verdict":"FAIL","findings":[{},{}]}')).toEqual({ verdict: 'FAIL', findings: 2 })
    expect(parseVerdict('{"verdict":"PASS","findings":[]}')).toEqual({ verdict: 'PASS', findings: 0 })
    expect(parseVerdict('{"verdict":"MAYBE"}')).toBeNull()
    expect(parseVerdict('# not json')).toBeNull()
    expect(parseVerdict('null')).toBeNull()
  })
})

describe('reconciliation', () => {
  test('snapshot first: the turn end replaces the estimate and the status, once', () => {
    const loops = addStep([], { agentId: 'a1', model: 'm', usage: null }, 1_000)
    const snapped = applySnapshot(loops, [{ id: 'a1', description: '', type: '', status: 'completed' }], 9_000)
    expect(snapped[0]?.status).toBe('done')
    expect(snapped[0]?.durationMs).toBe(8_000)
    expect(snapped[0]?.endedBy).toBe('snapshot')
    const ended = endLoop(snapped, 'a1', 'refusal', 5_000, 9_500)
    expect(ended[0]?.status).toBe('failed')
    expect(ended[0]?.durationMs).toBe(5_000)
    expect(ended[0]?.endedBy).toBe('turn')
    expect(ended[0]?.endedAt).toBe(9_000)
    expect(endLoop(ended, 'a1', 'answer', 7_000, 10_000)).toBe(ended)
  })

  test('snapshot first, no turn duration: the estimate stays', () => {
    const loops = addStep([], { agentId: 'a1', model: 'm', usage: null }, 1_000)
    const snapped = applySnapshot(loops, [{ id: 'a1', description: '', type: '', status: 'killed' }], 4_000)
    const ended = endLoop(snapped, 'a1', 'aborted', 0, 5_000)
    expect(ended[0]?.durationMs).toBe(3_000)
    expect(ended[0]?.status).toBe('stopped')
    expect(ended[0]?.endedBy).toBe('turn')
  })

  test('turn end first: the snapshot changes nothing, a second end is a no-op', () => {
    const loops = addStep([], { agentId: 'a1', model: 'm', usage: null }, 1_000)
    const ended = endLoop(loops, 'a1', 'answer', 5_000, 9_000)
    expect(ended[0]?.endedBy).toBe('turn')
    expect(ended[0]?.durationMs).toBe(5_000)
    const snap = [{ id: 'a1', description: '', type: '', status: 'failed' }]
    // Only marked listed: status, duration and end kept.
    const snapped = applySnapshot(ended, snap, 10_000)
    expect(snapped[0]).toEqual({ ...ended[0], listed: true })
    expect(applySnapshot(snapped, snap, 11_000)).toBe(snapped)
    expect(endLoop(snapped, 'a1', 'error', 1, 11_000)).toBe(snapped)
  })
})

describe('syncPhases', () => {
  test('run A, then B, then A again: A starts over, never restored', () => {
    const a = addPhase({ dir: null, byStep: {} }, 'run-a', '03-execute', USAGE)
    expect(syncPhases(a, 'run-a')).toBe(a)
    const b = syncPhases(a, 'run-b')
    expect(b).toEqual({ dir: 'run-b', byStep: {} })
    const back = syncPhases(b, 'run-a')
    expect(back).toEqual({ dir: 'run-a', byStep: {} })
    expect(syncPhases(a, null)).toEqual({ dir: null, byStep: {} })
  })
})

// Ported from task-board's board.test (agent cases): the ledger is now the
// one list of subagents.
describe('agent snapshot', () => {
  const explore = { id: 'a1', description: 'explore', type: 'Explore', status: 'running' }

  test('agent snapshot adds unknown agents and finishes ended ones', () => {
    const added = applySnapshot([], [explore], 10)
    expect(added).toHaveLength(1)
    expect(added[0]?.status).toBe('running')
    expect(added[0]?.label).toBe('explore')
    expect(added[0]?.type).toBe('Explore')
    expect(added[0]?.startedAt).toBe(10)
    const ended = applySnapshot(added, [{ ...explore, status: 'failed' }], 20)
    expect(ended[0]?.status).toBe('failed')
    expect(applySnapshot(ended, [{ ...explore, status: 'failed' }], 30)).toBe(ended)
  })

  test('an unknown agent already ended is added with its final status, never running', () => {
    for (const [word, status] of [['completed', 'done'], ['failed', 'failed'], ['killed', 'stopped']] as const) {
      const added = applySnapshot([], [{ ...explore, status: word }], 10)
      expect(added[0]?.status).toBe(status)
      expect(added[0]?.endedAt).toBe(10)
      expect(added[0]?.listed).toBe(true)
      expect(subagentsRunning(added)).toBe(false)
      expect(applySnapshot(added, [{ ...explore, status: word }], 20)).toBe(added)
    }
  })

  test('an unknown idle agent is added listed and idle: nothing at work', () => {
    const added = applySnapshot([], [{ ...explore, status: 'idle' }], 10)
    expect(added[0]?.idle).toBe(true)
    expect(subagentsRunning(added)).toBe(false)
    // Back at work: counted again; idle once more: not.
    const busy = applySnapshot(added, [explore], 20)
    expect(busy[0]?.idle).toBeUndefined()
    expect(subagentsRunning(busy)).toBe(true)
    expect(subagentsRunning(applySnapshot(busy, [{ ...explore, status: 'idle' }], 30))).toBe(false)
    for (const word of ['pending', 'waiting'] as const) {
      expect(subagentsRunning(applySnapshot([], [{ ...explore, status: word }], 10))).toBe(true)
    }
  })

  test('a fork (steps under an id never listed) is not at work and orphans nothing', () => {
    const fork = addStep([], { agentId: 'f1', model: 'm', usage: null }, 0)
    expect(subagentsRunning(fork)).toBe(false)
    expect(listedIds(fork)).toEqual([])
    expect(endedOwners(fork, endLoop(fork, 'f1', 'aborted', 1, 1))).toEqual([])
    expect(endedOwners(fork, endLoop(fork, 'f1', 'error', 1, 1))).toEqual([])
    const named = applySnapshot(fork, [{ id: 'f1', description: 'now listed', type: 'Explore', status: 'running' }], 2)
    expect(listedIds(named)).toEqual(['f1'])
    expect(subagentsRunning(named)).toBe(true)
  })

  test('a teammate is never finished by a snapshot or a turn', () => {
    const list = applySnapshot([], [{ id: 't1', description: 'mate', type: 'teammate', status: 'idle' }], 0)
    expect(list[0]?.status).toBe('running')
    expect(applySnapshot(list, [{ id: 't1', description: 'mate', type: 'teammate', status: 'completed' }], 1)).toBe(list)
    expect(endLoop(list, 't1', 'answer', 5, 2)).toBe(list)
  })

  test("a teammate's turn ending only clears its tool", () => {
    const mate = applySnapshot([], [{ id: 't1', description: 'mate', type: 'teammate', status: 'running' }], 0)
    const busy = startTool(mate, { agentId: 't1', tool: 'Bash', toolUseId: 'u1' }, 1)
    const idle = endLoop(busy, 't1', 'answer', 5, 9)
    expect(idle[0]?.status).toBe('running')
    expect(idle[0]?.tool).toBeUndefined()
    expect(idle[0]?.toolUseId).toBeUndefined()
    expect(endLoop(idle, 't1', 'answer', 5, 10)).toBe(idle)
  })

  test('turn.complete maps answer / aborted / error / refusal', () => {
    const one = launchLoop([], { id: 'a1', label: 'x', type: 'Explore' }, 0)
    expect(endLoop(one, 'a1', 'answer', 1, 1)[0]?.status).toBe('done')
    expect(endLoop(one, 'a1', 'aborted', 1, 1)[0]?.status).toBe('stopped')
    expect(endLoop(one, 'a1', 'error', 1, 1)[0]?.status).toBe('failed')
    expect(endLoop(one, 'a1', 'refusal', 1, 1)[0]?.status).toBe('failed')
    expect(endLoop(one, 'nope', 'answer', 1, 1)).toBe(one)
  })

  test('the turn ending clears the tool, keeps the tokens', () => {
    let loops = launchLoop([], { id: 'a1', label: 'x', type: 'Explore' }, 0)
    loops = startTool(loops, { agentId: 'a1', tool: 'Grep', toolUseId: 'g1' }, 1)
    loops = addStep(loops, { agentId: 'a1', model: 'm', usage: { ...USAGE, cache_read_input_tokens: 900_000 } }, 2)
    const done = endLoop(loops, 'a1', 'answer', 9, 9)
    expect(done[0]?.status).toBe('done')
    expect(done[0]?.tool).toBeUndefined()
    // Counted tokens leave the cache reads out (task-board's noteStep rule).
    expect(countedTotal(done[0]?.tally ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 })).toBe(34)
  })
})

describe('launchLoop', () => {
  test('a background launch adds a running named loop; a known one only gets its missing names', () => {
    const one = launchLoop([], { id: 'a1', label: 'scan', type: 'Explore' }, 5)
    expect(one[0]?.status).toBe('running')
    expect(one[0]?.label).toBe('scan')
    expect(one[0]?.since).toBe(5)
    expect(launchLoop(one, { id: 'a1', label: 'other', type: 'Plan' }, 6)).toBe(one)
    const stepped = addStep([], { agentId: 'a2', model: 'm', usage: null }, 0)
    const named = launchLoop(stepped, { id: 'a2', label: 'late' }, 1)
    expect(named[0]?.label).toBe('late')
    expect(named[0]?.steps).toBe(1)
  })

  test('the model asked at launch is shown until a step reports its own', () => {
    const one = launchLoop([], { id: 'a1', label: 'scan', type: 'Explore', model: 'haiku' }, 5)
    expect(one[0]?.model).toBe('haiku')
    expect(one[0]?.listed).toBe(true)
    const stepped = addStep(one, { agentId: 'a1', model: 'claude-sonnet-5', usage: null }, 6)
    expect(stepped[0]?.model).toBe('sonnet-5')
    // A launch seen after the first step keeps the step's model.
    const late = launchLoop(addStep([], { agentId: 'a2', model: 'claude-opus-5-5', usage: null }, 0), { id: 'a2', model: 'haiku' }, 1)
    expect(late[0]?.model).toBe('opus-5.5')
  })
})

describe('endedOwners', () => {
  test('a subagent ended failed or stopped is named; done, main and teammates are not', () => {
    let before = launchLoop([], { id: 'a1', type: 'Explore' }, 0)
    before = launchLoop(before, { id: 'a2', type: 'Explore' }, 0)
    before = launchLoop(before, { id: 'a3', type: 'Explore' }, 0)
    before = addStep(before, { model: 'm', usage: null }, 0)
    let after = endLoop(before, 'a1', 'error', 1, 1)
    after = endLoop(after, 'a2', 'aborted', 1, 1)
    after = endLoop(after, 'a3', 'answer', 1, 1)
    after = endLoop(after, undefined, 'error', 1, 1)
    expect(endedOwners(before, after)).toEqual(['a1', 'a2'])
    expect(endedOwners(after, after)).toEqual([])
    const snapped = applySnapshot(before, [{ id: 'a3', description: '', type: 'Explore', status: 'killed' }], 2)
    expect(endedOwners(before, snapped)).toEqual(['a3'])
  })

  test('subagentsRunning ignores the main loop', () => {
    const main = addStep([], { model: 'm', usage: null }, 0)
    expect(subagentsRunning(main)).toBe(false)
    const sub = launchLoop(main, { id: 'a1' }, 0)
    expect(subagentsRunning(sub)).toBe(true)
    expect(subagentsRunning(endLoop(sub, 'a1', 'answer', 1, 1))).toBe(false)
  })

  test('a teammate never counts as running (it is never ended), a subagent beside it does', () => {
    const mate = applySnapshot([], [{ id: 't1', description: 'mate', type: 'teammate', status: 'running' }], 0)
    expect(mate[0]?.status).toBe('running')
    expect(subagentsRunning(mate)).toBe(false)
    const after = endLoop(mate, 't1', 'answer', 1, 1)
    expect(subagentsRunning(after)).toBe(false)
    expect(subagentsRunning(launchLoop(after, { id: 'a1' }, 2))).toBe(true)
  })
})
