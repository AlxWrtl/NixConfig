// The APEX block and the commands, through the hooks: a live run read from mocked files, the
// block drawn first and only while the run is live, its phase moves in the log as `apex`.
import { expect, mock, test } from 'claude-code/testing'
import type { ElementQuery, FoundElement } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = 1_000_000_000

const pane = (bodyColumns: number, surface: 'terminal' | 'mobile' = 'terminal') => ({
  plugin: 'deck',
  component: 'Pane' as const,
  requestId: 'deck',
  surface,
  props: {
    title: 'Deck',
    isFocused: true,
    bodyColumns,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 70 },
    view: {},
  },
})

const context = (current: '03-execute' | '04-validate') => `# APEX: run under test
Tier: Standard (mods UI) — files under mods/
Branch: feat/test

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 02-plan | skipped | |
| 03-execute | ${current === '03-execute' ? 'in progress' : 'complete'} | |
| 04-validate | ${current === '04-validate' ? 'in progress' : 'pending'} | |
| 09-finish | pending | |
`

const VERDICT = JSON.stringify({ verdict: 'FAIL', findings: [{ problem: 'a' }, { problem: 'b' }] })

const command = (name: string) =>
  ({ command: name, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } }) as const

const STEP_RESULT = {
  turnId: 't1',
  index: 0,
  answer: '',
  toolUses: [],
  stopReason: 'tool_use',
  usage: { input_tokens: 1_000, output_tokens: 3_400, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, model: 'claude-opus-5-5' },
} as const

// A turn.step stream read to its end (the kit's top-level stream hands the result as the final value).
async function drain<C, R>(stream: AsyncGenerator<C, R>): Promise<R> {
  let step = await stream.next()
  while (step.done !== true) step = await stream.next()
  return step.value
}

type Mounted = { findAll: (q: ElementQuery) => Promise<FoundElement[]> }

// What a Client's surface module drew, as text (a shell's clock).
async function drawn(ui: Mounted, key: string): Promise<string> {
  return (await ui.findAll({ type: 'Text', in: key })).map(t => t.text).join('')
}

// ui.find matches a string text by inclusion: anchor what must be exact.
const exact = (text: string): RegExp => new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)

// A folder without 00-context.md: its files, and its own mtime (its newest file's when absent).
type Bare = { name: string; files: { name: string; mtimeMs: number }[]; dirMtimeMs?: number }

type World = {
  // The run's files: absent → no .claude/output/apex at all.
  run?: { current: '03-execute' | '04-validate'; mtimeMs?: number; verdict?: string; rounds?: number }
  // A second run folder, .claude/output/apex/<name>, holding these files and no 00-context.md.
  bare?: Bare
  // More folders without 00-context.md, beside `bare`.
  others?: Bare[]
  // HEAD's branch (feat/test when absent).
  head?: string
  opened: unknown[]
  statuses: number
  // Reads of the run folders (fs.list of .claude/output/apex): one per poll.
  polls: number
}

const fresh = (run?: World['run']): World => ({ ...(run === undefined ? {} : { run }), opened: [], statuses: 0, polls: 0 })

const APEX_ROOT = '/work/.claude/output/apex'

const bareDirs = (w: World): Bare[] => [...(w.bare === undefined ? [] : [w.bare]), ...(w.others ?? [])]

