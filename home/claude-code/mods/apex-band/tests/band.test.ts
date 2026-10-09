import { describe, expect, test } from 'claude-code/testing'

import {
  alertLine,
  baselineWord,
  cellWidth,
  elapsed,
  family,
  isBusy,
  layoutBand,
  phaseDot,
  stepLabel,
  stepMark,
  truncate,
  width,
} from '../hooks/band.ts'
import type { BandInput, Seg } from '../hooks/band.ts'
import type { ApexBandAlert, ApexBandLoop, ApexBandRun, ApexBandShell, ApexBandStep, ApexBandStepKind } from '../types'

const step = (name: string, kind: ApexBandStepKind): ApexBandStep => ({ step: name, status: kind, kind })

const RUN: ApexBandRun = {
  title: 'calm apex band',
  dir: 'calm-apex-band',
  steps: [
    step('00-init', 'done'),
    step('01-analyze', 'done'),
    step('02-plan', 'done'),
    step('03-execute', 'running'),
    step('04-validate', 'pending'),
    step('09-finish', 'pending'),
  ],
}

const loop = (id: string, model: string | undefined, status: ApexBandLoop['status'], at: number): ApexBandLoop => ({
  id,
  status,
  steps: 1,
  calls: 0,
  tally: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  startedAt: at,
  durationMs: 0,
  // A subagent fixture is one the agent list named (main never is).
  ...(id === 'main' ? {} : { listed: true }),
  ...(model === undefined ? {} : { model }),
  ...(status === 'running' ? { since: at } : { endedAt: at + 1 }),
})

const shell = (id: string, status: ApexBandShell['status']): ApexBandShell => ({
  id,
  label: id,
  startedAt: 0,
  status,
  ...(status === 'running' ? {} : { endedAt: 1 }),
})

// 3 opus and 2 haiku at work, one running shell; 7 subagents and 2 shells done.
const LOOPS: ApexBandLoop[] = [
  loop('main', 'opus-5.5', 'running', 0),
  loop('o1', 'opus-5.5', 'running', 1),
  loop('h1', 'haiku-4.5', 'running', 2),
  loop('o2', 'opus-5.5', 'running', 3),
  loop('h2', 'haiku-4.5', 'running', 4),
  loop('o3', 'opus-5.5', 'running', 5),
  ...Array.from({ length: 7 }, (_, i) => loop(`d${i}`, 'sonnet-5', 'done', 10 + i)),
]
const SHELLS: ApexBandShell[] = [shell('s1', 'running'), shell('s2', 'completed'), shell('s3', 'killed')]

const BUDGET: ApexBandAlert = { kind: 'budget', rounds: 2, cap: 2 }
const FAILED: ApexBandAlert = { kind: 'step', step: '04-validate' }
const RED: ApexBandAlert = { kind: 'verify', verdict: 'FAIL', findings: 2 }

const IDLE: BandInput = {
  run: RUN,
  loops: [loop('main', 'opus-5.5', 'done', 0)],
  shells: [],
  now: 12 * 60_000,
  cost: 1.234,
  frame: 0,
  alerts: [],
  seenAt: 0,
}

const BUSY: BandInput = { ...IDLE, loops: LOOPS, shells: SHELLS, alerts: [BUDGET] }

const textOf = (line: readonly Seg[] | undefined): string => (line ?? []).map(s => s.text).join('')
const texts = (lines: readonly (readonly Seg[])[]): string[] => lines.map(textOf)

const L1 = 'APEX · calm apex band  ●●●◐○  exécution · 12m · $1.23'
const L2 = '◐ opus ×3  ◓ haiku ×2  ⧗ shell ×1  ✓ 9 terminés'
const LONG = '⚠ Budget de correction épuisé — tape « apex: +1 tour » ou livre avec les résiduels'
const SHORT = '⚠ Budget épuisé — « apex: +1 tour »'

