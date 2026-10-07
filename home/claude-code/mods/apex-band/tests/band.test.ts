import { describe, expect, test } from 'claude-code/testing'

import { baselineWord, cellWidth, layoutBand, stepLabel, stepMark, truncate, width } from '../hooks/band.ts'
import type { Seg } from '../hooks/band.ts'
import type { Run, Step, StepKind } from '../hooks/context.ts'

const RUN: Run = {
  title: 'mods task-board + apex-band',
  mode: 'Standard',
  branch: 'feat/claude-mods',
  baseline: 'nix flake check -> green',
  steps: [],
  currentStep: '03-execute',
}

const step = (name: string, kind: StepKind): Step => ({ step: name, status: kind, kind })

const STEPS: Step[] = [
  step('00-init', 'done'),
  step('01-analyze', 'done'),
  step('02-plan', 'done'),
  step('03-execute', 'running'),
  step('04-validate', 'pending'),
  step('05-examine', 'skipped'),
  step('09-finish', 'pending'),
]

const LIVE: Run = { ...RUN, steps: STEPS }

// The text a line shows, its segments joined.
const textOf = (line: readonly Seg[] | undefined): string => (line ?? []).map(s => s.text).join('')

// The segment showing exactly `text` on a line.
const segOf = (line: readonly Seg[] | undefined, text: string): Seg | undefined =>
  (line ?? []).find(s => s.text === text)

describe('baselineWord', () => {
  test('green, red, skipped, raw', () => {
    expect(baselineWord('nix flake check --no-build -> green (13 ✅)')).toBe('vert')
    expect(baselineWord('red: 2 failed')).toBe('rouge')
    expect(baselineWord('skipped — tree dirty')).toBe('ignorée')
    expect(baselineWord('a very long baseline text that says nothing useful')).toBe('a very long baseline text tha…')
  })
})

describe('stepLabel', () => {
  test('prefix stripped, execute and validate shortened', () => {
    expect(stepLabel('00-init')).toBe('init')
    expect(stepLabel('03-execute')).toBe('exec')
    expect(stepLabel('04-validate')).toBe('valid')
    expect(stepLabel('02b-plan')).toBe('plan')
    expect(stepLabel('09-finish')).toBe('finish')
    expect(stepLabel('custom')).toBe('custom')
  })
})

describe('stepMark', () => {
  test('one glyph and tone per kind', () => {
    expect(stepMark('done')).toEqual({ text: '✓', tone: 'success' })
    expect(stepMark('running')).toEqual({ text: '●', tone: 'warning' })
    expect(stepMark('failed')).toEqual({ text: '✗', tone: 'error' })
    expect(stepMark('pending')).toEqual({ text: '○', dim: true })
    expect(stepMark('skipped')).toEqual({ text: '–', dim: true })
    expect(stepMark('other')).toEqual({ text: '·', dim: true })
  })
})

