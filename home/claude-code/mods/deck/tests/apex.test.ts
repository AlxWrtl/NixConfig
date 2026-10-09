// Ported from apex-band (context.test, the phases and verdict cases of stats.test), plus what
// the block and the log show of a run.
import { describe, expect, test } from 'claude-code/testing'

import {
  STALE_MS,
  addPhase,
  apexHeader,
  countedTotal,
  headBranch,
  isLive,
  onBranch,
  parseContext,
  parseVerdict,
  phaseMark,
  phaseNote,
  settleRun,
  statusKind,
  syncPhases,
} from '../hooks/apex'
import type { Usage } from '../hooks/apex'
import type { DeckApexRun } from '../types'

const NOW = 10 * STALE_MS

const STANDARD = `# APEX: mods task-board + apex-band
Date: 2026-10-06
Mode: Standard (allégé) — hook HIGH signal
Flags: -t -pr -o -n (-X -E)
Branch: feat/claude-mods-task-board-apex-band
Baseline: nix flake check --no-build -> green (13 ✅)

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 01-analyze | complete (approuvé par l'utilisateur) | |
| 02-plan | in_progress | |
| 03-execute | pending | |
| 09-finish | pending | |
`

const TIERED = `# APEX: mod maison \`deck\`
Date: 2026-10-09
Tier: Standard (mods UI; no hook guard) — files under home/claude-code/mods/
Flags: -t -pr -o -n
Branch: feat/deck-mod (trunk: master)

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 03-execute | running | |
| 04-validate | pending | |
`

const FRENCH = `# APEX — garde de sécurité
**Mode:** **haut-enjeu** (garde de sécurité — un affaiblissement laisse passer un
  contournement)
Flags résolus: -t -x -pr -o -n
Branche: \`fix/guard\` (master 95f807e)
Baseline skipped: tree dirty

## Progress
| Step | Status | Notes |
|---|---|---|
| 00-init | ✅ | |
| 01-analyze | SUPPRIMÉ (fusionné) | |
| 02-plan | in progress | |
| 04-validate | red | |
| 05-review | à voir avec l'utilisateur | |
| 09-finish | pending | |
`

const NO_MODE = `# APEX: no mode line
Flags: -t -x -v -pr -o -n (mode haut-enjeu, -v ajouté)
Branch: feat/x

## Notes
free text
`

const USAGE: Usage = { input_tokens: 10, output_tokens: 20, cache_read_input_tokens: 300, cache_creation_input_tokens: 4 }

describe('parseContext', () => {
  test('standard header and Progress table: Mode read as the tier', () => {
    const run = parseContext(STANDARD, 'dir')
    expect(run.title).toBe('mods task-board + apex-band')
    expect(run.tier).toBe('Standard')
    expect(run.branch).toBe('feat/claude-mods-task-board-apex-band')
    expect(run.steps.length).toBe(5)
    expect(run.steps[1]?.kind).toBe('done')
    expect(run.currentStep).toBe('02-plan')
  })

  test('Tier wins over Mode, cut to its head', () => {
    const run = parseContext(TIERED, 'dir')
    expect(run.tier).toBe('Standard')
    expect(run.branch).toBe('feat/deck-mod')
    expect(run.currentStep).toBe('03-execute')
    expect(parseContext('# APEX: x\nTier: High-stakes (new hook)\nMode: Fast\n', 'd').tier).toBe('High-stakes')
  })

  test('Branche, Flags résolus, bold wrapped Mode', () => {
    const run = parseContext(FRENCH, 'dir')
    expect(run.title).toBe('garde de sécurité')
    expect(run.tier).toBe('haut-enjeu')
    expect(run.branch).toBe('fix/guard')
    expect(run.steps.map(s => s.kind)).toEqual(['done', 'skipped', 'running', 'failed', 'other', 'pending'])
    expect(run.currentStep).toBe('02-plan')
  })

  test('no Mode: taken from the Flags parenthetical; no Progress table', () => {
    const run = parseContext(NO_MODE, 'dir')
    expect(run.tier).toBe('haut-enjeu')
    expect(run.steps.length).toBe(0)
    expect(run.currentStep).toBeUndefined()
  })

  test('CRLF line endings', () => {
    const run = parseContext(STANDARD.replace(/\n/g, '\r\n'), 'dir')
    expect(run.branch).toBe('feat/claude-mods-task-board-apex-band')
    expect(run.steps.length).toBe(5)
    expect(run.currentStep).toBe('02-plan')
  })

  test('no heading: the directory name is the title', () => {
    expect(parseContext('Mode: Fast\n', 'my-run').title).toBe('my-run')
    expect(parseContext('# Some plain title\n', 'my-run').title).toBe('Some plain title')
  })
})

