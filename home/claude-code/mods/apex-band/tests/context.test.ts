import { describe, expect, test } from 'claude-code/testing'

import { STALE_MS, isLive, parseContext, statusKind } from '../hooks/context.ts'

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

describe('parseContext', () => {
  test('standard header and Progress table', () => {
    const run = parseContext(STANDARD, 'dir')
    expect(run.title).toBe('mods task-board + apex-band')
    expect(run.mode).toBe('Standard')
    expect(run.branch).toBe('feat/claude-mods-task-board-apex-band')
    expect(run.baseline).toBe('nix flake check --no-build -> green (13 ✅)')
    expect(run.steps.length).toBe(5)
    expect(run.steps[1]?.kind).toBe('done')
    expect(run.currentStep).toBe('02-plan')
  })

  test('Branche, Flags résolus, bold wrapped Mode, Baseline skipped', () => {
    const run = parseContext(FRENCH, 'dir')
    expect(run.title).toBe('garde de sécurité')
    expect(run.mode).toBe('haut-enjeu')
    expect(run.branch).toBe('fix/guard')
    expect(run.baseline?.startsWith('skipped')).toBe(true)
    expect(run.steps.map(s => s.kind)).toEqual(['done', 'skipped', 'running', 'failed', 'other', 'pending'])
    expect(run.currentStep).toBe('02-plan')
  })

  test('no Mode: taken from the Flags parenthetical; no Progress table', () => {
    const run = parseContext(NO_MODE, 'dir')
    expect(run.mode).toBe('haut-enjeu')
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
    expect(statusKind('skipped (Fast)')).toBe('skipped')
    expect(statusKind('SUPPRIMÉ')).toBe('skipped')
    expect(statusKind('n/a')).toBe('skipped')
    expect(statusKind('red')).toBe('failed')
    expect(statusKind('échoué')).toBe('failed')
    expect(statusKind('reduced scope')).toBe('other')
    expect(statusKind('free text')).toBe('other')
  })
})

describe('isLive', () => {
  test('a fresh run with a pending row is live', () => {
    expect(isLive(parseContext(STANDARD, 'd'), NOW - 1000, NOW)).toBe(true)
  })

  test('a stale run is not live', () => {
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
