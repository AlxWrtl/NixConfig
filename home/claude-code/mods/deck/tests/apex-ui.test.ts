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

type World = {
  // The run's files: absent → no .claude/output/apex at all.
  run?: { current: '03-execute' | '04-validate'; mtimeMs?: number; verdict?: string; rounds?: number }
  // A second run folder, .claude/output/apex/<name>, holding these files and no 00-context.md.
  bare?: { name: string; files: { name: string; mtimeMs: number }[] }
  opened: unknown[]
  statuses: number
  // Reads of the run folders (fs.list of .claude/output/apex): one per poll.
  polls: number
}

const fresh = (run?: World['run']): World => ({ ...(run === undefined ? {} : { run }), opened: [], statuses: 0, polls: 0 })

const APEX_ROOT = '/work/.claude/output/apex'

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
    const b = w.bare
    if (b !== undefined && e.path === APEX_ROOT)
      return {
        value: [
          ...(r === undefined ? [] : [{ name: 'my-run', kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false }]),
          { name: b.name, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false },
        ],
      }
    if (b !== undefined && e.path === `${APEX_ROOT}/${b.name}`)
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
    const b = w.bare
    if (b !== undefined && e.path === `${APEX_ROOT}/${b.name}`)
      return { value: { kind: 'dir', size: 0, mtimeMs: Math.max(0, ...b.files.map(f => f.mtimeMs)), isLink: false } }
    if (b !== undefined && e.path.startsWith(`${APEX_ROOT}/${b.name}/`)) {
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
    if (e.path === '/work/.git/HEAD') return { value: 'ref: refs/heads/feat/test\n' }
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
  expect(await ui.find({ text: exact(' apex') })).toBeUndefined()
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
  expect(await live.find({ text: exact('APEX · feat/test · Standard') })).toBeDefined()
  await live.unmount()
})

test('a live run folder without 00-context.md draws, dock and inline: no tier, its newest file current', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w: World = { ...fresh(), bare: { name: '04-nav-flottante', files: [{ name: '02-plan.md', mtimeMs: NOW - 1000 }] } }
  world(on, w)
  await $.session.start(START)
  await openDeck($, clock)
  for (const mount of [pane(120), inline(80, 'terminal')]) {
    const ui = await $.ui.mount(mount)
    expect(await ui.find({ text: exact('APEX · feat/test') })).toBeDefined()
    expect((await ui.find({ text: exact('◐ 02-plan') }))?.props.bold).toBe(true)
    expect(await ui.find({ text: exact('○ 03-execute') })).toBeDefined()
    await ui.unmount()
  }

  // Its newest file 6 hours old: not live.
  w.bare = { name: '04-nav-flottante', files: [{ name: '02-plan.md', mtimeMs: NOW - 7 * 60 * 60 * 1000 }] }
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
  expect(await ui.find({ text: exact('APEX · feat/test') })).toBeDefined()
  expect(await ui.find({ text: exact('APEX · feat/test · Standard') })).toBeUndefined()
  expect(await ui.find({ text: exact('◐ 02-plan') })).toBeDefined()
  await ui.unmount()
})

test('a live run draws first: header with branch and tier, one dot per phase state, tokens per phase', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute' }))
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  await $.session.start(START)
  await openDeck($, clock)
  // A main-loop step lands in the polled phase's bucket: 1.0k in + 3.4k out.
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 1 }))
  for (const cols of [64, 120]) {
    const ui = await $.ui.mount(pane(cols))
    const header = await ui.find({ text: exact('APEX · feat/test · Standard') })
    expect(header?.props.color).toBe('planMode')
    expect(header?.props.bold).toBe(true)
    expect((await ui.find({ text: exact('● 00-init') }))?.props.color).toBe('planMode')
    expect((await ui.find({ text: exact('· 02-plan') }))?.props.color).toBe('subtle')
    const current = await ui.find({ text: exact('◐ 03-execute 4k') })
    expect(current?.props.bold).toBe(true)
    expect((await ui.find({ text: exact('○ 04-validate') }))?.props.color).toBe('inactive')
    expect(await ui.find({ text: exact('○ 09-finish') })).toBeDefined()
    // First, above every panel.
    const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
    const at = texts.findIndex(t => t === 'APEX · feat/test · Standard')
    expect(at >= 0 && at < texts.findIndex(t => /· main$/.test(t))).toBe(true)
    expect(await ui.find({ text: exact(' apex') })).toBeDefined()
    await ui.unmount()
  }
})

