import { expect, mock, test } from 'claude-code/testing'
import type { ElementQuery, FoundElement, Plugin, TestBody } from 'claude-code/testing'
import type { AgentInfo, On } from 'claude-code'

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

const BOARD_COMMAND = { ...RUN_COMMAND, command: 'task-board' } as const

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

// The main loop has no row: a plugin beside reads its counters from the
// state (every plugin reads every value) and answers them as the command's text.
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

type Mounted = { findAll: (q: ElementQuery) => Promise<FoundElement[]> }

// The shown text of every row of the pane.
async function rows(ui: Mounted): Promise<string[]> {
  const boxes = await ui.findAll({ type: 'Box' })
  return boxes.filter(b => b.props.flexDirection === 'row').map(b => b.text)
}

// The shown text of the pane's row for phase `label` (its glyph, label,
// token cell and share bar), or undefined when no such row is drawn.
async function phaseRow(ui: Mounted, label: string): Promise<string | undefined> {
  const found = await ui.findAll({ type: 'Box', text: new RegExp(`^. ${label} `) })
  return found.find(r => r.props.flexDirection === 'row')?.text
}

// A live run in /work/.claude/output/apex/my-run with its external verdict,
// one running subagent in the agent list, a session cost; counts each
// agent list read in `reads.agents`.
function world(
  on: On,
  reads: { agents: number } = { agents: 0 },
  opened: unknown[] = [],
  // idle: nobody at work in the agent list (only an open pane ticks).
  // agents: the agent list read instead of the one running subagent.
  panes: { open?: 'deny'; close?: 'throw'; idle?: true; agents?: AgentInfo[] } = {},
): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('env.get', () => ({ value: '/home/u' }))
  on('command.register', () => ({ value: { command: 'apex-pane' } }))
  on('fs.list', ($, e) => {
    if (e.path === '/work/.claude/output/apex')
      return { value: [{ name: 'my-run', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
    if (e.path === '/work/.claude/output/apex/my-run')
      return { value: [{ name: 'external-verify.json', kind: 'file', size: 1, mtimeMs: 1, isLink: false }] }
    return { deny: 'ENOENT' }
  })
  on('fs.stat', () => ({ value: { kind: 'file', size: 10, mtimeMs: NOW - 1000, isLink: false } }))
  on('fs.read', ($, e) => {
    if (e.path.endsWith('/external-verify.json')) return { value: VERDICT }
    if (e.path.endsWith('/00-context.md')) return { value: CONTEXT }
    return { deny: 'ENOENT' }
  })
  on('agent.list', () => {
    reads.agents += 1
    if (panes.idle === true) return { value: [] }
    if (panes.agents !== undefined) return { value: panes.agents }
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
    expect(await ui.find({ type: 'Text', text: /Shells/ })).toBeUndefined()
    await ui.unmount()
  }
})

for (const command of [RUN_COMMAND, BOARD_COMMAND]) {
  test(`/${command.command} opens pane apex titled APEX`, async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    const opened: unknown[] = []
    world(on, { agents: 0 }, opened)
    const answer = await $.command.run(command)
    expect(answer.text).toBe('Détail du run APEX ouvert.')
    expect(opened).toEqual([{ id: 'apex', title: 'APEX' }])
    await clock.settle()
  })
}

test('nothing opens without a command', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const opened: unknown[] = []
  world(on, { agents: 0 }, opened)
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  on('tool.call', { tool: 'Agent' }, () => ({ result: { status: 'async_launched', agentId: 'a2' } }))
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'm', messageCount: 1, agentId: 'a1' }))
  await $.tool.call({ tool: 'Agent', description: 'x', prompt: 'go', subagent_type: 'Explore' })
  await clock.advance(12_000)
  expect(opened).toEqual([])
})

