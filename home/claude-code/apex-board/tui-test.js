'use strict'
// apex-board --tui: tui.js on fixture runs built in a temp dir (a live run with a failed step, a
// shipped run, a stale one, a correction round, an external verdict, links escaping the runs
// dir). `node tui-test.js [path/to/tui.js]`: exits non-zero on the first failure, so a mutant copy
// of tui.js (board.js next to it) can be tested against the same cases.

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const T = require(path.resolve(process.argv[2] || path.join(__dirname, 'tui.js')))
const B = T.board

const HOUR = 60 * 60 * 1000
const NOW = Date.now()

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'apex-tui-'))
const runs = path.join(root, 'runs')
const budget = path.join(root, 'budget')
const outside = path.join(root, 'outside')

let passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (err) {
    process.stderr.write(`FAIL ${name}\n  ${err.message}\n`)
    fs.rmSync(root, { recursive: true, force: true })
    process.exit(1)
  }
}

// ---- fixtures ------------------------------------------------------------------

const ctx = (title, rows) => `# APEX: ${title}\nTier: Standard\nBranch: feat/${title}\n\n## Progress\n| Step | Status | Notes |\n|------|--------|-------|\n${rows.map(([s, st]) => `| ${s} | ${st} | |`).join('\n')}\n`
const write = (rel, text, ageMs = 0) => {
  const p = path.join(runs, rel)
  fs.mkdirSync(path.dirname(p), { recursive: true })
  fs.writeFileSync(p, text)
  const t = new Date(NOW - ageMs)
  fs.utimesSync(p, t, t)
}

const LIVE_CTX = ctx('live', [['00-init', 'complete'], ['04-validate', 'failed'], ['05-examine', 'pending']])
const DONE_CTX = ctx('shipped', [['00-init', 'complete'], ['09-finish', 'complete']])
const STALE_CTX = ctx('stale', [['00-init', 'complete'], ['03-execute', 'in progress']])
const PASS = JSON.stringify({ verdict: 'PASS', findings: [] })

write('live-failed/00-context.md', LIVE_CTX)
write('live-failed/04-validate.md', 'PASS\n\n# Validate\n\nAll **green**.\n')
write('live-failed/sub/notes.md', '# Notes\n')
write('done-pr/00-context.md', DONE_CTX, 8 * HOUR)
write('done-pr/pr.md', '# PR\n', 8 * HOUR)
write('done-pr/external-verify.json', PASS, 8 * HOUR)
write('stale/00-context.md', STALE_CTX, 7 * HOUR)
fs.mkdirSync(budget)
fs.writeFileSync(path.join(budget, 'live-failed.round1'), '')
fs.mkdirSync(path.join(outside, 'dir'), { recursive: true })
fs.writeFileSync(path.join(outside, 'secret.md'), 'TOP SECRET\n')
fs.writeFileSync(path.join(outside, 'dir', 'inner.md'), 'INNER SECRET\n')
fs.symlinkSync(path.join(outside, 'secret.md'), path.join(runs, 'live-failed', 'escape.md'))
fs.symlinkSync(path.join(outside, 'dir'), path.join(runs, 'live-failed', 'escape-dir'))
// A run dir that is itself a link out of the runs dir: never a run.
fs.symlinkSync(outside, path.join(runs, 'linked-run'))

const plain = (lines) => lines.map(T.stripAnsi)
const stateWith = (inputs, width, height) => ({
  ...T.initialState({ repo: 'fixture', width, height }),
  runs: inputs,
  now: NOW,
  status: { ok: true, count: inputs.length, time: '12:00:00' },
})

// ---- disk ----------------------------------------------------------------------

const problems = []
const inputs = T.readRuns(runs, budget, fs, problems)
const byId = Object.fromEntries(inputs.map((r) => [r.id, r]))

test('readRuns: real run dirs only, inputs as deriveRun takes them', () => {
  assert.deepStrictEqual(inputs.map((r) => r.id), ['done-pr', 'live-failed', 'stale'])
  assert.deepStrictEqual(problems, [])
  const live = byId['live-failed']
  assert.strictEqual(live.context, LIVE_CTX)
  assert.deepStrictEqual(live.files, ['00-context.md', '04-validate.md', 'escape-dir', 'escape.md'])
  assert.deepStrictEqual(live.budget, { rounds: 1, grants: 0 })
  assert.strictEqual(live.verdict, null)
  assert.strictEqual(typeof live.mtimeMs, 'number')
  assert.ok(Math.abs(live.mtimeMs - NOW) < 5000, `mtimeMs ${live.mtimeMs} not ~now`)
  const done = byId['done-pr']
  assert.strictEqual(done.verdict, PASS)
  assert.strictEqual(done.budget, undefined)
  assert.ok(Math.abs(done.mtimeMs - (NOW - 8 * HOUR)) < 5000)
})

