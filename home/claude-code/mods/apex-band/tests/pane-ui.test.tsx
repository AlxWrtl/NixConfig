import { expect, mock, test } from 'claude-code/testing'
import type { ElementQuery, FoundElement, Plugin } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = 1_000_000_000

const PANE = {
  component: 'Pane',
  requestId: 'apex',
  props: {
    title: 'APEX',
    isFocused: false,
    bodyColumns: 80,
    placement: 'inline',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const CONTEXT = `# APEX: run under test
Mode: Standard
Branch: feat/test
Baseline: green

## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 03-execute | in progress | |
| 09-finish | pending | |
`

const VERDICT = JSON.stringify({ verdict: 'FAIL', findings: [{ problem: 'a' }, { problem: 'b' }] })

const RUN_COMMAND = {
  command: 'apex-pane',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 80 },
} as const

// The kit's $ raises no ui.close: a plugin beside the one under test
// closes the pane as the person's close would, through $.ui.close.
const CLOSER: Plugin = {
  name: 'closer',
  register(on) {
    on('command.run', { command: 'close-apex' }, async $ => {
      await $.ui.close({ id: 'apex' })
      return { text: '' }
    })
  },
}

const CLOSE_COMMAND = { ...RUN_COMMAND, command: 'close-apex' } as const

// The main loop has no card: a plugin beside reads its counters from the
// state (any plugin reads any value) and answers them as the command's text.
const PROBE: Plugin = {
  name: 'probe',
  register(on) {
    on('command.run', { command: 'probe-main' }, async $ => {
      const { value = [] } = await $.state.get({ plugin: 'apex-band', key: 'loops' })
      const main = value.find(l => l.id === 'main')
      return { text: JSON.stringify({ calls: main?.calls ?? null, tool: main?.tool ?? null }) }
    })
  },
}

const PROBE_COMMAND = { ...RUN_COMMAND, command: 'probe-main' } as const

// A turn.step stream read to its end: its chunks and the value it returned
// (the kit's top-level stream hands the result as the final done value).
async function drain<C, R>(stream: AsyncGenerator<C, R>): Promise<{ chunks: C[]; result: R }> {
  const chunks: C[] = []
  let step = await stream.next()
  while (step.done !== true) {
    chunks.push(step.value)
    step = await stream.next()
  }
  return { chunks, result: step.value }
}

// ui.find matches a string text by inclusion: anchor what must be exact.
const exact = (text: string): RegExp => new RegExp(`^${text}$`)

// The shown text of the pane's row for phase `label` (its glyph, label,
// token cell and share bar), or undefined when no such row is drawn.
async function phaseRow(
  ui: { findAll: (q: ElementQuery) => Promise<FoundElement[]> },
  label: string,
): Promise<string | undefined> {
  const rows = await ui.findAll({ type: 'Box', text: new RegExp(`^. ${label} `) })
  return rows.find(r => r.props.flexDirection === 'row')?.text
}

// A live run in /work/.claude/output/apex/my-run with its external verdict,
// one running subagent in the agent list, a session cost; counts each
// agent list read in `reads.agents`.
function world(
  on: On,
  reads: { agents: number } = { agents: 0 },
  opened: unknown[] = [],
  panes: { open?: 'deny'; close?: 'throw' } = {},
): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('command.register', () => ({ value: { command: 'apex-pane' } }))
  on('fs.list', ($, e) => {
    if (e.path !== '/work/.claude/output/apex') return { deny: 'ENOENT' }
    return { value: [{ name: 'my-run', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
  })
  on('fs.stat', () => ({ value: { kind: 'file', size: 10, mtimeMs: NOW - 1000, isLink: false } }))
  on('fs.read', ($, e) => {
    if (e.path.endsWith('/external-verify.json')) return { value: VERDICT }
    if (e.path.endsWith('/00-context.md')) return { value: CONTEXT }
    return { deny: 'ENOENT' }
  })
  on('agent.list', () => {
    reads.agents += 1
    return { value: [{ id: 'a1', description: 'scan engine types', type: 'Explore', status: 'running' }] }
  })
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 1.5 } },
  }))
  on('ui.open', ($, e) => {
    opened.push({ id: e.id, title: e.title })
    if (panes.open === 'deny') return { deny: 'no pane here' }
    return { value: { isPlaced: true } }
  })
  on('ui.close', () => {
    // A failure beneath (not a deny: the kit raises that past the chain).
    if (panes.close === 'throw') throw new Error('kept open')
    return { value: undefined }
  })
  on('session.end', () => ({ sessionId: 's1' }))
}

const STEP_RESULT = {
  turnId: 't1',
  index: 0,
  answer: '',
  toolUses: [],
  stopReason: 'tool_use',
  usage: {
    input_tokens: 1_000,
    output_tokens: 3_400,
    cache_read_input_tokens: 0,
    cache_creation_input_tokens: 0,
    model: 'claude-opus-5-5',
  },
} as const

test('an empty pane says so', async $ => {
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: exact('Aucun run APEX en cours.') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Lancez \/apex/ })).toBeDefined()
    await ui.unmount()
  }
})

test('/apex-pane opens pane apex titled APEX; closing it stops the 1 s tick', { plugins: [CLOSER] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  const opened: unknown[] = []
  world(on, reads, opened)
  const answer = await $.command.run(RUN_COMMAND)
  expect(answer.text).toBe('Détail du run APEX ouvert.')
  expect(opened).toEqual([{ id: 'apex', title: 'APEX' }])
  await clock.settle()
  const atOpen = reads.agents
  await clock.advance(1000)
  expect(reads.agents).toBeGreaterThan(atOpen)
  await $.command.run(CLOSE_COMMAND)
  const atClose = reads.agents
  // Short of the 5 s poll: only the stopped 1 s tick could read again.
  await clock.advance(2000)
  expect(reads.agents).toBe(atClose)
})

