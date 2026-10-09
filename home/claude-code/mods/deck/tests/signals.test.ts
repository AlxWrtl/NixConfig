import { describe, expect, test } from 'claude-code/testing'

import type { DeckApexRun, DeckApexStep, DeckApexStepKind, DeckApexVerdict } from '../types'
import { alertsOf, budgetOf, isBudgetSpent, pickVerdict } from '../hooks/signals'

const step = (name: string, kind: DeckApexStepKind): DeckApexStep => ({ step: name, status: kind, kind })

const RUN: DeckApexRun = { title: 't', steps: [step('03-execute', 'running')], dir: '42-x' }

const verdict = (word: string, dir = '42-x'): DeckApexVerdict => ({ dir, verdict: word, findings: 3, mtimeMs: 1 })

describe('correction budget', () => {
  test('budget spent: two rounds and no grant', () => {
    const b = budgetOf(['42-x.round1', '42-x.round2'], '42-x')
    expect(b).toEqual({ dir: '42-x', rounds: 2, grants: 0 })
    expect(isBudgetSpent(b)).toBe(true)
  })

  test('budget not spent: one round used, or none at all', () => {
    expect(isBudgetSpent(budgetOf(['42-x.round1'], '42-x'))).toBe(false)
    expect(budgetOf([], '42-x')).toBeNull()
    expect(isBudgetSpent(null)).toBe(false)
  })

  test('a granted round lifts the cap by one', () => {
    const granted = budgetOf(['42-x.round1', '42-x.round2', '42-x.grant1'], '42-x')
    expect(isBudgetSpent(granted)).toBe(false)
    expect(isBudgetSpent(budgetOf(['42-x.round1', '42-x.round2', '42-x.round3', '42-x.grant1'], '42-x'))).toBe(true)
  })

  test('another run\'s files are not counted ("42-x" is not "42-xy")', () => {
    const names = ['42-xy.round1', '42-xy.round2', 'x.round1', '42-x.round0', '42-x.roundA', '42-x.round1']
    expect(budgetOf(names, '42-x')).toEqual({ dir: '42-x', rounds: 1, grants: 0 })
    expect(budgetOf(['42-xy.round1', '42-xy.round2'], '42-x')).toBeNull()
  })
})

describe('external verify', () => {
  test('both verify names: the newer file wins, a tie keeps the first', () => {
    const numbered = { name: '04-external-verify.json', mtimeMs: 10 }
    const bare = { name: 'external-verify.json', mtimeMs: 20 }
    expect(pickVerdict(numbered, bare)).toBe(bare)
    expect(pickVerdict(bare, numbered)).toBe(bare)
    expect(pickVerdict(numbered, null)).toBe(numbered)
    expect(pickVerdict(null, bare)).toBe(bare)
    expect(pickVerdict(null, null)).toBeNull()
    const same = { name: 'external-verify.json', mtimeMs: 10 }
    expect(pickVerdict(numbered, same)).toBe(numbered)
  })
})

describe('alertsOf', () => {
  test('no run, no alert; a calm run, no alert', () => {
    expect(alertsOf(null, verdict('FAIL'), { dir: '42-x', rounds: 2, grants: 0 })).toEqual([])
    expect(alertsOf(RUN, verdict('PASS'), { dir: '42-x', rounds: 1, grants: 0 })).toEqual([])
  })

  test('priority: failed step, then red verify, then spent budget', () => {
    const run: DeckApexRun = { ...RUN, steps: [step('04-validate', 'failed'), step('05-examine', 'failed')] }
    expect(alertsOf(run, verdict('BLOCKED'), { dir: '42-x', rounds: 2, grants: 0 })).toEqual([
      { kind: 'step', step: '04-validate' },
      { kind: 'step', step: '05-examine' },
      { kind: 'verify', verdict: 'BLOCKED', findings: 3 },
      { kind: 'budget', rounds: 2, cap: 2 },
    ])
  })

  test('FAIL, BLOCKED and ERROR alert; PASS and an unknown word do not', () => {
    expect(alertsOf(RUN, verdict('FAIL'), null)).toEqual([{ kind: 'verify', verdict: 'FAIL', findings: 3 }])
    expect(alertsOf(RUN, verdict('ERROR'), null)).toEqual([{ kind: 'verify', verdict: 'ERROR', findings: 3 }])
    expect(alertsOf(RUN, verdict('MAYBE'), null)).toEqual([])
  })

  test("another run's verdict or budget is ignored", () => {
    expect(alertsOf(RUN, verdict('FAIL', 'other'), { dir: 'other', rounds: 9, grants: 0 })).toEqual([])
  })
})
