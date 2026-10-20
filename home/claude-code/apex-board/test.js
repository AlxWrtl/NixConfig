'use strict'
// APEX board: stage rules of board.js on the three real 00-context.md shapes (copied from runs
// vorssaint-cask, 01-worktree-env-sync, wrangler-oauth-config) and on synthetic runs covering
// every AC7 branch. `node test.js [path/to/board.js]`: exits non-zero on the first failure, so a
// mutant copy of board.js can be tested against the same cases.

const assert = require('assert')
const path = require('path')

const board = require(path.resolve(process.argv[2] || path.join(__dirname, 'board.js')))

const HOUR = 60 * 60 * 1000
const NOW = Date.UTC(2026, 9, 20, 12, 0, 0)
const LIVE = NOW - HOUR
const IDLE = NOW - 7 * HOUR

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (err) {
    console.error(`FAIL ${name}\n  ${err.message}`)
    process.exit(1)
  }
}

// ---- real shapes -----------------------------------------------------------

// No Progress table, no branch, Tier on its own line.
const VORSSAINT = `# APEX: Ajouter le cask vorssaint (keep-awake capot fermé)
Tier: Direct
Flags: -pr
Files: modules/brew.nix
Est-lines: 1
Baseline: nix flake check --no-build -> pending

## ACs
- \`vorssaint\` présent dans \`homebrew.casks\` (groupe auto-updating, le cask déclare auto_updates)
- \`nix flake check --no-build\` vert

## Tokens
| Point | Coordinator context |
|-------|---------------------|
| start | 61219 |
| end | |
`

// Tier with a parenthesis, Branch with a trunk note, table with skipped + pending rows.
const WORKTREE = `# APEX: open .env to the sandbox + global worktree env-file sync hook
Date: 2026-10-19
Tier: High-stakes (sandbox denyRead/allowRead keys; new hook)
Flags: -t -f -x -pr -o -n -e
Branch: feat/worktree-env-sync (trunk: master)
Files: home/claude-code/settings.nix, home/claude-code/hooks.nix, home/claude-code/hooks/worktree-env-sync.sh (new), checks/hook-wiring.nix, README.md
Est-lines: ~120
Baseline: nix flake check --no-build -> pending

## Task
1. Remove \`\${homeDirectory}/**/.env\` and \`**/.env.*\` from sandbox.filesystem.denyRead
   (settings.nix:261-262) and the now-useless allowRead \`.env.example\` / \`.env.template\`
   (settings.nix:291-292). KEEP permissions.deny \`Read(**/.env)\` / \`Read(**/.env.*)\`.
2. Global hook: when hook input \`cwd\` is a linked git worktree, copy from the main
   checkout the gitignored files \`.env\`, \`.env.*\`, \`.dev.vars\` that are absent in the
   worktree. Never overwrite.

## Unproven premises (plan must source or probe)
- hook commands run outside the Bash sandbox
- PostToolUse matcher \`EnterWorktree\` fires

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 01-analyze | skipped | files known |
| 01b-obsidian | pending | |
| 02-plan | pending | |
| 03-execute | pending | |
| 04-validate | pending | |

## Tokens
Context growth, not billed tokens.

| phase | agent | model | tokens |
|-------|-------|-------|--------|

coordinator context: 113989→
`

const WORKTREE_FILES = ['00-context.md', '01b-obsidian.md', '02-plan.md', '05-examine.md', 'acs.txt', 'external-verify.json', 'external.log']

const WORKTREE_VERDICT = JSON.stringify({
  schema_version: 1,
  tool: 'apex-verify-external',
  verdict: 'FAIL',
  reason: '',
  model: 'gpt-5.6-terra',
  summary: 'Linked worktrees with separate git directories are skipped.',
  findings: [
    {
      file: 'home/claude-code/hooks/worktree-env-sync.sh',
      line: 39,
      severity: 'important',
      problem: 'The main checkout root is derived only when the common git directory ends in `/.git`.',
      expected_fix: 'Resolve the primary worktree root using Git worktree metadata.',
      ac: '3',
    },
  ],
}, null, 2)

