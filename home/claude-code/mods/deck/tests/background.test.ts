// The background agents panel: the pure readers of ~/.claude/jobs/<id>/state.json, then the
// panel drawn from mocked jobs folders, polled only while the pane is open.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { BG_KEEP_MS, BG_TIMELINE, bgCounts, bgKind, bgSummary, bgWord, inProject, parseJobState, parseTimeline, projectOf, recentBg, sortBg } from '../hooks/background'
import type { DeckBgAgent } from '../types'

const NOW = 1_000_000_000_000

const job = (o: Partial<DeckBgAgent> & Pick<DeckBgAgent, 'id' | 'state'>): DeckBgAgent => ({
  name: o.id,
  cwd: '/p/x',
  project: 'x',
  kind: bgKind(o.state),
  detail: '',
  intent: '',
  tokens: null,
  updatedAt: NOW,
  ...o,
})

// ---------------------------------------------------------------- pure

test('state words map to kinds; an unknown word is other and shows as itself', () => {
  expect(['working', 'blocked', 'done', 'completed', 'failed', 'error', 'stopped', 'killed', 'paused'].map(s => bgKind(s))).toEqual([
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

test('a working state whose tempo is blocked is stalled, shown as its kind, sorted after needs-you', () => {
  expect([bgKind('working', 'blocked'), bgKind('working', 'idle'), bgKind('blocked', 'blocked'), bgKind('working')]).toEqual(['stalled', 'working', 'needs-you', 'working'])
  // Exact case only, as the wrapper compares: anything else is not resumable, so not stalled.
  expect([bgKind('Working', 'BLOCKED'), bgKind('working', 'Blocked'), bgKind('WORKING', 'blocked')]).toEqual(['working', 'working', 'working'])
  const parsed = parseJobState('ab12cd34', JSON.stringify({ state: 'working', tempo: 'blocked', cwd: '/x' }))
  expect(parsed?.kind).toBe('stalled')
  expect(parseJobState('ab12cd34', JSON.stringify({ state: 'working', tempo: 3, cwd: '/x' }))?.kind).toBe('working')
  expect(bgWord({ kind: 'stalled', state: 'working' })).toBe('stalled')
  const list = [job({ id: 'w', state: 'working' }), job({ id: 's', state: 'working', kind: 'stalled' }), job({ id: 'n', state: 'blocked' })]
  expect(sortBg(list).map(a => a.id)).toEqual(['n', 's', 'w'])
  expect(bgSummary(list).map(p => p.text)).toEqual(['1 needs you', '1 stalled', '1 working'])
})

// Shape of a live state.json waiting on an AskUserQuestion (job d591f567): working, tempo blocked,
// the question in `needs` and in `block.questions`.
const ASKING = {
  state: 'working',
  tempo: 'blocked',
  cwd: '/x',
  needs: 'answer: Je pousse avec --no-verify ? (Oui, --no-verify (Recommandé) · Non, je pousse moi-même)',
  block: {
    questions: [
      {
        question: 'Je pousse avec --no-verify ?',
        options: [
          { label: 'Oui, --no-verify (Recommandé)', description: 'Ne saute que l’étape base de données.' },
          { label: 'Non, je pousse moi-même', description: 'Je m’arrête ici.' },
        ],
      },
    ],
  },
}

test('a working session blocked on a question (needs, or block.questions) needs you, never stalled', () => {
  expect(parseJobState('d591f567', JSON.stringify(ASKING))?.kind).toBe('needs-you')
  expect(parseJobState('a', JSON.stringify({ ...ASKING, block: undefined }))?.kind).toBe('needs-you')
  expect(parseJobState('a', JSON.stringify({ ...ASKING, needs: undefined }))?.kind).toBe('needs-you')
  expect(parseJobState('a', JSON.stringify({ ...ASKING, needs: null }))?.kind).toBe('needs-you')
  expect([bgKind('working', 'blocked', true), bgKind('working', 'blocked', false)]).toEqual(['needs-you', 'stalled'])
  // Neither a question nor a non-empty `needs`: stalled, whatever the empty shape.
  const bare = { state: 'working', tempo: 'blocked', cwd: '/x' }
  for (const rest of [{}, { needs: null, block: null }, { needs: '' }, { block: { questions: [] } }, { needs: '', block: {} }, { needs: 3, block: { questions: 'x' } }]) {
    expect(parseJobState('a', JSON.stringify({ ...bare, ...rest }))?.kind).toBe('stalled')
  }
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
    intent: '',
    tokens: null,
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

test('intent and tokens are read when present: intent one line and redacted, tokens a finite number else null', () => {
  const full = parseJobState('a', JSON.stringify({ state: 'working', cwd: '/x', intent: 'Fix the\n  login  page', tokens: 54002 }))
  expect([full?.intent, full?.tokens]).toEqual(['Fix the login page', 54002])
  const bare = parseJobState('a', JSON.stringify({ state: 'working', cwd: '/x' }))
  expect([bare?.intent, bare?.tokens]).toEqual(['', null])
  expect(parseJobState('a', JSON.stringify({ state: 'working', cwd: '/x', intent: 3, tokens: '54002' }))?.tokens).toBe(null)
  expect(parseJobState('a', JSON.stringify({ state: 'working', cwd: '/x', intent: 'use API_KEY=sk-abcdefghijkl1234' }))?.intent).not.toContain('abcdefghijkl')
})

const tl = (at: string, detail: unknown, state = 'working') => JSON.stringify({ at, state, detail, text: '' })

test('a timeline keeps its last steps oldest first: broken lines, empty details and bad dates skipped, repeats folded', () => {
  const text = [
    tl('2026-10-15T10:59:03.541Z', ''),
    tl('2026-10-15T10:59:20.962Z', 'Finding guard  assertions'),
    '{half',
    tl('2026-10-15T10:59:30.000Z', 'Finding guard assertions'),
    tl('soon', 'no date'),
    tl('2026-10-15T11:00:01.809Z', 'Checking e2e'),
    JSON.stringify([1]),
    tl('2026-10-15T11:00:02.000Z', 42),
    tl('2026-10-15T11:01:00.000Z', 'export API_KEY=sk-abcdefghijkl1234'),
    '',
  ].join('\n')
  const events = parseTimeline(text, 10)
  expect(events.map(e => e.detail.slice(0, 14))).toEqual(['Finding guard ', 'Checking e2e', 'export API_KEY'])
  expect(events[0]?.at).toBe(Date.parse('2026-10-15T10:59:20.962Z')) // a repeat keeps its first time
  expect(events[2]?.detail).not.toContain('abcdefghijkl')
  expect(events.every((e, i) => i === 0 || (events[i - 1]?.at ?? 0) < e.at)).toBe(true)
  const many = Array.from({ length: 9 }, (_, i) => tl(new Date(NOW + i * 1000).toISOString(), `step ${i}`)).join('\n')
  expect(parseTimeline(many, BG_TIMELINE).map(e => e.detail)).toEqual(['step 4', 'step 5', 'step 6', 'step 7', 'step 8'])
  expect(parseTimeline('', 5)).toEqual([])
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
  expect(bgCounts(list)).toEqual({ 'needs-you': 1, stalled: 0, working: 2, failed: 1, done: 1, stopped: 1, other: 1 })
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

test('only the sessions of the current project: its root, a subfolder, one of its worktrees', () => {
  const list = [
    job({ id: 'root', state: 'working', cwd: '/p/repo' }),
    job({ id: 'sub', state: 'working', cwd: '/p/repo/web' }),
    job({ id: 'wt', state: 'working', cwd: '/p/repo/.claude/worktrees/x' }),
    job({ id: 'other', state: 'working', cwd: '/p/other' }),
    job({ id: 'prefix', state: 'working', cwd: '/p/repo-2' }),
  ]
  expect(inProject(list, '/p/repo').map(a => a.id)).toEqual(['root', 'sub', 'wt'])
  expect(inProject(list, '/p/repo/.claude/worktrees/y').map(a => a.id)).toEqual(['root', 'sub', 'wt'])
})

// ---------------------------------------------------------------- through the hooks

const ROOT = '/home/u/.claude/jobs'

type Job = { id: string; mtimeMs: number; text?: string; timeline?: string }

type World = { jobs?: Job[]; listed: number; reads: number[]; timelineReads?: number }

// The session runs at the root of Preliz; a job's cwd defaults to that root.
const HERE = '/Users/a/projects/Preliz'

const state = (o: Record<string, unknown>) => JSON.stringify({ cwd: HERE, updatedAt: new Date(NOW - 60_000).toISOString(), ...o })

function world(on: On, w: World): void {
  on('session.start', () => ({ cwd: HERE }))
  on('session.cwd', () => ({ value: HERE }))
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
    const t = w.jobs?.find(x => e.path === `${ROOT}/${x.id}/timeline.jsonl`)
    if (t !== undefined) {
      w.timelineReads = (w.timelineReads ?? 0) + 1
      if (t.timeline === undefined) throw new Error('ENOENT')
      return { value: t.timeline }
    }
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
const START = { cwd: HERE, surface: 'terminal', isInteractive: true } as const

const JOBS: Job[] = [
  { id: 'aaaa0001', mtimeMs: NOW - 5000, text: state({ state: 'working', name: 'job working' }) },
  { id: 'aaaa0002', mtimeMs: NOW - 4000, text: state({ state: 'blocked', name: 'job blocked', detail: 'approve the plan', cwd: `${HERE}/web` }) },
  { id: 'aaaa0003', mtimeMs: NOW - 3000, text: state({ state: 'paused', name: 'job paused', cwd: `${HERE}/.claude/worktrees/wt` }) },
  { id: 'aaaa0004', mtimeMs: NOW - 2000, text: state({ state: 'done', name: 'job ancient', updatedAt: new Date(NOW - BG_KEEP_MS - 60_000).toISOString() }) },
  { id: 'aaaa0005', mtimeMs: NOW - 1000, text: '{half-written' },
  { id: 'aaaa0006', mtimeMs: NOW - 500 },
  // Another project: read, then left out of this session's panel.
  { id: 'aaaa0007', mtimeMs: NOW - 250, text: state({ state: 'working', name: 'job elsewhere', cwd: '/Users/a/projects/nix/.claude/worktrees/wt' }) },
]

test('with the pane open, only the current project shows (root, subfolder, worktree): needs-you first with its status line, an unknown state by its word; bad entries skipped', async ($, on) => {
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
    expect(await ui.findAll({ type: 'Text', text: /^ Preliz$/ })).toHaveLength(2) // the root, and a worktree read as its repo
    expect(await ui.find({ type: 'Text', text: /^ web$/ })).toBeDefined() // a subfolder shows by its own name
    expect(await ui.find({ text: /job elsewhere/ })).toBeUndefined() // another project
    expect(await ui.find({ type: 'Text', text: /^ nix$/ })).toBeUndefined()
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

test('a row pressed unfolds intent, status, tokens and its last steps; pressed again it folds; only its timeline is read', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const at = (ms: number) => new Date(NOW - ms).toISOString()
  const timeline = [tl(at(90_000), 'Finding guard assertions'), tl(at(80_000), 'Finding guard assertions'), tl(at(70_000), 'Checking e2e references'), '{half'].join('\n')
  const jobs: Job[] = [
    { id: 'cccc0001', mtimeMs: NOW - 2000, text: state({ state: 'working', name: 'job open', detail: 'Writing the note', intent: 'Shrink the ghost banner to a back button', tokens: 54002 }), timeline },
    { id: 'cccc0002', mtimeMs: NOW - 1000, text: state({ state: 'blocked', name: 'job other', detail: 'approve the plan' }), timeline: tl(at(1000), 'other step') },
  ]
  const w: World = { jobs, listed: 0, reads: [] }
  world(on, w)
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  expect(w.timelineReads ?? 0).toBe(0) // nothing unfolded: no timeline read
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: /^click: details$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Shrink the ghost banner/ })).toBeUndefined()
  await ui.press({ key: 'bg-cccc0001' })
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /^Shrink the ghost banner to a back button$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Writing the note$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^54k tok · cccc0001$/ })).toBeDefined()
  expect(await ui.findAll({ type: 'Text', text: /^\d\d:\d\d Finding guard assertions$/ })).toHaveLength(1) // a repeat folded
  expect(await ui.find({ type: 'Text', text: /^\d\d:\d\d Checking e2e references$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /other step/ })).toBeUndefined() // the other row stays folded
  expect(await ui.find({ type: 'Text', text: /^approve the plan$/ })).toBeDefined()
  expect(w.timelineReads).toBe(1)
  await ui.press({ key: 'bg-cccc0001' })
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /Shrink the ghost banner/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /Checking e2e references/ })).toBeUndefined()
  await ui.unmount()
})

test('an unfolded row without a timeline file still shows its intent and tokens', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const jobs: Job[] = [{ id: 'dddd0001', mtimeMs: NOW - 2000, text: state({ state: 'working', name: 'job bare', intent: 'Do the thing' }) }]
  world(on, { jobs, listed: 0, reads: [] })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  await ui.press({ key: 'bg-dddd0001' })
  await clock.settle()
  expect(await ui.find({ type: 'Text', text: /^Do the thing$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^dddd0001$/ })).toBeDefined() // no tokens: the id alone
  await ui.unmount()
})

