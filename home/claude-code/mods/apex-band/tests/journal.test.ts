import { describe, expect, test } from 'claude-code/testing'

import {
  LOG_CAP,
  NO_RECEIPTS,
  addCompaction,
  compactionCount,
  editPath,
  endReceipt,
  gaugeOf,
  isEditTool,
  pushLog,
  receiptAgent,
  receiptEdit,
  receiptError,
  startReceipt,
} from '../hooks/journal.ts'
import type { ApexBandLogEntry } from '../types'

describe('pushLog', () => {
  test('keeps the last LOG_CAP entries, newest last', () => {
    let log: ApexBandLogEntry[] = []
    for (let i = 0; i < LOG_CAP + 5; i++) log = pushLog(log, { at: i, kind: 'prompt', text: `p${i}` })
    expect(log).toHaveLength(LOG_CAP)
    expect(log[0]?.text).toBe('p5')
    expect(log[LOG_CAP - 1]?.text).toBe(`p${LOG_CAP + 4}`)
  })

  test('one line, cut with an ellipsis; empty text keeps the reference', () => {
    const log = pushLog([], { at: 1, kind: 'error', text: '  Bash\n  failed:\texit 1 ' })
    expect(log).toEqual([{ at: 1, kind: 'error', text: 'Bash failed: exit 1' }])
    const long = pushLog([], { at: 1, kind: 'done', text: 'w'.repeat(500) })
    expect(Array.from(long[0]?.text ?? '').length).toBeLessThan(500)
    expect(long[0]?.text.endsWith('…')).toBe(true)
    expect(pushLog(log, { at: 2, kind: 'prompt', text: ' \n ' })).toBe(log)
  })
})

describe('receipts', () => {
  test('lifecycle: agents and edits once each, errors counted, cost added', () => {
    let r = startReceipt(NO_RECEIPTS, { turnId: 't1', at: 1000, cost: 2 })
    expect(r.current?.costAtStart).toBe(2)
    expect(startReceipt(r, { turnId: 't1', at: 1500, cost: 9 })).toBe(r)
    r = receiptAgent(r, 'a1')
    r = receiptAgent(r, 'a2')
    const twice = receiptAgent(r, 'a1')
    expect(twice).toBe(r)
    r = receiptEdit(r, '/x/a.ts')
    expect(receiptEdit(r, '/x/a.ts')).toBe(r)
    r = receiptEdit(r, '/x/b.ts')
    r = receiptError(receiptError(r))
    const ended = endReceipt(r, { at: 4000, reason: 'answer', cost: 2.5 })
    expect(ended.current).toBeNull()
    expect(ended.last).toEqual({
      turnId: 't1',
      startedAt: 1000,
      endedAt: 4000,
      durationMs: 3000,
      reason: 'answer',
      agents: ['a1', 'a2'],
      edits: ['/x/a.ts', '/x/b.ts'],
      errors: 2,
      costAtStart: 2,
      costDelta: 0.5,
    })
  })

  test("the turn's own duration wins; unknown cost leaves no delta", () => {
    const r = startReceipt(NO_RECEIPTS, { turnId: 't1', at: 0, cost: null })
    const ended = endReceipt(r, { at: 9000, durationMs: 1234, reason: 'aborted', cost: 3 })
    expect(ended.last?.durationMs).toBe(1234)
    expect(ended.last?.costDelta).toBeUndefined()
  })

  test('without an open turn every change keeps the reference', () => {
    expect(receiptAgent(NO_RECEIPTS, 'a1')).toBe(NO_RECEIPTS)
    expect(receiptEdit(NO_RECEIPTS, '/a')).toBe(NO_RECEIPTS)
    expect(receiptError(NO_RECEIPTS)).toBe(NO_RECEIPTS)
    expect(endReceipt(NO_RECEIPTS, { at: 1, reason: 'answer', cost: 1 })).toBe(NO_RECEIPTS)
    const done = endReceipt(startReceipt(NO_RECEIPTS, { turnId: 't1', at: 0, cost: 1 }), { at: 5, reason: 'answer', cost: 1 })
    expect(receiptError(done)).toBe(done)
  })

  test('a new turn opens beside the last one', () => {
    const done = endReceipt(startReceipt(NO_RECEIPTS, { turnId: 't1', at: 0, cost: 1 }), { at: 5, reason: 'answer', cost: 2 })
    const next = startReceipt(done, { turnId: 't2', at: 10, cost: 2 })
    expect(next.current?.turnId).toBe('t2')
    expect(next.last?.turnId).toBe('t1')
  })
})

describe('edits', () => {
  test('edit tools and their paths', () => {
    expect(isEditTool('Edit')).toBe(true)
    expect(isEditTool('Write')).toBe(true)
    expect(isEditTool('NotebookEdit')).toBe(true)
    expect(isEditTool('Read')).toBe(false)
    expect(editPath('Edit', { file_path: '/a/b.ts', old_string: '', new_string: '' })).toBe('/a/b.ts')
    expect(editPath('NotebookEdit', { notebook_path: '/n.ipynb', new_source: '' })).toBe('/n.ipynb')
    expect(editPath('Read', { file_path: '/a' })).toBeUndefined()
    expect(editPath('Write', null)).toBeUndefined()
    expect(editPath('Write', { file_path: 7 })).toBeUndefined()
  })
})

describe('compactions', () => {
  test('counted per trigger; precompute ignored', () => {
    const one = addCompaction({}, 'auto')
    const two = addCompaction(addCompaction(one, 'manual'), 'auto')
    expect(two).toEqual({ auto: 2, manual: 1 })
    expect(compactionCount(two)).toBe(3)
    expect(addCompaction(two, 'precompute')).toBe(two)
    expect(compactionCount({})).toBe(0)
  })
})

describe('gaugeOf', () => {
  test('reads percent, tokens, window and the limits with their reset in ms', () => {
    const g = gaugeOf({
      context: { tokens: 45000, window: 200000, percent: 22.5 },
      rateLimits: [
        { kind: 'five_hour', percentUsed: 40, resetsAt: '2026-10-09T12:00:00Z' },
        { kind: 'seven_day', percentUsed: 7, resetsAt: 'soon' },
      ],
    })
    expect(g).toEqual({
      percent: 22.5,
      tokens: 45000,
      window: 200000,
      limits: [
        { kind: 'five_hour', percent: 40, resetsAt: Date.parse('2026-10-09T12:00:00Z') },
        { kind: 'seven_day', percent: 7 },
      ],
    })
  })

  test('percent from tokens when absent; nothing known gives nulls', () => {
    expect(gaugeOf({ context: { tokens: 50000, window: 200000 }, rateLimits: [] }).percent).toBe(25)
    const none = gaugeOf({ context: { window: 0 }, rateLimits: [] })
    expect(none).toEqual({ percent: null, tokens: null, window: 0, limits: [] })
  })

  test('an equal reading returns the previous gauge', () => {
    const reading = { context: { tokens: 1, window: 10 }, rateLimits: [{ kind: 'five_hour', percentUsed: 3 }] }
    const first = gaugeOf(reading)
    expect(gaugeOf(reading, first)).toBe(first)
    expect(gaugeOf({ ...reading, context: { tokens: 2, window: 10 } }, first)).not.toBe(first)
  })
})
