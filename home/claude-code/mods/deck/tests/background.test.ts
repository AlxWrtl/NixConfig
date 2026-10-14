// The background agents panel: the pure readers of ~/.claude/jobs/<id>/state.json, then the
// panel drawn from mocked jobs folders, polled only while the pane is open.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { BG_KEEP_MS, bgCounts, bgKind, bgSummary, bgWord, parseJobState, projectOf, recentBg, sortBg } from '../hooks/background'
import type { DeckBgAgent } from '../types'

const NOW = 1_000_000_000_000

const job = (o: Partial<DeckBgAgent> & Pick<DeckBgAgent, 'id' | 'state'>): DeckBgAgent => ({
  name: o.id,
  cwd: '/p/x',
  project: 'x',
  kind: bgKind(o.state),
  detail: '',
  updatedAt: NOW,
  ...o,
})

// ---------------------------------------------------------------- pure

test('state words map to kinds; an unknown word is other and shows as itself', () => {
  expect(['working', 'blocked', 'done', 'completed', 'failed', 'error', 'stopped', 'killed', 'paused'].map(bgKind)).toEqual([
    'working',
    'needs-you',
    'done',
    'done',
    'failed',
    'failed',
    'stopped',
    'stopped',
    'other',
  ])
  expect(bgWord({ kind: 'needs-you', state: 'blocked' })).toBe('needs you')
  expect(bgWord({ kind: 'other', state: 'paused' })).toBe('paused')
  expect(bgWord({ kind: 'done', state: 'completed' })).toBe('done')
})

test('a state.json parses defensively: no object, no string state or cwd → null', () => {
  const ok = parseJobState(
    'ab12cd34',
    JSON.stringify({ state: 'blocked', name: 'Fais le\nsmoke', cwd: '/Users/a/projects/carpress-ai', detail: 'wants  approval', updatedAt: '2026-08-06T05:42:11.089Z', extra: 1 }),
  )
  expect(ok).toEqual({
    id: 'ab12cd34',
    name: 'Fais le smoke',
    cwd: '/Users/a/projects/carpress-ai',
    project: 'carpress-ai',
    state: 'blocked',
    kind: 'needs-you',
    detail: 'wants approval',
    updatedAt: Date.parse('2026-08-06T05:42:11.089Z'),
  })
  expect(parseJobState('a', '{not json')).toBe(null)
  expect(parseJobState('a', '[]')).toBe(null)
  expect(parseJobState('a', 'null')).toBe(null)
  expect(parseJobState('a', JSON.stringify({ state: 'working' }))).toBe(null)
  expect(parseJobState('a', JSON.stringify({ state: 3, cwd: '/x' }))).toBe(null)
  const bare = parseJobState('ff00', JSON.stringify({ state: 'working', cwd: '/x/y', name: '  ', updatedAt: 'soon' }))
  expect([bare?.name, bare?.updatedAt, bare?.detail]).toEqual(['ff00', 0, ''])
  // A credential in the status line is masked before it reaches state.
  expect(parseJobState('a', JSON.stringify({ state: 'blocked', cwd: '/x', detail: 'export API_KEY=sk-abcdefghijkl1234' }))?.detail).not.toContain('abcdefghijkl')
})

test('the project is the folder name, a worktree read as its repo', () => {
  expect(projectOf('/Users/a/projects/Preliz')).toBe('Preliz')
  expect(projectOf('/Users/a/projects/Preliz/')).toBe('Preliz')
  expect(projectOf('/Users/a/projects/Preliz/.claude/worktrees/fix-vin')).toBe('Preliz')
  expect(projectOf('/')).toBe('/')
})

test('needs-you first, then failed, working, other, stopped, done; newest first within a kind', () => {
  const list = [
    job({ id: 'd', state: 'done' }),
    job({ id: 'w-old', state: 'working', updatedAt: NOW - 10 }),
    job({ id: 's', state: 'stopped' }),
    job({ id: 'o', state: 'paused' }),
    job({ id: 'n', state: 'blocked' }),
    job({ id: 'w-new', state: 'working' }),
    job({ id: 'f', state: 'failed' }),
  ]
  expect(sortBg(list).map(a => a.id)).toEqual(['n', 'f', 'w-new', 'w-old', 'o', 's', 'd'])
  expect(bgCounts(list)).toEqual({ 'needs-you': 1, working: 2, failed: 1, done: 1, stopped: 1, other: 1 })
  expect(bgSummary(list.slice(0, 2)).map(p => p.text)).toEqual(['1 working', '1 done'])
})

test('finished sessions leave after 24 h; the others stay however old', () => {
  const old = NOW - BG_KEEP_MS - 1
  const list = [
    job({ id: 'd', state: 'done', updatedAt: old }),
    job({ id: 's', state: 'stopped', updatedAt: old }),
    job({ id: 'n', state: 'blocked', updatedAt: old }),
    job({ id: 'd-new', state: 'done', updatedAt: NOW - 1000 }),
  ]
  expect(recentBg(list, NOW).map(a => a.id)).toEqual(['n', 'd-new'])
})