describe('layoutBand', () => {
  test('one line when it fits', () => {
    const lines = layoutBand(RUN, 200, 3)
    expect(lines.length).toBe(1)
    expect(textOf(lines[0])).toBe('APEX · mods task-board + apex-band · Standard · feat/claude-mods · baseline vert')
    expect(lines[0]?.[0]).toEqual({ text: 'APEX · mods task-board + apex-band', dim: true })
  })

  test('the step bar follows the head on line 1', () => {
    const lines = layoutBand(LIVE, 300, 3)
    expect(lines.length).toBe(1)
    expect(textOf(lines[0])).toBe(
      'APEX · mods task-board + apex-band · ✓ init › ✓ analyze › ✓ plan › ● exec › ○ valid › – examine › ○ finish' +
        ' · Standard · feat/claude-mods · baseline vert',
    )
  })

  test('chip styles: running bold, failed plain, others dim; separators dim', () => {
    const run: Run = {
      title: 't',
      steps: [step('00-init', 'done'), step('03-execute', 'running'), step('04-validate', 'failed'), step('x', 'other')],
    }
    const line = layoutBand(run, 200, 1)[0]
    expect(segOf(line, ' exec')).toEqual({ text: ' exec', bold: true })
    expect(segOf(line, ' valid')).toEqual({ text: ' valid' })
    expect(segOf(line, ' init')).toEqual({ text: ' init', dim: true })
    expect(segOf(line, ' x')).toEqual({ text: ' x', dim: true })
    expect(segOf(line, ' › ')).toEqual({ text: ' › ', dim: true })
    expect(segOf(line, '●')?.tone).toBe('warning')
    expect(segOf(line, '✗')?.tone).toBe('error')
  })

  test('baseline word toned: vert success, rouge error, ignorée and raw dim', () => {
    const word = (baseline: string): Seg | undefined => layoutBand({ title: 't', steps: [], baseline }, 200, 1)[0]?.at(-1)
    expect(word('green')).toEqual({ text: 'vert', tone: 'success' })
    expect(word('red')).toEqual({ text: 'rouge', tone: 'error' })
    expect(word('skipped')).toEqual({ text: 'ignorée', dim: true })
    expect(word('whatever')).toEqual({ text: 'whatever', dim: true })
  })

  test('two lines when narrow, each within the width', () => {
    const lines = layoutBand(RUN, 40, 3)
    expect(lines.length).toBe(2)
    for (const line of lines) expect(textOf(line).length <= 40).toBe(true)
    expect(textOf(lines[0]).startsWith('APEX · ')).toBe(true)
  })

  test('one truncated line when only one row is free', () => {
    const lines = layoutBand(RUN, 20, 1)
    expect(lines.length).toBe(1)
    expect(textOf(lines[0]).length).toBe(20)
    expect(textOf(lines[0]).endsWith('…')).toBe(true)
  })

  test('single row: meta dropped (branch, mode, baseline) before the bar degrades', () => {
    const run: Run = { ...LIVE, title: 't' }
    const full = textOf(layoutBand(run, 300, 1)[0])
    const barText = 'APEX · t · ✓ init › ✓ analyze › ✓ plan › ● exec › ○ valid › – examine › ○ finish'
    expect(textOf(layoutBand(run, full.length - 1, 1)[0])).toBe(`${barText} · Standard · baseline vert`)
    expect(textOf(layoutBand(run, barText.length + 16, 1)[0])).toBe(`${barText} · baseline vert`)
    expect(textOf(layoutBand(run, barText.length + 5, 1)[0])).toBe(barText)
  })

  test('meta on line 2: branch dropped before mode, mode before the cut', () => {
    const run: Run = { ...RUN, title: 't' }
    const two = (cols: number): string => textOf(layoutBand(run, cols, 2)[1])
    expect(two(43)).toBe('Standard · feat/claude-mods · baseline vert')
    expect(two(42)).toBe('Standard · baseline vert')
    expect(two(23)).toBe('baseline vert')
    expect(two(10)).toBe('baseline …')
  })

  test('bar degradation, one step at a time', () => {
    const run: Run = { title: 'a long run title', steps: STEPS }
    const at = (cols: number): string => textOf(layoutBand(run, cols, 1)[0])
    const d0 = 'APEX · a long run title · ✓ init › ✓ analyze › ✓ plan › ● exec › ○ valid › – examine › ○ finish'
    const d1 = 'APEX · a long run title · ✓ › ✓ › ✓ › ● exec › ○ valid › – examine › ○ finish'
    const d2 = 'APEX · a long run title · ✓ › ✓ › ✓ › ● exec › ○ › – › ○'
    const d3 = 'APEX · a long run title · ✓ ✓ ✓ ● exec ○ – ○'
    expect(at(d0.length)).toBe(d0)
    expect(at(d0.length - 1)).toBe(d1)
    expect(at(d1.length - 1)).toBe(d2)
    expect(at(d2.length - 1)).toBe(d3)
    // D4: title truncated, never under 8 cells.
    expect(at(d3.length - 1)).toBe('APEX · a long run tit… · ✓ ✓ ✓ ● exec ○ – ○')
    const d4min = 'APEX · a long … · ✓ ✓ ✓ ● exec ○ – ○'
    expect(at(d4min.length)).toBe(d4min)
    // D5: running chip and its position only.
    expect(at(d4min.length - 1)).toBe('APEX · a long run tit… · ● exec 4/7')
    const d5min = 'APEX · a long … · ● exec 4/7'
    expect(at(d5min.length)).toBe(d5min)
    // D6: hard cut.
    expect(at(d5min.length - 1)).toBe('APEX · a long … · ● exec 4…')
    expect(at(1)).toBe('…')
  })

  test('compact bar falls back to the last failed chip', () => {
    const failed: Run = { title: 't', steps: [step('a', 'failed'), step('b', 'done'), step('c', 'failed'), step('d', 'skipped')] }
    expect(textOf(layoutBand(failed, 18, 1)[0])).toBe('APEX · t · ✗ c 3/4')
  })

  test('compact bar without running/failed: next pending chip and its position', () => {
    const steps = [step('a', 'done'), step('b', 'done'), step('c', 'done'), step('d', 'pending'), step('e', 'pending'), step('f', 'pending')]
    const line = layoutBand({ title: 't', steps }, 18, 1)[0]
    expect(textOf(line)).toBe('APEX · t · ○ d 4/6')
    expect(segOf(line, '○')).toEqual({ text: '○', dim: true })
    expect(segOf(line, ' 4/6')).toEqual({ text: ' 4/6', dim: true })
  })

  test('compact bar with nothing pending: ✓ and n/n', () => {
    const steps = [step('a', 'done'), step('b', 'skipped'), step('c', 'other'), step('d', 'done'), step('e', 'skipped'), step('f', 'other')]
    const line = layoutBand({ title: 't', steps }, 16, 1)[0]
    expect(textOf(line)).toBe('APEX · t · ✓ 6/6')
    expect(segOf(line, '✓')).toEqual({ text: '✓', tone: 'success' })
  })

  test('few steps: the compact bar is skipped when wider, the spaced bar cut last', () => {
    const run: Run = { title: 'a long run title', steps: [step('00-init', 'done'), step('03-execute', 'running')] }
    const at = (cols: number): string => textOf(layoutBand(run, cols, 1)[0])
    const fit = 'APEX · a long … · ✓ ● exec'
    expect(at(fit.length)).toBe(fit)
    for (let cols = 1; cols < fit.length; cols++) {
      const text = at(cols)
      expect(text.length <= cols).toBe(true)
      expect(text.includes('2/2')).toBe(false)
      expect(text).toBe(cols === 1 ? '…' : `${fit.slice(0, cols - 1)}…`)
    }
  })

  test('exact fit: one line at the whole width, two lines one cell under', () => {
    for (const run of [RUN, LIVE]) {
      const w = textOf(layoutBand(run, 400, 2)[0]).length
      expect(layoutBand(run, w, 2).length).toBe(1)
      expect(layoutBand(run, w - 1, 2).length).toBe(2)
    }
  })

  test('emoji title: no surrogate split, code-point width within cols', () => {
    const lone = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/
    const runs: Run[] = [
      { title: '🚀 fix ✅ emoji 😀 long title', steps: [] },
      { title: '🚀 fix ✅ emoji 😀 long title', steps: STEPS, mode: 'Standard', baseline: 'green' },
    ]
    for (const run of runs)
      for (let cols = 1; cols <= 60; cols++)
        for (let maxRows = 1; maxRows <= 2; maxRows++)
          for (const line of layoutBand(run, cols, maxRows)) {
            const text = textOf(line)
            expect(lone.test(text)).toBe(false)
            for (const seg of line) expect(lone.test(seg.text)).toBe(false)
            expect(Array.from(text).length <= cols).toBe(true)
          }
  })

  test('every line fits: cols 1..120 × maxRows 1..3', () => {
    const runs: Run[] = [RUN, LIVE, { title: 't', steps: [] }, { ...LIVE, title: 'x'.repeat(90) }]
    for (const run of runs)
      for (let cols = 1; cols <= 120; cols++)
        for (let maxRows = 1; maxRows <= 3; maxRows++) {
          const lines = layoutBand(run, cols, maxRows)
          expect(lines.length >= 1 && lines.length <= Math.max(1, Math.min(2, maxRows))).toBe(true)
          for (const line of lines) expect(textOf(line).length <= Math.max(1, cols)).toBe(true)
        }
    expect(textOf(layoutBand(RUN, 0, 0)[0]).length).toBe(1)
  })

  test('missing fields are left out', () => {
    expect(layoutBand({ title: 't', steps: [] }, 80, 2)).toEqual([[{ text: 'APEX · t', dim: true }]])
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
  })

  test('BMP default-emoji symbols are wide, independently known widths', () => {
    expect(cellWidth(0x231a)).toBe(2)
    expect(cellWidth(0x2705)).toBe(2)
    expect(cellWidth(0x2b50)).toBe(2)
    expect(cellWidth(0x26a1)).toBe(2)
    expect(cellWidth(0x1f004)).toBe(2)
    expect(cellWidth(0x1f191)).toBe(2)
    expect(cellWidth(0x1f201)).toBe(2)
    expect(cellWidth(0x2713)).toBe(1)
  })

  test('the band\'s own glyphs stay one cell', () => {
    for (const cp of [0x2713, 0x2717, 0x25cf, 0x25cb, 0x25a0, 0x2013, 0x203a, 0xb7, 0x2588, 0x2591, 0x2026])
      expect(cellWidth(cp)).toBe(1)
  })

  test('a title of watches never exceeds cols, cells counted by a local table', () => {
    // Test-local widths, not cellWidth: ⌚ is 2 cells, every other glyph the
    // band draws here (ASCII, its marks and separators) is 1.
    const local = (line: readonly Seg[]): number =>
      Array.from(textOf(line)).reduce((n, ch) => n + (ch === '⌚' ? 2 : 1), 0)
    const run: Run = { ...LIVE, title: '⌚⌚⌚⌚⌚⌚⌚⌚⌚⌚' }
    for (const maxRows of [1, 2])
      for (let cols = 1; cols <= 40; cols++)
        for (const line of layoutBand(run, cols, maxRows)) expect(local(line) <= cols).toBe(true)
  })

  test('a wide glyph that does not fit is dropped, never halved', () => {
    expect(truncate('漢字漢字', 4)).toBe('漢…')
    expect(truncate('漢字漢字', 8)).toBe('漢字漢字')
    expect(truncate('🚀🚀', 2)).toBe('…')
  })

  test('CJK and emoji titles fit every width in cells', () => {
    const titles = ['漢字のタイトル 長い説明文です', '🚀🔍 emoji run 👨‍👩‍👧 family', 'ｆｕｌｌ ｗｉｄｔｈ 한국어']
    for (const title of titles)
      for (const maxRows of [1, 2])
        for (let cols = 1; cols <= 80; cols++)
          for (const line of layoutBand({ ...LIVE, title, branch: 'feat/日本語' }, cols, maxRows))
            expect(width(line) <= cols).toBe(true)
  })
})