// Tier line carrying Files and Est-lines, Branch with ", clean", shipped (pr.md) while its
// table still says 03-execute pending.
const WRANGLER = `# APEX: allow sandbox write to ~/.config/.wrangler/config
Date: 2026-10-18
Tier: High-stakes (sandbox allowWrite key) — Files: home/claude-code/settings.nix, checks/claude-config.nix — Est-lines: ~8
Flags: -t -f -x -pr -o -n -e (defaults)
Branch: fix/sandbox-wrangler-oauth-refresh (trunk: master), clean
Baseline: nix flake check --no-build -> green (rc=0)
User choice (AskUserQuestion): option "allowWrite config" over CLOUDFLARE_API_TOKEN / hook exemption.

## Evidence
- ~/.config/.wrangler/logs, 2026-10-18T14:33:11Z: \`Token refresh failed: EPERM: operation not permitted, open '/Users/alx/.config/.wrangler/config/default.toml'\`

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 01-analyze | skipped | files known |
| 01b-obsidian | skipped | vault silent on wrangler sandbox (session notes list has none) |
| 02-plan | complete | coordinator inline: diff spelled exactly, 2 hunks |
| 03-execute | pending | |
| 04-validate | pending | |

## Deviations
- Plan subagent and -f test-author not spawned: diff is two spelled list entries + comment.

## Tokens
| phase | agent | model | tokens |
|-------|-------|-------|--------|

coordinator context: 60259→unknown
`

const WRANGLER_FILES = ['00-context.md', '02-plan.md', 'acs.txt', 'commit.txt', 'diff.patch', 'external-verify.json', 'pr.md']
const PASS = JSON.stringify({ verdict: 'PASS', findings: [] })

const run = (over) => board.deriveRun({ id: 'r', context: null, mtimeMs: LIVE, files: ['00-context.md'], budget: { rounds: 0, grants: 0 }, verdict: null, ...over }, NOW)

test('vorssaint: header read without a table or a branch', () => {
  const c = board.parseContext(VORSSAINT, 'vorssaint-cask')
  assert.strictEqual(c.title, 'Ajouter le cask vorssaint (keep-awake capot fermé)')
  assert.strictEqual(c.tier, 'Direct')
  assert.strictEqual(c.branch, null)
  assert.strictEqual(c.steps, null)
  assert.strictEqual(c.blocked, null)
})

test('vorssaint: live, no table, only 00-context.md → Init', () => {
  const r = run({ id: 'vorssaint-cask', context: VORSSAINT })
  assert.strictEqual(r.column, 'init')
  assert.strictEqual(r.live, true)
  assert.strictEqual(r.flag, null)
})

test('worktree: tier head, branch head, steps', () => {
  const c = board.parseContext(WORKTREE, '01-worktree-env-sync')
  assert.strictEqual(c.title, 'open .env to the sandbox + global worktree env-file sync hook')
  assert.strictEqual(c.tier, 'High-stakes')
  assert.strictEqual(c.branch, 'feat/worktree-env-sync')
  assert.deepStrictEqual(c.steps.map((s) => s.kind), ['done', 'skipped', 'pending', 'pending', 'pending', 'pending'])
  assert.strictEqual(c.blocked, null)
})

test('worktree: live, ext FAIL and 2 rounds used → À toi, grant hint first', () => {
  const r = run({ id: '01-worktree-env-sync', context: WORKTREE, files: WORKTREE_FILES, verdict: WORKTREE_VERDICT, budget: { rounds: 2, grants: 0 } })
  assert.strictEqual(r.column, 'human')
  assert.strictEqual(r.flag, 'à toi')
  assert.deepStrictEqual(r.reasons, ['budget de correction épuisé (2/2)', 'vérif externe FAIL · 1 findings'])
  assert.strictEqual(r.hints[0], 'apex: +1 tour')
  assert.deepStrictEqual(r.chips.map((c) => [c.key, c.state]), [['tier', 'info'], ['ext', 'fail'], ['corr1', 'used'], ['corr2', 'used']])
})

test('worktree: live, nothing wrong → current step 01b-obsidian → Plan', () => {
  const r = run({ context: WORKTREE, files: WORKTREE_FILES.filter((f) => f !== 'external-verify.json') })
  assert.strictEqual(r.column, 'plan')
  assert.strictEqual(r.current, '01b-obsidian')
})

test('worktree: idle, ext FAIL → Terminé, inactif', () => {
  const r = run({ context: WORKTREE, files: WORKTREE_FILES, verdict: WORKTREE_VERDICT, mtimeMs: IDLE })
  assert.strictEqual(r.column, 'done')
  assert.strictEqual(r.flag, 'inactif')
  assert.deepStrictEqual(r.reasons, [])
})

test('wrangler: tier head before the em dash, branch before the trunk note', () => {
  const c = board.parseContext(WRANGLER, 'wrangler-oauth-config')
  assert.strictEqual(c.title, 'allow sandbox write to ~/.config/.wrangler/config')
  assert.strictEqual(c.tier, 'High-stakes')
  assert.strictEqual(c.branch, 'fix/sandbox-wrangler-oauth-refresh')
})

