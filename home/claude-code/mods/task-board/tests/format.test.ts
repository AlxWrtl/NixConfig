import { describe, expect, test } from 'claude-code/testing'

import {
  GLYPH_WIDTH,
  KIND_WIDTH,
  fmtTokens,
  formatDuration,
  glyph,
  hasBothGroups,
  layoutRow,
  summary,
  tone,
  truncate,
} from '../hooks/format.ts'
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

describe('glyph and tone', () => {
  test('one glyph and theme color per status, killed apart from failed', () => {
    expect(glyph('running')).toBe('●')
    expect(glyph('completed')).toBe('✓')
    expect(glyph('failed')).toBe('✗')
    expect(glyph('killed')).toBe('■')
    expect(tone('running')).toBe('warning')
    expect(tone('completed')).toBe('success')
    expect(tone('failed')).toBe('error')
    expect(tone('killed')).toBe('inactive')
  })
})

const make = (id: string, status: Task['status']): Task => ({ id, kind: 'shell', label: id, startedAt: 0, status })

describe('summary', () => {
  test('non-zero counts only, fixed order, French feminine plural', () => {
    const list = [
      make('k1', 'killed'),
      make('c1', 'completed'),
      make('r1', 'running'),
      make('c2', 'completed'),
      make('k2', 'killed'),
    ]
    expect(summary(list)).toEqual([
      { text: '1 en cours', tone: 'warning', bold: true },
      { text: '2 finies', tone: 'success', bold: false },
      { text: '2 arrêtées', tone: 'inactive', bold: false },
    ])
  })

  test('singulars, and an empty list has no part', () => {
    expect(summary([make('c1', 'completed'), make('f1', 'failed'), make('k1', 'killed')]).map(p => p.text)).toEqual([
      '1 finie',
      '1 échouée',
      '1 arrêtée',
    ])
    expect(summary([make('r1', 'running'), make('r2', 'running')]).map(p => p.text)).toEqual(['2 en cours'])
    expect(summary([])).toEqual([])
  })
})

describe('hasBothGroups', () => {
  test('true only with running and finished tasks', () => {
    expect(hasBothGroups([make('r1', 'running'), make('k1', 'killed')])).toBe(true)
    expect(hasBothGroups([make('r1', 'running')])).toBe(false)
    expect(hasBothGroups([make('c1', 'completed'), make('f1', 'failed')])).toBe(false)
    expect(hasBothGroups([])).toBe(false)
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

  for (const cols of [20, 39, 40, 80]) {
    test(`fits ${cols} columns`, () => {
      const row = layoutRow(task, 61_000, cols)
      expect(row.glyph).toBe('●')
      expect(row.tone).toBe('warning')
      expect(row.isDone).toBe(false)
      expect(row.dur).toBe('1m 01s')
      expect(row.kind).toBe(cols >= 40 ? 'shell' : '')
      const kindWidth = row.kind === '' ? 0 : KIND_WIDTH
      expect(GLYPH_WIDTH + kindWidth + row.text.length + 1 + row.dur.length <= cols).toBe(true)
    })
  }

  test('a long label is cut with an ellipsis', () => {
    expect(layoutRow(task, 0, 20).text.endsWith('…')).toBe(true)
    expect(layoutRow(task, 0, 80).text.endsWith('…')).toBe(false)
  })

  test('an agent with a type shows "{type} · {label}"', () => {
    const agent: Task = { id: 'a1', kind: 'agent', label: 'relire la PR', agentType: 'reviewer', startedAt: 0, status: 'running' }
    const row = layoutRow(agent, 0, 80)
    expect(row.kind).toBe('agent')
    expect(row.text).toBe('reviewer · relire la PR')
    const untyped: Task = { id: 'a2', kind: 'agent', label: 'relire la PR', startedAt: 0, status: 'running' }
    expect(layoutRow(untyped, 0, 80).text).toBe('relire la PR')
  })

  test('a finished task freezes its duration', () => {
    const row = layoutRow({ ...task, status: 'completed', endedAt: 5_000 }, 999_000, 80)
    expect(row.dur).toBe('5s')
    expect(row.glyph).toBe('✓')
    expect(row.tone).toBe('success')
    expect(row.isDone).toBe(true)
  })

  test('a killed task is drawn apart from a failed one', () => {
    const killed = layoutRow({ ...task, status: 'killed', endedAt: 1_000 }, 999_000, 80)
    expect(killed.glyph).toBe('■')
    expect(killed.tone).toBe('inactive')
    expect(killed.isDone).toBe(true)
    const failed = layoutRow({ ...task, status: 'failed', endedAt: 1_000 }, 999_000, 80)
    expect(failed.glyph).toBe('✗')
    expect(failed.tone).toBe('error')
  })

  test('truncate edges', () => {
    expect(truncate('abc', 0)).toBe('')
    expect(truncate('abc', 1)).toBe('…')
    expect(truncate('abc', 3)).toBe('abc')
  })
})

describe('fmtTokens', () => {
  test('boundaries: unit chosen after rounding', () => {
    expect(fmtTokens(0)).toBe('0')
    expect(fmtTokens(999)).toBe('999')
    expect(fmtTokens(1_000)).toBe('1.0k')
    expect(fmtTokens(1_234)).toBe('1.2k')
    expect(fmtTokens(9_949)).toBe('9.9k')
    expect(fmtTokens(9_999)).toBe('10k')
    expect(fmtTokens(12_000)).toBe('12k')
    expect(fmtTokens(999_499)).toBe('999k')
    expect(fmtTokens(999_999)).toBe('1.0M')
    expect(fmtTokens(-3)).toBe('0')
  })
})

describe('layoutRow detail', () => {
  const agent: Task = {
    id: 'a1',
    kind: 'agent',
    label: 'scanner les types du moteur pour la PR',
    agentType: 'Explore',
    startedAt: 0,
    status: 'running',
    tool: 'Read',
    tokens: 12_000,
  }

  test('a running agent shows " · tool · tokens"; a finished one keeps only the tokens', () => {
    expect(layoutRow(agent, 0, 120).detail).toBe(' · Read · 12k')
    expect(layoutRow({ ...agent, status: 'completed', endedAt: 1 }, 0, 120).detail).toBe(' · 12k')
    const { tool: _tool, tokens: _tokens, ...plain } = agent
    expect(layoutRow(plain, 0, 120).detail).toBe('')
  })

  for (const cols of [20, 39, 40, 60, 80]) {
    test(`label + detail fit ${cols} columns, the label keeps its cells first`, () => {
      const row = layoutRow(agent, 61_000, cols)
      const kindWidth = row.kind === '' ? 0 : KIND_WIDTH
      expect(GLYPH_WIDTH + kindWidth + row.text.length + row.detail.length + 1 + row.dur.length <= cols).toBe(true)
      expect(row.text.length).toBeGreaterThanOrEqual(Math.min(10, cols - GLYPH_WIDTH - kindWidth - 1 - row.dur.length))
    })
  }
})
