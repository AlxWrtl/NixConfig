import { describe, expect, test } from 'claude-code/testing'

import {
  PALETTE,
  bar,
  basename,
  cellWidth,
  compactWindow,
  contextFill,
  fmtPace,
  fmtReset,
  fmtTokens,
  gaugeSvg,
  layout,
  modelName,
  pace,
  paceColor,
  parentDir,
  parseHead,
  pickModel,
  pillSvg,
  resolveGitdir,
  thousands,
} from '../hooks/format.ts'
import type { StatusData } from '../hooks/format.ts'

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR
const NOW = Date.parse('2026-10-09T12:00:00Z')
const at = (ms: number) => new Date(NOW + ms).toISOString()

describe('modelName', () => {
  test('ids, aliases and display names', () => {
    expect(modelName('claude-opus-5-5[1m]')).toBe('Opus 5.5')
    expect(modelName('claude-opus-5-5')).toBe('Opus 5.5')
    expect(modelName('claude-haiku-4-5-20251001')).toBe('Haiku 4.5')
    expect(modelName('claude-3-5-sonnet-20241022')).toBe('Sonnet 3.5')
    expect(modelName('opus[1m]')).toBe('Opus')
    expect(modelName('Opus 5.5 (1M context)')).toBe('Opus 5.5')
    expect(modelName('')).toBe('')
  })

  test('a bare alias takes the version of the same family only', () => {
    expect(pickModel('opus[1m]', 'claude-opus-5-5')).toBe('Opus 5.5')
    expect(pickModel('opus', 'claude-sonnet-4-5')).toBe('Opus')
    expect(pickModel('claude-opus-5-5[1m]', 'claude-sonnet-4-5')).toBe('Opus 5.5')
    expect(pickModel('', 'claude-opus-5-5')).toBe('Opus 5.5')
    expect(pickModel('opus', undefined)).toBe('Opus')
  })
})

describe('compactWindow / contextFill', () => {
  test('the window follows the variable as the engine reads it', () => {
    expect(compactWindow(1_000_000, undefined)).toBe(1_000_000)
    expect(compactWindow(1_000_000, '400000')).toBe(400_000)
    expect(compactWindow(1_000_000, '500k')).toBe(100_000)
    expect(compactWindow(1_000_000, '2000000')).toBe(1_000_000)
    expect(compactWindow(200_000, '400000')).toBe(200_000)
    expect(compactWindow(1_000_000, 'abc')).toBe(1_000_000)
  })

  test('the fill is measured against that window', () => {
    expect(contextFill({ tokens: 120_000, window: 1_000_000, percent: 12 }, '400000')).toEqual({
      window: 400_000,
      pct: 30,
    })
    expect(contextFill({ tokens: 500_000, window: 1_000_000 }, '400000').pct).toBe(100)
    expect(contextFill({ window: 1_000_000, percent: 12 }, '400000').pct).toBe(12)
    expect(contextFill({ window: 0 }, undefined).pct).toBe(null)
    expect(contextFill({ window: 0, percent: 7 }, undefined).pct).toBe(7)
  })
})

describe('fmtReset', () => {
  test('minutes, hours with minute digits, days', () => {
    expect(fmtReset(NOW + 42 * MIN, NOW)).toBe('42min')
    expect(fmtReset(NOW + 59 * MIN + 59_000, NOW)).toBe('59min')
    expect(fmtReset(NOW + 60 * MIN, NOW)).toBe('1.00h')
    expect(fmtReset(NOW + 5 * HOUR + 7 * MIN, NOW)).toBe('5.07h')
    expect(fmtReset(NOW + 120 * HOUR + 52 * MIN, NOW)).toBe('5j 0h')
    expect(fmtReset(NOW + 25 * HOUR, NOW)).toBe('1j 1h')
    expect(fmtReset(NOW - MIN, NOW)).toBe('0min')
  })
})

describe('pace', () => {
  // Thousandths: the figures go through float division.
  const near = (value: number | null) => (value === null ? null : Math.round(value * 1000) / 1000)

  test('elapsed share of the window less the share used', () => {
    // 5h window, 42 min left: 258/300 = 86% elapsed, 61.5% used.
    expect(near(pace({ kind: 'five_hour', percentUsed: 61.5, resetsAt: at(42 * MIN) }, NOW))).toBe(24.5)
    // 7d window, 6 days left: 1/7 elapsed, 80% used.
    expect(near(pace({ kind: 'seven_day', percentUsed: 80, resetsAt: at(6 * DAY) }, NOW))).toBe(-65.714)
    // 5h window, 2.5h left: 50% elapsed, 55% used.
    expect(near(pace({ kind: 'five_hour', percentUsed: 55, resetsAt: at(150 * MIN) }, NOW))).toBe(-5)
  })

  test('no reset time or an unknown window: no pace', () => {
    expect(pace({ kind: 'five_hour', percentUsed: 61.5, resetsAt: null }, NOW)).toBeNull()
    expect(pace({ kind: 'seven_day_opus', percentUsed: 10, resetsAt: at(DAY) }, NOW)).toBeNull()
  })
})