// /work with (or without) a live run in .claude/output/apex/my-run, HOME at /home/u. A missing
// path throws, so the host's read of it rejects.
function world(on: On, w: World): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('env.get', () => ({ value: '/home/u' }))
  on('command.register', () => ({ value: { command: 'deck' } }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('agent.list', () => ({ value: [] }))
  on('fs.list', (_$, e) => {
    if (e.path === '/work/.claude/output/apex') w.polls += 1
    const r = w.run
    const bares = bareDirs(w)
    if (bares.length > 0 && e.path === APEX_ROOT)
      return {
        value: [
          ...(r === undefined ? [] : [{ name: 'my-run', kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false }]),
          ...bares.map(b => ({ name: b.name, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false })),
        ],
      }
    const b = bares.find(d => e.path === `${APEX_ROOT}/${d.name}`)
    if (b !== undefined)
      return { value: b.files.map(f => ({ name: f.name, kind: 'file' as const, size: 1, mtimeMs: f.mtimeMs, isLink: false })) }
    if (r === undefined) throw new Error('ENOENT')
    if (e.path === '/work/.claude/output/apex') return { value: [{ name: 'my-run', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
    if (e.path === '/work/.claude/output/apex/my-run' && r.verdict !== undefined)
      return { value: [{ name: 'external-verify.json', kind: 'file', size: 1, mtimeMs: 1, isLink: false }] }
    if (e.path === '/home/u/.claude/apex-correction-budget')
      return { value: Array.from({ length: r.rounds ?? 0 }, (_, i) => ({ name: `my-run.round${i + 1}`, kind: 'file', size: 0, mtimeMs: 0, isLink: false })) }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    for (const b of bareDirs(w)) {
      if (e.path === `${APEX_ROOT}/${b.name}`)
        return { value: { kind: 'dir', size: 0, mtimeMs: b.dirMtimeMs ?? Math.max(0, ...b.files.map(f => f.mtimeMs)), isLink: false } }
      if (!e.path.startsWith(`${APEX_ROOT}/${b.name}/`)) continue
      const file = b.files.find(f => e.path === `${APEX_ROOT}/${b.name}/${f.name}`)
      if (file === undefined) throw new Error('ENOENT')
      return { value: { kind: 'file', size: 1, mtimeMs: file.mtimeMs, isLink: false } }
    }
    return { value: { kind: 'file', size: 10, mtimeMs: w.run?.mtimeMs ?? NOW - 1000, isLink: false } }
  })
  on('fs.read', (_$, e) => {
    const r = w.run
    if (r !== undefined && e.path.endsWith('/external-verify.json') && r.verdict !== undefined) return { value: r.verdict }
    if (r !== undefined && e.path === `${APEX_ROOT}/my-run/00-context.md`) return { value: context(r.current) }
    if (e.path === '/work/.git/HEAD') return { value: `ref: refs/heads/${w.head ?? 'feat/test'}\n` }
    throw new Error('ENOENT')
  })
  on('ui.open', (_$, e) => {
    w.opened.push({ id: e.id, title: e.title })
    return { value: { isPlaced: true } }
  })
  on('ui.close', () => ({ value: undefined }))
  on('ui.status', () => {
    w.statuses += 1
    return { value: undefined }
  })
  on('session.end', () => ({ sessionId: 's1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
}

const START = { cwd: '/work', surface: 'terminal', isInteractive: true } as const

type Clock = { settle: () => Promise<unknown> }

// /deck: the pane opens and the run folders are polled at once.
async function openDeck($: { command: { run: (c: ReturnType<typeof command>) => Promise<unknown> } }, clock: Clock): Promise<void> {
  await $.command.run(command('deck'))
  await clock.settle()
}

const inline = (bodyColumns: number, surface: 'terminal' | 'mobile') => ({
  ...pane(bodyColumns, surface),
  props: { ...pane(bodyColumns, surface).props, placement: 'inline' as const },
})

test('without a live run there is no APEX block, no frame, no legend entry; a stale run neither', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh()
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ text: /· main$/ })).toBeDefined()
  expect(await ui.find({ text: /^APEX/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact(' apex') })).toBeUndefined()
  await ui.unmount()

  // A run whose context file has not moved for 6 hours is not live either.
  w.run = { current: '03-execute', mtimeMs: NOW - 7 * 60 * 60 * 1000 }
  await clock.advance(5000)
  const stale = await $.ui.mount(pane(120))
  expect(await stale.find({ text: /^APEX/ })).toBeUndefined()
  await stale.unmount()

  // Positive control: the same run, its file just written, draws.
  w.run = { current: '03-execute' }
  await clock.advance(5000)
  const live = await $.ui.mount(pane(120))
  expect(await live.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })).toBeDefined()
  await live.unmount()
})

test('a live run folder without 00-context.md draws, dock and inline: the folder as header, no tier, its newest file current', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { ...fresh(), bare: { name: '04-nav-flottante', files: [{ name: '02-plan.md', mtimeMs: NOW - 1000 }] } }
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  for (const mount of [pane(120), inline(80, 'terminal')]) {
    const ui = await $.ui.mount(mount)
    expect(await ui.find({ type: 'Text', text: exact('APEX · 04-nav-flottante') })).toBeDefined()
    // The live step row stands where the phase dots were.
    expect(await ui.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: exact('◐ 02-plan') })).toBeUndefined()
    await ui.unmount()
  }

  // Its newest step file just over an hour old: not live (a context file would be for 6 hours).
  w.bare = { name: '04-nav-flottante', files: [{ name: '02-plan.md', mtimeMs: NOW - 61 * 60 * 1000 }] }
  await clock.advance(5000)
  await clock.advance(5000)
  const stale = await $.ui.mount(pane(120))
  expect(await stale.find({ text: /^APEX/ })).toBeUndefined()
  await stale.unmount()

  // A 09-finish file: the run ended.
  w.bare = {
    name: '04-nav-flottante',
    files: [
      { name: '02-plan.md', mtimeMs: NOW - 3000 },
      { name: '09-finish.md', mtimeMs: NOW - 2000 },
    ],
  }
  await clock.advance(5000)
  await clock.advance(5000)
  const ended = await $.ui.mount(pane(120))
  expect(await ended.find({ text: /^APEX/ })).toBeUndefined()
  await ended.unmount()
})

test('a newer run folder without 00-context.md beats an older live one with it', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = {
    ...fresh({ current: '03-execute', mtimeMs: NOW - 60_000 }),
    bare: { name: 'zz-newer', files: [{ name: '02-plan.md', mtimeMs: NOW - 1000 }] },
  }
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: exact('APEX · zz-newer') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
  await ui.unmount()
})

test('a live run draws first: header with branch and tier, the step row in place of the phase dots, no token buckets', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  await $.session.start(START)
  await openDeck($, clock)
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 1 }))
  for (const cols of [64, 120]) {
    const ui = await $.ui.mount(pane(cols))
    const header = await ui.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })
    expect(header?.props.color).toBe('planMode')
    expect(header?.props.bold).toBe(true)
    for (const s of ['edit', 'gate', 'ship']) expect((await ui.find({ type: 'Text', text: exact(`○ ${s}`) }))?.props.color).toBe('inactive')
    expect(await ui.find({ text: /^[●◐○·✗] 0\d-/ })).toBeUndefined()
    expect(await ui.find({ text: /^[●◐○] \S+ \d+k$/ })).toBeUndefined()
    // First, above every panel.
    const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
    const at = texts.findIndex(t => t === 'APEX · feat/test · Standard')
    expect(at >= 0 && at < texts.findIndex(t => /· main$/.test(t))).toBe(true)
    expect(await ui.find({ type: 'Text', text: exact(' apex') })).toBeDefined()
    await ui.unmount()
  }
})

