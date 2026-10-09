// Pure reading of what asks the user to act (a failed step, a red external
// verification, a spent correction budget) and of the run's five phases.
// No `$`, no clock, no I/O: the hooks module lists and reads, this decides.

import type { ApexBandAlert, ApexBandBudget, ApexBandRun, ApexBandStep, ApexBandVerdict } from '../types'

// Rounds every run gets before the user must grant one more
// (hooks/correction-budget.js MAX_ROUNDS).
export const MAX_ROUNDS = 2

const ROUND = /^(.+)\.round([1-9][0-9]*)$/
const GRANT = /^(.+)\.grant([1-9][0-9]*)$/

// The correction budget of run `dir`, from the names of the budget folder:
// one `<dir>.round<n>` file per round used, one `<dir>.grant<n>` per round
// the user granted. Another run's files (even a longer name sharing the
// prefix) are not counted; null when the run has none.
export function budgetOf(names: readonly string[], dir: string): ApexBandBudget | null {
  let rounds = 0
  let grants = 0
  for (const name of names) {
    if (ROUND.exec(name)?.[1] === dir) rounds += 1
    else if (GRANT.exec(name)?.[1] === dir) grants += 1
  }
  return rounds === 0 && grants === 0 ? null : { dir, rounds, grants }
}

export const budgetCap = (b: ApexBandBudget): number => MAX_ROUNDS + b.grants

// True once every round the run may take is used.
export function isBudgetSpent(b: ApexBandBudget | null): boolean {
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
  run: ApexBandRun | null,
  verdict: ApexBandVerdict | null,
  budget: ApexBandBudget | null,
): ApexBandAlert[] {
  if (run === null) return []
  const alerts: ApexBandAlert[] = run.steps.filter(s => s.kind === 'failed').map((s): ApexBandAlert => ({ kind: 'step', step: s.step }))
  const red = verdict !== null && verdict.dir === run.dir ? redVerdict(verdict.verdict) : undefined
  if (red !== undefined && verdict !== null) alerts.push({ kind: 'verify', verdict: red, findings: verdict.findings })
  if (budget !== null && budget.dir === run.dir && isBudgetSpent(budget)) {
    alerts.push({ kind: 'budget', rounds: budget.rounds, cap: budgetCap(budget) })
  }
  return alerts
}

export type PhaseKey = 'init' | 'analyze' | 'plan' | 'exec' | 'valid'

export type PhaseState = 'done' | 'running' | 'failed' | 'pending'

export type PhaseBucket = { key: PhaseKey; label: string; state: PhaseState; isCurrent: boolean }

const PHASES: ReadonlyArray<{ key: PhaseKey; label: string }> = [
  { key: 'init', label: 'init' },
  { key: 'analyze', label: 'analyse' },
  { key: 'plan', label: 'plan' },
  { key: 'exec', label: 'exécution' },
  { key: 'valid', label: 'validation' },
]

// The phase of a step name by its two-digit prefix: 00 init, 01 analyze
// (01b-obsidian too), 02 plan, 03 exec, 04 to 08 valid (07/08-tests too);
// an unnumbered step (external-verify) is a check, so valid; 09-finish and
// every other number belong to no phase.
export function phaseOf(step: string): PhaseKey | undefined {
  const digits = /^(\d{2})/.exec(step)?.[1]
  if (digits === undefined) return 'valid'
  const n = Number(digits)
  if (n === 0) return 'init'
  if (n === 1) return 'analyze'
  if (n === 2) return 'plan'
  if (n === 3) return 'exec'
  if (n >= 4 && n <= 8) return 'valid'
  return undefined
}

// A bucket's state from its steps: one running wins, else one failed, else
// all done or skipped; otherwise it waits.
function stateOf(steps: readonly ApexBandStep[]): PhaseState {
  if (steps.some(s => s.kind === 'running')) return 'running'
  if (steps.some(s => s.kind === 'failed')) return 'failed'
  if (steps.every(s => s.kind === 'done' || s.kind === 'skipped')) return 'done'
  return 'pending'
}

// The five phases of a run's steps, in order, each with its state; the
// current one is the first running, else the first failed, else the first
// waiting, else the last with steps. A phase with no step reads as done
// before the current one, waiting after it.
export function phaseBuckets(steps: readonly ApexBandStep[]): PhaseBucket[] {
  const grouped = PHASES.map(p => steps.filter(s => phaseOf(s.step) === p.key))
  const states = grouped.map(g => (g.length === 0 ? undefined : stateOf(g)))
  const first = (want: PhaseState): number => states.findIndex(s => s === want)
  let current = first('running')
  if (current < 0) current = first('failed')
  if (current < 0) current = first('pending')
  if (current < 0) current = states.reduce<number>((last, s, i) => (s === undefined ? last : i), -1)
  return PHASES.map((p, i) => {
    const own = states[i]
    const state: PhaseState = own ?? (current >= 0 && i < current ? 'done' : 'pending')
    return { key: p.key, label: p.label, state, isCurrent: i === current }
  })
}
