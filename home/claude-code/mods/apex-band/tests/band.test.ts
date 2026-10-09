import { describe, expect, test } from 'claude-code/testing'

import {
  alertLine,
  baselineWord,
  cellWidth,
  clientProps,
  family,
  familyTone,
  hardCut,
  join,
  stepLabel,
  stepMark,
  truncate,
  width,
} from '../hooks/band.ts'
import type { Seg } from '../hooks/band.ts'
import type { ApexBandAlert } from '../types'

// The shared segment helpers of the pane and the agents block.

const BUDGET: ApexBandAlert = { kind: 'budget', rounds: 2, cap: 2 }
const FAILED: ApexBandAlert = { kind: 'step', step: '04-validate' }
const RED: ApexBandAlert = { kind: 'verify', verdict: 'FAIL', findings: 2 }

const textOf = (line: readonly Seg[] | undefined): string => (line ?? []).map(s => s.text).join('')

const LONG = '⚠ Budget de correction épuisé — tape « apex: +1 tour » ou livre avec les résiduels'
const SHORT = '⚠ Budget épuisé — « apex: +1 tour »'

describe('segments', () => {
  test('a live segment maps to its Client props, a static one to null', () => {
    const rail: Seg = { text: '───', live: { kind: 'rail', key: 'rail', cells: 3, drops: [1], active: true, tone: 'claude' } }
    expect(clientProps(rail)).toEqual({ cells: 3, drops: [1], active: true, tone: 'claude' })
    const clock: Seg = { text: '0:01', dim: true, live: { kind: 'clock', key: 'c', ms: 1000, running: true } }
    expect(clientProps(clock)).toEqual({ ms: 1000, running: true, tone: null, dim: true })
    expect(clientProps({ text: 'x' })).toBeNull()
  })

  test('a cut live segment loses its Client, keeps its text', () => {
    const seg: Seg = { text: '─'.repeat(10), live: { kind: 'rail', key: 'rail', cells: 10, drops: [], active: true, tone: 'claude' } }
    const cut = hardCut([seg], 5)
    expect(cut[0]?.live).toBeUndefined()
    expect(textOf(cut)).toBe('────…')
    expect(hardCut([seg], 10)[0]?.live).toBeDefined()
  })

  test('join: non-empty groups, a dim separator between', () => {
    const line = join([[{ text: 'a' }], [], [{ text: 'b' }]])
    expect(textOf(line)).toBe('a · b')
    expect(width(line)).toBe(5)
  })

  test('tones follow the model family', () => {
    expect(familyTone('opus')).toBe('claude')
    expect(familyTone('sonnet')).toBe('suggestion')
    expect(familyTone('haiku')).toBe('planMode')
    expect(familyTone('other')).toBe('text')
    expect(family('opus-5.5')).toBe('opus')
    expect(family('claude-haiku-4-5-20251001')).toBe('haiku')
    expect(family(undefined)).toBe('agent')
  })
})

describe('alerts', () => {
  test('meaning reads without colour: distinct glyphs and words', () => {
    expect(textOf(alertLine(FAILED, 80))).toBe('✗ Étape valid en échec')
    expect(textOf(alertLine(RED, 80))).toBe('✗ Vérif externe FAIL · 2 constats')
    expect(textOf(alertLine({ kind: 'verify', verdict: 'BLOCKED', findings: 1 }, 80))).toBe(
      '✗ Vérif externe BLOCKED · 1 constat',
    )
    expect(textOf(alertLine(FAILED, 80, 2))).toBe('✗ Étape valid en échec (+2)')
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

  test('a run of watches never exceeds cols, cells counted by a local table', () => {
    // Test-local widths, not cellWidth: ⌚ is 2 cells, every other glyph 1.
    const local = (text: string): number => Array.from(text).reduce((n, ch) => n + (ch === '⌚' ? 2 : 1), 0)
    const title = '⌚'.repeat(10)
    for (let cols = 1; cols <= 30; cols++) {
      expect(local(truncate(title, cols)) <= cols).toBe(true)
      expect(local(textOf(hardCut([{ text: title }], cols))) <= cols).toBe(true)
    }
  })

  test('a wide glyph that does not fit is dropped, never halved', () => {
    expect(truncate('漢字漢字', 4)).toBe('漢…')
    expect(truncate('漢字漢字', 8)).toBe('漢字漢字')
    expect(truncate('🚀🚀', 2)).toBe('…')
  })
})