test('alerts: a red external verify and a spent correction budget, in the warning colour', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute', verdict: VERDICT, rounds: 2 }))
  await $.session.start(START)
  await openDeck($, clock)
  const ui = await $.ui.mount(pane(80))
  const verify = await ui.find({ type: 'Text', text: exact('✗ external verify FAIL · 2 findings') })
  expect(verify?.props.color).toBe('error')
  expect((await ui.find({ type: 'Text', text: exact('■ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
  await ui.unmount()
})

test('background shells: a live duration while running, the status once stopped; calls pass through unchanged', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  // What reaches the engine beneath deck: it must be the call as made.
  const seen: unknown[] = []
  on('tool.call', { tool: 'Bash' }, (_$, e) => {
    seen.push(e)
    return { result: { backgroundTaskId: 'b1' } }
  })
  on('tool.call', { tool: 'TaskStop' }, (_$, e) => {
    seen.push(e)
    return { result: { task_id: 'b1' } }
  })
  await $.session.start(START)
  await openDeck($, clock)
  const bash = { tool: 'Bash', command: 'sleep 600', description: 'long sleep', run_in_background: true, tool_use_id: 'tu-bash' } as const
  const ran = await $.tool.call(bash)
  expect(ran).toEqual({ result: { backgroundTaskId: 'b1' } })
  expect(seen[0]).toEqual(bash)
  await clock.advance(65_000)

  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: exact('long sleep') })).toBeDefined()
  expect(await drawn(ui, 'shell-clock-b1')).toBe('1:05')
  expect((await ui.find({ type: 'Text', text: exact(' running') }))?.props.color).toBe('suggestion')
  await ui.unmount()
  // Without Clients the same duration is static text.
  const flat = await $.ui.mount(pane(80, 'mobile'))
  expect(await flat.find({ type: 'Text', text: exact('1:05') })).toBeDefined()
  await flat.unmount()

  const stop = { tool: 'TaskStop', task_id: 'b1', tool_use_id: 'tu-stop' } as const
  expect(await $.tool.call(stop)).toEqual({ result: { task_id: 'b1' } })
  expect(seen[1]).toEqual(stop)
  await clock.advance(10_000)
  const after = await $.ui.mount(pane(80, 'mobile'))
  expect((await after.find({ type: 'Text', text: exact(' killed') }))?.props.color).toBe('inactive')
  expect(await after.find({ type: 'Text', text: exact('1:05') })).toBeDefined() // frozen at the stop, 10 s ago
  await after.unmount()
})

test("an architect's shells close when its turn ends without an answer", async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  on('agent.spawn', () => ({ model: 'claude-fable-5-1', agentId: 'fab1' }))
  on('tool.call', { tool: 'Bash' }, () => ({ result: { backgroundTaskId: 'b9' } }))
  await $.session.start(START)
  await $.turn.start({ text: 'review it', turnId: 'H1' })
  await $.agent.spawn({
    prompt: 'review',
    description: 'final review',
    subagentType: 'fable-advisor:fable-advisor',
    tool_use_id: 'tu9',
    provider: { plugin: 'engine', tier: 'core' as const },
    parentModel: 'claude-opus-5-5',
    background: true,
    fork: false,
  })
  // The kit types no agentId on a call; the hooks read it at run time.
  await $.tool.call({ tool: 'Bash', command: 'sleep 9', description: 'architect sleep', run_in_background: true, agentId: 'fab1' } as never)
  await $.turn.complete({ answer: '', durationMs: 10, isAborted: true, turnId: 'H1', agentId: 'fab1', reason: 'aborted' })
  await openDeck($, clock)
  const ui = await $.ui.mount(pane(80, 'mobile'))
  expect(await ui.find({ type: 'Text', text: exact('architect sleep') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact(' killed') })).toBeDefined()
  await ui.unmount()
})

test('a phase change is written to the log as apex, in its own colour; a run ends after two misses', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh({ current: '03-execute' })
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  w.run = { current: '04-validate' }
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: exact('feat/test · 03-execute') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('03-execute → 04-validate') })).toBeDefined()
  const who = await ui.findAll({ type: 'Text', text: exact('apex') })
  expect(who.length).toBe(2)
  expect(who.every(x => x.props.color === 'planMode')).toBe(true)
  await ui.unmount()

  // One miss is not an end: the block stays, nothing logged.
  w.run = undefined
  await clock.advance(5000)
  const once = await $.ui.mount(pane(80))
  expect(await once.find({ text: /^APEX/ })).toBeDefined()
  expect(await once.find({ type: 'Text', text: exact('run ended') })).toBeUndefined()
  await once.unmount()
  // The second in a row is: the block leaves, the log says so.
  await clock.advance(5000)
  const gone = await $.ui.mount(pane(80))
  expect(await gone.find({ text: /^APEX/ })).toBeUndefined()
  expect(await gone.find({ type: 'Text', text: exact('run ended') })).toBeDefined()
  await gone.unmount()
})

test('the run folders are polled only while the pane is open, plus once per finished main turn', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh({ current: '03-execute' })
  world(on, w)
  await $.session.start(START)
  await clock.advance(20_000)
  expect(w.polls).toBe(0)
  // A finished main turn polls once, the pane closed: the log's apex line is written.
  await $.turn.start({ text: 'go', turnId: 'P1' })
  await $.turn.complete({ answer: 'ok', durationMs: 10, isAborted: false, turnId: 'P1', reason: 'answer' })
  await clock.settle()
  expect(w.polls).toBe(1)
  await clock.advance(20_000)
  expect(w.polls).toBe(1)
  // Open: every 5 s.
  await openDeck($, clock)
  const opened = w.polls
  await clock.advance(10_000)
  expect(w.polls).toBe(opened + 2)
  // Closed again: no more.
  expect((await $.command.run({ ...command('deck'), args: 'close' })).text).toBe('Deck closed.')
  const closed = w.polls
  await clock.advance(20_000)
  expect(w.polls).toBe(closed)
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: exact('feat/test · 03-execute') })).toBeDefined()
  await ui.unmount()
})