// ---------------------------------------------------------------- resume a stalled row

type Run = { argv: readonly string[]; timeoutMs: number | undefined }

const STALLED: Job[] = [
  { id: 'eeee0001', mtimeMs: NOW - 2000, text: state({ state: 'working', tempo: 'blocked', name: 'job stalled' }) },
  { id: 'eeee0002', mtimeMs: NOW - 1000, text: state({ state: 'working', name: 'job running' }) },
]

const BG_BIN = '/etc/profiles/per-user/alx/bin/claude-bg'

test('« ↻ relancer » on a stalled row only: one wrapper run per id at a time, logged, the panel read again', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { jobs: STALLED, listed: 0, reads: [] }
  world(on, w)
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
  const ui = await $.ui.mount(pane(120))
  expect(await ui.findAll({ type: 'Text', text: /^ ↻ relancer$/ })).toHaveLength(1)
  expect(await ui.find({ type: 'Text', text: /^ stalled$/ })).toBeDefined()
  expect(await ui.find({ key: 'bg-resume-eeee0002' })).toBeUndefined()
  const listedBefore = w.listed
  const first = ui.press({ key: 'bg-resume-eeee0001' })
  const second = ui.press({ key: 'bg-resume-eeee0001' })
  await clock.settle()
  release()
  await Promise.all([first, second])
  await clock.settle()
  expect(calls).toEqual([{ argv: [BG_BIN, 'resume', 'eeee0001'], timeoutMs: 60000 }])
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /eeee0001 relancé/ })).toBeDefined()
  expect(w.listed > listedBefore).toBe(true)
  await log.unmount()
})