test('readRuns: a missing budget dir is no round used, not a problem', () => {
  const p = []
  const again = T.readRuns(runs, path.join(root, 'no-budget'), fs, p)
  assert.deepStrictEqual(p, [])
  assert.strictEqual(again.find((r) => r.id === 'live-failed').budget, undefined)
})

test('board.js integration: À toi, Terminé, Terminé inactif', () => {
  const cards = Object.fromEntries(inputs.map((r) => [r.id, B.deriveRun(r, NOW)]))
  assert.strictEqual(cards['live-failed'].column, 'human')
  assert.deepStrictEqual(cards['live-failed'].reasons, ['étape 04-validate en échec'])
  assert.strictEqual(cards['done-pr'].column, 'done')
  assert.strictEqual(cards['done-pr'].flag, null)
  assert.strictEqual(cards.stale.column, 'done')
  assert.strictEqual(cards.stale.flag, 'inactif')
})

test('listRunFiles: subdirs walked, a symlinked dir listed and never descended', () => {
  const files = T.listRunFiles(path.join(runs, 'live-failed'))
  assert.ok(files.includes('sub/notes.md'), files.join(','))
  assert.ok(files.includes('escape-dir'), files.join(','))
  assert.ok(files.includes('escape.md'), files.join(','))
  assert.ok(!files.some((f) => f.startsWith('escape-dir/')), files.join(','))
})

test('readRunFile: links out of the runs dir are « hors du run », never read', () => {
  const inside = T.readRunFile(runs, 'live-failed', '04-validate.md')
  assert.strictEqual(inside.kind, 'text')
  assert.ok(inside.text.startsWith('PASS'))
  for (const rel of ['escape.md', 'escape-dir', 'escape-dir/inner.md', '../stale/00-context.md', 'sub/../../stale/00-context.md']) {
    const r = T.readRunFile(runs, 'live-failed', rel)
    assert.strictEqual(r.kind, 'outside', rel)
    assert.strictEqual(r.text, T.OUTSIDE, rel)
  }
  assert.strictEqual(T.readRunFile(runs, '..', 'outside/secret.md').kind, 'outside')
  assert.strictEqual(T.readRunFile(runs, 'live-failed', 'nope.md').kind, 'missing')
})

// ---- board ---------------------------------------------------------------------

test('renderBoard 180x50: 6 columns in order, cards, À TOI, truecolor, rounded boxes, exact width', () => {
  const { lines } = T.renderBoard(stateWith(inputs, 180, 50), 180, 50)
  assert.strictEqual(lines.length, 50)
  lines.forEach((l, y) => assert.strictEqual(T.visibleWidth(l), 180, `line ${y} width ${T.visibleWidth(l)}`))
  const text = plain(lines)
  const head = text.find((l) => l.includes('Init') && l.includes('Validate'))
  assert.ok(head, 'no column head line')
  const at = B.COLUMNS.map((c) => head.indexOf(c.label))
  assert.ok(at.every((x, k) => x >= 0 && (k === 0 || x > at[k - 1])), `labels out of order: ${at}`)
  const all = text.join('\n')
  for (const id of ['live-failed', 'done-pr', 'stale']) assert.ok(all.includes(id), id)
  assert.ok(all.includes('À TOI'))
  assert.ok(all.includes('INACTIF'))
  assert.ok(all.includes('étape 04-validate'))
  assert.ok(all.includes('APEX board · fixture'))
  assert.ok(all.includes('/apex -x <tâche>'))
  assert.ok(lines.join('').includes('38;2;255;121;198'), 'no human truecolor')
  assert.ok(all.includes('╭') && all.includes('╯'))
})

test('renderBoard: narrow and tiny terminals never overflow', () => {
  for (const [w, h] of [[60, 30], [23, 12], [10, 5], [1, 1]]) {
    const { lines } = T.renderBoard(stateWith(inputs, w, h), w, h)
    assert.strictEqual(lines.length, h, `${w}x${h}`)
    lines.forEach((l, y) => assert.strictEqual(T.visibleWidth(l), w, `${w}x${h} line ${y}`))
  }
})