test('inline, a live run takes its rows first: dots, each alert, running shells, within 8 rows', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute', verdict: VERDICT, rounds: 2 }))
  let n = 0
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: `i${++n}` }))
  on('tool.call', { tool: 'Bash' }, () => ({ result: { backgroundTaskId: 'b1' } }))
  await $.session.start(START)
  await openDeck($, clock)
  await $.turn.start({ text: 'go', turnId: 'I1' })
  for (const d of ['one', 'two', 'three', 'four', 'five']) {
    await $.agent.spawn({
      prompt: d,
      description: `task ${d}`,
      subagentType: 'general-purpose',
      tool_use_id: `tu-${d}`,
      provider: { plugin: 'engine', tier: 'core' as const },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
  }
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'long sleep', run_in_background: true })
  await clock.advance(65_000)
  for (const surface of ['terminal', 'mobile'] as const) {
    const ui = await $.ui.mount(inline(80, surface))
    const root = (await ui.drawn()) as { children?: unknown[] }
    expect((root.children ?? []).filter(Boolean).length <= 8).toBe(true)
    expect(await ui.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: exact('○ edit') }))?.props.color).toBe('inactive')
    expect(await ui.find({ type: 'Text', text: exact('○ ship') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: exact('◐ 03-execute') })).toBeUndefined()
    expect((await ui.find({ type: 'Text', text: exact('✗ external verify FAIL · 2 findings') }))?.props.color).toBe('error')
    expect((await ui.find({ type: 'Text', text: exact('■ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
    expect(await ui.find({ type: 'Text', text: exact('long sleep') })).toBeDefined()
    if (surface === 'terminal') expect(await drawn(ui, 'shell-clock-b1')).toBe('1:05')
    else expect(await ui.find({ type: 'Text', text: exact('1:05') })).toBeDefined()
    // The agents get what is left: one row, then « +4 more ».
    expect(await ui.find({ text: /^\+4 more agents/ })).toBeDefined()
    await ui.unmount()
  }
})

test('no gate and no other-loops panel, whatever runs; a plain call passes through unchanged', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  const seen: unknown[] = []
  on('tool.call', (_$, e) => {
    seen.push(e)
    return { result: {}, text: 'ok' }
  })
  await $.session.start(START)
  await openDeck($, clock)
  // A loop no card matches (a workflow agent, a fork) and a plain tool call.
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'm', messageCount: 1, agentId: 'wf1' }))
  const read = { tool: 'Read', file_path: '/x', tool_use_id: 'tu-read' } as const
  expect(await $.tool.call(read)).toEqual({ result: {}, text: 'ok' })
  expect(seen[0]).toEqual(read)
  for (const cols of [64, 120]) {
    const ui = await $.ui.mount(pane(cols))
    expect(await ui.find({ text: /permissions|GATE|other loops/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: exact(' gate') })).toBeUndefined()
    await ui.unmount()
  }
})

for (const name of ['deck', 'apex-pane', 'task-board']) {
  test(`/${name} opens the deck pane`, async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    const w = fresh()
    world(on, w)
    const answer = await $.command.run(command(name))
    expect(answer.text).toBe('Deck opened. Focus it with ctrl+x tab; 1-6 expand cards.')
    expect(w.opened).toEqual([{ id: 'deck', title: 'Deck' }])
    await clock.settle()
  })
}

test('nothing opens at session start and no status line is drawn', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh({ current: '03-execute' })
  world(on, w)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'a1' }))
  await $.session.start(START)
  await clock.settle()
  await $.turn.start({ text: 'go', turnId: 'T1' })
  await $.agent.spawn({
    prompt: 'look',
    description: 'look around',
    subagentType: 'Explore',
    tool_use_id: 'tu1',
    provider: { plugin: 'engine', tier: 'core' as const },
    parentModel: 'claude-opus-5-5',
    background: true,
    fork: false,
  })
  await clock.advance(12_000)
  expect(w.opened).toEqual([])
  expect(w.statuses).toBe(0)
})

test('a run folder without 00-context.md is hidden while HEAD is master or main', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { ...fresh(), bare: { name: '04-nav', files: [{ name: '02-plan.md', mtimeMs: NOW - 1000 }] }, head: 'master' }
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  for (const head of ['master', 'main', 'feat/x']) {
    w.head = head
    await clock.advance(5000)
    const ui = await $.ui.mount(pane(120))
    const header = await ui.find({ type: 'Text', text: /^APEX ·[^◐●○✗]*$/ })
    expect(header?.text).toBe(head === 'feat/x' ? 'APEX · 04-nav' : undefined)
    await ui.unmount()
  }
})

test('ranking: newest time wins, past the folders own mtime; the 3 ranked newest runs are listed, plus the newest context run', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = fresh()
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  const step = (at: number) => [{ name: '02-plan.md', mtimeMs: at }]
  const header = async (): Promise<string | undefined> => {
    await clock.advance(5000)
    const ui = await $.ui.mount(pane(120))
    const found = await ui.find({ type: 'Text', text: /^APEX ·[^◐●○✗]*$/ })
    await ui.unmount()
    return found?.text
  }

  // A context run newer than a bare folder wins: its tier in the header.
  w.run = { current: '03-execute', mtimeMs: NOW - 1000 }
  w.bare = { name: 'zz-old', files: step(NOW - 60_000) }
  expect(await header()).toBe('APEX · feat/test · Standard')

  // A bare folder ranked first by its own mtime, its step file older: the context run wins.
  w.run = { current: '03-execute', mtimeMs: NOW - 60_000 }
  w.bare = { name: 'zz-moved', files: step(NOW - 90_000), dirMtimeMs: NOW + 9000 }
  expect(await header()).toBe('APEX · feat/test · Standard')

  // Four bare folders: only the 3 ranked newest are listed; the newest step among them wins.
  w.run = undefined
  w.bare = undefined
  w.others = [
    { name: 'r1', files: step(NOW - 5000), dirMtimeMs: NOW - 100 },
    { name: 'r2', files: step(NOW - 7000), dirMtimeMs: NOW - 200 },
    { name: 'r3', files: step(NOW - 6000), dirMtimeMs: NOW - 300 },
    { name: 'r4', files: step(NOW + 9000), dirMtimeMs: NOW - 400 },
  ]
  expect(await header()).toBe('APEX · r1')

  // A folder without a step file takes no slot and is never chosen.
  w.others = [
    { name: 'junk', files: [{ name: 'notes.md', mtimeMs: NOW + 20_000 }], dirMtimeMs: NOW - 50 },
    { name: 'r1', files: step(NOW - 9000), dirMtimeMs: NOW - 100 },
    { name: 'r2', files: step(NOW - 8000), dirMtimeMs: NOW - 200 },
    { name: 'r3', files: step(NOW + 19_000), dirMtimeMs: NOW - 300 },
  ]
  expect(await header()).toBe('APEX · r3')

  // The newest context run is listed even when 3 bare folders rank above it.
  w.run = { current: '03-execute', mtimeMs: NOW - 60_000 }
  w.others = [
    { name: 'r1', files: step(NOW - 120_000), dirMtimeMs: NOW - 100 },
    { name: 'r2', files: step(NOW - 120_000), dirMtimeMs: NOW - 200 },
    { name: 'r3', files: step(NOW - 120_000), dirMtimeMs: NOW - 300 },
  ]
  expect(await header()).toBe('APEX · feat/test · Standard')
})