test('a working row blocked on a question shows needs you and carries no « ↻ relancer »', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const jobs: Job[] = [
    { id: 'ffff0001', mtimeMs: NOW - 2000, text: state({ ...ASKING, cwd: HERE, name: 'job asking' }) },
    { id: 'ffff0002', mtimeMs: NOW - 1000, text: state({ state: 'working', tempo: 'blocked', name: 'job stalled' }) },
  ]
  world(on, { jobs, listed: 0, reads: [] })
  const calls: string[][] = []
  on('process.run', (_$, e) => {
    calls.push([...e.argv])
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: /^ needs you$/ })).toBeDefined()
  expect(await ui.find({ key: 'bg-resume-ffff0001' })).toBeUndefined()
  expect(await ui.find({ key: 'bg-resume-ffff0002' })).toBeDefined()
  expect(await ui.findAll({ type: 'Text', text: /^ ↻ relancer$/ })).toHaveLength(1)
  expect(calls).toEqual([])
  await ui.unmount()
})

test('a refused resume logs the exit code and the wrapper\'s first stderr line', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { jobs: STALLED, listed: 0, reads: [] })
  on('process.run', () => ({
    value: { exitCode: 2, stdout: '', stderr: '\nclaude-bg: job eeee0001 is working/idle, not stalled\n', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  await ui.press({ key: 'bg-resume-eeee0001' })
  await clock.settle()
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /eeee0001 exit 2 · claude-bg:/ })).toBeDefined()
  await log.unmount()
})