describe('paceColor', () => {
  test('green from 0, yellow above -10, red from -10 down', () => {
    expect(paceColor(24.5)).toBe('#5fd75f')
    expect(paceColor(0)).toBe(PALETTE.green)
    expect(paceColor(-0.1)).toBe(PALETTE.yellow)
    expect(paceColor(-5)).toBe('#ffd75f')
    expect(paceColor(-9.9)).toBe(PALETTE.yellow)
    expect(paceColor(-10)).toBe(PALETTE.red)
    expect(paceColor(100 / 7 - 80)).toBe('#ff5f5f')
  })
})

describe('fmtPace', () => {
  test('sign, one decimal, percent', () => {
    expect(fmtPace(24.5)).toBe('+24.5%')
    expect(fmtPace(-5)).toBe('-5.0%')
    expect(fmtPace(100 / 7 - 80)).toBe('-65.7%')
    expect(fmtPace(3)).toBe('+3.0%')
  })
})

describe('fmtTokens', () => {
  test('thousands as k, rounded; small counts as they are', () => {
    expect(fmtTokens(84_000)).toBe('84k')
    expect(fmtTokens(200_000)).toBe('200k')
    expect(fmtTokens(1_000)).toBe('1k')
    expect(fmtTokens(1_499)).toBe('1k')
    expect(fmtTokens(1_500)).toBe('2k')
    expect(fmtTokens(999)).toBe('999')
    expect(fmtTokens(0)).toBe('0')
  })
})

describe('gaugeSvg / pillSvg', () => {
  const isSvg = (markup: string) => {
    expect(markup.startsWith('<svg')).toBe(true)
    expect(markup.trimEnd().endsWith('</svg>')).toBe(true)
    expect(markup.length).toBeLessThanOrEqual(131_072)
  }

  test('a gauge is one SVG document that moves with the percentage', () => {
    isSvg(gaugeSvg(62))
    isSvg(gaugeSvg(0))
    isSvg(gaugeSvg(100))
    expect(gaugeSvg(10)).not.toBe(gaugeSvg(90))
  })

  test('a pill is one SVG document carrying its label', () => {
    const markup = pillSvg(42, '84k/200k')
    isSvg(markup)
    expect(markup).toContain('84k/200k')
    expect(pillSvg(10, '84k/200k')).not.toBe(pillSvg(90, '84k/200k'))
  })
})

describe('bar', () => {
  const filled = (pct: number) => bar(pct)[0]
  test('thresholds 59/60/84/85', () => {
    expect(filled(59)?.color).toBe(PALETTE.green)
    expect(filled(60)?.color).toBe(PALETTE.orange)
    expect(filled(84)?.color).toBe(PALETTE.orange)
    expect(filled(85)?.color).toBe(PALETTE.red)
  })
  test('ten cells, filled by whole tens, clamped', () => {
    expect(bar(59).map(s => s.text).join('')).toBe('█████░░░░░')
    expect(bar(0)).toEqual([{ text: '░░░░░░░░░░', color: PALETTE.grey }])
    expect(bar(150)).toEqual([{ text: '██████████', color: PALETTE.red }])
    expect(bar(-5).map(s => s.text).join('')).toBe('░░░░░░░░░░')
  })
})

describe('thousands', () => {
  test('en_US grouping', () => {
    expect(thousands(0)).toBe('0')
    expect(thousands(999)).toBe('999')
    expect(thousands(1000)).toBe('1,000')
    expect(thousands(1234567)).toBe('1,234,567')
    expect(thousands(-12345)).toBe('-12,345')
  })
})