test('a new run clears the finished cards and shells; the running ones stay', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { ...fresh(), bare: { name: 'run-a', files: [{ name: '02-plan.md', mtimeMs: NOW - 1000 }] } }
  world(on, w)
  let shellN = 0
  on('tool.call', { tool: 'Bash' }, () => ({ result: { backgroundTaskId: `b${++shellN}` } }))
  on('tool.call', { tool: 'TaskStop' }, (_$, e) => ({ result: { task_id: e.task_id } }))
  let agentN = 0
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: `ag${++agentN}` }))
  await $.session.start(START)
  await openDeck($, clock)
  const agent = (description: string) => ({
    prompt: description,
    description,
    subagentType: 'Explore',
    tool_use_id: `tu-${description}`,
    provider: { plugin: 'engine', tier: 'core' as const },
    parentModel: 'claude-opus-5-5',
    background: true,
    fork: false,
  })
  await $.agent.spawn(agent('still going'))
  await $.agent.spawn(agent('all done'))
  await $.turn.complete({ answer: 'ok', durationMs: 10, isAborted: false, turnId: 'A2', agentId: 'ag2', reason: 'answer' })
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'keep running', run_in_background: true, tool_use_id: 'tu-1' })
  await $.tool.call({ tool: 'Bash', command: 'sleep 9', description: 'stop me', run_in_background: true, tool_use_id: 'tu-2' })
  await $.tool.call({ tool: 'TaskStop', task_id: 'b2', tool_use_id: 'tu-3' })

  // The same run polled again: nothing cleared.
  await clock.advance(5000)
  const same = await $.ui.mount(pane(120))
  expect(await same.find({ type: 'Text', text: exact('agents · 1 running · 2 total') })).toBeDefined()
  expect(await same.find({ type: 'Text', text: exact('stop me') })).toBeDefined()
  await same.unmount()

  // Another run folder: the finished card and shell go.
  w.bare = { name: 'run-b', files: [{ name: '03-execute.md', mtimeMs: NOW + 4000 }] }
  await clock.advance(5000)
  const next = await $.ui.mount(pane(120))
  expect(await next.find({ type: 'Text', text: exact('APEX · run-b') })).toBeDefined()
  expect(await next.find({ type: 'Text', text: exact('agents · 1 running · 1 total') })).toBeDefined()
  expect(await next.find({ type: 'Text', text: exact('keep running') })).toBeDefined()
  expect(await next.find({ type: 'Text', text: exact('stop me') })).toBeUndefined()
  await next.unmount()
})

// ---------------------------------------------------------------- session run (Skill(apex), no folder)

const skill = (name: string, n: number) => ({ tool: 'Skill', skill: name, args: `brief ${n}`, tool_use_id: `tu-skill-${n}` }) as const

// The Skill tool beneath deck: answers as the engine does, records what reached it.
function skillTool(on: On, seen: unknown[]): void {
  on('tool.call', { tool: 'Skill' }, (_$, e) => {
    seen.push(e)
    return { result: { success: true, commandName: e.skill } }
  })
}

const sessionHeader = { type: 'Text' as const, text: /^APEX ·[^◐●○✗]*$/ }

test('a main-loop Skill(apex) call without a run folder draws HEAD as header and the step row; the call passes unchanged', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh()
  world(on, w)
  const seen: unknown[] = []
  skillTool(on, seen)
  await $.session.start(START)
  await openDeck($, clock)
  const before = await $.ui.mount(pane(120))
  expect(await before.find({ text: /^APEX/ })).toBeUndefined()
  await before.unmount()

  const call = skill('apex', 1)
  expect(await $.tool.call(call)).toEqual({ result: { success: true, commandName: 'apex' } })
  expect(seen[0]).toEqual(call)
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect((await ui.find(sessionHeader))?.text).toBe('APEX · feat/test')
  expect(await ui.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('◐ apex') })).toBeUndefined()
  await ui.unmount()
})

test('the session run hides on master or main, 1 h after the last call, and on /clear or /deck reset', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh()
  world(on, w)
  skillTool(on, [])
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  for (const head of ['master', 'main', 'feat/x']) {
    w.head = head
    await clock.advance(5000)
    const ui = await $.ui.mount(pane(120))
    expect((await ui.find(sessionHeader))?.text).toBe(head === 'feat/x' ? 'APEX · feat/x' : undefined)
    await ui.unmount()
  }
  // 1 h after the last call: gone.
  await clock.advance(60 * 60 * 1000)
  const late = await $.ui.mount(pane(120))
  expect(await late.find(sessionHeader)).toBeUndefined()
  await late.unmount()

  // A new call brings it back; /clear drops it.
  await $.tool.call(skill('apex', 2))
  await clock.advance(5000)
  const back = await $.ui.mount(pane(120))
  expect((await back.find(sessionHeader))?.text).toBe('APEX · feat/x')
  await back.unmount()
  await $.session.end({ reason: 'clear', sessionId: 's1' } as never)
  await clock.advance(5000)
  const cleared = await $.ui.mount(pane(120))
  expect(await cleared.find(sessionHeader)).toBeUndefined()
  await cleared.unmount()

  // /deck reset drops it too.
  await $.tool.call(skill('apex', 3))
  await clock.advance(5000)
  expect(await $.command.run({ ...command('deck'), args: 'reset' })).toEqual({ text: 'Deck reset.' })
  await clock.advance(5000)
  const reset = await $.ui.mount(pane(120))
  expect(await reset.find(sessionHeader)).toBeUndefined()
  await reset.unmount()
})

