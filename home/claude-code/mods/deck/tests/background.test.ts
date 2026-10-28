// The background agents panel: the pure readers of ~/.claude/session-state/<name>.json, then the
// panel drawn from a mocked session-state folder, polled only while the pane is open.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { BG_KEEP_MS, SESSION_NAME, bgCounts, bgSummary, bgWord, inProject, parseSessionState, projectOf, recentBg, sessionKind, sortBg } from '../hooks/background'
import { BG_NAME_MIN, bgRowFit, fmtAge } from '../hooks/core'
import type { DeckBgAgent } from '../types'

const NOW = 1_000_000_000_000

const row = (o: Partial<DeckBgAgent> & Pick<DeckBgAgent, 'id' | 'state'>): DeckBgAgent => ({
  name: o.id,
  cwd: '/p/x',
  project: 'x',
  kind: sessionKind(o.state),
  detail: '',
  intent: '',
  updatedAt: NOW,
  ...o,
})

// ---------------------------------------------------------------- pure

test('the five state words are their kinds, exact case; any other word is other and shows as itself', () => {
  expect(['needs-you', 'waiting', 'idle', 'working', 'done', 'Working', 'blocked', 'stalled', ''].map(sessionKind)).toEqual([
    'needs-you',
    'waiting',
    'idle',
    'working',
    'done',
    'other',
    'other',
    'other',
    'other',
  ])
  expect(bgWord({ kind: 'needs-you', state: 'needs-you' })).toBe('needs you')
  expect(bgWord({ kind: 'other', state: 'paused' })).toBe('paused')
  expect(bgWord({ kind: 'waiting', state: 'waiting' })).toBe('waiting')
})

test('a session name is claude-dispatch\'s rule', () => {
  expect(['fix-vin', 'a', '0-x', 'a'.repeat(48)].every(n => SESSION_NAME.test(n))).toBe(true)
  expect(['', '-x', 'Fix', 'a_b', 'a.b', '.fix.json.1.2.tmp', 'a'.repeat(49), 'a b', 'a\n'].some(n => SESSION_NAME.test(n))).toBe(false)
})

// The file session-state.js writes, as it writes it.
const STATE = {
  name: 'fix-vin',
  state: 'needs-you',
  event: 'Notification',
  updatedAt: '2026-10-20T09:00:00.000Z',
  cwd: '/Users/a/projects/Preliz/.claude/worktrees/fix-vin',
  sessionId: 'a0000000-0000-4000-8000-000000000000',
  transcriptPath: '/x.jsonl',
  intent: 'Fix the\n  VIN  decoder',
  notice: 'Claude needs your permission to use Bash',
}

test('a state file parses defensively: no object, no string state or cwd, a name not its stem → null', () => {
  expect(parseSessionState('fix-vin', JSON.stringify(STATE))).toEqual({
    id: 'fix-vin',
    name: 'fix-vin',
    cwd: STATE.cwd,
    project: 'Preliz',
    state: 'needs-you',
    kind: 'needs-you',
    detail: 'Claude needs your permission to use Bash',
    intent: 'Fix the VIN decoder',
    updatedAt: Date.parse('2026-10-20T09:00:00.000Z'),
  })
  expect(parseSessionState('fix-vin', '{not json')).toBe(null)
  expect(parseSessionState('fix-vin', '[]')).toBe(null)
  expect(parseSessionState('fix-vin', 'null')).toBe(null)
  expect(parseSessionState('fix-vin', JSON.stringify({ ...STATE, cwd: undefined }))).toBe(null)
  expect(parseSessionState('fix-vin', JSON.stringify({ ...STATE, state: 3 }))).toBe(null)
  expect(parseSessionState('other', JSON.stringify(STATE))).toBe(null) // name ≠ stem
  expect(parseSessionState('fix-vin', JSON.stringify({ ...STATE, name: undefined }))).toBe(null)
  expect(parseSessionState('-x', JSON.stringify({ ...STATE, name: '-x' }))).toBe(null) // no session name
  const bare = parseSessionState('fix-vin', JSON.stringify({ name: 'fix-vin', state: 'paused', cwd: '/x', updatedAt: 'soon', intent: 3 }))
  expect([bare?.kind, bare?.updatedAt, bare?.detail, bare?.intent]).toEqual(['other', 0, '', ''])
  // A credential in the notice or the intent is masked before it reaches state.
  const leak = parseSessionState('fix-vin', JSON.stringify({ ...STATE, notice: 'export API_KEY=sk-abcdefghijkl1234', intent: 'use API_KEY=sk-abcdefghijkl1234' }))
  expect(`${leak?.detail} ${leak?.intent}`).not.toContain('abcdefghijkl')
})