describe('git HEAD', () => {
  test('branch, detached, garbage', () => {
    expect(parseHead('ref: refs/heads/feat/status-bar-mod\n')).toBe('feat/status-bar-mod')
    expect(parseHead('ref: refs/heads/master')).toBe('master')
    expect(parseHead('0123456789abcdef0123456789abcdef01234567\n')).toBeUndefined()
    expect(parseHead('')).toBeUndefined()
  })
  test('worktree gitdir, absolute and relative', () => {
    expect(resolveGitdir('gitdir: /repo/.git/worktrees/x\n', '/wt')).toBe('/repo/.git/worktrees/x')
    expect(resolveGitdir('gitdir: ../repo/.git/worktrees/x', '/wt')).toBe('/wt/../repo/.git/worktrees/x')
    expect(resolveGitdir('nothing', '/wt')).toBeUndefined()
  })
  test('paths', () => {
    expect(parentDir('/a/b')).toBe('/a')
    expect(parentDir('/a')).toBe('/')
    expect(parentDir('/')).toBe('/')
    expect(basename('/Users/alx/.config/nix-darwin/')).toBe('nix-darwin')
    expect(basename('/')).toBe('/')
  })
})

describe('layout', () => {
  const data: StatusData = {
    model: 'Opus 5.5',
    cwd: '/Users/alx/.config/nix-darwin',
    branch: 'feat/status-bar-mod',
    tokensIn: 123456,
    tokensOut: 789,
    contextPercent: 42,
    limits: [
      { kind: 'five_hour', percentUsed: 61.5, resetsAt: new Date(NOW + 5 * HOUR + 7 * MIN).toISOString() },
      { kind: 'seven_day', percentUsed: 85, resetsAt: new Date(NOW + 120 * HOUR + 52 * MIN).toISOString() },
    ],
    now: NOW,
  }
  const text = (line: readonly { text: string }[] | undefined) => (line ?? []).map(s => s.text).join('')

  test('one line when wide, its content as the script drew it', () => {
    const lines = layout(data, 200)
    expect(lines).toHaveLength(1)
    const one = text(lines[0])
    expect(one.startsWith('🤖 Opus 5.5 | 📁 nix-darwin | ⎇ feat/status-bar-mod | 📊 123,456/789 | 🧠 ')).toBe(true)
    expect(one.includes(' 42% | ⏳ ')).toBe(true)
    expect(one).toMatch(/ 62% [+-]\d+\.\d% · 5\.07h \| 📆 /)
    expect(one.endsWith(' 85% -56.9% · 5j 0h')).toBe(true)
  })

  test('a quota window draws its percentage, its pace, then its reset', () => {
    const segsAfter = (limit: StatusData['limits'][number], pct: string) => {
      const line = layout({ ...data, limits: [limit] }, 200)[0] ?? []
      const i = line.findIndex(s => s.text === pct)
      expect(i).toBeGreaterThan(-1)
      expect(line[i]?.color).toBe(PALETTE.cyan)
      return line.slice(i + 1)
    }
    const ahead = segsAfter({ kind: 'five_hour', percentUsed: 61.5, resetsAt: at(42 * MIN) }, ' 62%')
    expect(ahead).toEqual([
      { text: ' +24.5%', color: '#5fd75f' },
      { text: ' · 42min', color: PALETTE.cyan },
    ])
    const behind = segsAfter({ kind: 'seven_day', percentUsed: 80, resetsAt: at(6 * DAY) }, ' 80%')
    expect(behind).toEqual([
      { text: ' -65.7%', color: '#ff5f5f' },
      { text: ' · 6j 0h', color: PALETTE.cyan },
    ])
    const close = segsAfter({ kind: 'five_hour', percentUsed: 55, resetsAt: at(150 * MIN) }, ' 55%')
    expect(close[0]).toEqual({ text: ' -5.0%', color: '#ffd75f' })
    expect(segsAfter({ kind: 'five_hour', percentUsed: 61.5, resetsAt: null }, ' 62%')).toEqual([])
  })

  test('two groups when narrow, or one line when the width is unknown', () => {
    const lines = layout(data, 80)
    expect(lines).toHaveLength(2)
    expect(text(lines[0]).endsWith('📊 123,456/789')).toBe(true)
    expect(text(lines[1]).startsWith('🧠 ')).toBe(true)
    expect(layout(data, undefined)).toHaveLength(1)
  })

  test('no branch, no quota windows', () => {
    const one = text(layout({ ...data, branch: null, limits: [] }, 200)[0])
    expect(one.includes('⎇')).toBe(false)
    expect(one.includes('⏳')).toBe(false)
    expect(one.endsWith(' 42%')).toBe(true)
  })

  test('emoji count two cells', () => {
    expect(cellWidth('🤖 a')).toBe(4)
    expect(cellWidth('⏳')).toBe(2)
    expect(cellWidth('⎇█░')).toBe(3)
  })
})