test('a live run folder wins over the session run', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  skillTool(on, [])
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('◐ apex') })).toBeUndefined()
  await ui.unmount()
})

test("a subagent's Skill(apex), another skill or a failed call draws no session run", async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  on('tool.call', { tool: 'Skill' }, (_$, e) =>
    e.args === 'brief 3' ? { result: undefined, isError: true } : { result: { success: true, commandName: e.skill } },
  )
  await $.session.start(START)
  await openDeck($, clock)
  // The kit types no agentId on a call; the hooks read it at run time.
  await $.tool.call({ ...skill('apex', 1), agentId: 'sub1' } as never)
  await $.tool.call(skill('commit', 2))
  await $.tool.call(skill('apex', 3))
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ text: /^APEX/ })).toBeUndefined()
  await ui.unmount()
  // Positive control: the same call on the main loop draws.
  await $.tool.call(skill('apex', 4))
  await clock.advance(5000)
  const live = await $.ui.mount(pane(120))
  expect((await live.find(sessionHeader))?.text).toBe('APEX · feat/test')
  await live.unmount()
})

test('a second Skill(apex) is a new run: finished cards and shells go, running ones stay; the first clears nothing', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  skillTool(on, [])
  let shellN = 0
  on('tool.call', { tool: 'Bash' }, () => ({ result: { backgroundTaskId: `b${++shellN}` } }))
  on('tool.call', { tool: 'TaskStop' }, (_$, e) => ({ result: { task_id: e.task_id } }))
  let agentN = 0
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: `ag${++agentN}` }))
  await $.session.start(START)
  await openDeck($, clock)
  const agent = (description: string) => ({
    prompt: description,
    description,
    subagentType: 'Explore',
    tool_use_id: `tu-${description}`,
    provider: { plugin: 'engine', tier: 'core' as const },
    parentModel: 'claude-opus-5-5',
    background: true,
    fork: false,
  })
  await $.agent.spawn(agent('still going'))
  await $.agent.spawn(agent('all done'))
  await $.turn.complete({ answer: 'ok', durationMs: 10, isAborted: false, turnId: 'A2', agentId: 'ag2', reason: 'answer' })
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'keep running', run_in_background: true, tool_use_id: 'tu-1' })
  await $.tool.call({ tool: 'Bash', command: 'sleep 9', description: 'stop me', run_in_background: true, tool_use_id: 'tu-2' })
  await $.tool.call({ tool: 'TaskStop', task_id: 'b2', tool_use_id: 'tu-3' })

  // The session's first apex call: nothing cleared.
  await $.tool.call(skill('apex', 1))
  await clock.advance(5000)
  const first = await $.ui.mount(pane(120))
  expect((await first.find(sessionHeader))?.text).toBe('APEX · feat/test')
  expect(await first.find({ type: 'Text', text: exact('agents · 1 running · 2 total') })).toBeDefined()
  expect(await first.find({ type: 'Text', text: exact('stop me') })).toBeDefined()
  await first.unmount()

  // A second call: a new run.
  await clock.advance(5000)
  await $.tool.call(skill('apex', 2))
  await clock.advance(5000)
  const next = await $.ui.mount(pane(120))
  expect(await next.find({ type: 'Text', text: exact('agents · 1 running · 1 total') })).toBeDefined()
  expect(await next.find({ type: 'Text', text: exact('keep running') })).toBeDefined()
  expect(await next.find({ type: 'Text', text: exact('stop me') })).toBeUndefined()
  await next.unmount()
})

// ---------------------------------------------------------------- live steps (tool calls of the run)

// Every tool beneath deck: Skill answers as the engine does, Bash prints what `stdout` gives for
// its command, the rest answers { ok: true }.
function tools(on: On, stdout: (command: string) => string = () => ''): void {
  on('tool.call', (_$, e) => {
    if (e.tool === 'Skill') return { result: { success: true, commandName: 'apex' } }
    const command: unknown = Reflect.get(e, 'command')
    if (e.tool === 'Bash') return { result: { stdout: stdout(typeof command === 'string' ? command : ''), stderr: '', interrupted: false } }
    return { result: { ok: true } }
  })
}

const editCall = (file: string) => ({ tool: 'Edit', file_path: file, old_string: 'a', new_string: 'b' }) as const
const bash = (command: string) => ({ tool: 'Bash', command }) as const
const spawnOf = (subagentType: string, description: string) => ({
  prompt: description,
  description,
  subagentType,
  tool_use_id: `tu-${description}`,
  provider: { plugin: 'engine', tier: 'core' as const },
  parentModel: 'claude-opus-5-5',
  background: true,
  fork: false,
})

