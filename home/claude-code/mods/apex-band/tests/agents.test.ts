import { describe, expect, test } from 'claude-code/testing'

import {
  CARD_MAX,
  CARD_MIN,
  CARD_ROWS,
  MAX_CARDS,
  agentsLine,
  blockLoops,
  cardWidth,
  clockSeg,
  kTokens,
  layoutAgents,
  railLine,
} from '../hooks/agents.ts'
import type { AgentsOptions } from '../hooks/agents.ts'
import { width } from '../hooks/band.ts'
import type { Seg } from '../hooks/band.ts'
import type { ApexBandLoop } from '../types'

const MIN = 60_000
const NOW = 20 * MIN

const agent = (id: string, model: string, startedAt: number, extra: Partial<ApexBandLoop> = {}): ApexBandLoop => ({
  id,
  label: `task ${id}`,
  type: 'Explore',
  model,
  status: 'running',
  steps: 12,
  calls: 20,
  listed: true,
  tally: { input: 1000, output: 3200, cacheRead: 0, cacheWrite: 0 },
  startedAt,
  since: startedAt,
  durationMs: 0,
  context: 45_000,
  ...extra,
})

const MODELS = ['claude-opus-5-5[1m]', 'claude-sonnet-5', 'claude-haiku-4-5-20251001']
const agents = (n: number): ApexBandLoop[] =>
  Array.from({ length: n }, (_, i) => agent(`a${i + 1}`, MODELS[i % 3] ?? 'opus', NOW - (n - i) * MIN))

const BAND: AgentsOptions = { numbered: false, includeDone: false }
const textOf = (line: readonly Seg[] | undefined): string => (line ?? []).map(s => s.text).join('')
const block = (n: number, cols: number, rows: number, opts = BAND) => layoutAgents({ loops: agents(n), now: NOW }, cols, rows, opts)

describe('layoutAgents: shape by room', () => {
  for (const cols of [80, 120])
    for (let n = 1; n <= MAX_CARDS; n++)
      test(`${n} card(s) at ${cols}: rail + four bordered rows`, () => {
        const { mode, lines } = block(n, cols, 8)
        expect(mode).toBe('cards')
        expect(lines).toHaveLength(1 + CARD_ROWS)
        expect(textOf(lines[0]).startsWith('◆ main ')).toBe(true)
        expect(width(lines[0] ?? [])).toBe(cols)
        const cw = cardWidth(n, cols) ?? 0
        expect(cw >= CARD_MIN && cw <= CARD_MAX).toBe(true)
        for (const line of lines.slice(1)) expect(width(line)).toBe(n * cw + n - 1)
        const count = (r: number, glyph: string): number => Array.from(textOf(lines[r])).filter(c => c === glyph).length
        expect([count(1, '╭'), count(1, '╮'), count(4, '╰'), count(4, '╯')]).toEqual([n, n, n, n])
        expect([count(2, '│'), count(3, '│')]).toEqual([2 * n, 2 * n])
        expect(textOf(lines[1]).startsWith('╭')).toBe(true)
        expect(textOf(lines[4]).endsWith('╯')).toBe(true)
      })

  test('a card reads label, type · model, ctx · out, steps and its clock', () => {
    const lines = block(1, 80, 5).lines.map(textOf)
    expect(lines[1]).toBe(`╭─ ● task a1 ${'─'.repeat(22)}╮`)
    expect(lines[2]).toBe(`│ Explore · opus-5.5${' '.repeat(15)}│`)
    expect(lines[3]).toBe(`│ ctx 45k · out 3.2k${' '.repeat(15)}│`)
    expect(lines[4]).toBe(`╰─ 12 steps ${'─'.repeat(15)}  1:00 ─╯`)
  })

  test('four agents, or cards too narrow, or under five rows: lanes', () => {
    expect(block(4, 120, 8).mode).toBe('lanes')
    expect(block(2, 40, 8).mode).toBe('lanes')
    expect(block(3, 120, 4).mode).toBe('lanes')
  })

  test('a single row: one line counting agents by family', () => {
    const { mode, lines } = block(3, 80, 1)
    expect(mode).toBe('line')
    expect(lines.map(textOf)).toEqual(['● 3 agents · opus×1 sonnet×1 haiku×1'])
    expect(textOf(agentsLine(agents(1), 80))).toBe('● 1 agent · opus×1')
    expect(textOf(agentsLine(agents(3), 12))).toBe('● 3 agents')
    expect(block(3, 80, 0).lines).toEqual([])
  })

  test('lanes: rail + rows − 1 lanes, the last counting the others (+k)', () => {
    const { lines } = block(5, 80, 3)
    expect(lines).toHaveLength(3)
    expect(textOf(lines[2]).endsWith(' +3')).toBe(true)
    expect(textOf(block(2, 80, 4).lines[2]).includes('+')).toBe(false)
    for (const line of block(5, 80, 8).lines) expect(width(line) <= 80).toBe(true)
  })

  test('lanes: bars start at the spawn, ● head while running, ✓ when done', () => {
    const loops = [agent('a1', 'opus', NOW - 4 * MIN), agent('a2', 'haiku', NOW - 2 * MIN, { status: 'done', endedAt: NOW - MIN })]
    const { lines } = layoutAgents({ loops, now: NOW }, 60, 4, { numbered: false, includeDone: true })
    const [rail, first, second] = lines.map(textOf)
    expect(first?.startsWith('● task a1')).toBe(true)
    expect(first?.includes('━●')).toBe(true)
    expect(second?.startsWith('✓ task a2')).toBe(true)
    expect(second?.includes('━✓')).toBe(true)
    // The rail drops a ┬ at each lane's first bar cell.
    const barStart = (s: string | undefined): number => Array.from(s ?? '').findIndex(c => c === '━')
    expect(Array.from(rail ?? '')[barStart(first)]).toBe('┬')
    expect(Array.from(rail ?? '')[barStart(second)]).toBe('┬')
  })

  test('narrow lanes drop the family column, then the axis', () => {
    const at = (cols: number): string => textOf(block(2, cols, 4).lines[1])
    expect(at(60).includes('opus')).toBe(true)
    expect(at(36).includes('opus')).toBe(true)
    expect(at(35).includes('opus')).toBe(false)
    expect(at(35).includes('━')).toBe(true)
    expect(at(26).includes('━')).toBe(false)
    for (let cols = 1; cols <= 60; cols++) for (const line of block(4, cols, 6).lines) expect(width(line) <= cols).toBe(true)
  })

  test('border tones follow the model family', () => {
    const lines = block(3, 120, 5).lines
    const tones = (lines[1] ?? []).filter(s => s.text.startsWith('╭')).map(s => s.tone)
    expect(tones).toEqual(['claude', 'suggestion', 'planMode'])
  })

  test('numbered: cards and lanes carry 1, 2, 3', () => {
    const numbered = { numbered: true, includeDone: false }
    expect(textOf(block(2, 80, 5, numbered).lines[1]).includes('● 1 task a1')).toBe(true)
    expect(textOf(block(4, 80, 6, numbered).lines[2]).startsWith('2 ● ')).toBe(true)
  })
})