test('Terminé cap: 35 done runs → 30 cards then +5', () => {
  const many = []
  for (let k = 0; k < 35; k++) many.push({ id: `run-${String(k).padStart(2, '0')}`, context: DONE_CTX, mtimeMs: NOW - (8 + k) * HOUR, files: ['00-context.md', 'pr.md'] })
  const text = plain(T.renderBoard(stateWith(many, 180, 400), 180, 400).lines).join('\n')
  for (let k = 0; k < 30; k++) assert.ok(text.includes(`run-${String(k).padStart(2, '0')}`), `run-${k} missing`)
  for (let k = 30; k < 35; k++) assert.ok(!text.includes(`run-${k}`), `run-${k} shown past the cap`)
  assert.ok(/\+5\b/.test(text), 'no +5')
})

// ---- reduce --------------------------------------------------------------------

const selected = (s) => {
  const v = T.renderBoard(s, s.width, s.height).view.sel
  const card = v.idx >= 0 ? B.groupRuns(s.runs.map((r) => B.deriveRun(r, s.now)))[B.COLUMNS[v.col].key].cards[v.idx] : null
  return { col: v.col, id: card ? card.id : null }
}

test('reduce: arrows move between columns and cards, enter opens, esc closes, q quits', () => {
  let s = stateWith(inputs, 180, 50)
  // Newest first: stale (7 h) above done-pr (8 h) in Terminé, the first non-empty column.
  assert.deepStrictEqual(selected(s), { col: 4, id: 'stale' })
  s = T.reduce(s, 'down')
  assert.deepStrictEqual(selected(s), { col: 4, id: 'done-pr' })
  s = T.reduce(s, 'down')
  assert.deepStrictEqual(selected(s), { col: 4, id: 'done-pr' })
  s = T.reduce(s, 'up')
  assert.deepStrictEqual(selected(s), { col: 4, id: 'stale' })
  s = T.reduce(T.reduce(s, 'down'), 'right')
  assert.deepStrictEqual(selected(s), { col: 5, id: 'live-failed' })
  s = T.reduce(s, 'right')
  assert.deepStrictEqual(selected(s), { col: 5, id: 'live-failed' })
  s = T.reduce(s, 'left')
  assert.deepStrictEqual(selected(s), { col: 4, id: 'stale' })
  s = T.reduce(s, 'left')
  assert.deepStrictEqual(selected(s), { col: 3, id: null })
  assert.strictEqual(T.reduce(s, 'enter').drawer, null)
  s = T.reduce(T.reduce(T.reduce(s, 'right'), 'down'), 'enter')
  assert.strictEqual(s.drawer.id, 'done-pr')
  assert.strictEqual(s.need, 'drawer')
  s = T.reduce({ ...s, need: null }, 'esc')
  assert.strictEqual(s.drawer, null)
  assert.strictEqual(T.reduce(s, 'q').quit, true)
  assert.strictEqual(T.reduce(s, 'ctrl-c').quit, true)
})

test('reduce: click on a card opens it, files load, file keys follow, click on × closes', () => {
  let s = stateWith(inputs, 180, 50)
  const hit = T.renderBoard(s, 180, 50).hits.find((h) => h.hit.type === 'card' && h.hit.id === 'live-failed')
  assert.ok(hit, 'no hit rect for live-failed')
  s = T.reduce(s, { type: 'mouse', x: hit.x + 2, y: hit.y + 1, button: 'left', wheel: 0 })
  assert.strictEqual(s.drawer.id, 'live-failed')
  s = T.loadDrawer(s, runs)
  assert.strictEqual(s.need, null)
  assert.strictEqual(s.drawer.path, '00-context.md')
  assert.ok(s.drawer.files.includes('sub/notes.md'))
  assert.strictEqual(s.drawer.tones['04-validate.md'], 'good')
  const drawn = plain(T.renderBoard(s, 180, 50).lines).join('\n')
  assert.ok(drawn.includes('live-failed · À toi · 05-examine · actif'), 'drawer head')
  assert.ok(drawn.includes('SUB'), 'subdir group')
  s = T.reduce(s, 'down')
  assert.strictEqual(s.drawer.path, '04-validate.md')
  assert.strictEqual(s.need, 'file')
  s = T.loadDrawer(s, runs)
  assert.ok(plain(T.renderBoard(s, 180, 50).lines).join('\n').includes('All green.'), 'markdown doc')
  s = T.loadDrawer({ ...s, drawer: { ...s.drawer, path: 'escape.md' } }, runs)
  const esc = plain(T.renderBoard(s, 180, 50).lines).join('\n')
  assert.ok(esc.includes(T.OUTSIDE), 'escape not shown as outside')
  assert.ok(!esc.includes('TOP SECRET'), 'escaping link was read')
  const close = T.renderBoard(s, 180, 50).hits.find((h) => h.hit.type === 'close')
  s = T.reduce(s, { type: 'mouse', x: close.x + 1, y: close.y + 1, button: 'left', wheel: 0 })
  assert.strictEqual(s.drawer, null)
})