describe('statusKind', () => {
  test('every measured spelling', () => {
    expect(statusKind('complete')).toBe('done')
    expect(statusKind('complete (approuvé)')).toBe('done')
    expect(statusKind('**done**')).toBe('done')
    expect(statusKind('pending')).toBe('pending')
    expect(statusKind('in progress')).toBe('running')
    expect(statusKind('in_progress')).toBe('running')
    expect(statusKind('en cours')).toBe('running')
    expect(statusKind('skipped (Léger)')).toBe('skipped')
    expect(statusKind('SUPPRIMÉ')).toBe('skipped')
    expect(statusKind('n/a')).toBe('skipped')
    expect(statusKind('red')).toBe('failed')
    expect(statusKind('échoué')).toBe('failed')
    expect(statusKind('reduced scope')).toBe('other')
    expect(statusKind('free text')).toBe('other')
  })
})

describe('isLive', () => {
  test('a fresh run with a pending row is live; a stale one is not', () => {
    expect(isLive(parseContext(STANDARD, 'd'), NOW - 1000, NOW)).toBe(true)
    expect(isLive(parseContext(STANDARD, 'd'), NOW - STALE_MS, NOW)).toBe(false)
  })

  test('a finished run is not live', () => {
    const done = STANDARD.replace(/\| (in_progress|pending) \|/g, '| complete |')
    expect(isLive(parseContext(done, 'd'), NOW, NOW)).toBe(false)
    const finishedOnly = STANDARD.replace('| 09-finish | pending |', '| 09-finish | complete |')
    expect(isLive(parseContext(finishedOnly, 'd'), NOW, NOW)).toBe(false)
    const skippedFinish = STANDARD.replace('| 09-finish | pending |', '| 09-finish | skipped (Fast) |')
    expect(isLive(parseContext(skippedFinish, 'd'), NOW, NOW)).toBe(false)
  })

  test('no Progress table: live on freshness alone', () => {
    expect(isLive(parseContext(NO_MODE, 'd'), NOW - 1000, NOW)).toBe(true)
    expect(isLive(parseContext(NO_MODE, 'd'), NOW - STALE_MS - 1, NOW)).toBe(false)
  })
})

describe('branch', () => {
  const run = parseContext(STANDARD, 'd')

  test('a symbolic ref names the branch; a detached sha or garbage none', () => {
    expect(headBranch('ref: refs/heads/fix/apex-band-hide\n')).toBe('fix/apex-band-hide')
    expect(headBranch('ref: refs/heads/feat/x\r\n')).toBe('feat/x')
    expect(headBranch('5328846a1b2c3d4e5f60718293a4b5c6d7e8f901\n')).toBeUndefined()
    expect(headBranch('gitdir: ../.git/worktrees/x\n')).toBeUndefined()
    expect(headBranch('')).toBeUndefined()
  })

  test('same branch is on, another is off; unknown either side is on', () => {
    expect(onBranch(run, 'feat/claude-mods-task-board-apex-band')).toBe(true)
    expect(onBranch(run, 'master')).toBe(false)
    expect(onBranch(parseContext('# APEX: x\n', 'd'), 'master')).toBe(true)
    expect(onBranch(run, undefined)).toBe(true)
  })
})