test('wrangler: pr.md / commit.txt → Terminé though 03-execute is pending, live or not', () => {
  for (const mtimeMs of [LIVE, IDLE]) {
    const r = run({ context: WRANGLER, files: WRANGLER_FILES, verdict: PASS, mtimeMs })
    assert.strictEqual(r.column, 'done')
    assert.strictEqual(r.finished, true)
    assert.strictEqual(r.flag, null)
    assert.strictEqual(r.chips[1].state, 'pass')
  }
  assert.strictEqual(run({ context: WRANGLER, files: ['00-context.md', 'commit.txt'] }).column, 'done')
})

test('wrangler: without pr.md / commit.txt, live → current 03-execute → Execute', () => {
  const r = run({ context: WRANGLER, files: ['00-context.md', '02-plan.md'], verdict: PASS })
  assert.strictEqual(r.column, 'execute')
})

// ---- synthetic: AC7 branches --------------------------------------------------

const ctx = (rows, extra = '') => `# APEX: synthetic\nTier: Standard\nBranch: feat/x\n${extra}\n## Progress\n| Step | Status | Notes |\n|------|--------|-------|\n${rows.map(([s, st]) => `| ${s} | ${st} | |`).join('\n')}\n`

test('idle ≥ 6 h → Terminé; just under 6 h → live', () => {
  const text = ctx([['00-init', 'complete'], ['03-execute', 'in progress']])
  assert.strictEqual(run({ context: text, mtimeMs: NOW - board.STALE_MS }).column, 'done')
  assert.strictEqual(run({ context: text, mtimeMs: NOW - board.STALE_MS }).live, false)
  assert.strictEqual(run({ context: text, mtimeMs: NOW - board.STALE_MS + 1 }).column, 'execute')
  assert.strictEqual(run({ context: text, mtimeMs: null }).column, 'done')
})

test('live with a failed step → À toi; idle → Terminé inactif', () => {
  const text = ctx([['00-init', 'complete'], ['04-validate', 'failed'], ['05-examine', 'pending']])
  const r = run({ context: text })
  assert.strictEqual(r.column, 'human')
  assert.deepStrictEqual(r.reasons, ['étape 04-validate en échec'])
  assert.deepStrictEqual(r.hints, ['répondre dans la session · /deck'])
  const idle = run({ context: text, mtimeMs: IDLE })
  assert.strictEqual(idle.column, 'done')
  assert.strictEqual(idle.flag, 'inactif')
})

test('failed spellings: red, échoué, **failed**', () => {
  for (const status of ['red', 'échoué', '**failed** (gate)']) {
    assert.strictEqual(run({ context: ctx([['03-execute', status]]) }).column, 'human', status)
  }
  assert.strictEqual(board.statusKind('redone'), 'other')
})

test('live with a blocked step → À toi', () => {
  const r = run({ context: ctx([['00-init', 'complete'], ['02-plan', 'blocked']]) })
  assert.strictEqual(r.column, 'human')
  assert.deepStrictEqual(r.reasons, ['étape 02-plan bloquée'])
})

test('live with a BLOCKED line → À toi; BLOCKED in prose, a table cell or a fence → not', () => {
  for (const line of ['BLOCKED: waiting for the user', '**Status:** BLOCKED (needs key)', '- BLOCKED by the sandbox']) {
    const r = run({ context: ctx([['03-execute', 'in progress']], line) })
    assert.strictEqual(r.column, 'human', line)
  }
  const prose = ['Tree clean. Command is SANDBOX-BLOCKED (writes)', '4. Fable only when Codex is BLOCKED', '```\nBLOCKED\n```'].join('\n')
  const rows = [['03-execute', 'in progress'], ['04-validate', 'complete']]
  assert.strictEqual(run({ context: ctx(rows, prose) }).column, 'execute')
  assert.strictEqual(run({ context: ctx([['04-validate', 'complete'], ['05-examine', 'pending']]).replace('| complete | |', '| complete | -e BLOCKED timeout |') }).column, 'validate')
})

test('budget: rounds ≥ 2 + grants → À toi with `apex: +1 tour`', () => {
  const text = ctx([['03-execute', 'in progress']])
  assert.strictEqual(run({ context: text, budget: { rounds: 1, grants: 0 } }).column, 'execute')
  assert.strictEqual(run({ context: text, budget: { rounds: 2, grants: 1 } }).column, 'execute')
  const r = run({ context: text, budget: { rounds: 3, grants: 1 } })
  assert.strictEqual(r.column, 'human')
  assert.deepStrictEqual(r.hints, ['apex: +1 tour'])
  assert.deepStrictEqual(r.chips.slice(2).map((c) => c.state), ['used', 'used', 'used'])
})