test('parseInput: keys, SGR mouse press and wheel, lone esc', () => {
  const ev = T.parseInput('\x1b[A\x1b[B\x1b[C\x1b[D\r q\t\x1b[5~\x1b[6~\x1b[<0;10;5M\x1b[<0;10;5m\x1b[<64;1;1M\x1b[<65;2;3M\x03\x1b')
  assert.deepStrictEqual(ev, [
    'up', 'down', 'right', 'left', 'enter', 'space', 'q', 'tab', 'pgup', 'pgdn',
    { type: 'mouse', x: 9, y: 4, button: 'left', wheel: 0 },
    { type: 'mouse', x: 0, y: 0, button: null, wheel: -1 },
    { type: 'mouse', x: 1, y: 2, button: null, wheel: 1 },
    'ctrl-c', 'esc',
  ])
})

// ---- markdown ------------------------------------------------------------------

test('renderMarkdown: verdict badge, heading, table, tasks, code, width', () => {
  const md = 'PASS — all good\n\n# Title\n\nSome **bold** and `code` and [a link](https://x.y).\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n1. one\n\n> quoted\n\n```\ncode line\n```\n'
  const lines = T.renderMarkdown(md, 40)
  const text = plain(lines)
  assert.ok(text[0].includes('PASS — all good'))
  assert.ok(lines[0].includes('38;2;80;250;123'), 'badge not in pass color')
  const title = lines.find((l) => T.stripAnsi(l) === 'Title')
  assert.ok(title && title.includes(';1m'), 'heading not bold')
  assert.ok(text.some((l) => l.startsWith('┌')) && text.some((l) => l.startsWith('└')))
  assert.ok(text.some((l) => l.includes('☑ done')) && text.some((l) => l.includes('☐ todo')))
  assert.ok(text.some((l) => l.includes('code line')))
  assert.ok(text.some((l) => l.startsWith('│ quoted')))
  lines.forEach((l) => assert.ok(T.visibleWidth(l) <= 40, `wider than 40: ${T.stripAnsi(l)}`))
  for (const l of T.renderMarkdown(`${'word '.repeat(30)}${'x'.repeat(50)}\n| ${'c | '.repeat(20)}\n`, 10)) {
    assert.ok(T.visibleWidth(l) <= 10, `wider than 10: ${T.stripAnsi(l)}`)
  }
})

test('renderMarkdown: control chars in a file never reach the terminal', () => {
  const out = T.renderMarkdown('a\x1b[31mb\x07c\x1b]0;title\x07', 40).join('')
  const raw = out.split('\x1b[0').join('')
  assert.ok(!raw.includes('\x1b[31m') && !raw.includes('\x07') && !raw.includes('\x1b]'), JSON.stringify(out))
  assert.ok(T.stripAnsi(out).includes('a?[31mb?c?]0;title?'))
})

// ---- terminal restore ----------------------------------------------------------

test('terminal restore: LEAVE leaves the alt screen, shows the cursor, stops the mouse', () => {
  assert.ok(T.ENTER.includes('\x1b[?1049h') && T.ENTER.includes('\x1b[?1000h') && T.ENTER.includes('\x1b[?1006h'))
  assert.ok(T.LEAVE.includes('\x1b[?1049l'), 'LEAVE does not leave the alt screen')
  assert.ok(T.LEAVE.includes('\x1b[?25h'), 'LEAVE does not show the cursor')
  assert.ok(T.LEAVE.includes('\x1b[?1000l') && T.LEAVE.includes('\x1b[?1006l'), 'LEAVE does not stop the mouse')
  const written = []
  const raw = []
  const restore = T.makeRestore((s) => written.push(s), (on) => raw.push(on))
  restore()
  restore()
  assert.deepStrictEqual(written, [T.LEAVE])
  assert.deepStrictEqual(raw, [false])
  const late = []
  T.makeRestore((s) => late.push(s), () => {
    throw new Error('stdin closed')
  })()
  assert.deepStrictEqual(late, [T.LEAVE], 'a failing raw-mode reset skipped LEAVE')
})

fs.rmSync(root, { recursive: true, force: true })
process.stdout.write(`apex-board tui: ${passed} tests passed\n`)
