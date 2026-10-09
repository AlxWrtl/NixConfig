// Pure reading of what asks the user to act (a failed step, a red external
// verification, a spent correction budget).
// No `$`, no clock, no I/O: the hooks module lists and reads, this decides.

import type { DeckApexAlert, DeckApexBudget, DeckApexRun, DeckApexVerdict } from '../types'

// Rounds every run gets before the user must grant one more
// (hooks/correction-budget.js MAX_ROUNDS).
export const MAX_ROUNDS = 2

const ROUND = /^(.+)\.round([1-9][0-9]*)$/
const GRANT = /^(.+)\.grant([1-9][0-9]*)$/

// The correction budget of run `dir`, from the names of the budget folder:
// one `<dir>.round<n>` file per round used, one `<dir>.grant<n>` per round
// the user granted. Another run's files (even a longer name sharing the
// prefix) are not counted; null when the run has none.
export function budgetOf(names: readonly string[], dir: string): DeckApexBudget | null {
  let rounds = 0
  let grants = 0
  for (const name of names) {
    if (ROUND.exec(name)?.[1] === dir) rounds += 1
    else if (GRANT.exec(name)?.[1] === dir) grants += 1
  }
  return rounds === 0 && grants === 0 ? null : { dir, rounds, grants }
}

export const budgetCap = (b: DeckApexBudget): number => MAX_ROUNDS + b.grants

// True once every round the run may take is used.
export function isBudgetSpent(b: DeckApexBudget | null): boolean {
  return b !== null && b.rounds >= budgetCap(b)
}

// The newer of two candidates by mtime (the verify file has two names:
// <run>/04-external-verify.json and <run>/external-verify.json); on a tie
// the first.
export function pickVerdict<T extends { mtimeMs: number }>(a: T | null, b: T | null): T | null {
  if (a === null) return b
  if (b === null) return a
  return b.mtimeMs > a.mtimeMs ? b : a
}

type RedVerdict = 'FAIL' | 'BLOCKED' | 'ERROR'

function redVerdict(word: string): RedVerdict | undefined {
  if (word === 'FAIL' || word === 'BLOCKED' || word === 'ERROR') return word
  return undefined
}

// What the user must act on for `run`, most urgent first: each failed step,
// then a red external verification, then a spent correction budget. A
// verdict or budget of another run directory is ignored; no run, no alert.
export function alertsOf(
  run: DeckApexRun | null,
  verdict: DeckApexVerdict | null,
  budget: DeckApexBudget | null,
): DeckApexAlert[] {
  if (run === null) return []
  const alerts: DeckApexAlert[] = run.steps.filter(s => s.kind === 'failed').map((s): DeckApexAlert => ({ kind: 'step', step: s.step }))
  const red = verdict !== null && verdict.dir === run.dir ? redVerdict(verdict.verdict) : undefined
  if (red !== undefined && verdict !== null) alerts.push({ kind: 'verify', verdict: red, findings: verdict.findings })
  if (budget !== null && budget.dir === run.dir && isBudgetSpent(budget)) {
    alerts.push({ kind: 'budget', rounds: budget.rounds, cap: budgetCap(budget) })
  }
  return alerts
}
