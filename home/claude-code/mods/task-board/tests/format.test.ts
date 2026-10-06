import { describe, expect, test } from 'claude-code/testing'

import { formatDuration, label, layoutRow, truncate } from '../hooks/format.ts'
import type { Task } from '../hooks/board.ts'

describe('formatDuration', () => {
  test('boundaries', () => {
    expect(formatDuration(0)).toBe('0s')
    expect(formatDuration(59_900)).toBe('59s')
    expect(formatDuration(60_000)).toBe('1m 00s')
    expect(formatDuration(3_599_000)).toBe('59m 59s')
    expect(formatDuration(3_600_000)).toBe('1h 00m')
    expect(formatDuration(-5)).toBe('0s')
  })
})

describe('label', () => {
  test('French state words', () => {
    expect(label('running')).toBe('en cours')
    expect(label('completed')).toBe('fini')
    expect(label('failed')).toBe('échoué')
    expect(label('killed')).toBe('échoué')
  })
})

describe('layoutRow', () => {
  const task: Task = {
    id: 'b1',
    kind: 'shell',
    label: 'pnpm test --run a very long command line that will not fit',
    startedAt: 0,
    status: 'running',
  }

  for (const cols of [20, 80]) {
    test(`fits ${cols} columns`, () => {
      const row = layoutRow(task, 61_000, cols)
      expect(row.state.trim()).toBe('en cours')
      expect(row.dur).toBe('1m 01s')
      expect(row.state.length + 1 + row.text.length + 1 + row.dur.length <= cols).toBe(true)
    })
  }

  test('a long label is cut with an ellipsis', () => {
    expect(layoutRow(task, 0, 20).text.endsWith('…')).toBe(true)
  })

  test('a finished task freezes its duration', () => {
    const row = layoutRow({ ...task, status: 'completed', endedAt: 5_000 }, 999_000, 80)
    expect(row.dur).toBe('5s')
    expect(row.state.trim()).toBe('fini')
  })

  test('truncate edges', () => {
    expect(truncate('abc', 0)).toBe('')
    expect(truncate('abc', 1)).toBe('…')
    expect(truncate('abc', 3)).toBe('abc')
  })
})