test('the project is the folder name, a worktree read as its repo', () => {
  expect(projectOf('/Users/a/projects/Preliz')).toBe('Preliz')
  expect(projectOf('/Users/a/projects/Preliz/')).toBe('Preliz')
  expect(projectOf('/Users/a/projects/Preliz/.claude/worktrees/fix-vin')).toBe('Preliz')
  expect(projectOf('/')).toBe('/')
})

test('needs-you first, then waiting, idle, working, other, done; newest first within a kind', () => {
  const list = [
    row({ id: 'd', state: 'done' }),
    row({ id: 'w-old', state: 'working', updatedAt: NOW - 10 }),
    row({ id: 'i', state: 'idle' }),
    row({ id: 'o', state: 'paused' }),
    row({ id: 'n', state: 'needs-you' }),
    row({ id: 'w-new', state: 'working' }),
    row({ id: 'a', state: 'waiting' }),
  ]
  expect(sortBg(list).map(a => a.id)).toEqual(['n', 'a', 'i', 'w-new', 'w-old', 'o', 'd'])
  expect(bgCounts(list)).toEqual({ 'needs-you': 1, waiting: 1, idle: 1, working: 2, other: 1, done: 1 })
  expect(bgSummary(list).map(p => p.text)).toEqual(['1 needs you', '1 waiting', '1 idle', '2 working', '1 other', '1 done'])
  expect(bgSummary(list.slice(0, 2)).map(p => p.text)).toEqual(['1 working', '1 done'])
})

test('a session silent over 24 h leaves, done or not; the others stay', () => {
  const old = NOW - BG_KEEP_MS - 1
  const list = [
    row({ id: 'd', state: 'done', updatedAt: old }),
    row({ id: 'w', state: 'working', updatedAt: old }),
    row({ id: 'n', state: 'needs-you', updatedAt: old }),
    row({ id: 'd-new', state: 'done', updatedAt: NOW - 1000 }),
    row({ id: 'edge', state: 'waiting', updatedAt: NOW - BG_KEEP_MS }),
  ]
  expect(recentBg(list, NOW).map(a => a.id)).toEqual(['d-new', 'edge'])
})

test('only the sessions of the current project: its root, a subfolder, one of its worktrees', () => {
  const list = [
    row({ id: 'root', state: 'working', cwd: '/p/repo' }),
    row({ id: 'sub', state: 'working', cwd: '/p/repo/web' }),
    row({ id: 'wt', state: 'working', cwd: '/p/repo/.claude/worktrees/x' }),
    row({ id: 'other', state: 'working', cwd: '/p/other' }),
    row({ id: 'prefix', state: 'working', cwd: '/p/repo-2' }),
  ]
  expect(inProject(list, '/p/repo').map(a => a.id)).toEqual(['root', 'sub', 'wt'])
  expect(inProject(list, '/p/repo/.claude/worktrees/y').map(a => a.id)).toEqual(['root', 'sub', 'wt'])
})