test('ext: PASS live → no À toi; FAIL / BLOCKED / ERROR live → À toi; unreadable → no verdict', () => {
  const text = ctx([['04-validate', 'in progress']])
  assert.strictEqual(run({ context: text, verdict: PASS }).column, 'validate')
  for (const verdict of ['FAIL', 'BLOCKED', 'ERROR']) {
    assert.strictEqual(run({ context: text, verdict: JSON.stringify({ verdict }) }).column, 'human', verdict)
  }
  const half = run({ context: text, verdict: '{"verdict": "FA' })
  assert.strictEqual(half.column, 'validate')
  assert.strictEqual(half.chips[1].state, 'unset')
})

test('current step NN mapping: running first, else first pending', () => {
  const cases = [
    ['00-init', 'init'], ['01-analyze', 'plan'], ['01b-obsidian', 'plan'], ['02-plan', 'plan'], ['02c-verify', 'plan'],
    ['03-execute', 'execute'], ['04-validate', 'validate'], ['05-examine', 'validate'], ['06-resolve', 'validate'],
    ['07/08-tests', 'validate'], ['08-run-tests', 'validate'], ['09-finish', 'done'], ['09b-note', 'done'],
  ]
  for (const [step, column] of cases) {
    assert.strictEqual(run({ context: ctx([['00-init', 'complete'], [step, 'pending']]) }).column, step === '00-init' ? 'init' : column, step)
  }
  const both = run({ context: ctx([['02-plan', 'pending'], ['04-validate', 'in progress']]) })
  assert.strictEqual(both.column, 'validate')
  assert.strictEqual(both.current, '04-validate')
  assert.strictEqual(run({ context: ctx([['Execute', 'in_progress']]) }).column, 'execute')
})

test('all steps done or skipped → Terminé, not inactif', () => {
  const r = run({ context: ctx([['00-init', 'complete'], ['01-analyze', 'skipped'], ['09-finish', 'done']]) })
  assert.strictEqual(r.column, 'done')
  assert.strictEqual(r.finished, true)
  assert.strictEqual(r.flag, null)
})

test('no table → highest NN-*.md; none → Init; no 00-context.md at all', () => {
  const noTable = '# APEX: bare\nTier: Direct\n'
  assert.strictEqual(run({ context: noTable, files: ['00-context.md', '01-analyze.md', '02-plan.md', '04-validate.md', 'acs.txt'] }).column, 'validate')
  assert.strictEqual(run({ context: noTable, files: ['00-context.md', '02-plan.md', '04-external-verify.json'] }).column, 'plan')
  assert.strictEqual(run({ context: noTable, files: ['00-context.md', '03-execute.md'] }).column, 'execute')
  assert.strictEqual(run({ context: noTable, files: ['00-context.md', 'pr.md', '02-plan.md'] }).column, 'done')
  assert.strictEqual(run({ context: noTable, files: [] }).column, 'init')
  const bare = run({ id: 'bare', context: null, mtimeMs: null, files: ['01-analyze.md'] })
  assert.strictEqual(bare.column, 'done')
  assert.strictEqual(bare.flag, 'inactif')
  assert.strictEqual(bare.title, 'bare')
})

test('tier from Flags when no Tier line: `(mode X)`, `(mode: X —`', () => {
  assert.strictEqual(board.parseContext('# APEX: t\nFlags: -t -pr (mode Standard, défaut)\n', 't').tier, 'Standard')
  assert.strictEqual(board.parseContext('# APEX: t\nFlags: -t -x  (mode: high-stakes — touches)\n', 't').tier, 'high-stakes')
})

test('chips: tier unknown dashed, ext absent dashed, corr unused dashed', () => {
  const r = run({ context: '# APEX: t\n' })
  assert.deepStrictEqual(r.chips.map((c) => [c.label, c.state]), [['tier', 'unset'], ['ext', 'unset'], ['corr1', 'unset'], ['corr2', 'unset']])
  const one = run({ context: VORSSAINT, budget: { rounds: 1, grants: 0 } })
  assert.deepStrictEqual(one.chips.map((c) => [c.label, c.state]), [['Direct', 'info'], ['ext', 'unset'], ['corr1', 'used'], ['corr2', 'unset']])
})

// ---- helpers -------------------------------------------------------------------