describe('layoutBand: what is drawn', () => {
  test('no run and nothing running draws nothing', () => {
    expect(layoutBand({ ...IDLE, run: null }, 80, 3)).toEqual([])
    // An alert without a run is not drawn either.
    expect(layoutBand({ ...IDLE, run: null, alerts: [BUDGET] }, 80, 3)).toEqual([])
  })

  test('no run, a subagent or a shell running: the activity row only', () => {
    expect(texts(layoutBand({ ...BUSY, run: null }, 120, 3))).toEqual([L2])
    const shellOnly = { ...IDLE, run: null, shells: [shell('s1', 'running')] }
    expect(texts(layoutBand(shellOnly, 80, 3))).toEqual(['⧗ shell ×1'])
  })

  test('a teammate stays listed as running but never counts as at work', () => {
    const mate: ApexBandLoop = { ...loop('t1', 'opus-5.5', 'running', 1), type: 'teammate' }
    const withMate = { ...IDLE, loops: [...IDLE.loops, mate] }
    expect(isBusy(withMate.loops, [])).toBe(false)
    expect(texts(layoutBand(withMate, 80, 3))).toEqual([L1])
    expect(layoutBand({ ...withMate, run: null }, 80, 3)).toEqual([])
    // Beside a working subagent, only that one is grouped.
    const both = { ...withMate, loops: [...withMate.loops, loop('o1', 'haiku-4.5', 'running', 2)] }
    expect(texts(layoutBand(both, 80, 3))).toEqual([L1, '◐ haiku ×1'])
  })

  test('a fork loop (steps under an id no agent list named) is never grouped', () => {
    const { listed: _listed, ...fork } = loop('f1', 'opus-5.5', 'running', 1)
    const withFork = { ...IDLE, loops: [...IDLE.loops, fork] }
    expect(isBusy(withFork.loops, [])).toBe(false)
    expect(texts(layoutBand(withFork, 80, 3))).toEqual([L1])
    const both = { ...withFork, loops: [...withFork.loops, loop('o1', 'haiku-4.5', 'running', 2)] }
    expect(texts(layoutBand(both, 80, 3))).toEqual([L1, '◐ haiku ×1'])
  })

  test('a listed subagent the agent list reads idle is not grouped', () => {
    const idle: ApexBandLoop = { ...loop('i1', 'opus-5.5', 'running', 1), idle: true }
    expect(isBusy([...IDLE.loops, idle], [])).toBe(false)
    expect(texts(layoutBand({ ...IDLE, loops: [...IDLE.loops, idle] }, 80, 3))).toEqual([L1])
  })

  test('an idle live run: L1 only', () => {
    const lines = layoutBand(IDLE, 120, 3)
    expect(texts(lines)).toEqual([L1])
    expect(lines[0]?.[0]).toEqual({ text: 'APEX · calm apex band', dim: true })
    expect(lines[0]?.find(s => s.text === 'exécution')?.bold).toBe(true)
  })

  test('a live run, work in flight and a budget alert: three rows at 120', () => {
    expect(texts(layoutBand(BUSY, 120, 3))).toEqual([L1, L2, LONG])
  })

  test('a run without steps, seen time or cost is its head alone', () => {
    const bare: BandInput = { ...IDLE, run: { title: 't', steps: [] }, seenAt: null, cost: null }
    expect(layoutBand(bare, 80, 3)).toEqual([[{ text: 'APEX · t', dim: true }]])
  })

  test('phase dots: buckets by prefix, a failed phase named in red', () => {
    const run: ApexBandRun = {
      title: 't',
      steps: [step('00-init', 'done'), step('01-analyze', 'done'), step('02-plan', 'failed'), step('03-execute', 'pending')],
    }
    const line = layoutBand({ ...IDLE, run, seenAt: null, cost: null }, 80, 1)[0]
    expect(textOf(line)).toBe('APEX · t  ●●✗○○  plan')
    expect(line?.find(s => s.text === 'plan')?.tone).toBe('error')
  })
})

describe('layoutBand: rows by priority', () => {
  test('maxRows 1 with an alert: L1 prefixed ⚠', () => {
    const lines = layoutBand(BUSY, 120, 1)
    expect(texts(lines)).toEqual([`⚠ ${L1}`])
    expect(lines[0]?.[0]).toEqual({ text: '⚠ ', tone: 'warning' })
  })

  test('maxRows 1 without an alert: L1 as is', () => {
    expect(texts(layoutBand({ ...BUSY, alerts: [] }, 120, 1))).toEqual([L1])
  })

  test('maxRows 2: the alert wins over the activity row', () => {
    expect(texts(layoutBand(BUSY, 120, 2))).toEqual([L1, LONG])
    expect(texts(layoutBand({ ...BUSY, alerts: [] }, 120, 2))).toEqual([L1, L2])
  })

  test('maxRows 3 (or more): L1, L2, L3 in that order', () => {
    expect(texts(layoutBand(BUSY, 120, 3))).toEqual([L1, L2, LONG])
    expect(texts(layoutBand(BUSY, 120, 9))).toEqual([L1, L2, LONG])
  })

  test('the first alert by priority, the others counted', () => {
    const lines = texts(layoutBand({ ...BUSY, alerts: [FAILED, RED, BUDGET] }, 120, 3))
    expect(lines[2]).toBe('✗ Étape valid en échec (+2)')
  })
})