test('a background row at panel width 54 keeps at least 16 cells for the name: no project, the arrow only', () => {
  const narrow = bgRowFit(54)
  expect(narrow.nameCols >= BG_NAME_MIN).toBe(true)
  expect([narrow.hasProject, narrow.pick]).toEqual([false, ' ↗'])
  // Wide enough for everything: the project and the full label, the name still at 16 or more.
  const roomy = bgRowFit(72)
  expect([roomy.hasProject, roomy.pick, roomy.nameCols]).toEqual([true, ' ↗ afficher', 16])
  expect(bgRowFit(71).hasProject).toBe(false)
})

test('a background age is whole minutes', () => {
  expect([0, 29_000, 30_000, 60_000, 89_000, 12 * 60_000, 3 * 3_600_000 + 5 * 60_000 + 20_000, 24 * 3_600_000].map(fmtAge)).toEqual([
    '<1m',
    '<1m',
    '1m',
    '1m',
    '1m',
    '12m',
    '3h05m',
    '24h00m',
  ])
})

// ---------------------------------------------------------------- through the hooks

const ROOT = '/home/u/.claude/session-state'

/** One listing entry: `text` absent = it vanishes before its read; `link` = a symbolic link. */
type Entry = { name: string; mtimeMs: number; text?: string; link?: boolean; size?: number; kind?: 'file' | 'dir' | 'other' }

/** `entries` absent = no session-state folder; `rootLink` = the folder is a link. */
type World = { entries?: Entry[]; rootLink?: boolean; listed: number; reads: string[] }

// The session runs at the root of Preliz; a session's cwd defaults to that root.
const HERE = '/Users/a/projects/Preliz'

const state = (name: string, o: Record<string, unknown>) =>
  JSON.stringify({ name, event: 'Stop', cwd: HERE, sessionId: 's', transcriptPath: '/t', intent: '', notice: '', updatedAt: new Date(NOW - 60_000).toISOString(), ...o })

const file = (name: string, mtimeMs: number, o: Record<string, unknown>): Entry => ({ name: `${name}.json`, mtimeMs, text: state(name, o) })

function world(on: On, w: World): void {
  on('session.start', () => ({ cwd: HERE }))
  on('session.cwd', () => ({ value: HERE }))
  on('env.get', () => ({ value: '/home/u' }))
  on('command.register', () => ({ value: { command: 'deck' } }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 1 } } }))
  on('agent.list', () => ({ value: [] }))
  on('fs.list', (_$, e) => {
    if (e.path === ROOT && w.entries !== undefined) {
      w.listed += 1
      return {
        value: w.entries.map(x => ({
          name: x.name,
          kind: x.link === true ? ('other' as const) : (x.kind ?? ('file' as const)),
          size: x.size ?? (x.text ?? '').length,
          mtimeMs: x.mtimeMs,
          isLink: x.link === true,
        })),
      }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    if (e.path === ROOT && w.entries !== undefined) return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: w.rootLink === true } }
    const x = w.entries?.find(y => e.path === `${ROOT}/${y.name}`)
    if (x === undefined) throw new Error('ENOENT')
    return { value: { kind: x.kind ?? 'file', size: x.size ?? (x.text ?? '').length, mtimeMs: x.mtimeMs, isLink: x.link === true } }
  })
  on('fs.read', (_$, e) => {
    const x = w.entries?.find(y => e.path === `${ROOT}/${y.name}`)
    if (x !== undefined) w.reads.push(x.name)
    if (x?.text === undefined) throw new Error('ENOENT')
    return { value: x.text }
  })
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.close', () => ({ value: undefined }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
}

const pane = (bodyColumns: number, placement: 'dock' | 'inline' = 'dock') => ({
  plugin: 'deck',
  component: 'Pane' as const,
  requestId: 'deck',
  surface: 'terminal' as const,
  props: { title: 'Deck', isFocused: true, bodyColumns, placement, scroll: { offset: 0, bodyRows: 70 }, view: {} },
})

const deck = { command: 'deck', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } } as const
const START = { cwd: HERE, surface: 'terminal', isInteractive: true } as const