describe('phases', () => {
  test('usage goes to the current step and resets on a new run dir', () => {
    let phases = addPhase({ dir: null, byStep: {} }, 'run-a', '03-execute', USAGE)
    phases = addPhase(phases, 'run-a', '03-execute', USAGE)
    expect(phases.byStep['03-execute']?.output).toBe(40)
    expect(countedTotal(phases.byStep['03-execute'] ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 })).toBe(68)
    expect(addPhase(phases, 'run-a', undefined, USAGE)).toBe(phases)
    const fresh = addPhase(phases, 'run-b', '01-analyze', USAGE)
    expect(fresh.dir).toBe('run-b')
    expect(fresh.byStep['03-execute']).toBeUndefined()
    expect(fresh.byStep['01-analyze']?.input).toBe(10)
  })

  test('run A, then B, then A again: A starts over, never restored', () => {
    const a = addPhase({ dir: null, byStep: {} }, 'run-a', '03-execute', USAGE)
    expect(syncPhases(a, 'run-a')).toBe(a)
    const b = syncPhases(a, 'run-b')
    expect(b).toEqual({ dir: 'run-b', byStep: {} })
    expect(syncPhases(b, 'run-a')).toEqual({ dir: 'run-a', byStep: {} })
    expect(syncPhases(a, null)).toEqual({ dir: null, byStep: {} })
  })
})

describe('parseVerdict', () => {
  test('reads the verdict and counts findings; rejects anything else', () => {
    expect(parseVerdict('{"verdict":"FAIL","findings":[{},{}]}')).toEqual({ verdict: 'FAIL', findings: 2 })
    expect(parseVerdict('{"verdict":"PASS","findings":[]}')).toEqual({ verdict: 'PASS', findings: 0 })
    expect(parseVerdict('{"verdict":"MAYBE"}')).toBeNull()
    expect(parseVerdict('# not json')).toBeNull()
    expect(parseVerdict('null')).toBeNull()
  })
})

describe('what the block and the log show', () => {
  const run = parseContext(FRENCH, 'd')

  test('one dot per state: done ●, current ◐, pending ○, failed ✗, skipped ·', () => {
    expect(run.steps.map(s => phaseMark(s, run.currentStep))).toEqual(['done', 'skipped', 'current', 'failed', 'pending', 'pending'])
    // The polled current step is current even while its row still reads pending.
    const pendingRun = parseContext(STANDARD.replace('| 02-plan | in_progress |', '| 02-plan | complete |'), 'd')
    expect(pendingRun.currentStep).toBe('03-execute')
    expect(pendingRun.steps.map(s => phaseMark(s, pendingRun.currentStep))).toEqual(['done', 'done', 'done', 'current', 'pending'])
  })

  test('the header names the branch (else the title) and the tier', () => {
    expect(apexHeader(parseContext(TIERED, 'd'))).toBe('APEX · feat/deck-mod · Standard')
    expect(apexHeader({ title: 'no branch run', steps: [] })).toBe('APEX · no branch run')
  })

  test('a log line when a run appears, its step moves or it ends; none otherwise', () => {
    const a: DeckApexRun = { title: 't', branch: 'feat/x', steps: [], currentStep: '03-execute', dir: 'r1' }
    expect(phaseNote(null, null)).toBeNull()
    expect(phaseNote(null, a)).toBe('feat/x · 03-execute')
    expect(phaseNote(a, { ...a })).toBeNull()
    expect(phaseNote(a, { ...a, currentStep: '04-validate' })).toBe('03-execute → 04-validate')
    expect(phaseNote(a, { ...a, dir: 'r2' })).toBe('feat/x · 03-execute')
    expect(phaseNote(a, null)).toBe('run ended')
  })
})

describe('settleRun', () => {
  const a: DeckApexRun = { title: 't', steps: [], currentStep: '03-execute', dir: 'r1' }

  test('a run found is kept as found, the miss count reset', () => {
    expect(settleRun(null, a, 0)).toEqual({ run: a, misses: 0 })
    expect(settleRun(a, a, 1)).toEqual({ run: a, misses: 0 })
  })

  test('one miss keeps the run shown; the second in a row ends it', () => {
    const once = settleRun(a, null, 0)
    expect(once).toEqual({ run: a, misses: 1 })
    expect(phaseNote(a, once.run)).toBeNull()
    const twice = settleRun(once.run, null, once.misses)
    expect(twice).toEqual({ run: null, misses: 0 })
    expect(phaseNote(a, twice.run)).toBe('run ended')
    expect(settleRun(null, null, 5)).toEqual({ run: null, misses: 0 })
  })
})
