// Ported from apex-band (context.test, the phases and verdict cases of stats.test), plus what
// the block and the log show of a run.
import { describe, expect, test } from 'claude-code/testing'

import {
  BARE_STALE_MS,
  STALE_MS,
  apexHeader,
  bareShown,
  callSwitch,
  classifyAgent,
  classifyCall,
  answerLines,
  endAgent,
  explainStep,
  gateEvidence,
  isMergeCall,
  modelFamily,
  pathTail,
  reviewLines,
  runEndedAt,
  shipEvidence,
  parseCodex,
  parseReview,
  seeStep,
  startSteps,
  stepCells,
  stepDetail,
  headBranch,
  isLive,
  newestStep,
  onBranch,
  parseContext,
  parseVerdict,
  phaseMark,
  phaseNote,
  runFromFiles,
  runSwitch,
  sessionKey,
  sessionRunOf,
  settleRun,
  statusKind,
} from '../hooks/apex'
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

describe('live steps', () => {
  const K = 'session:1'
  const call = (tool: string, input: { file_path?: string; notebook_path?: string; command?: string }, inSubagent = false) =>
    classifyCall(tool, input, inSubagent)

  test('AC4: writes under .claude/output/apex are plan, any other edit is edit', () => {
    expect(call('Write', { file_path: '/repo/.claude/output/apex/run/02-plan.md' })).toBe('plan')
    expect(call('Edit', { file_path: '.claude/output/apex/run/00-context.md' })).toBe('plan')
    expect(call('Edit', { file_path: '/repo/src/a.ts' })).toBe('edit')
    expect(call('Write', { file_path: '/repo/src/b.ts' })).toBe('edit')
    expect(call('NotebookEdit', { notebook_path: '/repo/n.ipynb' })).toBe('edit')
    expect(call('Read', { file_path: '/repo/src/a.ts' })).toBeNull()
  })

  test('gate, Codex and ship from the main loop Bash; AC6: never from a subagent', () => {
    for (const c of ['nix flake check', 'pnpm test', 'pnpm typecheck && pnpm lint', 'claude plugin validate --strict x', 'npx tsc -p .', 'cargo test'])
      expect(call('Bash', { command: c })).toBe('gate')
    expect(call('Bash', { command: 'scripts/apex-verify-external run-x' })).toBe('Codex')
    for (const c of ['git commit -m x', 'git push -u origin f', 'gh pr create -F b', 'gh pr merge 3 --squash'])
      expect(call('Bash', { command: c })).toBe('ship')
    expect(call('Bash', { command: 'ls -la' })).toBeNull()
    expect(call('Bash', { command: 'tscx' })).toBeNull()
    for (const c of ['pnpm test', 'apex-verify-external', 'git commit -m x']) expect(call('Bash', { command: c }, true)).toBeNull()
    expect(call('Edit', { file_path: '/repo/src/a.ts' }, true)).toBe('edit')
  })

  test('agents: implementers, test-runner, reviewers; others none', () => {
    for (const t of ['frontend-expert', 'backend-expert', 'nix-expert', 'debugger', 'quick-fix', 'plugin:nix-expert']) expect(classifyAgent(t)).toBe('implement')
    expect(classifyAgent('test-runner')).toBe('tests')
    expect(classifyAgent('code-reviewer')).toBe('review')
    expect(classifyAgent('security-auditor')).toBe('review')
    expect(classifyAgent('Explore')).toBeNull()
  })

  test('AC3/AC2 verdicts: Codex output and the reviewer answer, first match', () => {
    expect(parseCodex('…\nEXTERNAL-VERIFY PASS run=x findings=0\n')).toEqual({ verdict: 'PASS', findings: 0 })
    expect(parseCodex('EXTERNAL-VERIFY FAIL model=gpt findings=2')).toEqual({ verdict: 'FAIL', findings: 2 })
    expect(parseCodex('nothing here')).toBeNull()
    expect(parseReview('Verdict: NEEDS_FIXES, not APPROVED')).toBe('NEEDS_FIXES')
    expect(parseReview('## APPROVED')).toBe('APPROVED')
    expect(parseReview('fine')).toBeNull()
    expect(modelFamily('claude-opus-5-5[1m]')).toBe('Opus')
    expect(modelFamily('haiku')).toBe('Haiku')
  })

  test('AC1: edit then gate reads ● edit ◐ gate ○ ship', () => {
    let s = startSteps(K)
    expect(stepCells(s).map(c => `${c.mark} ${c.label}`)).toEqual(['pending edit', 'pending gate', 'pending ship'])
    s = seeStep(s, K, 'edit', 10)
    s = seeStep(s, K, 'gate', 20)
    expect(stepCells(s).map(c => `${c.mark} ${c.label}`)).toEqual(['done edit', 'current gate', 'pending ship'])
    // Optional steps appear once seen, in the fixed order.
    s = seeStep(s, K, 'Codex', 30, { verdict: 'FAIL', findings: 2 })
    s = seeStep(s, K, 'plan', 40)
    const cells = stepCells(s)
    expect(cells.map(c => c.label)).toEqual(['plan', 'edit', 'gate', 'Codex FAIL 2', 'ship'])
    expect(cells.find(c => c.name === 'Codex')?.isWarn).toBe(true)
    expect(cells.find(c => c.name === 'plan')?.mark).toBe('current')
  })

  test('AC2: a running agent step stays current with its detail; its end sets the verdict', () => {
    let s = seeStep(startSteps(K), K, 'review', 100, { agentId: 'r1', detail: 'Adversarial review (Opus)' })
    expect(stepDetail(s)).toEqual({ name: 'review', mark: 'current', text: 'review : Adversarial review (Opus)', since: 100 })
    s = endAgent(s, 'r1', 200, 'APPROVED')
    expect(stepCells(s).find(c => c.name === 'review')).toEqual({ name: 'review', label: 'review APPROVED', mark: 'done', isWarn: false })
    expect(stepDetail(s)).toEqual({ name: 'review', mark: 'done', text: 'review : APPROVED' })
    expect(endAgent(s, 'nobody', 300, null)).toBe(s)
    // A subagent's edit while an implementer runs: edit current, the implementer still ◐ with its detail.
    let t = seeStep(startSteps(K), K, 'implement', 10, { agentId: 'i1', detail: 'Build (Sonnet)' })
    t = seeStep(t, K, 'edit', 20)
    expect(stepCells(t).filter(c => c.mark === 'current').map(c => c.name)).toEqual(['edit', 'implement'])
    expect(stepDetail(t)?.text).toBe('implement : Build (Sonnet)')
  })

  test('AC5: a new run key starts over', () => {
    const s = seeStep(startSteps('session:1'), 'session:1', 'gate', 10)
    const t = seeStep(s, 'session:2', 'edit', 20)
    expect(t.runKey).toBe('session:2')
    expect(t.steps.map(x => x.name)).toEqual(['edit'])
    expect(startSteps('session:3')).toEqual({ runKey: 'session:3', steps: [], current: null })
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

describe('runFromFiles (a run folder without 00-context.md)', () => {
  test('only 02-plan.md: title the folder, no tier, 02-plan current, the known steps after it pending', () => {
    const run = runFromFiles('04-nav-flottante', [{ name: '02-plan.md', mtimeMs: NOW - 1000 }])
    expect(run.title).toBe('04-nav-flottante')
    expect(run.tier).toBeUndefined()
    expect(run.branch).toBeUndefined()
    expect(run.currentStep).toBe('02-plan')
    expect(run.steps.map(s => `${s.step}:${s.kind}`)).toEqual([
      '02-plan:running',
      '03-execute:pending',
      '04-validate:pending',
      '05-examine:pending',
      '06-resolve:pending',
      '07-tests:pending',
      '08-run-tests:pending',
      '09-finish:pending',
    ])
    expect(apexHeader({ ...run, branch: 'feat/x' })).toBe('APEX · feat/x')
    expect(apexHeader(run)).toBe('APEX · 04-nav-flottante')
    expect(isLive(run, NOW - 1000, NOW)).toBe(true)
  })

  test('present files done, the most recently modified current; other files and names ignored', () => {
    const run = runFromFiles('r', [
      { name: '00-init.md', mtimeMs: 1 },
      { name: '01b-obsidian.md', mtimeMs: 2 },
      { name: '02-plan.md', mtimeMs: 5 },
      { name: '03-execute.md', mtimeMs: 4 },
      { name: 'external-verify.json', mtimeMs: 9 },
      { name: 'codex.log', mtimeMs: 9 },
      { name: 'notes.md', mtimeMs: 9 },
    ])
    expect(run.currentStep).toBe('02-plan')
    expect(run.steps.map(s => `${s.step}:${s.kind}`)).toEqual([
      '00-init:done',
      '01b-obsidian:done',
      '02-plan:running',
      '03-execute:done',
      '04-validate:pending',
      '05-examine:pending',
      '06-resolve:pending',
      '07-tests:pending',
      '08-run-tests:pending',
      '09-finish:pending',
    ])
  })

  test('a 09-finish file ends the run', () => {
    const ended = runFromFiles('r', [
      { name: '02-plan.md', mtimeMs: NOW - 2000 },
      { name: '09-finish.md', mtimeMs: NOW - 1000 },
    ])
    expect(isLive(ended, NOW - 1000, NOW)).toBe(false)
  })
})

describe('a run folder without 00-context.md: step files, trunk, 1 h window', () => {
  const plan = (at: number) => runFromFiles('04-nav', [{ name: '02-plan.md', mtimeMs: at }])

  test('00-context.md and other .md files are no step file', () => {
    const files = [
      { name: '00-context.md', mtimeMs: NOW },
      { name: 'notes.md', mtimeMs: NOW },
      { name: '02-plan.md', mtimeMs: NOW - 5000 },
    ]
    expect(newestStep(files)).toBe(NOW - 5000)
    expect(newestStep(files.slice(0, 2))).toBe(-Infinity)
    expect(runFromFiles('r', files).steps.some(s => s.step === '00-context')).toBe(false)
  })

  test('hidden when HEAD is master or main; shown on another branch or HEAD unknown', () => {
    const run = plan(NOW - 1000)
    expect(bareShown(run, NOW - 1000, 'master', NOW)).toBe(false)
    expect(bareShown(run, NOW - 1000, 'main', NOW)).toBe(false)
    expect(bareShown(run, NOW - 1000, 'feat/x', NOW)).toBe(true)
    expect(bareShown(run, NOW - 1000, undefined, NOW)).toBe(true)
  })

  test('live for 1 h from its newest step file, where a context run gets 6 h', () => {
    expect(BARE_STALE_MS).toBe(60 * 60 * 1000)
    const run = plan(NOW - BARE_STALE_MS + 1)
    expect(bareShown(run, NOW - BARE_STALE_MS + 1, 'feat/x', NOW)).toBe(true)
    expect(bareShown(run, NOW - BARE_STALE_MS, 'feat/x', NOW)).toBe(false)
    expect(isLive(run, NOW - BARE_STALE_MS, NOW)).toBe(true)
  })

  test('its header names the folder, not a branch', () => {
    expect(apexHeader(plan(NOW))).toBe('APEX · 04-nav')
  })
})

describe('runSwitch (a new run clears the finished cards)', () => {
  test('first run seen: not new; same run: not new; another dir: new', () => {
    const first = runSwitch(null, 'a')
    expect(first).toEqual({ isNew: false, last: 'a' })
    expect(runSwitch(first.last, 'a')).toEqual({ isNew: false, last: 'a' })
    expect(runSwitch(first.last, 'b')).toEqual({ isNew: true, last: 'b' })
  })

  test('no run (a miss, or the run ended) keeps the last dir: the same run back is not new', () => {
    const gone = runSwitch('a', null)
    expect(gone).toEqual({ isNew: false, last: 'a' })
    expect(runSwitch(gone.last, 'a').isNew).toBe(false)
    expect(runSwitch(gone.last, 'b').isNew).toBe(true)
    expect(runSwitch(null, null)).toEqual({ isNew: false, last: null })
  })

  test('with settleRun: a 1-poll miss then the same run clears nothing', () => {
    const a: DeckApexRun = { title: 't', steps: [], dir: 'a' }
    let last: string | null = null
    let shown: DeckApexRun | null = null
    let misses = 0
    const news: boolean[] = []
    for (const found of [a, null, a, null, null, a]) {
      const settled = settleRun(shown, found, misses)
      shown = settled.run
      misses = settled.misses
      const sw = runSwitch(last, shown?.dir ?? null)
      last = sw.last
      news.push(sw.isNew)
    }
    expect(news).toEqual([false, false, false, false, false, false])
  })
})

describe('session run (a main-loop Skill(apex) call, no run folder)', () => {
  const at = { startedAt: NOW - 5000, lastAt: NOW - 5000, args: 'fix the thing' }

  test('live off the trunk under 1 h from the last call: HEAD as header, no tier, one current apex row', () => {
    const run = sessionRunOf(at, 'feat/x', NOW)
    expect(run).toEqual({
      title: 'apex',
      branch: 'feat/x',
      steps: [{ step: 'apex', status: 'in progress', kind: 'running' }],
      currentStep: 'apex',
      dir: sessionKey(at.startedAt),
    })
    expect(run === null ? '' : apexHeader(run)).toBe('APEX · feat/x')
    expect(run === null ? undefined : phaseMark(run.steps[0] ?? { step: '', status: '', kind: 'other' }, run.currentStep)).toBe('current')
  })

  test('hidden on master or main, 1 h after the last call, and without a call', () => {
    expect(sessionRunOf(at, 'master', NOW)).toBeNull()
    expect(sessionRunOf(at, 'main', NOW)).toBeNull()
    expect(sessionRunOf(null, 'feat/x', NOW)).toBeNull()
    expect(sessionRunOf({ ...at, lastAt: NOW - BARE_STALE_MS + 1 }, 'feat/x', NOW)).not.toBeNull()
    expect(sessionRunOf({ ...at, lastAt: NOW - BARE_STALE_MS }, 'feat/x', NOW)).toBeNull()
  })

  test('a call is a new run once any run was seen; the folder it then writes is the same run', () => {
    expect(callSwitch(null, sessionKey(1))).toEqual({ isNew: false, last: sessionKey(1) })
    expect(callSwitch(sessionKey(1), sessionKey(2))).toEqual({ isNew: true, last: sessionKey(2) })
    expect(callSwitch('a', sessionKey(3))).toEqual({ isNew: true, last: sessionKey(3) })
    // The poll that then finds the run's folder (or an older session key) clears nothing.
    expect(runSwitch(sessionKey(3), 'b')).toEqual({ isNew: false, last: 'b' })
    expect(runSwitch(sessionKey(3), sessionKey(2)).isNew).toBe(false)
    expect(runSwitch('b', 'c').isNew).toBe(true)
  })
})

describe('step details (clock at rest, explanations, anchored review)', () => {
  const K = 'session:1'

  test('AC4: parseReview reads the labelled verdict line, else the first line; prose is ignored', () => {
    expect(parseReview('BLOCKED by X\n…\nVerdict: APPROVED')).toBe('APPROVED')
    expect(parseReview('NEEDS_FIXES\n\nThe gate was not BLOCKED, it ran.')).toBe('NEEDS_FIXES')
    expect(parseReview('Looks fine overall.\nNothing BLOCKED here, APPROVED by me.')).toBeNull()
    expect(parseReview('\n**APPROVED** — clean')).toBe('APPROVED')
    expect(parseReview('Summary\n**Verdict**: needs_fixes')).toBe('NEEDS_FIXES')
    expect(reviewLines('Verdict: NEEDS_FIXES\n\n- a.ts: null deref\n- b.ts: race\n- c.ts: typo\n- d.ts: more')).toEqual([
      '- a.ts: null deref',
      '- b.ts: race',
      '- c.ts: typo',
    ])
  })

  test('AC1: the run rests once the main turn ended with no agent or shell of the run running', () => {
    const run = { startedAt: 100, turnEndAt: 500 }
    expect(runEndedAt({ startedAt: 100 }, [], [])).toBeNull()
    expect(runEndedAt({ startedAt: 100, turnEndAt: null }, [], [])).toBeNull()
    expect(runEndedAt(run, [], [])).toBe(500)
    // A running card of this run keeps the clock going; an older run's running card does not.
    expect(runEndedAt(run, [{ spawnedAt: 200, endedAt: null, status: 'running' }], [])).toBeNull()
    expect(runEndedAt(run, [{ spawnedAt: 50, endedAt: null, status: 'running' }], [])).toBe(500)
    // The latest of the turn end, an agent end, a shell end.
    expect(runEndedAt(run, [{ spawnedAt: 200, endedAt: 900, status: 'done' }], [{ startedAt: 300, endedAt: 700, status: 'completed' }])).toBe(900)
    expect(runEndedAt(run, [], [{ startedAt: 300, status: 'running' }])).toBeNull()
    // Merged: at rest once the turn ended, whatever still runs.
    expect(runEndedAt({ ...run, merged: true }, [], [{ startedAt: 300, status: 'running' }])).toBe(500)
  })

  test('AC3: edit lists distinct file tails, 6 at most, then +N more; ○ reads not reached yet', () => {
    let s = startSteps(K)
    expect(explainStep(s, 'edit').lines).toEqual(['not reached yet'])
    for (const [i, f] of ['a', 'b', 'a', 'c', 'd', 'e', 'f', 'g', 'h'].entries()) s = seeStep(s, K, 'edit', i, { files: [pathTail(`/repo/src/${f}.ts`)] })
    expect(explainStep(s, 'edit').lines).toEqual(['src/a.ts, src/b.ts, src/c.ts, src/d.ts, src/e.ts, src/f.ts +2 more'])
    expect(pathTail('x.ts')).toBe('x.ts')
  })

  test('AC3: gate shows its command, its exit status and its last output line', () => {
    const fail = gateEvidence('pnpm test --run', { stdout: 'ok 1\nnot ok 2\n\n', stderr: '' }, true)
    expect(fail).toEqual({ command: 'pnpm test --run', isError: true, lastLine: 'not ok 2' })
    const s = seeStep(startSteps(K), K, 'gate', 1, fail)
    expect(explainStep(s, 'gate').lines).toEqual(['$ pnpm test --run', 'failed · not ok 2'])
    const code = gateEvidence('nix flake check', { stdout: '', stderr: 'error: x\n', returnCodeInterpretation: 'Exit code 3' }, true)
    expect(code.exitCode).toBe(3)
    expect(explainStep(seeStep(startSteps(K), K, 'gate', 1, code), 'gate').lines).toEqual(['$ nix flake check', 'exit 3 · error: x'])
    const ok = gateEvidence('tsc', { stdout: 'done', stderr: '' }, false)
    expect(explainStep(seeStep(startSteps(K), K, 'gate', 1, ok), 'gate').lines).toEqual(['$ tsc', 'ok · done'])
  })

  test('AC3: Codex verdict and findings, or no verdict when it ran in background', () => {
    const v = seeStep(startSteps(K), K, 'Codex', 1, { verdict: 'FAIL', findings: 2 })
    expect(explainStep(v, 'Codex').lines).toEqual(['FAIL · 2 findings'])
    expect(explainStep(seeStep(startSteps(K), K, 'Codex', 1), 'Codex').lines).toEqual(['no verdict (ran in background)'])
  })

  test('AC3: review verdict and the lines after it; implement agent, model, status, duration, answer', () => {
    let s = seeStep(startSteps(K), K, 'review', 1000, { agentId: 'r1', detail: 'Review (Opus)' })
    expect(explainStep(s, 'review')).toEqual({ lines: ['Review (Opus) · running'], since: 1000 })
    s = endAgent(s, 'r1', 61_000, 'NEEDS_FIXES', { lines: reviewLines('NEEDS_FIXES\n- fix a\n- fix b') })
    expect(explainStep(s, 'review').lines).toEqual(['NEEDS_FIXES · Review (Opus) · done · 1:00', '- fix a', '- fix b'])

    let i = seeStep(startSteps(K), K, 'implement', 0, { agentId: 'i1', detail: 'Build it (Sonnet)' })
    i = endAgent(i, 'i1', 5000, null, { lines: answerLines('\nDone: built it.\nAll green.\nMore.'), isFailed: true })
    expect(explainStep(i, 'implement').lines).toEqual(['Build it (Sonnet) · failed · 0:05', 'Done: built it.', 'All green.'])
  })

  test('AC3: ship reads the commit subject and the PR URL, kept across its calls', () => {
    expect(shipEvidence('git commit -m "feat: add x" -m body', '')).toEqual({ command: 'git commit -m "feat: add x" -m body', subject: 'feat: add x' })
    expect(shipEvidence("git commit -m \"$(cat <<'EOF'\nfix: heredoc subject\n\nbody\nEOF\n)\"", '').subject).toBe('fix: heredoc subject')
    expect(shipEvidence('git commit -F msg.txt', '').subject).toBeUndefined()
    const pr = shipEvidence('gh pr create -F body.md', 'https://github.com/o/r/pull/42\n')
    expect(pr.url).toBe('https://github.com/o/r/pull/42')
    let s = seeStep(startSteps(K), K, 'ship', 1, shipEvidence('git commit -m "feat: add x"', ''))
    s = seeStep(s, K, 'ship', 2, pr)
    expect(explainStep(s, 'ship').lines).toEqual(['commit: feat: add x', 'PR: https://github.com/o/r/pull/42'])
    expect(explainStep(seeStep(startSteps(K), K, 'ship', 1, shipEvidence('git push', '')), 'ship').lines).toEqual(['$ git push'])
    expect(isMergeCall('gh pr merge 3 --squash')).toBe(true)
    expect(isMergeCall('gh pr create')).toBe(false)
  })
})
