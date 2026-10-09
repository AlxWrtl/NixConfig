import { describe, expect, test } from 'claude-code/testing'

import { width } from '../hooks/band.ts'
import type { Seg } from '../hooks/band.ts'
import {
  JOURNAL_ROWS,
  MAX_DONE,
  age,
  countdown,
  fmtTokens,
  formatDuration,
  layoutPane,
  loopMark,
  paneHotkeys,
  shellMark,
  shellSummary,
  wrap,
} from '../hooks/pane.ts'
import type { PaneInput } from '../hooks/pane.ts'
import type { ApexBandLogEntry, ApexBandLoop, ApexBandReceipt, ApexBandRun, ApexBandShell } from '../types'

// The text a line shows, its segments joined.
const text = (line: readonly Seg[]): string => line.map(s => s.text).join('')
const cells = (line: readonly Seg[]): number => width(line)
const tally = (input: number, output: number) => ({ input, output, cacheRead: 0, cacheWrite: 0 })
// The section names, in the order their rules come.
const sections = (lines: readonly Seg[][]): string[] =>
  lines.map(text).flatMap(l => {
    const m = /^── (.+?) ─*$/.exec(l)
    return m?.[1] === undefined ? [] : [m[1]]
  })
// The lines under a section's rule, up to the next rule.
const section = (lines: readonly Seg[][], name: string): string[] => {
  const shown = lines.map(text)
  const at = shown.findIndex(l => l.startsWith(`── ${name} `))
  if (at < 0) return []
  const rest = shown.slice(at + 1)
  const end = rest.findIndex(l => l.startsWith('── '))
  return end < 0 ? rest : rest.slice(0, end)
}

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
  listed: true,
  ...extra,
})

const shell = (id: string, extra: Partial<ApexBandShell> = {}): ApexBandShell => ({
  id,
  label: id,
  startedAt: 0,
  status: 'running',
  ...extra,
})

const receipt = (extra: Partial<ApexBandReceipt> = {}): ApexBandReceipt => ({
  turnId: 't1',
  startedAt: 5_000,
  agents: [],
  edits: [],
  errors: 0,
  costAtStart: 1,
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
    loop('main', { tally: tally(50_000, 2_000), listed: undefined, effort: 'high' }),
    loop('a1', {
      label: 'scan engine types',
      type: 'Explore',
      model: 'opus-5.5',
      tool: 'Read',
      calls: 12,
      steps: 4,
      context: 45_000,
      tally: { input: 1_000, output: 3_400, cacheRead: 100, cacheWrite: 100 },
      startedAt: 5_000,
      since: 5_000,
      task: 'Read the engine types under .claude-plugin and list every surface the pane may use',
      recent: [
        { tool: 'Read', target: 'hooks/pane.ts' },
        { tool: 'Grep', target: 'layoutPane' },
        { tool: 'Bash', target: 'pnpm test' },
      ],
      answer: 'Found three surfaces: Pane, AbovePrompt and Client.',
    }),
    loop('a2', {
      label: 'review',
      type: 'code-reviewer',
      status: 'done',
      since: undefined,
      startedAt: 8_000,
      durationMs: 42_000,
      endedAt: 50_000,
      calls: 3,
    }),
  ],
  shells: [],
  alerts: [],
  showAll: false,
  model: 'claude-opus-5-5[1m]',
  gauge: null,
  receipts: { current: null, last: null },
  log: [],
  compactions: {},
  expanded: null,
}

const GAUGE = {
  percent: 34,
  tokens: 68_000,
  window: 200_000,
  limits: [
    { kind: 'five_hour', percent: 42, resetsAt: 65_000 + 72 * 60_000 },
    { kind: 'seven_day', percent: 18 },
  ],
}

const LOG: ApexBandLogEntry[] = Array.from({ length: 10 }, (_, i) => ({
  at: 5_000 * i,
  kind: (['prompt', 'spawn', 'done', 'edit', 'error', 'compact'] as const)[i % 6] ?? 'prompt',
  text: `entrée ${i}`,
}))