const SESSIONS: Entry[] = [
  file('s-working', NOW - 5000, { state: 'working' }),
  file('s-asks', NOW - 4000, { state: 'needs-you', notice: 'approve the plan', cwd: `${HERE}/web` }),
  file('s-paused', NOW - 3000, { state: 'paused', cwd: `${HERE}/.claude/worktrees/wt` }),
  file('s-ancient', NOW - 2000, { state: 'done', updatedAt: new Date(NOW - BG_KEEP_MS - 60_000).toISOString() }),
  { name: 's-half.json', mtimeMs: NOW - 1000, text: '{not json' },
  { name: 's-gone.json', mtimeMs: NOW - 500 },
  // Another project: read, then left out of this session's panel.
  file('s-elsewhere', NOW - 250, { state: 'working', cwd: '/Users/a/projects/nix/.claude/worktrees/wt' }),
]

test('with the pane open, only the current project shows (root, subfolder, worktree): needs-you first with its notice, an unknown state by its word; bad entries skipped', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { entries: SESSIONS, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  // 80 and 150 (two 74-col columns) leave room for the project column; 66 and 120 (two 59-col
  // columns) drop it for the name.
  for (const cols of [66, 80, 120, 150]) {
    const hasProject = cols === 80 || cols === 150
    const ui = await $.ui.mount(pane(cols))
    expect(await ui.find({ type: 'Text', text: /^background agents · 3$/ })).toBeDefined()
    const names = (await ui.findAll({ type: 'Text', text: /^s-/ })).map(t => t.text)
    expect(names).toEqual(['s-asks', 's-working', 's-paused'])
    expect(await ui.find({ type: 'Text', text: /^approve the plan$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ paused$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ needs you$/ })).toBeDefined()
    expect(await ui.findAll({ type: 'Text', text: /^ Preliz$/ })).toHaveLength(hasProject ? 2 : 0) // the root, and a worktree read as its repo
    expect((await ui.find({ type: 'Text', text: /^ web$/ })) !== undefined).toBe(hasProject) // a subfolder shows by its own name
    expect(await ui.find({ text: /s-elsewhere/ })).toBeUndefined() // another project
    expect(await ui.find({ type: 'Text', text: /^ nix$/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /^ 1m$/ })).toBeDefined() // age since updatedAt, whole minutes
    expect(await ui.find({ text: /s-ancient/ })).toBeUndefined() // silent over 24 h
    await ui.unmount()
  }
})

test('at 110 columns (two 54-col panels) a long name keeps 16 cells: no project, « ↗ », needs-you `!` bold, waiting `◌`', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const long = 'fix-the-vin-decoder-for-imported-trucks'
  const entries: Entry[] = [file(long, NOW - 2000, { state: 'needs-you' }), file('s-waits', NOW - 1000, { state: 'waiting' })]
  world(on, { entries, listed: 0, reads: [] })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(110))
  expect(await ui.find({ type: 'Text', text: long })).toBeDefined()
  // The name's box holds 16 cells at least; a shorter name holds its own length.
  expect((await ui.findAll({ type: 'Box' })).map(b => b.props.minWidth).filter(m => m !== undefined)).toEqual([BG_NAME_MIN, 's-waits'.length])
  expect(await ui.find({ type: 'Text', text: /^ Preliz$/ })).toBeUndefined()
  expect(await ui.findAll({ type: 'Text', text: /^ ↗$/ })).toHaveLength(2)
  expect(await ui.find({ type: 'Text', text: /afficher/ })).toBeUndefined()
  const asks = await ui.find({ type: 'Text', text: /^! $/ })
  expect([asks?.props.color, asks?.props.bold]).toEqual(['error', true])
  expect((await ui.find({ type: 'Text', text: /^◌ $/ }))?.props.color).toBe('warning')
  expect(await ui.find({ type: 'Text', text: /^[◆◇] $/ })).toBeUndefined()
  expect((await ui.find({ type: 'Text', text: /^ 1m$/ }))?.props.color).toBe('inactive')
  // The legend's swatch is a stroke of the border it names, not ■ (stopped).
  expect((await ui.findAll({ type: 'Text', text: /^──$/ })).length > 0).toBe(true)
  expect(await ui.find({ type: 'Text', text: /^■$/ })).toBeUndefined()
  await ui.unmount()
})

