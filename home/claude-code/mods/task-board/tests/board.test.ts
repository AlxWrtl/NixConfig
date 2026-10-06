import { describe, expect, test } from 'claude-code/testing'

import {
  CAP,
  addAgent,
  addShell,
  applyAgentSnapshot,
  clear,
  finishAgentTurn,
  finishByNotification,
  parseTaskNotification,
  parseTaskNotifications,
  runningCount,
  stopShell,
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

  test('a killed or failed owner closes its running shells', () => {
    const owner = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    const list = addShell(owner, { id: 'b1', label: 'sleep', startedAt: 1, ownerAgentId: 'a1' })
    const bySnapshot = applyAgentSnapshot(list, [{ id: 'a1', description: 'x', type: 'Explore', status: 'killed' }], 50)
    const shellAfter = bySnapshot.find(t => t.id === 'b1')
    expect(shellAfter?.status).toBe('killed')
    expect(shellAfter?.endedAt).toBe(50)
    const byTurn = finishAgentTurn(list, 'a1', 'error', 60)
    expect(byTurn.find(t => t.id === 'b1')?.status).toBe('killed')
    expect(byTurn.find(t => t.id === 'b1')?.endedAt).toBe(60)
    expect(finishAgentTurn(list, 'a1', 'aborted', 70).find(t => t.id === 'b1')?.status).toBe('killed')
  })

  test('a completed owner keeps its shells running', () => {
    const owner = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    const list = addShell(owner, { id: 'b1', label: 'sleep', startedAt: 1, ownerAgentId: 'a1' })
    const bySnapshot = applyAgentSnapshot(list, [{ id: 'a1', description: 'x', type: 'Explore', status: 'completed' }], 50)
    expect(bySnapshot.find(t => t.id === 'b1')?.status).toBe('running')
    expect(finishAgentTurn(list, 'a1', 'answer', 50).find(t => t.id === 'b1')?.status).toBe('running')
  })

  test('shells of another owner or of the main loop are untouched', () => {
    let list = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    list = addAgent(list, { id: 'a2', label: 'y', startedAt: 0, agentType: 'Explore' })
    list = addShell(list, { id: 'b2', label: 'other', startedAt: 1, ownerAgentId: 'a2' })
    list = addShell(list, { id: 'b3', label: 'main', startedAt: 2 })
    const out = finishAgentTurn(list, 'a1', 'aborted', 50)
    expect(out.find(t => t.id === 'b2')?.status).toBe('running')
    expect(out.find(t => t.id === 'b3')?.status).toBe('running')
  })

  test('an already finished shell keeps its end state and time', () => {
    const owner = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    const started = addShell(owner, { id: 'b1', label: 'sleep', startedAt: 1, ownerAgentId: 'a1' })
    const done = finishByNotification(started, { id: 'b1', status: 'completed' }, 5)
    const out = finishAgentTurn(done, 'a1', 'aborted', 50)
    expect(out.find(t => t.id === 'b1')?.status).toBe('completed')
    expect(out.find(t => t.id === 'b1')?.endedAt).toBe(5)
  })

  test('no shell to close: the snapshot answers the same reference', () => {
    const owner = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    const list = addShell(owner, { id: 'b1', label: 'sleep', startedAt: 1, ownerAgentId: 'a1' })
    expect(applyAgentSnapshot(list, [{ id: 'a1', description: 'x', type: 'Explore', status: 'running' }], 50)).toBe(list)
  })

  test('an owner gone from the agent list closes its running shells', () => {
    const owner = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    const list = addShell(owner, { id: 'b1', label: 'sleep', startedAt: 1, ownerAgentId: 'a1' })
    const out = applyAgentSnapshot(list, [], 80)
    expect(out.find(t => t.id === 'b1')?.status).toBe('killed')
    expect(out.find(t => t.id === 'b1')?.endedAt).toBe(80)
  })

  test('clear empties, and an empty list stays the same reference', () => {
    expect(clear(shell('b1')).length).toBe(0)
    const empty: Task[] = []
    expect(clear(empty)).toBe(empty)
  })
})

describe('task notification text', () => {
  const text = (id: string, status: string): string =>
    `<task-notification>\n<task-id>${id}</task-id>\n<status>${status}</status>\n<summary>Background command "x" ${status}</summary>\n</task-notification>`

  test('completed / failed / killed are read with their id', () => {
    expect(parseTaskNotification(text('banaihxzj', 'completed'))).toEqual({ id: 'banaihxzj', status: 'completed' })
    expect(parseTaskNotification(text('b2', 'failed'))).toEqual({ id: 'b2', status: 'failed' })
    expect(parseTaskNotification(text('b3', 'killed'))).toEqual({ id: 'b3', status: 'killed' })
  })

  test('an unknown status, a malformed row or a missing id read as nothing', () => {
    expect(parseTaskNotification(text('b1', 'running'))).toBeUndefined()
    expect(parseTaskNotification('<task-id>b1</task-id><status>completed')).toBeUndefined()
    expect(parseTaskNotification('<status>completed</status>')).toBeUndefined()
    expect(parseTaskNotification(text('', 'completed'))).toBeUndefined()
    expect(parseTaskNotification('plain text')).toBeUndefined()
  })

  test("a completed owner's shell closes on its parsed notification", () => {
    const owner = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    const started = addShell(owner, { id: 'b1', label: 'reindex', startedAt: 1, ownerAgentId: 'a1' })
    const ownerDone = finishAgentTurn(started, 'a1', 'answer', 10)
    expect(ownerDone.find(t => t.id === 'b1')?.status).toBe('running')
    const note = parseTaskNotification(text('b1', 'completed'))
    expect(note).toBeDefined()
    const out = note === undefined ? ownerDone : finishByNotification(ownerDone, note, 20)
    expect(out.find(t => t.id === 'b1')?.status).toBe('completed')
    expect(out.find(t => t.id === 'b1')?.endedAt).toBe(20)
    expect(note === undefined ? out : finishByNotification(out, note, 30)).toBe(out)
  })

  test('a row with one block reads one notification', () => {
    expect(parseTaskNotifications(`[SYSTEM NOTIFICATION]\n\n${text('b1', 'completed')}`)).toEqual([
      { id: 'b1', status: 'completed' },
    ])
    expect(parseTaskNotifications('plain text')).toEqual([])
  })

  test('a batched row reads every block, skipping a malformed one', () => {
    const row = [text('b1', 'completed'), text('b2', 'failed'), text('b3', 'running')].join('\n')
    expect(parseTaskNotifications(row)).toEqual([
      { id: 'b1', status: 'completed' },
      { id: 'b2', status: 'failed' },
    ])
  })

  test('a TaskStop closes a running shell as killed; an agent or unknown id is a no-op', () => {
    const list = shell('b1', 5)
    const out = stopShell(list, 'b1', 40)
    expect(out[0]?.status).toBe('killed')
    expect(out[0]?.endedAt).toBe(40)
    expect(stopShell(list, 'zz', 40)).toBe(list)
    expect(stopShell(out, 'b1', 50)).toBe(out)
    const agent = addAgent([], { id: 'a1', label: 'x', startedAt: 0, agentType: 'Explore' })
    expect(stopShell(agent, 'a1', 40)).toBe(agent)
  })
})
