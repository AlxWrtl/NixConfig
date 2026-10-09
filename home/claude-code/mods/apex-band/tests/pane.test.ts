import { describe, expect, test } from 'claude-code/testing'

import { width } from '../hooks/band.ts'
import type { Seg } from '../hooks/band.ts'
import { MAX_DONE, fmtTokens, formatDuration, layoutPane, loopMark, shellMark, shellSummary } from '../hooks/pane.ts'
import type { PaneInput } from '../hooks/pane.ts'
import type { ApexBandLoop, ApexBandRun, ApexBandShell } from '../types'

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

const shell = (id: string, extra: Partial<ApexBandShell> = {}): ApexBandShell => ({
  id,
  label: id,
  startedAt: 0,
  status: 'running',
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
  shells: [],
  alerts: [],
  showAll: false,
}

describe('formats', () => {
  test('tokens and durations', () => {
    expect(fmtTokens(950)).toBe('950')
    expect(fmtTokens(1_234)).toBe('1.2k')
    expect(fmtTokens(45_600)).toBe('46k')
    expect(fmtTokens(1_300_000)).toBe('1.3M')
    expect(fmtTokens(-3)).toBe('0')
  })

  test('the unit is chosen after rounding', () => {
    expect(fmtTokens(999)).toBe('999')
    expect(fmtTokens(1_000)).toBe('1.0k')
    expect(fmtTokens(9_949)).toBe('9.9k')
    expect(fmtTokens(9_999)).toBe('10k')
    expect(fmtTokens(999_499)).toBe('999k')
    expect(fmtTokens(999_999)).toBe('1.0M')
  })

  test('duration boundaries', () => {
    expect(formatDuration(0)).toBe('0s')
    expect(formatDuration(59_900)).toBe('59s')
    expect(formatDuration(60_000)).toBe('1m 00s')
    expect(formatDuration(65_000)).toBe('1m 05s')
    expect(formatDuration(3_599_000)).toBe('59m 59s')
    expect(formatDuration(3_600_000)).toBe('1h 00m')
    expect(formatDuration(-5)).toBe('0s')
  })

  test('one glyph and tone per status, killed apart from failed', () => {
    expect(shellMark('running')).toEqual({ text: '●', tone: 'warning' })
    expect(shellMark('completed')).toEqual({ text: '✓', tone: 'success' })
    expect(shellMark('failed')).toEqual({ text: '✗', tone: 'error' })
    expect(shellMark('killed')).toEqual({ text: '■', tone: 'inactive' })
    expect(loopMark('stopped')).toEqual({ text: '■', tone: 'inactive' })
  })
})

describe('shellSummary', () => {
  test('non-zero counts only, fixed order, masculine plural', () => {
    const list = [
      shell('k1', { status: 'killed' }),
      shell('c1', { status: 'completed' }),
      shell('r1'),
      shell('c2', { status: 'completed' }),
      shell('k2', { status: 'killed' }),
    ]
    expect(shellSummary(list)).toEqual([
      { text: '1 en cours', tone: 'warning', bold: true },
      { text: ' · ', dim: true },
      { text: '2 finis', tone: 'success' },
      { text: ' · ', dim: true },
      { text: '2 arrêtés', tone: 'inactive' },
    ])
  })

  test('singulars, and an empty list has no part', () => {
    const one = [shell('c', { status: 'completed' }), shell('f', { status: 'failed' }), shell('k', { status: 'killed' })]
    expect(text(shellSummary(one))).toBe('1 fini · 1 échoué · 1 arrêté')
    expect(text(shellSummary([shell('r1'), shell('r2')]))).toBe('2 en cours')
    expect(shellSummary([])).toEqual([])
  })
})

describe('layoutPane', () => {
  test('no run, nothing seen: the empty state', () => {
    const lines = layoutPane({ ...WORLD, run: null, loops: [loop('main', {})] }, 80).map(text)
    expect(lines).toEqual(['Aucun run APEX en cours.', 'Lancez /apex ; le détail s’affiche ici.'])
  })

  test('no run but shells and subagents: still listed', () => {
    const shown = layoutPane({ ...WORLD, run: null, shells: [shell('b1', { label: 'dormir' })] }, 80).map(text)
    expect(shown[0]).toBe('Aucun run APEX en cours.')
    expect(shown.includes('Sous-agents')).toBe(true)
    expect(shown.includes('● scan engine types · opus-5.5 · 4.5k · 1m 00s')).toBe(true)
    expect(shown.includes('Shells en arrière-plan')).toBe(true)
    expect(shown.includes('● dormir · 1m 05s')).toBe(true)
    expect(shown.some(l => l.includes('Vérif externe'))).toBe(false)
  })

  test('header, phases ≈, one line per subagent, totals and verdict at 80 columns', () => {
    const lines = layoutPane(WORLD, 80)
    const shown = lines.map(text)
    expect(shown[0]).toBe('APEX · Pane /apex — détail du run')
    expect(lines[0]?.[0]?.bold).toBe(true)
    expect(shown[1]).toBe('High-stakes · feat/apex-pane · baseline vert')
    expect(shown.some(l => l.startsWith('Phases ≈ tokens'))).toBe(true)
    const analyze = shown.find(l => l.includes('analyze')) ?? ''
    // 30k of 40k counted: 8 of 10 cells, brand tone, no track behind.
    expect(analyze.endsWith('30k  ━━━━━━━━')).toBe(true)
    const pending = lines.find(l => text(l).includes('valid'))
    expect(pending?.find(s => s.text.includes('—'))?.dim).toBe(true)
    expect(text(pending ?? []).includes('━')).toBe(false)
    // Running first; tokens counted without cache reads (1 000 + 3 400 + 100).
    const first = shown.indexOf('● scan engine types · opus-5.5 · 4.5k · 1m 00s')
    const second = shown.indexOf('✓ review · 42s')
    expect(first).toBeGreaterThan(0)
    expect(second).toBe(first + 1)
    const running = lines[first] ?? []
    expect(running[1]).toEqual({ text: ' scan engine types', bold: true })
    expect(running[2]?.dim).toBe(true)
    expect(lines[second]?.[1]?.dim).toBe(true)
    expect(shown.includes('principal 52k · sous-agents 4.5k · cache 100 · $1.23')).toBe(true)
    const verdict = lines.find(l => text(l).startsWith('✗ FAIL'))
    expect(verdict?.[0]?.tone).toBe('error')
    expect(text(verdict ?? [])).toBe('✗ FAIL · 2 constats')
    // No Action block without an alert, no shells block without a shell.
    expect(shown.includes('Action')).toBe(false)
    expect(shown.includes('Shells en arrière-plan')).toBe(false)
    // The main loop has no row.
    expect(shown.some(l => l.includes('main'))).toBe(false)
  })

  test('alerts come first under « Action », each on its own line', () => {
    const lines = layoutPane(
      {
        ...WORLD,
        alerts: [
          { kind: 'verify', verdict: 'FAIL', findings: 2 },
          { kind: 'budget', rounds: 2, cap: 2 },
        ],
      },
      120,
    )
    const shown = lines.map(text)
    expect(shown.slice(0, 3)).toEqual([
      'Action',
      '✗ Vérif externe FAIL · 2 constats',
      '⚠ Budget de correction épuisé — tape « apex: +1 tour » ou livre avec les résiduels',
    ])
    expect(lines[1]?.[0]?.tone).toBe('error')
    expect(lines[2]?.[0]?.tone).toBe('warning')
    expect(shown[4]).toBe('APEX · Pane /apex — détail du run')
    // Narrower than the long wording: the short one.
    expect(layoutPane({ ...WORLD, alerts: [{ kind: 'budget', rounds: 3, cap: 3 }] }, 60).map(text)[1]).toBe(
      '⚠ Budget épuisé — « apex: +1 tour »',
    )
  })

  test('shells: counts, running first oldest-first, then finished most-recent-first, frozen times', () => {
    const shells = [
      shell('b1', { label: 'premier', startedAt: 1_000, status: 'killed', endedAt: 6_000 }),
      shell('b2', { label: 'second', startedAt: 2_000 }),
      shell('b3', { label: 'troisième', startedAt: 3_000, status: 'completed', endedAt: 8_000 }),
      shell('b4', { label: 'quatrième', startedAt: 500 }),
    ]
    const lines = layoutPane({ ...WORLD, shells }, 80)
    const shown = lines.map(text)
    const at = shown.indexOf('Shells en arrière-plan')
    expect(shown.slice(at + 1, at + 6)).toEqual([
      '2 en cours · 1 fini · 1 arrêté',
      '● quatrième · 1m 04s',
      '● second · 1m 03s',
      '✓ troisième · 5s',
      '■ premier · 5s',
    ])
    expect(lines[at + 2]?.[0]?.tone).toBe('warning')
    expect(lines[at + 5]?.[0]?.tone).toBe('inactive')
    expect(lines[at + 5]?.[1]?.dim).toBe(true)
    expect(lines[at + 2]?.[1]?.bold).toBe(true)
  })

  test(`past ${MAX_DONE} finished, the most recent ones and « +N terminés »; showAll lists all`, () => {
    const done = Array.from({ length: 8 }, (_, i) =>
      loop(`d${i}`, { label: `fini ${i}`, status: 'done', since: undefined, endedAt: 1_000 * i }),
    )
    const finished = Array.from({ length: 8 }, (_, i) =>
      shell(`s${i}`, { label: `shell ${i}`, status: 'completed', endedAt: 1_000 * i }),
    )
    const folded = layoutPane({ ...WORLD, loops: done, shells: finished }, 80).map(text)
    expect(folded.some(l => l.startsWith('✓ fini 7'))).toBe(true)
    expect(folded.some(l => l.startsWith('✓ fini 2'))).toBe(true)
    expect(folded.some(l => l.startsWith('✓ fini 1'))).toBe(false)
    expect(folded.findIndex(l => l.startsWith('✓ fini 7'))).toBeLessThan(folded.findIndex(l => l.startsWith('✓ fini 6')))
    expect(folded.some(l => l.startsWith('✓ shell 1 '))).toBe(false)
    expect(folded.filter(l => l === '+2 terminés')).toHaveLength(2)
    const all = layoutPane({ ...WORLD, loops: done, shells: finished, showAll: true }, 80).map(text)
    expect(all.some(l => l.startsWith('✓ fini 0'))).toBe(true)
    expect(all.some(l => l.startsWith('✓ shell 0'))).toBe(true)
    expect(all.some(l => l.includes('terminés'))).toBe(false)
  })

  test('a long label is cut first, the details kept', () => {
    const long = loop('l1', { label: 'pnpm test --run a very long command line that will not fit, not even at eighty columns', model: 'opus-5.5' })
    for (const cols of [40, 60, 80]) {
      const row = layoutPane({ ...WORLD, loops: [long] }, cols).find(l => text(l).startsWith('● pnpm')) ?? []
      expect(cells(row) <= cols).toBe(true)
      expect(text(row).endsWith(' · opus-5.5 · 1m 05s')).toBe(true)
      expect(text(row).includes('…')).toBe(true)
    }
    const shellRow = layoutPane({ ...WORLD, shells: [shell('b', { label: 'x'.repeat(100) })] }, 30)
      .map(text)
      .find(l => l.startsWith('● x'))
    expect(shellRow?.endsWith('… · 1m 05s')).toBe(true)
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
    expect(shown.some(l => l.includes('PASS'))).toBe(false)
  })

  test('no verdict at all: no « Vérif externe » block, the totals last', () => {
    const shown = layoutPane({ ...WORLD, verdict: null }, 80).map(text)
    expect(shown.some(l => l.includes('Vérif externe'))).toBe(false)
    expect(shown[shown.length - 1]?.startsWith('principal')).toBe(true)
  })

  test('totals wrap and keep the cost at 46 columns', () => {
    const live: PaneInput = {
      ...WORLD,
      cost: 36.1,
      verdict: null,
      loops: [
        loop('main', { tally: { input: 2_000, output: 30_000, cacheRead: 1_800_000, cacheWrite: 40_000 } }),
        loop('x1', { label: 'scan', status: 'done', tally: { input: 1_000, output: 2_400, cacheRead: 160_000, cacheWrite: 8_000 } }),
      ],
    }
    const shown = layoutPane(live, 46).map(text)
    const at = shown.indexOf('Totaux')
    expect(shown[at + 1]).toBe('principal 72k · sous-agents 11k · cache 2.0M')
    expect(shown[at + 2]).toBe('$36.10')
  })

  for (const cols of [30, 39, 40, 46, 80, 120]) {
    test(`every line fits ${cols} columns`, () => {
      const long: PaneInput = {
        ...WORLD,
        run: { ...RUN, title: 'x'.repeat(200), branch: 'b'.repeat(90) },
        shells: [shell('b', { label: 'y'.repeat(120) })],
        alerts: [{ kind: 'step', step: '03-execute' }, { kind: 'budget', rounds: 2, cap: 2 }],
      }
      for (const line of layoutPane(long, cols)) expect(cells(line) <= cols).toBe(true)
      for (const line of layoutPane(WORLD, cols)) expect(cells(line) <= cols).toBe(true)
    })
  }

  test('below 40 columns the share bar and the model are dropped', () => {
    const shown = layoutPane(WORLD, 39).map(text)
    expect(shown.some(l => l.includes('━'))).toBe(false)
    expect(shown.some(l => l.includes('opus-5.5'))).toBe(false)
    expect(shown.includes('● scan engine types · 4.5k · 1m 00s')).toBe(true)
    expect(layoutPane(WORLD, 40).map(text).some(l => l.includes('━'))).toBe(true)
  })
})

describe('wide glyphs', () => {
  test('CJK and emoji titles and labels fit every width in cells', () => {
    const wide: PaneInput = {
      ...WORLD,
      run: { ...RUN, title: '漢字のタイトル🚀🚀 長い説明文です', branch: 'feat/日本語' },
      loops: [...WORLD.loops, loop('w1', { label: '型を調べる 🔍👨‍👩‍👧 エージェント' })],
      shells: [shell('s', { label: '🚀 長いコマンド' })],
    }
    for (let cols = 1; cols <= 80; cols++)
      for (const line of layoutPane(wide, cols)) expect(width(line) <= cols).toBe(true)
  })
})
