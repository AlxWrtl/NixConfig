import { describe, expect, test } from 'claude-code/testing'

import { width } from '../hooks/band.ts'
import type { Seg } from '../hooks/band.ts'
import { fmtTokens, formatDuration, layoutPane } from '../hooks/pane.ts'
import type { PaneInput } from '../hooks/pane.ts'
import type { ApexBandLoop, ApexBandRun } from '../types'

// The text a line shows, its segments joined.
const text = (line: readonly Seg[]): string => line.map(s => s.text).join('')
const cells = (line: readonly Seg[]): number => Array.from(text(line)).length
const tally = (input: number, output: number) => ({ input, output, cacheRead: 0, cacheWrite: 0 })

const RUN: ApexBandRun = {
  title: 'Pane /apex — détail du run',
  mode: 'High-stakes',
  branch: 'feat/apex-pane',
  baseline: 'green',
  dir: 'apex-pane',
  currentStep: '03-execute',
  steps: [
    { step: '00-init', status: 'complete', kind: 'done' },
    { step: '01-analyze', status: 'complete', kind: 'done' },
    { step: '03-execute', status: 'in progress', kind: 'running' },
    { step: '04-validate', status: 'pending', kind: 'pending' },
  ],
}

const loop = (id: string, extra: Partial<ApexBandLoop>): ApexBandLoop => ({
  id,
  status: 'running',
  steps: 1,
  calls: 0,
  tally: tally(0, 0),
  startedAt: 0,
  durationMs: 0,
  since: 0,
  ...extra,
})

const WORLD: PaneInput = {
  run: RUN,
  now: 65_000,
  cost: 1.234,
  verdict: { dir: 'apex-pane', verdict: 'FAIL', findings: 2, mtimeMs: 1 },
  phases: {
    dir: 'apex-pane',
    byStep: { '01-analyze': tally(30_000, 0), '03-execute': tally(10_000, 0) },
  },
  loops: [
    loop('main', { tally: tally(50_000, 2_000) }),
    loop('a1', {
      label: 'scan engine types',
      type: 'Explore',
      model: 'opus-5.5',
      tool: 'Read',
      calls: 12,
      tally: { input: 1_000, output: 3_400, cacheRead: 100, cacheWrite: 100 },
      startedAt: 5_000,
      since: 5_000,
    }),
    loop('a2', {
      label: 'review',
      type: 'code-reviewer',
      status: 'done',
      since: undefined,
      durationMs: 42_000,
      endedAt: 50_000,
      calls: 3,
    }),
  ],
}

describe('formats', () => {
  test('tokens and durations', () => {
    expect(fmtTokens(950)).toBe('950')
    expect(fmtTokens(1_234)).toBe('1.2k')
    expect(fmtTokens(45_600)).toBe('46k')
    expect(fmtTokens(1_300_000)).toBe('1.3M')
    expect(formatDuration(65_000)).toBe('1m 05s')
  })

  test('the unit is chosen after rounding', () => {
    expect(fmtTokens(999)).toBe('999')
    expect(fmtTokens(9_949)).toBe('9.9k')
    expect(fmtTokens(9_960)).toBe('10k')
    expect(fmtTokens(9_999)).toBe('10k')
    expect(fmtTokens(999_499)).toBe('999k')
    expect(fmtTokens(999_500)).toBe('1.0M')
    expect(fmtTokens(999_999)).toBe('1.0M')
  })
})