test('a resume whose command cannot start logs « échec ou pas de retour », not a silent drop', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { jobs: STALLED, listed: 0, reads: [] })
  on('process.run', () => {
    throw new Error('spawn ENOENT')
  })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  await ui.press({ key: 'bg-resume-eeee0001' })
  await clock.settle()
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /^eeee0001 échec ou pas de retour/ })).toBeDefined()
  await log.unmount()
})

// ---------------------------------------------------------------- open any row in a new window

test('« ⧉ ouvrir » on every row, before « ↻ relancer »: one wrapper run per id at a time, logged', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { jobs: STALLED, listed: 0, reads: [] })
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
  const ui = await $.ui.mount(pane(120))
  expect(await ui.findAll({ type: 'Text', text: /^ ⧉ ouvrir$/ })).toHaveLength(2)
  expect(await ui.find({ key: 'bg-open-eeee0001' })).toBeDefined()
  expect(await ui.find({ key: 'bg-open-eeee0002' })).toBeDefined()
  const labels = (await ui.findAll({ type: 'Text', text: /^ (⧉ ouvrir|↻ relancer)$/ })).map(t => t.text)
  expect(labels).toEqual([' ⧉ ouvrir', ' ↻ relancer', ' ⧉ ouvrir'])
  const first = ui.press({ key: 'bg-open-eeee0002' })
  const second = ui.press({ key: 'bg-open-eeee0002' })
  await clock.settle()
  release()
  await Promise.all([first, second])
  await clock.settle()
  expect(calls).toEqual([{ argv: [BG_BIN, 'open', 'eeee0002'], timeoutMs: 15000 }])
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /eeee0002 ouvert/ })).toBeDefined()
  await log.unmount()
})

test('a refused open logs the exit code and the wrapper\'s first stderr line; one that cannot start logs « échec »', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { jobs: STALLED, listed: 0, reads: [] })
  let n = 0
  on('process.run', () => {
    n += 1
    // A throwing test hook is skipped: the engine then reports no implementation, an Error.
    if (n > 1) throw new Error('spawn ENOENT')
    return { value: { exitCode: 2, stdout: '', stderr: '\nclaude-bg: no job eeee0001\n', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  await $.session.start(START)
  await $.command.run(deck)
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  await ui.press({ key: 'bg-open-eeee0001' })
  await clock.settle()
  await ui.press({ key: 'bg-open-eeee0002' })
  await clock.settle()
  await ui.unmount()
  const log = await $.ui.mount(pane(120))
  expect(await log.find({ type: 'Text', text: /eeee0001 exit 2 · claude-bg:/ })).toBeDefined()
  expect(await log.find({ type: 'Text', text: /^eeee0002 échec · ./ })).toBeDefined()
  await log.unmount()
})
