import { describe, expect, test } from 'claude-code/testing'

import {
  MAIN,
  addPhase,
  addStep,
  applySnapshot,
  endLoop,
  endTool,
  loopDuration,
  parseVerdict,
  shortModel,
  splitTotals,
  startTool,
  syncPhases,
  tallyTotal,
  countedTotal,
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
    expect(applySnapshot(ended, snap, 10_000)).toBe(ended)
    expect(endLoop(ended, 'a1', 'error', 1, 11_000)).toBe(ended)
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