// The engine allows one unmatched tool.call observer per module: the step and the turn's edit
// count share it, and this test sees both from one call.
test('AC1/AC6: Skill(apex), an edit, a gate: ● edit ◐ gate ○ ship; a subagent Bash is no gate; the one call observer feeds steps and turn', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on)
  await $.session.start(START)
  await openDeck($, clock)
  await $.turn.start({ text: 'go', turnId: 'S1' })
  await $.tool.call(skill('apex', 1))
  // The call passes unchanged through both unfiltered tool.call observers.
  expect(await $.tool.call(editCall('/work/src/a.ts'))).toEqual({ result: { ok: true } })
  await $.tool.call({ ...bash('pnpm test'), agentId: 'sub1' } as never)
  await $.tool.call({ ...bash('git commit -m x'), agentId: 'sub1' } as never)
  await clock.advance(5000)
  // 80 columns: one column, the receipt wide enough to count the turn's edits.
  const mid = await $.ui.mount(pane(80))
  expect((await mid.find({ type: 'Text', text: exact('◐ edit') }))?.props.bold).toBe(true)
  expect(await mid.find({ type: 'Text', text: exact('○ gate') })).toBeDefined()
  expect(await mid.find({ type: 'Text', text: exact('○ ship') })).toBeDefined()
  // The turn observer counted the same edit: the two unfiltered observers both ran.
  expect(await mid.find({ text: / · 1 edit · 0 errors$/ })).toBeDefined()
  await mid.unmount()

  expect(await $.tool.call(bash('pnpm typecheck'))).toEqual({ result: { stdout: '', stderr: '', interrupted: false } })
  await clock.advance(5000)
  for (const mount of [pane(120), inline(80, 'terminal')]) {
    const ui = await $.ui.mount(mount)
    expect((await ui.find({ type: 'Text', text: exact('● edit') }))?.props.color).toBe('planMode')
    expect((await ui.find({ type: 'Text', text: exact('◐ gate') }))?.props.bold).toBe(true)
    expect((await ui.find({ type: 'Text', text: exact('○ ship') }))?.props.color).toBe('inactive')
    await ui.unmount()
  }
  // A subagent's edit marks edit.
  await $.tool.call({ ...editCall('/work/src/b.ts'), agentId: 'sub1' } as never)
  const sub = await $.ui.mount(pane(120))
  expect(await sub.find({ type: 'Text', text: exact('◐ edit') })).toBeDefined()
  expect(await sub.find({ type: 'Text', text: exact('● gate') })).toBeDefined()
  await sub.unmount()
})

test('AC2: a reviewer running shows ◐ review and its detail with a live clock; its answer sets the verdict', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on)
  on('agent.spawn', () => ({ model: 'claude-opus-5-5', agentId: 'r1' }))
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await $.agent.spawn(spawnOf('code-reviewer', 'Adversarial review'))
  await clock.advance(7000)
  const ui = await $.ui.mount(pane(120))
  expect((await ui.find({ type: 'Text', text: exact('◐ review') }))?.props.bold).toBe(true)
  expect(await ui.find({ type: 'Text', text: exact('◐ review : Adversarial review (Opus) ') })).toBeDefined()
  expect(await drawn(ui, 'step-clock')).toBe('0:07')
  await ui.unmount()

  await $.turn.complete({ answer: '## Verdict: APPROVED', durationMs: 7000, isAborted: false, turnId: 'R1', agentId: 'r1', reason: 'answer' })
  const done = await $.ui.mount(pane(120))
  expect(await done.find({ type: 'Text', text: exact('● review APPROVED') })).toBeDefined()
  expect(await done.find({ type: 'Text', text: exact('● review : APPROVED') })).toBeDefined()
  await done.unmount()
})

test('AC3: apex-verify-external output: ● Codex PASS, then Codex FAIL 2 in the warning colour', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  let verdict = 'EXTERNAL-VERIFY PASS run=r findings=0'
  tools(on, c => (c.includes('apex-verify-external') ? verdict : ''))
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await $.tool.call(bash('apex-verify-external .claude/output/apex/r'))
  await clock.advance(5000)
  const pass = await $.ui.mount(pane(120))
  expect((await pass.find({ type: 'Text', text: exact('● Codex PASS') }))?.props.color).toBe('planMode')
  await pass.unmount()
  verdict = 'EXTERNAL-VERIFY FAIL run=r findings=2'
  await $.tool.call(bash('apex-verify-external .claude/output/apex/r'))
  const fail = await $.ui.mount(pane(120))
  expect((await fail.find({ type: 'Text', text: exact('● Codex FAIL 2') }))?.props.color).toBe('error')
  await fail.unmount()
})

test('AC4: writes under .claude/output/apex are plan, not edit; git commit and gh pr are ship', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on)
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await $.tool.call({ tool: 'Write', file_path: '/work/.claude/output/apex/r/02-plan.md', content: 'x' })
  await clock.advance(5000)
  const plan = await $.ui.mount(pane(120))
  expect(await plan.find({ type: 'Text', text: exact('◐ plan') })).toBeDefined()
  expect(await plan.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
  await plan.unmount()
  await $.tool.call(bash('git commit -m "feat: x"'))
  await $.tool.call(bash('gh pr create -F body.md'))
  const ship = await $.ui.mount(pane(120))
  expect(await ship.find({ type: 'Text', text: exact('● plan') })).toBeDefined()
  expect(await ship.find({ type: 'Text', text: exact('◐ ship') })).toBeDefined()
  expect(await ship.find({ type: 'Text', text: exact('○ gate') })).toBeDefined()
  await ship.unmount()
})

test('AC5: a new Skill(apex) resets the steps; the header clock counts from that call, the task under it', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on)
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await $.tool.call(editCall('/work/src/a.ts'))
  await clock.advance(65_000)
  const first = await $.ui.mount(pane(120))
  expect((await first.find(sessionHeader))?.text).toBe('APEX · feat/test')
  expect(await drawn(first, 'apex-clock')).toBe('1:05')
  expect(await first.find({ type: 'Text', text: exact('brief 1') })).toBeDefined()
  expect(await first.find({ type: 'Text', text: exact('◐ edit') })).toBeDefined()
  await first.unmount()

  await $.tool.call(skill('apex', 2))
  await clock.advance(5000)
  const second = await $.ui.mount(pane(120))
  expect(await drawn(second, 'apex-clock')).toBe('0:05')
  expect(await second.find({ type: 'Text', text: exact('brief 2') })).toBeDefined()
  expect(await second.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
  await second.unmount()
})

test('AC5: with a live run folder the header keeps its tier and gains the call clock', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  tools(on)
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await $.tool.call(bash('nix flake check'))
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })).toBeDefined()
  expect(await drawn(ui, 'apex-clock')).toBe('0:05')
  expect(await ui.find({ type: 'Text', text: exact('◐ gate') })).toBeDefined()
  await ui.unmount()
})

// ---------------------------------------------------------------- step details (clock at rest, explanations)