test('/apex-pane: closing the pane stops the 1 s tick', { plugins: [CLOSER] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  // Nobody at work: only the open pane keeps the tick.
  world(on, reads, [], { idle: true })
  await $.command.run(RUN_COMMAND)
  await clock.settle()
  const atOpen = reads.agents
  await clock.advance(1000)
  expect(reads.agents).toBeGreaterThan(atOpen)
  await $.command.run(CLOSE_COMMAND)
  await clock.advance(1000)
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

  // The kit's $.tool.call carries no agentId: a main-loop call.
  const ran = await $.tool.call({ tool: 'Read', file_path: '/x', tool_use_id: 'u1' })
  expect(ran).toEqual({ result: toolAnswer })
  expect((await $.command.run(PROBE_COMMAND)).text).toBe(JSON.stringify({ calls: 1, tool: null }))

  await $.command.run(RUN_COMMAND)
  await clock.settle()

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...PANE })
    expect((await ui.find({ type: 'Text', text: exact('APEX · run under test') }))?.props.bold).toBe(true)
    expect((await ui.find({ type: 'Text', text: exact(' scan engine types') }))?.props.bold).toBe(true)
    expect((await rows(ui)).includes('● scan engine types · opus-5.5 · 4.4k · 0s')).toBe(true)
    expect((await ui.find({ type: 'Text', text: exact(' · opus-5\\.5 · 4\\.4k · 0s') }))?.props.dimColor).toBe(true)
    expect(await phaseRow(ui, 'exec')).toMatch(/^● exec +8\.8k +━{10}$/)
    expect(await ui.find({ type: 'Text', text: exact('Vérif externe') })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: exact('✗ FAIL') }))?.props.color).toBe('error')
    expect(await ui.find({ type: 'Text', text: exact('2 constats') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^\$1\.50$/ })).toBeDefined()
    // The red verdict is asked of the user first.
    expect((await rows(ui))[0]).toBe('Action')
    expect((await rows(ui))[1]).toBe('✗ Vérif externe FAIL · 2 constats')
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
  expect((await rows(ui)).includes('✓ scan engine types · opus-5.5 · 4.4k · 5s')).toBe(true)
  await ui.unmount()
})

test('/clear resets the subagents, phases, verdict and cost', { plugins: [CLOSER] }, async ($, on) => {
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
  // Every figure is gone, the run too until the next poll reads it again.
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('Aucun run APEX en cours.') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'scan engine types' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'Vérif externe' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'FAIL' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '$' })).toBeUndefined()
  await ui.unmount()
  // The next poll finds the run again: its phase buckets start over.
  await clock.advance(5000)
  const after = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await phaseRow(after, 'exec')).toMatch(/^● exec +—$/)
  await after.unmount()
})

test('a refused open arms no 1 s tick', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, reads, [], { open: 'deny', idle: true })
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
  world(on, reads, [], { close: 'throw', idle: true })
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

test('a running subagent’s time advances with the clock while the pane is open', async ($, on) => {
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
  expect((await rows(ui)).includes('● scan engine types · opus-5.5 · 4.4k · 0s')).toBe(true)
  await ui.unmount()
  await clock.advance(3000)
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect((await rows(ui)).includes('● scan engine types · opus-5.5 · 4.4k · 3s')).toBe(true)
  await ui.unmount()
})

// Ported from task-board: background shells on the apex pane.

const bgAnswer = (id: string) => ({ stdout: '', stderr: '', interrupted: false, backgroundTaskId: id })

test('a background shell shows ● and "1 en cours", its result passes through unchanged', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  const answer = bgAnswer('bg-1')
  on('tool.call', { tool: 'Bash' }, () => ({ result: answer }))

  const ran = await $.tool.call({ tool: 'Bash', command: 'sleep 5', description: 'dormir', run_in_background: true })
  expect(ran.deny).toBeUndefined()
  expect(ran.result).toEqual(answer)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: exact('Shells en arrière-plan') })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: exact('●') }))?.props.color).toBe('warning')
    expect((await ui.find({ type: 'Text', text: exact('1 en cours') }))?.props.bold).toBe(true)
    expect((await ui.find({ type: 'Text', text: exact(' dormir') }))?.props.bold).toBe(true)
    expect(await ui.find({ type: 'Text', text: 'terminés' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a foreground shell is not listed', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: 'hi', stderr: '', interrupted: false } }))
  await $.tool.call({ tool: 'Bash', command: 'echo hi' })
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: /Shells/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact('Aucun run APEX en cours.') })).toBeDefined()
  await ui.unmount()
})

const notification = (id: string, status: string) =>
  ({
    component: 'UserMessage',
    props: {
      text: `<task-notification>${id}</task-notification>`,
      origin: { kind: 'task-notification' },
      isExpanded: false,
      task: { id, status, durationMs: 5_000 },
    },
  }) as const

