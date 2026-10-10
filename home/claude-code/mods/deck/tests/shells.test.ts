// Ported from apex-band (shell, notification, TaskStop and orphan cases): the owner's end
// comes from its turn.complete (shellsAfterTurn, applied by register.tsx to every subagent) or
// the agent snapshot (closeBySnapshot).
import { describe, expect, test } from 'claude-code/testing'

import {
  CAP,
  addShell,
  clearFinished,
  closeBySnapshot,
  finishByNotification,
  parseTaskNotification,
  parseTaskNotifications,
  runningShells,
  shellsAfterTurn,
  stopShell,
} from '../hooks/shells'
import type { Shell } from '../hooks/shells'

const shell = (id: string, startedAt = 0): Shell[] => addShell([], { id, label: `cmd ${id}`, startedAt, toolUseId: `tu-${id}` })

// The owner `a1` ended by its turn with `reason` at `at`.
const ownerTurn = (list: Shell[], reason: string, at: number): Shell[] => shellsAfterTurn(list, 'a1', reason, at)

const owned = (): Shell[] => addShell([], { id: 'b1', label: 'sleep', startedAt: 1, ownerAgentId: 'a1' })
const snap = (status: string, type = 'Explore') => [{ id: 'a1', type, status }]

describe('shells reducer', () => {
  test('a background shell starts running', () => {
    const list = shell('b1', 100)
    expect(list.length).toBe(1)
    expect(list[0]?.status).toBe('running')
    expect(list[0]?.toolUseId).toBe('tu-b1')
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

  test('the list is capped and keeps running shells first', () => {
    let list: Shell[] = []
    for (let i = 0; i < CAP + 10; i += 1) {
      list = addShell(list, { id: `s${i}`, label: 'x', startedAt: i })
      if (i < CAP + 5) list = finishByNotification(list, { id: `s${i}`, status: 'completed' }, i + 1)
    }
    expect(list.length).toBe(CAP)
    expect(runningShells(list)).toBe(5)
    expect(list[0]?.status).toBe('running')
    expect(list[5]?.status).toBe('completed')
  })
})

describe('orphan shells', () => {
  test('a killed or failed owner closes its running shells', () => {
    const list = owned()
    const bySnapshot = closeBySnapshot(list, snap('killed'), ['a1'], 50)
    const shellAfter = bySnapshot.find(t => t.id === 'b1')
    expect(shellAfter?.status).toBe('killed')
    expect(shellAfter?.endedAt).toBe(50)
    expect(closeBySnapshot(list, snap('failed'), ['a1'], 55).find(t => t.id === 'b1')?.status).toBe('killed')
    const byTurn = ownerTurn(list, 'error', 60)
    expect(byTurn.find(t => t.id === 'b1')?.status).toBe('killed')
    expect(byTurn.find(t => t.id === 'b1')?.endedAt).toBe(60)
    expect(ownerTurn(list, 'aborted', 70).find(t => t.id === 'b1')?.status).toBe('killed')
    expect(ownerTurn(list, 'refusal', 80).find(t => t.id === 'b1')?.status).toBe('killed')
  })

  test('a completed owner keeps its shells running', () => {
    const list = owned()
    expect(closeBySnapshot(list, snap('completed'), ['a1'], 50)).toBe(list)
    expect(ownerTurn(list, 'answer', 50)).toBe(list)
  })

  test("a teammate's shells stay while it is listed, ended or not", () => {
    const list = owned()
    expect(closeBySnapshot(list, snap('killed', 'teammate'), ['a1'], 50)).toBe(list)
    expect(closeBySnapshot(list, snap('idle', 'teammate'), ['a1'], 50)).toBe(list)
    expect(closeBySnapshot(list, [], ['a1'], 60).find(t => t.id === 'b1')?.status).toBe('killed')
  })

  test('shells of another owner or of the main loop are untouched', () => {
    let list = addShell([], { id: 'b2', label: 'other', startedAt: 1, ownerAgentId: 'a2' })
    list = addShell(list, { id: 'b3', label: 'main', startedAt: 2 })
    const out = ownerTurn(list, 'aborted', 50)
    expect(out).toBe(list)
    expect(out.find(t => t.id === 'b2')?.status).toBe('running')
    expect(out.find(t => t.id === 'b3')?.status).toBe('running')
    expect(closeBySnapshot(list, snap('killed'), ['a1'], 50)).toBe(list)
  })

  test('an already finished shell keeps its end state and time', () => {
    const done = finishByNotification(owned(), { id: 'b1', status: 'completed' }, 5)
    const out = ownerTurn(done, 'aborted', 50)
    expect(out.find(t => t.id === 'b1')?.status).toBe('completed')
    expect(out.find(t => t.id === 'b1')?.endedAt).toBe(5)
  })

  test('no shell to close: the snapshot answers the same reference', () => {
    const list = owned()
    expect(closeBySnapshot(list, snap('running'), ['a1'], 50)).toBe(list)
  })

  test('an owner gone from the agent list closes its running shells', () => {
    const out = closeBySnapshot(owned(), [], ['a1'], 80)
    expect(out.find(t => t.id === 'b1')?.status).toBe('killed')
    expect(out.find(t => t.id === 'b1')?.endedAt).toBe(80)
  })

  test('an owner never seen as a loop is not closed for being absent', () => {
    const list = owned()
    expect(closeBySnapshot(list, [], [], 80)).toBe(list)
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
    const ownerDone = ownerTurn(owned(), 'answer', 10)
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
    // An agent id is never a shell row: TaskStop on a subagent changes nothing here.
    expect(stopShell(list, 'a1', 40)).toBe(list)
  })
})

describe('shellsAfterTurn', () => {
  test('a turn ended without an answer closes that owner\'s running shells, whatever the owner', () => {
    // An architect's shells too: register.tsx applies it before the architect's early return.
    const list = addShell(owned(), { id: 'b2', label: 'review', startedAt: 2, ownerAgentId: 'fab1' })
    const out = shellsAfterTurn(list, 'fab1', 'aborted', 40)
    expect(out.find(t => t.id === 'b2')?.status).toBe('killed')
    expect(out.find(t => t.id === 'b2')?.endedAt).toBe(40)
    expect(out.find(t => t.id === 'b1')?.status).toBe('running')
  })

  test('an answer, or an owner with no shell, changes nothing (same reference)', () => {
    const list = owned()
    expect(shellsAfterTurn(list, 'a1', 'answer', 40)).toBe(list)
    expect(shellsAfterTurn(list, 'zz', 'aborted', 40)).toBe(list)
  })
})

describe('clearFinished (a new run began)', () => {
  const card = (id: string, status: string) => ({ id, status })

  test('finished cards and ended shells go, running ones stay', () => {
    const cards = [card('c1', 'done'), card('c2', 'running'), card('c3', 'failed'), card('c4', 'stopped')]
    let shells = addShell(shell('b1', 1), { id: 'b2', label: 'cmd b2', startedAt: 2 })
    shells = addShell(shells, { id: 'b3', label: 'cmd b3', startedAt: 3 })
    shells = stopShell(shells, 'b1', 10)
    shells = finishByNotification(shells, { id: 'b3', status: 'completed' }, 11)
    const out = clearFinished(cards, shells)
    expect(out.cards.map(c => c.id)).toEqual(['c2'])
    expect(out.shells.map(s => `${s.id}:${s.status}`)).toEqual(['b2:running'])
  })

  test('nothing finished: the same references back', () => {
    const cards = [card('c1', 'running')]
    const shells = shell('b1', 1)
    const out = clearFinished(cards, shells)
    expect(out.cards).toBe(cards)
    expect(out.shells).toBe(shells)
  })
})