test('details AC1: the run clock freezes once the main turn ends at rest (dim, no live clock); a new tool call restarts it', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on)
  await $.session.start(START)
  await openDeck($, clock)
  await $.turn.start({ text: 'go', turnId: 'C1' })
  await $.tool.call(skill('apex', 1))
  await clock.advance(30_000)
  await $.turn.complete({ answer: 'done', durationMs: 30_000, isAborted: false, turnId: 'C1', reason: 'answer' })
  for (const wait of [5000, 60_000]) {
    await clock.advance(wait)
    const ui = await $.ui.mount(pane(120))
    expect((await ui.find(sessionHeader))?.text).toBe('APEX · feat/test')
    expect((await ui.find({ type: 'Text', text: exact('0:30') }))?.props.color).toBe('inactive')
    await ui.unmount()
  }
  // New activity: the clock runs again from the call.
  await $.tool.call(editCall('/work/src/a.ts'))
  const again = await $.ui.mount(pane(120))
  expect(await drawn(again, 'apex-clock')).toBe('1:35')
  expect(await again.find({ type: 'Text', text: exact('0:30') })).toBeUndefined()
  await again.unmount()
})

test('details AC1: an agent of the run still running keeps the clock live past the turn end', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on)
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: 'i1' }))
  await $.session.start(START)
  await openDeck($, clock)
  await $.turn.start({ text: 'go', turnId: 'C2' })
  await $.tool.call(skill('apex', 1))
  await $.agent.spawn(spawnOf('frontend-expert', 'Build it'))
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 'C2', reason: 'answer' })
  await clock.advance(10_000)
  const live = await $.ui.mount(pane(120))
  expect(await drawn(live, 'apex-clock')).toBe('0:10')
  await live.unmount()
  // Its end brings the run to rest at that end.
  await $.turn.complete({ answer: 'Built.', durationMs: 10_000, isAborted: false, turnId: 'I1', agentId: 'i1', reason: 'answer' })
  await clock.advance(20_000)
  const rest = await $.ui.mount(pane(120))
  expect((await rest.find({ type: 'Text', text: exact('0:10') }))?.props.color).toBe('inactive')
  await rest.unmount()
})

test('details AC2/AC3: a step Button opens its explanation, again closes it, another switches to it; one at a time', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh())
  tools(on, c => (c.startsWith('pnpm test') ? 'ok 1\nnot ok 2\n' : c.startsWith('gh pr create') ? 'https://github.com/o/r/pull/7\n' : ''))
  on('agent.spawn', () => ({ model: 'claude-opus-5-5', agentId: 'r1' }))
  await $.session.start(START)
  await openDeck($, clock)
  await $.tool.call(skill('apex', 1))
  await $.tool.call(editCall('/work/src/a.ts'))
  await $.tool.call(editCall('/work/hooks/b.tsx'))
  await $.tool.call(bash('pnpm test'))
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: exact('src/a.ts, hooks/b.tsx') })).toBeUndefined()
  await ui.press({ key: 'step-edit' })
  expect(await ui.find({ type: 'Text', text: exact('src/a.ts, hooks/b.tsx') })).toBeDefined()
  await ui.press({ key: 'step-gate' })
  expect(await ui.find({ type: 'Text', text: exact('src/a.ts, hooks/b.tsx') })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact('$ pnpm test') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('ok · not ok 2') })).toBeDefined()
  await ui.press({ key: 'step-gate' })
  expect(await ui.find({ type: 'Text', text: exact('$ pnpm test') })).toBeUndefined()
  await ui.press({ key: 'step-ship' })
  expect(await ui.find({ type: 'Text', text: exact('not reached yet') })).toBeDefined()
  await ui.unmount()

  // Ship and review evidence, read from the hooks.
  await $.tool.call(bash('git commit -m "feat: add x"'))
  await $.tool.call(bash('gh pr create -F b.md'))
  await $.agent.spawn(spawnOf('code-reviewer', 'Adversarial review'))
  await clock.advance(7000)
  await $.turn.complete({ answer: 'NEEDS_FIXES\n\n- fix a\nnot BLOCKED', durationMs: 7000, isAborted: false, turnId: 'R1', agentId: 'r1', reason: 'answer' })
  const later = await $.ui.mount(pane(120))
  expect(await later.find({ type: 'Text', text: exact('commit: feat: add x') })).toBeDefined() // ship still open
  expect(await later.find({ type: 'Text', text: exact('PR: https://github.com/o/r/pull/7') })).toBeDefined()
  await later.press({ key: 'step-review' })
  expect(await later.find({ type: 'Text', text: exact('NEEDS_FIXES · Adversarial review (Opus) · done · 0:07') })).toBeDefined()
  expect(await later.find({ type: 'Text', text: exact('- fix a') })).toBeDefined()
  expect(await later.find({ type: 'Text', text: exact('commit: feat: add x') })).toBeUndefined()
  await later.unmount()
})

test('details AC5: inline, an open explanation stays within the 8 rows', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute', verdict: VERDICT, rounds: 2 }))
  let n = 0
  on('agent.spawn', () => ({ model: 'claude-sonnet-5-5', agentId: `i${++n}` }))
  on('tool.call', { tool: 'Bash' }, () => ({ result: { backgroundTaskId: 'b1' } }))
  await $.session.start(START)
  await openDeck($, clock)
  await $.turn.start({ text: 'go', turnId: 'I1' })
  for (const d of ['one', 'two', 'three']) await $.agent.spawn(spawnOf('general-purpose', `task ${d}`))
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'long sleep', run_in_background: true })
  await clock.advance(5000)
  const ui = await $.ui.mount(inline(80, 'terminal'))
  await ui.press({ key: 'step-gate' })
  const root = (await ui.drawn()) as { children?: unknown[] }
  expect((root.children ?? []).filter(Boolean).length <= 8).toBe(true)
  expect(await ui.find({ type: 'Text', text: exact('not reached yet') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('APEX · feat/test · Standard') })).toBeDefined()
  await ui.press({ key: 'step-gate' })
  expect(await ui.find({ type: 'Text', text: exact('not reached yet') })).toBeUndefined()
  await ui.unmount()
})