describe('layoutBand: fitting', () => {
  for (const cols of [40, 80, 120]) {
    test(`widths ${cols}: every line within the columns`, () => {
      for (const input of [IDLE, BUSY, { ...BUSY, run: { ...RUN, title: 'x'.repeat(200) } }, { ...BUSY, run: null }])
        for (let maxRows = 1; maxRows <= 3; maxRows++)
          for (const line of layoutBand(input, cols, maxRows)) expect(width(line) <= cols).toBe(true)
    })
  }

  test('the title shrinks to 8 cells first, then elapsed, cost and the phase word go', () => {
    const long = { ...IDLE, run: { ...RUN, title: 'x'.repeat(60) } }
    // 60 columns: the title is cut, the tail kept whole.
    expect(textOf(layoutBand(long, 60, 1)[0])).toBe(`APEX · ${'x'.repeat(20)}…  ●●●◐○  exécution · 12m · $1.23`)
    // 40 columns: elapsed and cost dropped before the title goes under 8.
    expect(textOf(layoutBand(long, 40, 1)[0])).toBe(`APEX · ${'x'.repeat(14)}…  ●●●◐○  exécution`)
    // 28 columns: the phase word goes too.
    expect(textOf(layoutBand(long, 28, 1)[0])).toBe(`APEX · ${'x'.repeat(13)}…  ●●●◐○`)
    // Narrower: a hard cut.
    const cut = textOf(layoutBand(long, 12, 1)[0])
    expect(cut.endsWith('…')).toBe(true)
    expect(Array.from(cut).length).toBe(12)
  })

  test('the activity row drops « terminés », then tightens, then cuts', () => {
    const busy = { ...BUSY, run: null }
    expect(texts(layoutBand(busy, 47, 3))).toEqual([L2])
    expect(texts(layoutBand(busy, 46, 3))).toEqual(['◐ opus ×3  ◓ haiku ×2  ⧗ shell ×1'])
    expect(texts(layoutBand(busy, 30, 3))).toEqual(['◐ opus×3 ◓ haiku×2 ⧗ shell×1'])
    const cut = texts(layoutBand(busy, 15, 3))[0] ?? ''
    expect(cut.endsWith('…')).toBe(true)
    expect(Array.from(cut).length <= 15).toBe(true)
  })

  test('budget: the long wording when it fits, else the short one', () => {
    expect(textOf(alertLine(BUDGET, 120))).toBe(LONG)
    expect(textOf(alertLine(BUDGET, 82))).toBe(LONG)
    expect(textOf(alertLine(BUDGET, 81))).toBe(SHORT)
    expect(textOf(alertLine(BUDGET, 80))).toBe(SHORT)
    const cut = textOf(alertLine(BUDGET, 20))
    expect(cut.startsWith('⚠ Budget')).toBe(true)
    expect(Array.from(cut).length).toBe(20)
  })

  test('every line fits: cols 1..120 × maxRows 0..3', () => {
    const lone = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/
    const titles = ['t', 'x'.repeat(90), '🚀 fix ✅ emoji 😀 long title', '漢字のタイトル 長い説明文です']
    for (const title of titles)
      for (const input of [IDLE, BUSY, { ...BUSY, alerts: [RED, FAILED] }])
        for (let cols = 1; cols <= 120; cols++)
          for (let maxRows = 0; maxRows <= 3; maxRows++) {
            const lines = layoutBand({ ...input, run: { ...RUN, title } }, cols, maxRows)
            expect(lines.length >= 1 && lines.length <= Math.max(1, Math.min(3, maxRows))).toBe(true)
            for (const line of lines) {
              expect(width(line) <= cols).toBe(true)
              for (const seg of line) expect(lone.test(seg.text)).toBe(false)
            }
          }
  })
})