// ---------------------------------------------------------------- through the hooks

const ROOT = '/home/u/.claude/jobs'

type Job = { id: string; mtimeMs: number; text?: string }

type World = { jobs?: Job[]; listed: number; reads: number[] }

const state = (o: Record<string, unknown>) => JSON.stringify({ cwd: '/Users/a/projects/Preliz', updatedAt: new Date(NOW - 60_000).toISOString(), ...o })

function world(on: On, w: World): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('env.get', () => ({ value: '/home/u' }))
  on('command.register', () => ({ value: { command: 'deck' } }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 1 } } }))
  on('agent.list', () => ({ value: [] }))
  on('fs.list', (_$, e) => {
    if (e.path === ROOT && w.jobs !== undefined) {
      w.listed += 1
      w.reads.push(0)
      return {
        value: [
          { name: 'pins.json', kind: 'file' as const, size: 2, mtimeMs: NOW, isLink: false },
          ...w.jobs.map(j => ({ name: j.id, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false })),
        ],
      }
    }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    const j = w.jobs?.find(x => e.path === `${ROOT}/${x.id}`)
    if (j === undefined) throw new Error('ENOENT')
    return { value: { kind: 'dir', size: 0, mtimeMs: j.mtimeMs, isLink: false } }
  })
  on('fs.read', (_$, e) => {
    if (e.path.startsWith(`${ROOT}/`)) w.reads[w.reads.length - 1] = (w.reads[w.reads.length - 1] ?? 0) + 1
    const j = w.jobs?.find(x => e.path === `${ROOT}/${x.id}/state.json`)
    if (j?.text === undefined) throw new Error('ENOENT')
    return { value: j.text }
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
const START = { cwd: '/work', surface: 'terminal', isInteractive: true } as const

const JOBS: Job[] = [
  { id: 'aaaa0001', mtimeMs: NOW - 5000, text: state({ state: 'working', name: 'job working' }) },
  { id: 'aaaa0002', mtimeMs: NOW - 4000, text: state({ state: 'blocked', name: 'job blocked', detail: 'approve the plan' }) },
  { id: 'aaaa0003', mtimeMs: NOW - 3000, text: state({ state: 'paused', name: 'job paused', cwd: '/Users/a/projects/nix/.claude/worktrees/wt' }) },
  { id: 'aaaa0004', mtimeMs: NOW - 2000, text: state({ state: 'done', name: 'job ancient', updatedAt: new Date(NOW - BG_KEEP_MS - 60_000).toISOString() }) },
  { id: 'aaaa0005', mtimeMs: NOW - 1000, text: '{half-written' },
  { id: 'aaaa0006', mtimeMs: NOW - 500 },
]

test('with the pane open, every project shows: needs-you first with its status line, an unknown state by its word; bad entries skipped', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { jobs: JOBS, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  for (const cols of [66, 120]) {
    const ui = await $.ui.mount(pane(cols))
    expect(await ui.find({ type: 'Text', text: /^background agents · 3$/ })).toBeDefined()
    const names = (await ui.findAll({ type: 'Text', text: /^job / })).map(t => t.text)
    expect(names).toEqual(['job blocked', 'job working', 'job paused'])
    expect(await ui.find({ type: 'Text', text: /^approve the plan$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ paused$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ needs you$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ nix$/ })).toBeDefined() // the worktree's repo
    expect(await ui.find({ type: 'Text', text: /^ 1m00s$/ })).toBeDefined() // age since updatedAt
    expect(await ui.find({ text: /job ancient/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('at most 12 state.json reads per poll, the newest folders; 6 rows then +N more', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const many: Job[] = Array.from({ length: 15 }, (_, i) => ({
    id: `bbbb${String(i).padStart(4, '0')}`,
    mtimeMs: NOW - i * 1000,
    text: state({ state: 'working', name: `job ${i}` }),
  }))
  const w: World = { jobs: many, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  expect(w.reads.length > 0).toBe(true)
  expect(w.reads.every(n => n <= 12)).toBe(true)
  const ui = await $.ui.mount(pane(66))
  expect(await ui.find({ type: 'Text', text: /^background agents · 12$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^job 0$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^job 12$/ })).toBeUndefined() // the 13th newest: never read
  expect(await ui.find({ type: 'Text', text: /^\+6 more · claude agents$/ })).toBeDefined()
  await ui.unmount()
})

test('no jobs folder: no panel and no error; the run scan still polls', async ($, on) => {
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

test('pane closed: a finished turn polls the run, never the jobs folder', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { jobs: JOBS, listed: 0, reads: [] }
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
  world(on, { jobs: JOBS, listed: 0, reads: [] })
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
  world(on, { jobs: JOBS, listed: 0, reads: [] })
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