describe('layoutPane', () => {
  test('no run: the empty state', () => {
    const lines = layoutPane({ ...WORLD, run: null }, 80).map(text)
    expect(lines).toEqual(['Aucun run APEX en cours.', 'Lancez /apex ; le détail s’affiche ici.'])
  })

  test('header, phases ≈, cards, totals and verdict at 80 columns', () => {
    const lines = layoutPane(WORLD, 80)
    const shown = lines.map(text)
    expect(shown[0]).toBe('APEX · Pane /apex — détail du run')
    expect(lines[0]?.[0]?.bold).toBe(true)
    expect(shown[1]).toBe('High-stakes · feat/apex-pane · baseline vert')
    expect(shown.some(l => l.startsWith('Phases ≈ tokens'))).toBe(true)
    const analyze = shown.find(l => l.includes('analyze')) ?? ''
    expect(analyze.includes('30k')).toBe(true)
    // 30k of 40k counted: 8 of 10 cells, brand tone, no track behind.
    expect(analyze.endsWith('30k  ━━━━━━━━')).toBe(true)
    const bar = lines.find(l => text(l).includes('analyze'))?.find(s => s.text.includes('━'))
    expect(bar?.tone).toBe('claude')
    const pending = lines.find(l => text(l).includes('valid'))
    expect(pending?.find(s => s.text.includes('—'))?.dim).toBe(true)
    // A 0-token row has no bar at all.
    expect(text(pending ?? []).includes('━')).toBe(false)
    expect(shown.some(l => l.includes('░'))).toBe(false)
    // Running card first, its two detail lines in full; finished card dimmed.
    const first = shown.indexOf('● scan engine types')
    const second = shown.indexOf('✓ review')
    expect(first).toBeGreaterThan(0)
    expect(second).toBeGreaterThan(first)
    // in = input + cache write (1 000 + 100), the cache read apart.
    expect(shown[first + 1]).toBe('  opus-5.5 · 1m 00s · in 1.1k · out 3.4k')
    expect(shown[first + 2]).toBe('  Explore · Read · 12 appels · cache 100')
    expect(lines[first + 1]?.[0]?.dim).toBe(true)
    expect(lines[first + 2]?.[0]?.dim).toBe(true)
    expect(lines[second]?.[1]?.dim).toBe(true)
    // A card without cache reads shows no cache part.
    expect(shown[second + 2]).toBe('  code-reviewer · 3 appels')
    // Counted totals leave cache reads out: sous-agents 1 000 + 3 400 + 100.
    expect(shown.includes('principal 52k · sous-agents 4.5k · cache 100 · $1.23')).toBe(true)
    expect(lines.find(l => text(l).startsWith('principal'))?.find(s => s.text === 'cache 100')?.dim).toBe(true)
    expect(shown.includes('Vérif externe')).toBe(true)
    const verdict = lines.find(l => text(l).startsWith('✗ FAIL'))
    expect(verdict?.[0]?.tone).toBe('error')
    expect(text(verdict ?? [])).toBe('✗ FAIL · 2 constats')
    // The main loop has no card.
    expect(shown.some(l => l.includes('main'))).toBe(false)
  })

  test('phases of another run dir and a verdict of another run are not shown', () => {
    const shown = layoutPane(
      {
        ...WORLD,
        phases: { ...WORLD.phases, dir: 'old-run' },
        verdict: { dir: 'old-run', verdict: 'PASS', findings: 0, mtimeMs: 1 },
      },
      80,
    ).map(text)
    expect(shown.some(l => l.includes('30k'))).toBe(false)
    expect(shown.some(l => l.includes('Vérif externe'))).toBe(false)
    expect(shown.some(l => l.includes('en attente'))).toBe(false)
    expect(shown.some(l => l.includes('PASS'))).toBe(false)
  })

  test('no verdict at all: no « Vérif externe » block, the totals last', () => {
    const shown = layoutPane({ ...WORLD, verdict: null }, 80).map(text)
    expect(shown.some(l => l.includes('Vérif externe'))).toBe(false)
    expect(shown[shown.length - 1]?.startsWith('principal')).toBe(true)
  })

  test('a live-like run at 46 columns: card line A whole, totals wrap and keep the cost', () => {
    const live: PaneInput = {
      ...WORLD,
      cost: 36.1,
      verdict: null,
      phases: { dir: 'apex-pane', byStep: {} },
      loops: [
        loop('main', { tally: { input: 2_000, output: 30_000, cacheRead: 1_800_000, cacheWrite: 40_000 } }),
        loop('x1', {
          label: 'scan engine types',
          type: 'Explore',
          model: 'sonnet-5.5',
          status: 'done',
          since: undefined,
          calls: 12,
          durationMs: 65_000,
          endedAt: 60_000,
          tally: { input: 1_000, output: 2_400, cacheRead: 160_000, cacheWrite: 8_000 },
        }),
      ],
    }
    const lines = layoutPane(live, 46)
    const shown = lines.map(text)
    for (const line of lines) expect(width(line) <= 46).toBe(true)
    expect(shown.some(l => l.includes('…'))).toBe(false)
    const head = shown.indexOf('✓ scan engine types')
    expect(shown[head + 1]).toBe('  sonnet-5.5 · 1m 05s · in 9.0k · out 2.4k')
    expect(shown[head + 2]).toBe('  Explore · 12 appels · cache 160k')
    // Counted: main 2k + 30k + 40k, sub 1k + 2.4k + 8k; cache 1.8M + 160k.
    const at = shown.indexOf('Totaux')
    expect(shown[at + 1]).toBe('principal 72k · sous-agents 11k · cache 2.0M')
    expect(shown[at + 2]).toBe('$36.10')
    // No step has tokens: no bar anywhere.
    expect(shown.some(l => l.includes('━') || l.includes('░'))).toBe(false)
  })

  test('more than six finished cards: the most recent six and « +N terminés »', () => {
    const done = Array.from({ length: 8 }, (_, i) =>
      loop(`d${i}`, { label: `fini ${i}`, status: 'done', since: undefined, endedAt: 1_000 * i }),
    )
    const shown = layoutPane({ ...WORLD, loops: done }, 80).map(text)
    expect(shown.includes('✓ fini 7')).toBe(true)
    expect(shown.includes('✓ fini 2')).toBe(true)
    expect(shown.includes('✓ fini 1')).toBe(false)
    expect(shown.indexOf('✓ fini 7')).toBeLessThan(shown.indexOf('✓ fini 6'))
    expect(shown.includes('+2 terminés')).toBe(true)
  })

  test('a step with a tiny share still gets one bar cell', () => {
    const tiny: PaneInput = {
      ...WORLD,
      phases: { dir: 'apex-pane', byStep: { '01-analyze': tally(1_000_000, 0), '03-execute': tally(100, 0) } },
    }
    const lines = layoutPane(tiny, 46)
    const exec = text(lines.find(l => text(l).includes('exec')) ?? [])
    expect(exec.endsWith('100  ━')).toBe(true)
    expect(text(lines.find(l => text(l).includes('analyze')) ?? []).endsWith('1.0M  ━━━━━━━━━━')).toBe(true)
  })

  test('phase figures leave cache reads out', () => {
    const cached: PaneInput = {
      ...WORLD,
      phases: {
        dir: 'apex-pane',
        byStep: { '03-execute': { input: 2_000, output: 3_000, cacheRead: 900_000, cacheWrite: 5_000 } },
      },
    }
    const exec = text(layoutPane(cached, 80).find(l => text(l).includes('exec')) ?? [])
    expect(exec.includes('10k')).toBe(true)
    expect(exec.includes('905k') || exec.includes('910k')).toBe(false)
  })

  for (const cols of [30, 40, 46, 80, 120]) {
    test(`every line fits ${cols} columns`, () => {
      const long = { ...WORLD, run: { ...RUN, title: 'x'.repeat(200), branch: 'b'.repeat(90) } }
      for (const line of layoutPane(long, cols)) expect(cells(line) <= cols).toBe(true)
      for (const line of layoutPane(WORLD, cols)) expect(cells(line) <= cols).toBe(true)
      expect(layoutPane(WORLD, cols).some(l => text(l).includes('░'))).toBe(false)
    })
  }

  test('below 40 columns the share bar and the type and model are dropped', () => {
    const shown = layoutPane(WORLD, 39).map(text)
    expect(shown.some(l => l.includes('━') || l.includes('░'))).toBe(false)
    expect(shown.includes('  Read · 1m 00s')).toBe(true)
    // One detail line per card below 40 columns.
    expect(shown[shown.indexOf('● scan engine types') + 2]).toBe('✓ review')
    expect(shown.some(l => l.includes('opus-5.5'))).toBe(false)
    expect(layoutPane(WORLD, 40).map(text).some(l => l.includes('━'))).toBe(true)
  })
})