test('alerts: a red external verify and a spent correction budget, in the warning colour', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh({ current: '03-execute', verdict: VERDICT, rounds: 2 }))
  await $.session.start(START)
  await openDeck($, clock)
  const ui = await $.ui.mount(pane(80))
  const verify = await ui.find({ text: exact('✗ external verify FAIL · 2 findings') })
  expect(verify?.props.color).toBe('error')
  expect((await ui.find({ text: exact('■ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
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
  expect(await ui.find({ text: exact('long sleep') })).toBeDefined()
  expect(await drawn(ui, 'shell-clock-b1')).toBe('1:05')
  expect((await ui.find({ text: exact(' running') }))?.props.color).toBe('suggestion')
  await ui.unmount()
  // Without Clients the same duration is static text.
  const flat = await $.ui.mount(pane(80, 'mobile'))
  expect(await flat.find({ text: exact('1:05') })).toBeDefined()
  await flat.unmount()

  const stop = { tool: 'TaskStop', task_id: 'b1', tool_use_id: 'tu-stop' } as const
  expect(await $.tool.call(stop)).toEqual({ result: { task_id: 'b1' } })
  expect(seen[1]).toEqual(stop)
  await clock.advance(10_000)
  const after = await $.ui.mount(pane(80, 'mobile'))
  expect((await after.find({ text: exact(' killed') }))?.props.color).toBe('inactive')
  expect(await after.find({ text: exact('1:05') })).toBeDefined() // frozen at the stop, 10 s ago
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
  expect(await ui.find({ text: exact('architect sleep') })).toBeDefined()
  expect(await ui.find({ text: exact(' killed') })).toBeDefined()
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
  expect(await ui.find({ text: exact('feat/test · 03-execute') })).toBeDefined()
  expect(await ui.find({ text: exact('03-execute → 04-validate') })).toBeDefined()
  const who = await ui.findAll({ type: 'Text', text: exact('apex') })
  expect(who.length).toBe(2)
  expect(who.every(x => x.props.color === 'planMode')).toBe(true)
  await ui.unmount()

  // One miss is not an end: the block stays, nothing logged.
  w.run = undefined
  await clock.advance(5000)
  const once = await $.ui.mount(pane(80))
  expect(await once.find({ text: /^APEX/ })).toBeDefined()
  expect(await once.find({ text: exact('run ended') })).toBeUndefined()
  await once.unmount()
  // The second in a row is: the block leaves, the log says so.
  await clock.advance(5000)
  const gone = await $.ui.mount(pane(80))
  expect(await gone.find({ text: /^APEX/ })).toBeUndefined()
  expect(await gone.find({ text: exact('run ended') })).toBeDefined()
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
  expect(await ui.find({ text: exact('feat/test · 03-execute') })).toBeDefined()
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
    expect(await ui.find({ text: exact('APEX · feat/test · Standard') })).toBeDefined()
    expect((await ui.find({ text: exact('● 00-init') }))?.props.color).toBe('planMode')
    expect((await ui.find({ text: exact('◐ 03-execute') }))?.props.bold).toBe(true)
    expect(await ui.find({ text: exact('○ 09-finish') })).toBeDefined()
    expect((await ui.find({ text: exact('✗ external verify FAIL · 2 findings') }))?.props.color).toBe('error')
    expect((await ui.find({ text: exact('■ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
    expect(await ui.find({ text: exact('long sleep') })).toBeDefined()
    if (surface === 'terminal') expect(await drawn(ui, 'shell-clock-b1')).toBe('1:05')
    else expect(await ui.find({ text: exact('1:05') })).toBeDefined()
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
    expect(await ui.find({ text: exact(' gate') })).toBeUndefined()
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
