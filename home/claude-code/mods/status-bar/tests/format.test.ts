import { describe, expect, test } from 'claude-code/testing'

import {
  PALETTE,
  bar,
  basename,
  cellWidth,
  fmtReset,
  layout,
  modelName,
  parentDir,
  parseHead,
  pickModel,
  resolveGitdir,
  thousands,
} from '../hooks/format.ts'
import type { StatusData } from '../hooks/format.ts'

const MIN = 60_000
const HOUR = 60 * MIN
const NOW = Date.parse('2026-10-09T12:00:00Z')

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
    expect(one.includes(' 62% · 5.07h | 📆 ')).toBe(true)
    expect(one.endsWith(' 85% · 5j 0h')).toBe(true)
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