describe('live segments', () => {
  test('the rail is live: cells, drops relative to its left end, active while one works', () => {
    const line = railLine(40, [10, 20], true)
    expect(textOf(line)).toBe(`◆ main ${'─'.repeat(3)}┬${'─'.repeat(9)}┬${'─'.repeat(19)}`)
    expect(line[1]?.live).toEqual({ kind: 'rail', key: 'rail', cells: 33, drops: [3, 13], active: true, tone: 'claude' })
    expect(railLine(5, [], true).some(s => s.live !== undefined)).toBe(false)
    const done = [agent('a1', 'opus', 0, { status: 'done', endedAt: MIN })]
    const lines = layoutAgents({ loops: done, now: NOW }, 80, 8, { numbered: false, includeDone: true }).lines
    const live = lines[0]?.[1]?.live
    expect(live?.kind === 'rail' ? live.active : null).toBe(false)
  })

  test('a clock is live: its running time, counting while it runs', () => {
    const seg = clockSeg(agent('a1', 'opus', NOW - 90_000), NOW)
    expect(seg.text).toBe(' 1:30')
    expect(seg.live).toEqual({ kind: 'clock', key: 'clock:a1', ms: 90_000, running: true })
    const ended = clockSeg(agent('a2', 'opus', 0, { status: 'done', since: undefined, durationMs: 5_000 }), NOW)
    expect(ended.live).toEqual({ kind: 'clock', key: 'clock:a2', ms: 5_000, running: false })
  })
})

describe('which loops', () => {
  test('at work only, unless includeDone adds the listed ones that ended; oldest first', () => {
    const loops = [
      agent('b', 'opus', 2),
      agent('a', 'opus', 1),
      agent('d', 'opus', 3, { status: 'done' }),
      agent('t', 'opus', 4, { type: 'teammate' }),
      agent('f', 'opus', 5, { listed: false }),
      agent('main', 'opus', 0),
    ]
    expect(blockLoops(loops, false).map(l => l.id)).toEqual(['a', 'b'])
    expect(blockLoops(loops, true).map(l => l.id)).toEqual(['a', 'b', 'd'])
  })

  test('kTokens: 950, 3.2k, 45k, 1.2M', () => {
    expect([950, 3_200, 45_000, 1_200_000].map(kTokens)).toEqual(['950', '3.2k', '45k', '1.2M'])
  })
})