for (const [status, mark, color, word] of [
  ['completed', '✓', 'success', '1 fini'],
  ['failed', '✗', 'error', '1 échoué'],
] as const) {
  test(`a task notification (${status}) turns the shell ${mark} "${word}"`, async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-2') }))
    // The engine's own row, beneath the plugin (which passes it on unchanged).
    on('ui.render', { component: 'UserMessage' }, ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>{e.props.text}</Text>
    })
    await $.tool.call({ tool: 'Bash', command: 'false', description: 'tester', run_in_background: true })

    const row = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...notification('bg-2', status) })
    expect(await row.find({ type: 'Text', text: /task-notification/ })).toBeDefined()
    await clock.settle()
    await row.unmount()

    const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
    expect((await ui.find({ type: 'Text', text: exact(mark) }))?.props.color).toBe(color)
    expect(await ui.find({ type: 'Text', text: exact(word) })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^\d+ en cours$/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '●' })).toBeUndefined()
    expect((await rows(ui)).includes(`${mark} tester · 5s`)).toBe(true)
    await ui.unmount()
  })
}

test('a TaskStop of a background shell turns it ■ "arrêté", never "échoué", its result passes through unchanged', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-3') }))
  const stopped = { message: 'Successfully stopped task: bg-3', task_id: 'bg-3', task_type: 'local_bash' }
  on('tool.call', { tool: 'TaskStop' }, () => ({ result: stopped }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', description: 'attendre', run_in_background: true })

  const ran = await $.tool.call({ tool: 'TaskStop', task_id: 'bg-3' })
  expect(ran.result).toEqual(stopped)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...PANE })
    expect((await ui.find({ type: 'Text', text: exact('■') }))?.props.color).toBe('inactive')
    expect(await ui.find({ type: 'Text', text: exact('1 arrêté') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'échoué' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '✗' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /^\d+ en cours$/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('a refused or failed TaskStop leaves the shell "en cours"', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-4') }))
  let refuse = true
  on('tool.call', { tool: 'TaskStop' }, () => (refuse ? { deny: 'non' } : { result: 'No task found', isError: true as const }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', run_in_background: true })

  await $.tool.call({ tool: 'TaskStop', task_id: 'bg-4' })
  refuse = false
  await $.tool.call({ tool: 'TaskStop', task_id: 'bg-4' })

  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('●') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('1 en cours') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '■' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'arrêté' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'échoué' })).toBeUndefined()
  await ui.unmount()
})

const subagentRow = (id: string) =>
  `[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n<task-notification>\n<task-id>${id}</task-id>\n<status>completed</status>\n<summary>Background command "x" completed (exit code 0)</summary>\n</task-notification>`

for (const [name, extra, mark, word] of [
  ['a subagent\'s notification row turns its shell ✓ "fini"', { agentId: 'a1', origin: { kind: 'task-notification' } }, '✓', '1 fini'],
  ['a main-loop notification row is left to ui.render', { origin: { kind: 'task-notification' } }, '●', '1 en cours'],
  ['a subagent row of another origin is ignored', { agentId: 'a1', origin: { kind: 'model', model: 'm' } }, '●', '1 en cours'],
] as const) {
  test(name, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-5') }))
    await $.tool.call({ tool: 'Bash', command: 'reindex', run_in_background: true })

    const message = {
      type: 'user' as const,
      role: 'user' as const,
      isMeta: true as const,
      content: [{ type: 'text', text: subagentRow('bg-5') }],
    }
    // The row is relayed unchanged (the plugin reads it before next).
    const appended = await $.session.append({ message, door: 'delivery', uuid: 'row-1', ...extra })
    expect(appended).toEqual({ message, uuid: 'row-1' })

    const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
    expect(await ui.find({ type: 'Text', text: exact(mark) })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: exact(word) })).toBeDefined()
    await ui.unmount()
  })
}

for (const [reason, mark, word] of [
  ['aborted', '■', '1 arrêté'],
  ['error', '■', '1 arrêté'],
  ['answer', '●', '1 en cours'],
] as const) {
  test(`a subagent ending (${reason}) leaves its shell ${mark} "${word}"`, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('tool.call', { tool: 'Agent' }, () => ({
      result: { status: 'async_launched', agentId: 'a1', description: 'owner' },
    }))
    on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-6') }))
    on('turn.complete', () => ({ text: 'fini' }))
    await $.tool.call({ tool: 'Agent', description: 'owner', prompt: 'go', subagent_type: 'Explore' })
    // The kit's $.tool.call input has no agentId field (a type gap only: the
    // hooks receive it at run time); the shell is owned by subagent a1.
    // @ts-expect-error agentId is not part of the kit's tool.call input type
    await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'orphelin', run_in_background: true, agentId: 'a1' })
    const done = await $.turn.complete({
      answer: '',
      durationMs: 1_000,
      isAborted: reason === 'aborted',
      turnId: 't1',
      agentId: 'a1',
      reason,
    })
    expect(done).toEqual({ text: 'fini' })

    const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
    expect((await rows(ui)).some(r => r.startsWith(`${mark} orphelin · `))).toBe(true)
    expect(await ui.find({ type: 'Text', text: exact(word) })).toBeDefined()
    await ui.unmount()
  })
}