test('parseIndex: python http.server listing', () => {
  const html = `<!DOCTYPE HTML>
<html lang="en"><head><title>Directory listing for /runs/</title></head><body>
<h1>Directory listing for /runs/</h1><hr><ul>
<li><a href="01-worktree-env-sync/">01-worktree-env-sync/</a></li>
<li><a href="02-plan.md">02-plan.md</a></li>
<li><a href="caf%C3%A9%20run/">café run/</a></li>
<li><a href="a%26b.md">a&amp;b.md</a></li>
<li><a href="link/">link@</a></li>
</ul><hr></body></html>`
  assert.deepStrictEqual(board.parseIndex(html), [
    { name: '01-worktree-env-sync', dir: true },
    { name: '02-plan.md', dir: false },
    { name: 'café run', dir: true },
    { name: 'a&b.md', dir: false },
    { name: 'link', dir: true },
  ])
  assert.deepStrictEqual(board.parseIndex('<a href="../">up</a><a href="%E0%A4%A">bad</a><a href="/abs">x</a>'), [])
})

test('parseBudget: rounds and grants per run id', () => {
  const b = board.parseBudget(['01-worktree-env-sync.round1', '01-worktree-env-sync.round2', '28-snap.grant1', '28-snap.grant2', '28-snap.round1', 'noise.txt'])
  assert.deepStrictEqual(b.get('01-worktree-env-sync'), { rounds: 2, grants: 0 })
  assert.deepStrictEqual(b.get('28-snap'), { rounds: 1, grants: 2 })
  assert.strictEqual(b.get('noise.txt'), undefined)
})

test('verdictFile: the latest round, NN prefix as tie-breaker', () => {
  assert.strictEqual(board.verdictFile(WORKTREE_FILES), 'external-verify.json')
  assert.strictEqual(board.verdictFile(['04-external-verify.json', '06-external-verify.json']), '06-external-verify.json')
  assert.strictEqual(board.verdictFile(['00-context.md', 'acs.txt']), null)
  assert.strictEqual(board.verdictFile(['external-verify.json.bak', 'external-verify.md']), null)
  // The four real later-round names (apex-pane, 54-nix-audit-fixes, pnpm-store-lock, 65-git-prefix-redos).
  assert.strictEqual(board.verdictFile(['external-verify.json', 'external-verify-2.json']), 'external-verify-2.json')
  assert.strictEqual(board.verdictFile(['04-external-verify-2.json', '04-external-verify.json']), '04-external-verify-2.json')
  assert.strictEqual(board.verdictFile(['external-verify.json', 'external-verify3.json', 'external-verify2.json']), 'external-verify3.json')
  assert.strictEqual(board.verdictFile(['external-verify-r1.json', 'external-verify.json']), 'external-verify-r1.json')
  // Rounds compare as numbers, not text: 10 is after 9.
  assert.strictEqual(board.verdictFile(['external-verify-10.json', 'external-verify-9.json']), 'external-verify-10.json')
  // Equal round: the higher NN wins, an unprefixed name wins over NN-.
  assert.strictEqual(board.verdictFile(['06-external-verify-2.json', '04-external-verify-2.json']), '06-external-verify-2.json')
  assert.strictEqual(board.verdictFile(['04-external-verify.json', 'external-verify.json']), 'external-verify.json')
})

test('groupRuns: 6 columns, newest first, Terminé capped at 30 then +N', () => {
  assert.deepStrictEqual(board.COLUMNS.map((c) => c.label), ['Init', 'Plan', 'Execute', 'Validate', 'Terminé', 'À toi'])
  const cards = []
  for (let i = 0; i < 35; i++) cards.push(run({ id: `d${i}`, context: VORSSAINT, mtimeMs: IDLE - i * HOUR }))
  cards.push(run({ id: 'live', context: VORSSAINT }))
  const g = board.groupRuns(cards)
  assert.strictEqual(g.done.cards.length, 30)
  assert.strictEqual(g.done.more, 5)
  assert.strictEqual(g.done.cards[0].id, 'd0')
  assert.strictEqual(g.init.cards[0].id, 'live')
})

test('fileTone: verdict dot from the first line, JSON verdict', () => {
  assert.strictEqual(board.fileTone('04-validate.md', '\n**Verdict: APPROVED**\nbody'), 'good')
  assert.strictEqual(board.fileTone('05-examine.md', 'NEEDS_FIXES\n'), 'warn')
  assert.strictEqual(board.fileTone('x.md', '# BLOCKED by the sandbox'), 'stop')
  assert.strictEqual(board.fileTone('x.md', 'Plan\nAPPROVED'), null)
  assert.strictEqual(board.fileTone('external-verify.json', WORKTREE_VERDICT), 'stop')
  assert.strictEqual(board.fileTone('external-verify.json', PASS), 'good')
  assert.strictEqual(board.fileTone('acs.txt', 'AC1'), null)
})

process.stdout.write(`apex-board: ${passed} tests passed\n`)