describe('layoutBand: calm and readable', () => {
  test('the spinner frame changes only the glyphs', () => {
    const strip = (s: string): string => s.replace(/[◐◓◑◒]/g, '*')
    const a = texts(layoutBand(BUSY, 120, 3))
    const b = texts(layoutBand({ ...BUSY, frame: 1 }, 120, 3))
    expect(a).not.toEqual(b)
    expect(a.map(strip)).toEqual(b.map(strip))
    expect(b[1]?.startsWith('◓ opus ×3  ◑ haiku ×2')).toBe(true)
    // L1's running phase dot does not spin.
    expect(a[0]).toBe(b[0])
  })

  test('spinner tones follow the model family; a shell is inactive', () => {
    const l2 = layoutBand({ ...BUSY, run: null }, 120, 3)[0] ?? []
    expect(l2[0]).toEqual({ text: '◐', tone: 'claude' })
    expect(l2.find(s => s.text === '◓')?.tone).toBe('planMode')
    expect(l2.find(s => s.text === '⧗')?.tone).toBe('inactive')
    expect(family('opus-5.5')).toBe('opus')
    expect(family('claude-haiku-4-5-20251001')).toBe('haiku')
    expect(family(undefined)).toBe('agent')
  })

  test('meaning reads without colour: distinct glyphs and words', () => {
    const dots = (['done', 'running', 'failed', 'pending'] as const).map(s => phaseDot(s).text)
    expect(new Set(dots).size).toBe(4)
    expect(textOf(alertLine(FAILED, 80))).toBe('✗ Étape valid en échec')
    expect(textOf(alertLine(RED, 80))).toBe('✗ Vérif externe FAIL · 2 constats')
    expect(textOf(alertLine({ kind: 'verify', verdict: 'BLOCKED', findings: 1 }, 80))).toBe(
      '✗ Vérif externe BLOCKED · 1 constat',
    )
  })

  test('elapsed in minutes, then hours', () => {
    expect(elapsed(-5)).toBe('0m')
    expect(elapsed(59_999)).toBe('0m')
    expect(elapsed(12 * 60_000)).toBe('12m')
    expect(elapsed(65 * 60_000)).toBe('1h05')
  })
})

describe('kept helpers', () => {
  test('baselineWord: green, red, skipped, raw', () => {
    expect(baselineWord('nix flake check --no-build -> green (13 ✅)')).toBe('vert')
    expect(baselineWord('red: 2 failed')).toBe('rouge')
    expect(baselineWord('skipped — tree dirty')).toBe('ignorée')
    expect(baselineWord('a very long baseline text that says nothing useful')).toBe('a very long baseline text tha…')
  })

  test('stepLabel: prefix stripped, execute and validate shortened', () => {
    expect(stepLabel('00-init')).toBe('init')
    expect(stepLabel('03-execute')).toBe('exec')
    expect(stepLabel('04-validate')).toBe('valid')
    expect(stepLabel('02b-plan')).toBe('plan')
    expect(stepLabel('custom')).toBe('custom')
  })

  test('stepMark: one glyph and tone per kind', () => {
    expect(stepMark('done')).toEqual({ text: '✓', tone: 'success' })
    expect(stepMark('running')).toEqual({ text: '●', tone: 'warning' })
    expect(stepMark('failed')).toEqual({ text: '✗', tone: 'error' })
    expect(stepMark('pending')).toEqual({ text: '○', dim: true })
    expect(stepMark('skipped')).toEqual({ text: '–', dim: true })
    expect(stepMark('other')).toEqual({ text: '·', dim: true })
  })
})

describe('cell widths', () => {
  test('wide, zero-width and narrow code points', () => {
    expect(cellWidth('漢'.codePointAt(0) ?? 0)).toBe(2)
    expect(cellWidth('🚀'.codePointAt(0) ?? 0)).toBe(2)
    expect(cellWidth(0x200d)).toBe(0)
    expect(cellWidth(0xfe0f)).toBe(0)
    expect(cellWidth(0x301)).toBe(0)
    expect(cellWidth('a'.codePointAt(0) ?? 0)).toBe(1)
    expect(cellWidth(0x231a)).toBe(2)
    expect(cellWidth(0x2705)).toBe(2)
  })

  test("the band's own glyphs stay one cell", () => {
    for (const glyph of ['✓', '✗', '●', '○', '◐', '◓', '◑', '◒', '⧗', '⚠', '■', '–', '›', '·', '…', '×', '«', '»'])
      expect(cellWidth(glyph.codePointAt(0) ?? 0)).toBe(1)
  })

  test('a title of watches never exceeds cols, cells counted by a local table', () => {
    // Test-local widths, not cellWidth: ⌚ is 2 cells, every other glyph the
    // band draws here is 1.
    const local = (line: readonly Seg[]): number =>
      Array.from(textOf(line)).reduce((n, ch) => n + (ch === '⌚' ? 2 : 1), 0)
    const input = { ...BUSY, run: { ...RUN, title: '⌚⌚⌚⌚⌚⌚⌚⌚⌚⌚' } }
    for (const maxRows of [1, 2, 3])
      for (let cols = 1; cols <= 60; cols++)
        for (const line of layoutBand(input, cols, maxRows)) expect(local(line) <= cols).toBe(true)
  })

  test('a wide glyph that does not fit is dropped, never halved', () => {
    expect(truncate('漢字漢字', 4)).toBe('漢…')
    expect(truncate('漢字漢字', 8)).toBe('漢字漢字')
    expect(truncate('🚀🚀', 2)).toBe('…')
  })
})