test('links, dotted temp files, invalid stems, other kinds and oversized files are never read', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const entries: Entry[] = [
    file('s-ok', NOW - 1000, { state: 'working' }),
    { ...file('s-link', NOW - 900, { state: 'working' }), link: true },
    { name: '.s-ok.json.123.456.tmp', mtimeMs: NOW - 800, text: state('s-ok', { state: 'done' }) },
    { name: 'Bad_Name.json', mtimeMs: NOW - 700, text: state('Bad_Name', { state: 'working' }) },
    { name: 's-ok.txt', mtimeMs: NOW - 600, text: state('s-ok', { state: 'working' }) },
    { ...file('s-dir', NOW - 500, { state: 'working' }), kind: 'dir' },
    { ...file('s-big', NOW - 400, { state: 'working' }), size: 64 * 1024 + 1 },
    // Named by another stem inside: parsed, then dropped.
    { name: 's-liar.json', mtimeMs: NOW - 300, text: state('s-ok', { state: 'working' }) },
  ]
  const w: World = { entries, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  expect([...new Set(w.reads)].sort()).toEqual(['s-liar.json', 's-ok.json'])
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: /^background agents · 1$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^s-ok$/ })).toBeDefined()
  await ui.unmount()
})

test('a linked session-state folder is not listed', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { entries: SESSIONS, rootLink: true, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  expect([w.listed, w.reads.length]).toEqual([0, 0])
  const ui = await $.ui.mount(pane(66))
  expect(await ui.find({ text: /background agents/ })).toBeUndefined()
  await ui.unmount()
})

test('at most 12 reads per poll, the newest files; 6 rows then +N more', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const many: Entry[] = Array.from({ length: 15 }, (_, i) => file(`s-${i}`, NOW - i * 1000, { state: 'working' }))
  const w: World = { entries: many, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  expect(w.listed > 0).toBe(true)
  expect(w.reads.length <= 12 * w.listed).toBe(true)
  expect(w.reads.includes('s-12.json')).toBe(false) // the 13th newest: never read
  const ui = await $.ui.mount(pane(66))
  expect(await ui.find({ type: 'Text', text: /^background agents · 12$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^s-0$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^s-12$/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^\+6 more$/ })).toBeDefined()
  await ui.unmount()
})

test('no session-state folder: no panel and no error; the run scan still polls', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(66))
  expect(await ui.find({ text: /· main$/ })).toBeDefined()
  expect(await ui.find({ text: /background agents/ })).toBeUndefined()
  await ui.unmount()
})

test('pane closed: a finished turn polls the run, never the session-state folder', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { entries: SESSIONS, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.turn.start({ text: 'go', turnId: 'T1' })
  await $.turn.complete({ answer: '', durationMs: 10, isAborted: false, turnId: 'T1', reason: 'answer' })
  await clock.settle()
  await clock.advance(10_000)
  expect(w.listed).toBe(0)
  // Positive control: opened, the same world is read at once.
  await $.command.run(deck)
  await clock.settle()
  expect(w.listed > 0).toBe(true)
})

test('panels config without background hides it', { options: { panels: 'main,agents,log' } }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { entries: SESSIONS, listed: 0, reads: [] })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(66))
  expect(await ui.find({ text: /background agents/ })).toBeUndefined()
  await ui.unmount()
  const mini = await $.ui.mount(pane(80, 'inline'))
  expect(await mini.find({ type: 'Text', text: /^bg: $/ })).toBeUndefined()
  await mini.unmount()
})

