import { describe, expect, test } from 'claude-code/testing'

import {
  CAP,
  addAgent,
  addShell,
  applyAgentSnapshot,
  clear,
  finishAgentTurn,
  finishByNotification,
  runningCount,
} from '../hooks/board.ts'
import type { Task } from '../hooks/board.ts'

const shell = (id: string, startedAt = 0): Task[] => addShell([], { id, label: `cmd ${id}`, startedAt, toolUseId: `tu-${id}` })

describe('board reducer', () => {
  test('a background shell starts running', () => {
    const list = shell('b1', 100)
    expect(list.length).toBe(1)
    expect(list[0]?.status).toBe('running')
    expect(list[0]?.kind).toBe('shell')
  })

  test('adding a known id is a no-op (same reference)', () => {
    const list = shell('b1')
    expect(addShell(list, { id: 'b1', label: 'again', startedAt: 5 })).toBe(list)
  })

  test('notification by id finishes the shell', () => {
    const list = finishByNotification(shell('b1', 1000), { id: 'b1', status: 'completed', durationMs: 5000 }, 99_999)
    expect(list[0]?.status).toBe('completed')
    expect(list[0]?.endedAt).toBe(6000)
  })

  test('notification by toolUseId finishes the shell', () => {
    const list = finishByNotification(shell('b1'), { toolUseId: 'tu-b1', status: 'failed' }, 42)
    expect(list[0]?.status).toBe('failed')
    expect(list[0]?.endedAt).toBe(42)
  })

  test('unknown id, unknown status word and repeats are no-ops', () => {
    const list = shell('b1')
    expect(finishByNotification(list, { id: 'zz', status: 'completed' }, 1)).toBe(list)
    expect(finishByNotification(list, { id: 'b1', status: 'paused' }, 1)).toBe(list)
    expect(finishByNotification(list, { id: 'b1' }, 1)).toBe(list)
    const done = finishByNotification(list, { id: 'b1', status: 'killed' }, 7)
    expect(done[0]?.status).toBe('killed')
    expect(finishByNotification(done, { id: 'b1', status: 'completed' }, 9)).toBe(done)
  })

  test('the list is capped and keeps running tasks first', () => {
    let list: Task[] = []
    for (let i = 0; i < CAP + 10; i += 1) {
      list = addShell(list, { id: `s${i}`, label: 'x', startedAt: i })
      if (i < CAP + 5) list = finishByNotification(list, { id: `s${i}`, status: 'completed' }, i + 1)
    }
    expect(list.length).toBe(CAP)
    expect(runningCount(list)).toBe(5)
    expect(list[0]?.status).toBe('running')
    expect(list[5]?.status).toBe('completed')
  })

  test('agent snapshot adds unknown agents and finishes ended ones', () => {
    const added = applyAgentSnapshot([], [{ id: 'a1', description: 'explore', type: 'Explore', status: 'running' }], 10)
    expect(added[0]?.kind).toBe('agent')
    expect(added[0]?.status).toBe('running')
    const ended = applyAgentSnapshot(added, [{ id: 'a1', description: 'explore', type: 'Explore', status: 'failed' }], 20)
    expect(ended[0]?.status).toBe('failed')
    expect(applyAgentSnapshot(ended, [{ id: 'a1', description: 'explore', type: 'Explore', status: 'failed' }], 30)).toBe(ended)
  })

  test('a teammate is never finished by a snapshot or a turn', () => {
    const list = applyAgentSnapshot([], [{ id: 't1', description: 'mate', type: 'teammate', status: 'idle' }], 0)
    expect(list[0]?.status).toBe('running')
    expect(applyAgentSnapshot(list, [{ id: 't1', description: 'mate', type: 'teammate', status: 'completed' }], 1)).toBe(list)
    expect(finishAgentTurn(list, 't1', 'answer', 2)).toBe(list)
  })

  test('turn.complete maps answer / aborted / error / refusal', () => {
    const one = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    expect(finishAgentTurn(one, 'a1', 'answer', 1)[0]?.status).toBe('completed')
    expect(finishAgentTurn(one, 'a1', 'aborted', 1)[0]?.status).toBe('killed')
    expect(finishAgentTurn(one, 'a1', 'error', 1)[0]?.status).toBe('failed')
    expect(finishAgentTurn(one, 'a1', 'refusal', 1)[0]?.status).toBe('failed')
    expect(finishAgentTurn(one, 'nope', 'answer', 1)).toBe(one)
  })

  test('clear empties, and an empty list stays the same reference', () => {
    expect(clear(shell('b1')).length).toBe(0)
    const empty: Task[] = []
    expect(clear(empty)).toBe(empty)
  })
})