test('a shell owned by a loop no agent list names (a fork) stays running after a poll', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { agents: 0 }, [], { idle: true })
  on('turn.step', async function* () {
    return STEP_RESULT
  })
  on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-f') }))
  on('turn.complete', () => ({ text: 'fini' }))
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await drain($.turn.step({ turnId: 't1', index: 0, model: 'm', messageCount: 1, agentId: 'f1' }))
  // @ts-expect-error agentId is not part of the kit's tool.call input type
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'du fork', run_in_background: true, agentId: 'f1' })
  // Its turn aborting says nothing of its type: the shell is kept too.
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: true, turnId: 't1', agentId: 'f1', reason: 'aborted' })
  await clock.advance(5_000)
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect((await rows(ui)).some(r => r.startsWith('● du fork · '))).toBe(true)
  expect(await ui.find({ type: 'Text', text: exact('1 en cours') })).toBeDefined()
  await ui.unmount()
})

test('an agent already finished when first listed shows in the pane as finished', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { agents: 0 }, [], {
    agents: [{ id: 'a9', description: 'déjà fini', type: 'Explore', status: 'completed' }],
  })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect((await rows(ui)).includes('✓ déjà fini · 0s')).toBe(true)
  expect((await ui.find({ type: 'Text', text: exact(' déjà fini') }))?.props.dimColor).toBe(true)
  await ui.unmount()
})

test('a multiline shell command is one pane row', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({ result: bgAnswer('bg-m') }))
  await $.tool.call({ tool: 'Bash', command: 'echo a\n   echo b', run_in_background: true })
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect((await rows(ui)).some(r => r.startsWith('● echo a echo b · '))).toBe(true)
  expect(await ui.find({ type: 'Text', text: /\n/ })).toBeUndefined()
  await ui.unmount()
})

// One running shell and `finished` shells stopped at 1 000, then the pane
// opened by /task-board.
async function board($: Parameters<TestBody>[0], on: Parameters<TestBody>[1], finished: number): Promise<void> {
  const clock = mock.clock(on, { now: 1_000 })
  let n = 0
  on('tool.call', { tool: 'Bash' }, () => {
    n += 1
    return { result: bgAnswer(`bg-${n}`) }
  })
  on('tool.call', { tool: 'TaskStop' }, () => ({ result: { message: 'stopped' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  for (let i = 1; i <= finished; i += 1) {
    await $.tool.call({ tool: 'Bash', command: 'true', description: `fini ${i}`, run_in_background: true })
    await clock.advance(1_000)
    await $.tool.call({ tool: 'TaskStop', task_id: `bg-${i}` })
  }
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'en vie', run_in_background: true })
  await $.command.run(BOARD_COMMAND)
}

test('past six finished shells, the oldest fold into "+2 terminés" with [t]', async ($, on) => {
  await board($, on, 8)
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact(' en vie') })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: exact('\\+2 terminés') }))?.props.dimColor).toBe(true)
  expect(await ui.find({ type: 'Text', text: exact(' fini 3') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact(' fini 2') })).toBeUndefined()
  expect((await ui.find({ key: 'toggle' }))?.props.label).toBe('tout afficher')
  expect((await ui.find({ key: 'toggle' }))?.props.hotkey).toBe('t')
  expect(await ui.find({ key: 'clear-done' })).toBeUndefined()
  await ui.unmount()
})

test('six finished shells or fewer: every one shown, no fold line, no [t]', async ($, on) => {
  await board($, on, 6)
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact(' fini 1') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\+\d+ terminés/ })).toBeUndefined()
  expect(await ui.find({ key: 'toggle' })).toBeUndefined()
  await ui.unmount()
})

test('[t] shows every finished shell then folds them again', async ($, on) => {
  await board($, on, 8)
  let ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  await ui.press({ key: 'toggle' })
  await ui.unmount()
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact(' fini 1') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\+\d+ terminés/ })).toBeUndefined()
  expect((await ui.find({ key: 'toggle' }))?.props.label).toBe('replier')
  await ui.press({ key: 'toggle' })
  await ui.unmount()
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact(' fini 1') })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact('\\+2 terminés') })).toBeDefined()
  await ui.unmount()
})