test('inline, one summary row in panel order', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { entries: SESSIONS, listed: 0, reads: [] })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(80, 'inline'))
  expect(await ui.find({ type: 'Text', text: /^bg: $/ })).toBeDefined()
  const parts = (await ui.findAll({ type: 'Text', text: /^\d+ (needs you|working|other)$/ })).map(t => t.text)
  expect(parts).toEqual(['1 needs you', '1 working', '1 other'])
  expect(await ui.find({ text: /background agents/ })).toBeUndefined()
  await ui.unmount()
})

test('a row pressed unfolds its intent and notice; pressed again it folds; the other rows stay folded', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const entries: Entry[] = [
    file('s-open', NOW - 2000, { state: 'waiting', intent: 'Shrink the ghost banner to a back button', notice: 'Claude is waiting for your input' }),
    file('s-other', NOW - 1000, { state: 'working', intent: 'Other intent' }),
  ]
  world(on, { entries, listed: 0, reads: [] })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: /^click: details$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Shrink the ghost banner/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^Claude is waiting/ })).toBeUndefined()
  await ui.press({ key: 'bg-s-open' })
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /^Shrink the ghost banner to a back button$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Claude is waiting for your input$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Other intent/ })).toBeUndefined()
  await ui.press({ key: 'bg-s-open' })
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /Shrink the ghost banner/ })).toBeUndefined()
  await ui.unmount()
})

// ---------------------------------------------------------------- « ↗ afficher »

type Run = { argv: readonly string[]; timeoutMs: number | undefined }

const PICKABLE: Entry[] = [
  file('s-ended', NOW - 3000, { state: 'done' }),
  file('s-waits', NOW - 2000, { state: 'waiting' }),
  file('s-runs', NOW - 1000, { state: 'working' }),
]

const PANE_BIN = '/etc/profiles/per-user/alx/bin/agent-pane'

test('« ↗ afficher » on every row not done: one agent-pane run per name at a time, exact argv, logged', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { entries: PICKABLE, listed: 0, reads: [] })
  const calls: Run[] = []
  let release: () => void = () => undefined
  const gate = new Promise<void>(r => {
    release = r
  })
  on('process.run', async (_$, e) => {
    calls.push({ argv: e.argv, timeoutMs: e.init?.timeoutMs })
    await gate
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(150))
  expect(await ui.findAll({ type: 'Text', text: /^ ↗ afficher$/ })).toHaveLength(2)
  expect(await ui.find({ key: 'bg-pick-s-waits' })).toBeDefined()
  expect(await ui.find({ key: 'bg-pick-s-runs' })).toBeDefined()
  expect(await ui.find({ key: 'bg-pick-s-ended' })).toBeUndefined() // done: nothing to show
  const first = ui.press({ key: 'bg-pick-s-waits' })
  const second = ui.press({ key: 'bg-pick-s-waits' })
  await clock.settle()
  release()
  await Promise.all([first, second])
  await clock.settle()
  expect(calls).toEqual([{ argv: [PANE_BIN, 'pick', 's-waits'], timeoutMs: 5000 }])
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /s-waits affichée en haut/ })).toBeDefined()
  await log.unmount()
})

test('a refused pick logs the exit code and agent-pane\'s first stderr line', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { entries: PICKABLE, listed: 0, reads: [] })
  on('process.run', () => ({
    value: { exitCode: 2, stdout: '', stderr: '\nagent-pane: cannot write /x/target\n', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  await ui.press({ key: 'bg-pick-s-runs' })
  await clock.settle()
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /s-runs exit 2 · agent-pane: cannot write/ })).toBeDefined()
  await log.unmount()
})

test('a pick whose command cannot start logs « échec ou pas de retour », not a silent drop', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { entries: PICKABLE, listed: 0, reads: [] })
  on('process.run', () => {
    throw new Error('spawn ENOENT')
  })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  await ui.press({ key: 'bg-pick-s-runs' })
  await clock.settle()
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /^s-runs échec ou pas de retour/ })).toBeDefined()
  await log.unmount()
})