describe('wide glyphs', () => {
  test('CJK and emoji titles and descriptions fit every width in cells', () => {
    const wide: PaneInput = {
      ...WORLD,
      run: { ...RUN, title: '漢字のタイトル🚀🚀 長い説明文です', branch: 'feat/日本語' },
      loops: [
        ...WORLD.loops,
        { id: 'w1', label: '型を調べる 🔍👨‍👩‍👧 エージェント', status: 'running', steps: 1, calls: 0, tally: tally(1, 1), startedAt: 0, durationMs: 0, since: 0 },
      ],
    }
    for (let cols = 1; cols <= 80; cols++)
      for (const line of layoutPane(wide, cols)) expect(width(line) <= cols).toBe(true)
  })

  test('a title of watches never exceeds cols, cells counted by a local table', () => {
    // Test-local widths, not cellWidth: ⌚ is 2 cells, every other glyph is 1.
    const local = (line: readonly Seg[]): number =>
      Array.from(text(line)).reduce((n, ch) => n + (ch === '⌚' ? 2 : 1), 0)
    const watches: PaneInput = { ...WORLD, run: { ...RUN, title: '⌚⌚⌚⌚⌚⌚⌚⌚⌚⌚' } }
    for (let cols = 1; cols <= 40; cols++)
      for (const line of layoutPane(watches, cols)) expect(local(line) <= cols).toBe(true)
  })
})