// Everything at once: every section has something.
const FULL: PaneInput = {
  ...WORLD,
  alerts: [{ kind: 'budget', rounds: 2, cap: 2 }],
  gauge: GAUGE,
  compactions: { auto: 1, manual: 1 },
  receipts: { current: receipt({ agents: ['a1'], edits: ['/r/hooks/pane.ts'], errors: 1 }), last: null },
  log: LOG,
  shells: [shell('b1', { label: 'pnpm test' })],
  loops: [...WORLD.loops, loop('f1', { label: 'fork', listed: undefined, steps: 7 })],
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

  test('ages and countdowns', () => {
    expect(age(12_000)).toBe('12s')
    expect(age(185_000)).toBe('3m')
    expect(age(7_300_000)).toBe('2h')
    expect(age(3 * 86_400_000)).toBe('3j')
    expect(countdown(30_000)).toBe('1m')
    expect(countdown(72 * 60_000)).toBe('1h12')
    expect(countdown((3 * 24 + 4) * 3_600_000)).toBe('3j04h')
  })

  test('wrap: words, a split long word, the last row cut with …', () => {
    expect(wrap('un deux trois quatre', 9, 6)).toEqual(['un deux', 'trois', 'quatre'])
    expect(wrap('abcdefghij', 4, 6)).toEqual(['abcd', 'efgh', 'ij'])
    expect(wrap('un deux trois quatre cinq', 9, 2)).toEqual(['un deux', 'trois…'])
    for (const row of wrap('漢字のタイトル 長い説明文です', 5, 6)) expect(width([{ text: row }]) <= 5).toBe(true)
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

describe('layoutPane sections', () => {
  test('no run, nothing seen: the empty state', () => {
    const lines = layoutPane({ ...WORLD, run: null, cost: null, model: null, loops: [loop('main', { listed: undefined })] }, 80)
    expect(lines.map(text)).toEqual(['Aucun run APEX en cours.', 'Lancez /apex ; le détail s’affiche ici.'])
  })

  test('every section under its rule, in order', () => {
    const lines = layoutPane(FULL, 100)
    expect(sections(lines)).toEqual([
      'Action',
      'Principal',
      'Run',
      'Agents',
      'Boucles',
      'Reçu',
      'Journal',
      'Shells en arrière-plan',
      'Totaux',
      'Vérif externe',
    ])
    // A rule spans the width, its name bold.
    const first = lines[0] ?? []
    expect(cells(first)).toBe(100)
    expect(first[1]).toEqual({ text: 'Action', bold: true })
  })

  test('no run but shells and subagents: still listed', () => {
    const lines = layoutPane({ ...WORLD, run: null, shells: [shell('b1', { label: 'dormir' })] }, 80)
    expect(section(lines, 'Run')).toEqual(['Aucun run APEX en cours.'])
    expect(section(lines, 'Agents').some(l => l.includes('1 scan engine'))).toBe(true)
    expect(section(lines, 'Shells en arrière-plan')).toContain('● dormir · 1m 05s')
    expect(sections(lines)).not.toContain('Vérif externe')
  })
})

describe('Principal', () => {
  test('model · effort · cost, the gauge with ⟲, the windows with ↻', () => {
    const lines = layoutPane({ ...WORLD, gauge: GAUGE, compactions: { auto: 2 } }, 100)
    expect(section(lines, 'Principal')).toEqual([
      '◆ opus-5.5 · effort high · $1.23',
      'ctx ▰▰▰▱▱▱▱▱▱▱ 34% 68k/200k ⟲2',
      '5h 42% ↻1h12 · 7j 18%',
    ])
  })

  test('unread gauge: ctx –; below 40 columns, five cells', () => {
    expect(section(layoutPane(WORLD, 80), 'Principal')[1]).toBe('ctx –')
    const narrow = section(layoutPane({ ...WORLD, gauge: GAUGE }, 39), 'Principal')
    expect(narrow).toContain('ctx ▰▰▱▱▱ 34% 68k/200k')
  })

  test('the gauge turns amber past 70, red past 90', () => {
    const tone = (percent: number) =>
      layoutPane({ ...WORLD, gauge: { ...GAUGE, percent } }, 80)
        .find(l => text(l).startsWith('ctx '))
        ?.find(s => s.text.startsWith('▰'))?.tone
    expect(tone(34)).toBe('claude')
    expect(tone(75)).toBe('warning')
    expect(tone(95)).toBe('error')
  })

  test('a reset already past has no countdown', () => {
    const gauge = { ...GAUGE, limits: [{ kind: 'five_hour', percent: 99, resetsAt: 1_000 }] }
    expect(section(layoutPane({ ...WORLD, gauge }, 80), 'Principal')).toContain('5h 99%')
  })
})

describe('Run', () => {
  test('header, meta, phases ≈ with share bars', () => {
    const lines = layoutPane(WORLD, 80)
    const run = section(lines, 'Run')
    expect(run[0]).toBe('APEX · Pane /apex — détail du run')
    expect(run[1]).toBe('High-stakes · feat/apex-pane · baseline vert')
    expect(run[2]?.startsWith('Phases ≈ tokens')).toBe(true)
    const analyze = run.find(l => l.includes('analyze')) ?? ''
    // 30k of 40k counted: 8 of 10 cells, brand tone, no track behind.
    expect(analyze.endsWith('30k  ━━━━━━━━')).toBe(true)
    const pending = lines.find(l => text(l).includes('valid'))
    expect(pending?.find(s => s.text.includes('—'))?.dim).toBe(true)
    expect(text(pending ?? []).includes('━')).toBe(false)
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
})

describe('Agents', () => {
  test('numbered cards under the rail at 80 columns, the done one beside', () => {
    const lines = layoutPane(WORLD, 80)
    const agents = section(lines, 'Agents')
    expect(agents[0]?.startsWith('◆ main ')).toBe(true)
    expect(agents[1]?.startsWith('╭─ ● 1 scan engine types')).toBe(true)
    expect(agents[1]?.includes('✓ 2 review')).toBe(true)
    expect(agents.some(l => l.includes('Explore · opus-5.5'))).toBe(true)
    expect(agents.some(l => l.includes('ctx 45k · out 3.4k'))).toBe(true)
    expect(agents.some(l => l.startsWith('╰─ 4 steps'))).toBe(true)
    // The clock is live: a Client draws it on.
    const clock = lines.flat().find(s => s.live?.kind === 'clock' && s.live.key === 'clock:a1')
    expect(clock?.live).toEqual({ kind: 'clock', key: 'clock:a1', ms: 60_000, running: true })
    // The main loop is no agent.
    expect(agents.some(l => l.includes('main ') && !l.startsWith('◆'))).toBe(false)
  })

  test('four agents: numbered lanes', () => {
    const four = [
      ...WORLD.loops,
      loop('a3', { label: 'trois', model: 'haiku', startedAt: 10_000, since: 10_000 }),
      loop('a4', { label: 'quatre', model: 'sonnet', startedAt: 20_000, since: 20_000 }),
    ]
    const agents = section(layoutPane({ ...WORLD, loops: four }, 100), 'Agents')
    expect(agents).toHaveLength(5)
    expect(agents[1]?.startsWith('1 ● scan engine t…')).toBe(true)
    expect(agents[4]?.startsWith('4 ● quatre')).toBe(true)
    expect(agents[1]?.includes('opus')).toBe(true)
  })

  test('hotkeys follow the numbering, at most six', () => {
    expect(paneHotkeys(WORLD)).toEqual([
      { n: 1, id: 'a1' },
      { n: 2, id: 'a2' },
    ])
    const many = Array.from({ length: 9 }, (_, i) => loop(`r${i}`, { label: `run ${i}`, startedAt: i }))
    const keys = paneHotkeys({ ...WORLD, loops: many })
    expect(keys).toHaveLength(6)
    expect(keys[5]).toEqual({ n: 6, id: 'r5' })
    // Unlisted loops get no key.
    expect(paneHotkeys({ ...WORLD, loops: [loop('f', { listed: undefined })] })).toEqual([])
  })

  test('the expanded agent: task wrapped, last three tools, answer head', () => {
    const lines = layoutPane({ ...WORLD, expanded: 'a1' }, 60)
    const agents = section(lines, 'Agents')
    const at = agents.findIndex(l => l.startsWith('▾ 1 scan engine types · Explore · opus-5.5'))
    expect(at).toBeGreaterThan(0)
    const block = agents.slice(at + 1)
    expect(block[0]?.startsWith('  tâche   Read the engine types')).toBe(true)
    expect(block.filter(l => l.startsWith('  outils  ') || l.startsWith('          ')).length >= 3).toBe(true)
    expect(block).toContain('  outils  Read hooks/pane.ts')
    expect(block).toContain('          Grep layoutPane')
    expect(block).toContain('          Bash pnpm test')
    expect(block.some(l => l.startsWith('  réponse Found three surfaces'))).toBe(true)
    for (const line of lines) expect(cells(line) <= 60).toBe(true)
  })

  test('a long task keeps six rows at most, an empty agent says so', () => {
    const long = 'mot '.repeat(400)
    const loops = [loop('x', { label: 'x', task: long, answer: 'réponse '.repeat(100) })]
    const agents = section(layoutPane({ ...WORLD, loops, expanded: 'x' }, 50), 'Agents')
    const task = agents.filter(l => l.startsWith('  tâche') || (l.startsWith('          mot')))
    expect(task).toHaveLength(6)
    expect(task[5]?.endsWith('…')).toBe(true)
    const answer = agents.slice(agents.findIndex(l => l.startsWith('  réponse')))
    expect(answer).toHaveLength(3)
    const bare = section(layoutPane({ ...WORLD, loops: [loop('y', { label: 'y' })], expanded: 'y' }, 50), 'Agents')
    expect(bare[bare.length - 1]).toBe('  rien à détailler pour l’instant')
    // An id not drawn: no block.
    expect(section(layoutPane({ ...WORLD, expanded: 'nope' }, 80), 'Agents').some(l => l.startsWith('▾'))).toBe(false)
  })

  test(`past ${MAX_DONE} finished, the most recent ones and « +N terminés »; showAll lists all`, () => {
    const done = Array.from({ length: 8 }, (_, i) =>
      loop(`d${i}`, { label: `fini ${i}`, status: 'done', since: undefined, startedAt: i, endedAt: 1_000 * i }),
    )
    const finished = Array.from({ length: 8 }, (_, i) =>
      shell(`s${i}`, { label: `shell ${i}`, status: 'completed', endedAt: 1_000 * i }),
    )
    const folded = layoutPane({ ...WORLD, loops: done, shells: finished }, 80)
    const agents = section(folded, 'Agents')
    expect(agents.some(l => l.includes('fini 7'))).toBe(true)
    expect(agents.some(l => l.startsWith('1 ✓ fini 2'))).toBe(true)
    expect(agents.some(l => l.includes('fini 1 '))).toBe(false)
    expect(folded.map(text).some(l => l.startsWith('✓ shell 1 '))).toBe(false)
    expect(folded.map(text).filter(l => l === '+2 terminés')).toHaveLength(2)
    const all = layoutPane({ ...WORLD, loops: done, shells: finished, showAll: true }, 80).map(text)
    expect(all.some(l => l.includes('fini 0'))).toBe(true)
    expect(all.some(l => l.startsWith('✓ shell 0'))).toBe(true)
    expect(all.some(l => l.includes('terminés'))).toBe(false)
  })

  test('below 40 columns: numbered rows, no model, no share bar', () => {
    const lines = layoutPane(WORLD, 39)
    const shown = lines.map(text)
    expect(shown.some(l => l.includes('━'))).toBe(false)
    const agents = section(lines, 'Agents')
    expect(agents.some(l => l.includes('opus'))).toBe(false)
    expect(agents[0]).toBe('1 ● scan engine types · 4.5k  1:00')
    expect(agents[1]).toBe('2 ✓ review  0:42')
    expect(layoutPane(WORLD, 40).map(text).some(l => l.includes('━'))).toBe(true)
  })
})

describe('Boucles', () => {
  test('only loops no agent list names, with their ⟲ steps', () => {
    const loops = [
      ...WORLD.loops,
      loop('f1', { label: 'fork summary', listed: undefined, steps: 7, tally: tally(2_000, 0) }),
      loop('t1', { label: 'teammate', type: 'teammate', steps: 3 }),
    ]
    const shown = section(layoutPane({ ...WORLD, loops }, 80), 'Boucles')
    expect(shown).toEqual(['● fork summary · ⟲ 7 · 2.0k · 1m 05s', '● teammate · ⟲ 3 · 1m 05s'])
    expect(sections(layoutPane(WORLD, 80))).not.toContain('Boucles')
  })

  test('a long label is cut first, the details kept', () => {
    const long = loop('l1', {
      label: 'pnpm test --run a very long command line that will not fit, not even at eighty columns',
      listed: undefined,
    })
    for (const cols of [40, 60, 80]) {
      const row = layoutPane({ ...WORLD, loops: [long] }, cols).find(l => text(l).startsWith('● pnpm')) ?? []
      expect(cells(row) <= cols).toBe(true)
      expect(text(row).endsWith(' · ⟲ 1 · 1m 05s')).toBe(true)
      expect(text(row).includes('…')).toBe(true)
    }
    const shellRow = layoutPane({ ...WORLD, shells: [shell('b', { label: 'x'.repeat(100) })] }, 30)
      .map(text)
      .find(l => l.startsWith('● x'))
    expect(shellRow?.endsWith('… · 1m 05s')).toBe(true)
  })
})

describe('Reçu', () => {
  test('the turn under way: ● live clock, counts, cost so far, edited files', () => {
    const current = receipt({ agents: ['a1', 'a2'], edits: ['/r/hooks/pane.ts', '/r/tests/pane.test.ts'], errors: 1 })
    const lines = layoutPane({ ...WORLD, receipts: { current, last: receipt() } }, 100)
    expect(section(lines, 'Reçu')).toEqual([
      '● en cours  1:00 · 2 agents · 2 éditions · 1 erreur · +$0.23',
      '✎ hooks/pane.ts, tests/pane.test.ts',
    ])
    const clock = lines.flat().find(s => s.live?.key === 'clock:turn:t1')
    expect(clock?.live).toEqual({ kind: 'clock', key: 'clock:turn:t1', ms: 60_000, running: true })
    expect(lines.flat().find(s => s.text === '1 erreur')?.tone).toBe('error')
  })

  test('the last turn once ended: its status, duration and cost delta', () => {
    const last = receipt({ endedAt: 50_000, durationMs: 125_000, reason: 'answer', costDelta: 0.42, agents: ['a1'] })
    expect(section(layoutPane({ ...WORLD, receipts: { current: null, last } }, 100), 'Reçu')).toEqual([
      '✓ dernier tour 2m 05s · 1 agent · 0 édition · 0 erreur · +$0.42',
    ])
    const aborted = { ...last, reason: 'aborted' }
    expect(section(layoutPane({ ...WORLD, receipts: { current: null, last: aborted } }, 100), 'Reçu')[0]?.startsWith('■')).toBe(true)
    expect(sections(layoutPane(WORLD, 80))).not.toContain('Reçu')
  })
})

describe('Journal', () => {
  test(`the last ${JOURNAL_ROWS} entries, newest last, glyph and age`, () => {
    const lines = layoutPane({ ...WORLD, log: LOG }, 80)
    const shown = section(lines, 'Journal')
    expect(shown).toHaveLength(JOURNAL_ROWS)
    expect(shown[0]).toBe('55s ✓ entrée 2')
    expect(shown[JOURNAL_ROWS - 1]).toBe('20s ✎ entrée 9')
    expect(shown.map(l => l.slice(4, 5)).join('')).toBe('✓✎✗⟲›┬✓✎')
    const at = lines.findIndex(l => text(l).startsWith('── Journal'))
    expect(lines[at + 3]?.[1]?.tone).toBe('error')
  })
})

describe('Shells / Totaux / Vérif externe', () => {
  test('totals and verdict close the pane', () => {
    const lines = layoutPane(WORLD, 80)
    expect(section(lines, 'Totaux')).toEqual(['principal 52k · sous-agents 4.5k · cache 100 · $1.23'])
    const verdict = lines.find(l => text(l).startsWith('✗ FAIL'))
    expect(verdict?.[0]?.tone).toBe('error')
    expect(text(verdict ?? [])).toBe('✗ FAIL · 2 constats')
    expect(sections(lines)).not.toContain('Action')
    expect(sections(lines)).not.toContain('Shells en arrière-plan')
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
    expect(section(lines, 'Action')).toEqual([
      '✗ Vérif externe FAIL · 2 constats',
      '⚠ Budget de correction épuisé — tape « apex: +1 tour » ou livre avec les résiduels',
    ])
    expect(lines[1]?.[0]?.tone).toBe('error')
    expect(lines[2]?.[0]?.tone).toBe('warning')
    expect(text(lines[3] ?? []).startsWith('── Principal')).toBe(true)
    expect(text(layoutPane({ ...WORLD, alerts: [{ kind: 'budget', rounds: 3, cap: 3 }] }, 60)[1] ?? [])).toBe(
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
    expect(section(lines, 'Shells en arrière-plan')).toEqual([
      '2 en cours · 1 fini · 1 arrêté',
      '● quatrième · 1m 04s',
      '● second · 1m 03s',
      '✓ troisième · 5s',
      '■ premier · 5s',
    ])
    const at = lines.findIndex(l => text(l).startsWith('── Shells'))
    expect(lines[at + 2]?.[0]?.tone).toBe('warning')
    expect(lines[at + 2]?.[1]?.bold).toBe(true)
    expect(lines[at + 5]?.[0]?.tone).toBe('inactive')
    expect(lines[at + 5]?.[1]?.dim).toBe(true)
  })

  test('no verdict at all: no « Vérif externe », the totals last', () => {
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
    expect(section(layoutPane(live, 46), 'Totaux')).toEqual(['principal 72k · sous-agents 11k · cache 2.0M', '$36.10'])
  })
})

describe('widths', () => {
  const LONG: PaneInput = {
    ...FULL,
    expanded: 'a1',
    run: { ...RUN, title: 'x'.repeat(200), branch: 'b'.repeat(90) },
    shells: [shell('b', { label: 'y'.repeat(120) })],
    alerts: [{ kind: 'step', step: '03-execute' }, { kind: 'budget', rounds: 2, cap: 2 }],
    log: [...LOG, { at: 0, kind: 'edit', text: 'z'.repeat(300) }],
  }

  test('every line fits from 20 to 160 columns', () => {
    for (let cols = 20; cols <= 160; cols++) {
      for (const line of layoutPane(LONG, cols)) expect(cells(line) <= cols).toBe(true)
      for (const line of layoutPane(WORLD, cols)) expect(cells(line) <= cols).toBe(true)
    }
  })

  test('CJK and emoji titles and labels fit every width in cells', () => {
    const wide: PaneInput = {
      ...FULL,
      expanded: 'w1',
      run: { ...RUN, title: '漢字のタイトル🚀🚀 長い説明文です', branch: 'feat/日本語' },
      loops: [...WORLD.loops, loop('w1', { label: '型を調べる 🔍👨‍👩‍👧 エージェント', task: '漢字'.repeat(80) })],
      shells: [shell('s', { label: '🚀 長いコマンド' })],
    }
    for (let cols = 1; cols <= 80; cols++)
      for (const line of layoutPane(wide, cols)) expect(width(line) <= cols).toBe(true)
  })
})