test('steps, tool calls and turn ends fill the pane; every result passes through unchanged', { plugins: [PROBE] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  on('turn.step', async function* () {
    yield { kind: 'text', index: 0, text: 'chunk' }
    return STEP_RESULT
  })
  const toolAnswer = { file: { filePath: '/x', content: 'hi' } }
  on('tool.call', () => ({ result: toolAnswer }))
  on('turn.complete', () => ({ text: 'fini' }))

  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()

  const { chunks, result } = await drain(
    $.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 3, agentId: 'a1' }),
  )
  expect(chunks).toEqual([{ kind: 'text', index: 0, text: 'chunk' }])
  expect(result).toEqual(STEP_RESULT)
  // A main-loop step too: phase exec 8.8k, principal 4.4k, sous-agents 4.4k.
  const main = await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 4 }))
  expect(main.result).toEqual(STEP_RESULT)

  // The kit's $.tool.call carries no agentId: a main-loop call, never
  // counted on the subagent's card (per-agent calls: stats.test.ts).
  const ran = await $.tool.call({ tool: 'Read', file_path: '/x', tool_use_id: 'u1' })
  expect(ran).toEqual({ result: toolAnswer })
  // The main loop has no card: its counters read from the state itself
  // (one call counted, its current tool cleared once the call ended).
  expect((await $.command.run(PROBE_COMMAND)).text).toBe(JSON.stringify({ calls: 1, tool: null }))

  await $.command.run(RUN_COMMAND)
  await clock.settle()

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...PANE })
    expect((await ui.find({ type: 'Text', text: exact('APEX · run under test') }))?.props.bold).toBe(true)
    expect(await ui.find({ type: 'Text', text: exact(' scan engine types') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^  opus-5\.5 · 0s · in 1\.0k · out 3\.4k$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^  Explore · 0 appel$/ })).toBeDefined()
    expect(await phaseRow(ui, 'exec')).toMatch(/^● exec +8\.8k +━{10}$/)
    expect(await ui.find({ type: 'Text', text: '░' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: exact('Vérif externe') })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: exact('✗ FAIL') }))?.props.color).toBe('error')
    expect(await ui.find({ type: 'Text', text: exact('2 constats') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^\$1\.50$/ })).toBeDefined()
    await ui.unmount()
  }

  const done = await $.turn.complete({
    answer: 'ok',
    durationMs: 5_000,
    isAborted: false,
    turnId: 't1',
    agentId: 'a1',
    reason: 'answer',
  })
  expect(done).toEqual({ text: 'fini' })
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect((await ui.find({ type: 'Text', text: exact('✓') }))?.props.color).toBe('success')
  expect((await ui.find({ type: 'Text', text: exact(' scan engine types') }))?.props.dimColor).toBe(true)
  await ui.unmount()
})

test('/clear resets the cards, phases, verdict and cost', { plugins: [CLOSER] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const { chunks } = await drain($.turn.step({ turnId: 't1', index: 0, model: 'm', messageCount: 1, agentId: 'a1' }))
  expect(chunks).toEqual([])
  await $.command.run(RUN_COMMAND)
  await clock.settle()
  await $.command.run(CLOSE_COMMAND)
  const before = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await phaseRow(before, 'exec')).toMatch(/^● exec +4\.4k +━{10}$/)
  expect(await before.find({ type: 'Text', text: exact('Vérif externe') })).toBeDefined()
  await before.unmount()

  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } })
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: 'scan engine types' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact('aucun pour l’instant') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'Vérif externe' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'en attente' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'FAIL' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '$' })).toBeUndefined()
  expect(await phaseRow(ui, 'exec')).toMatch(/^● exec +—$/)
  const dashes = await ui.findAll({ type: 'Text', text: exact(' +—') })
  expect(dashes).toHaveLength(3)
  for (const dash of dashes) expect(dash.props.dimColor).toBe(true)
  await ui.unmount()
})

test('a refused open arms no 1 s tick', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, reads, [], { open: 'deny' })
  let refused = false
  try {
    await $.command.run(RUN_COMMAND)
  } catch {
    refused = true
  }
  expect(refused).toBe(true)
  await clock.settle()
  const atOpen = reads.agents
  // Short of the 5 s poll: only a 1 s tick could read again.
  await clock.advance(3000)
  expect(reads.agents).toBe(atOpen)
})

test('a close kept open beneath keeps the 1 s tick', { plugins: [CLOSER] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, reads, [], { close: 'throw' })
  await $.command.run(RUN_COMMAND)
  await clock.settle()
  const atOpen = reads.agents
  await clock.advance(1000)
  expect(reads.agents).toBeGreaterThan(atOpen)
  try {
    await $.command.run(CLOSE_COMMAND)
  } catch {
    // The close refused beneath: the pane stays open.
  }
  const atClose = reads.agents
  await clock.advance(2000)
  expect(reads.agents).toBeGreaterThan(atClose)
})

test('a running card’s time advances with the clock while the pane is open', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'm', messageCount: 1, agentId: 'a1' }))
  await $.command.run(RUN_COMMAND)
  await clock.settle()
  let ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: /^  opus-5\.5 · 0s · in 1\.0k · out 3\.4k$/ })).toBeDefined()
  await ui.unmount()
  await clock.advance(3000)
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: /^  opus-5\.5 · 3s · in 1\.0k · out 3\.4k$/ })).toBeDefined()
  await ui.unmount()
})
