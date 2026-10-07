import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

const PANE = {
  component: 'Pane',
  requestId: 'task-board',
  props: {
    title: 'Tâches',
    isFocused: false,
    bodyColumns: 60,
    placement: 'inline',
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

// ui.find matches a string text by inclusion: anchor what must be exact.
const exact = (text: string): RegExp => new RegExp(`^${text}$`)

test('an empty board says so', async $ => {
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'task-board', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: /Aucune tâche/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /s'affichent ici/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a background shell shows ● and "1 en cours", its result passes through unchanged', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  const answer = { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-1' }
  on('tool.call', { tool: 'Bash' }, () => ({ result: answer }))

  const ran = await $.tool.call({ tool: 'Bash', command: 'sleep 5', description: 'dormir', run_in_background: true })
  expect(ran.deny).toBeUndefined()
  expect(ran.result).toEqual(answer)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'task-board', surface, ...PANE })
    expect((await ui.find({ type: 'Text', text: exact('●') }))?.props.color).toBe('warning')
    expect((await ui.find({ type: 'Text', text: exact('1 en cours') }))?.props.bold).toBe(true)
    expect(await ui.find({ type: 'Text', text: exact('shell') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: exact('dormir') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'terminées' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a foreground shell is not listed', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({ result: { stdout: 'hi', stderr: '', interrupted: false } }))
  await $.tool.call({ tool: 'Bash', command: 'echo hi' })
  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: /Aucune tâche/ })).toBeDefined()
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
  ['completed', '✓', 'success', '1 finie'],
  ['failed', '✗', 'error', '1 échouée'],
] as const) {
  test(`a task notification (${status}) turns the shell ${mark} "${word}"`, async ($, on) => {
    const clock = mock.clock(on, { now: 1_000 })
    on('tool.call', { tool: 'Bash' }, () => ({
      result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-2' },
    }))
    // The engine's own row, beneath the plugin (which passes it on unchanged).
    on('ui.render', { component: 'UserMessage' }, ($, e) => {
      const { Text } = $.ui.resolve(e)
      return <Text>{e.props.text}</Text>
    })
    await $.tool.call({ tool: 'Bash', command: 'false', run_in_background: true })

    const row = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...notification('bg-2', status) })
    await clock.settle()
    await row.unmount()

    const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
    expect((await ui.find({ type: 'Text', text: exact(mark) }))?.props.color).toBe(color)
    expect(await ui.find({ type: 'Text', text: exact(word) })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'en cours' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '●' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: exact('5s') })).toBeDefined()
    await ui.unmount()
  })
}

test('a TaskStop of a background shell turns it ■ "arrêtée", never "échouée", its result passes through unchanged', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({
    result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-3' },
  }))
  const stopped = { message: 'Successfully stopped task: bg-3', task_id: 'bg-3', task_type: 'local_bash' }
  on('tool.call', { tool: 'TaskStop' }, () => ({ result: stopped }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', description: 'attendre', run_in_background: true })

  const ran = await $.tool.call({ tool: 'TaskStop', task_id: 'bg-3' })
  expect(ran.result).toEqual(stopped)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'task-board', surface, ...PANE })
    expect((await ui.find({ type: 'Text', text: exact('■') }))?.props.color).toBe('inactive')
    expect(await ui.find({ type: 'Text', text: exact('1 arrêtée') })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'échoué' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '✗' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'en cours' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a refused or failed TaskStop leaves the shell "en cours"', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({
    result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-4' },
  }))
  let refuse = true
  on('tool.call', { tool: 'TaskStop' }, () => (refuse ? { deny: 'non' } : { result: 'No task found', isError: true as const }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', run_in_background: true })

  await $.tool.call({ tool: 'TaskStop', task_id: 'bg-4' })
  refuse = false
  await $.tool.call({ tool: 'TaskStop', task_id: 'bg-4' })

  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('●') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('1 en cours') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: '■' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: '✗' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'arrêtée' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'échoué' })).toBeUndefined()
  await ui.unmount()
})

const subagentRow = (id: string) =>
  `[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n<task-notification>\n<task-id>${id}</task-id>\n<status>completed</status>\n<summary>Background command "x" completed (exit code 0)</summary>\n</task-notification>`

for (const [name, extra, mark, word] of [
  ['a subagent\'s notification row turns its shell ✓ "finie"', { agentId: 'a1', origin: { kind: 'task-notification' } }, '✓', '1 finie'],
  ['a main-loop notification row is left to ui.render', { origin: { kind: 'task-notification' } }, '●', '1 en cours'],
  ['a subagent row of another origin is ignored', { agentId: 'a1', origin: { kind: 'model', model: 'm' } }, '●', '1 en cours'],
] as const) {
  test(name, async ($, on) => {
    mock.clock(on, { now: 1_000 })
    on('tool.call', { tool: 'Bash' }, () => ({
      result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-5' },
    }))
    await $.tool.call({ tool: 'Bash', command: 'reindex', run_in_background: true })

    const message = {
      type: 'user' as const,
      role: 'user' as const,
      isMeta: true as const,
      content: [{ type: 'text', text: subagentRow('bg-5') }],
    }
    // The kit has no session.append bottom: a test hook answering without
    // next is skipped, and the bottom throws. The plugin reads the row before
    // next, so its effect is checked past that throw.
    await expect($.session.append({ message, door: 'delivery', uuid: 'row-1', ...extra })).rejects.toThrow(
      /no implementation for session.append/,
    )

    const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
    expect(await ui.find({ type: 'Text', text: exact(mark) })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: exact(word) })).toBeDefined()
    await ui.unmount()
  })
}

test('running and finished rows: header counts, then "terminées" before the finished group', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  let next = 0
  on('tool.call', { tool: 'Bash' }, () => {
    next += 1
    return { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: `bg-${next}` } }
  })
  on('tool.call', { tool: 'TaskStop' }, () => ({ result: { message: 'stopped', task_id: 'bg-1', task_type: 'local_bash' } }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', description: 'premier', run_in_background: true })
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', description: 'second', run_in_background: true })
  await $.tool.call({ tool: 'TaskStop', task_id: 'bg-1' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'task-board', surface, ...PANE })
    const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
    expect(texts.slice(0, 3)).toEqual(['1 en cours', ' · ', '1 arrêtée'])
    expect((await ui.find({ type: 'Text', text: exact(' · ') }))?.props.dimColor).toBe(true)
    const grouped = texts.indexOf('terminées')
    expect(grouped).toBeGreaterThan(texts.indexOf('second'))
    expect(grouped).toBeLessThan(texts.indexOf('■'))
    expect(texts.indexOf('■')).toBeLessThan(texts.indexOf('premier'))
    expect((await ui.find({ type: 'Text', text: exact('premier') }))?.props.dimColor).toBe(true)
    expect((await ui.find({ type: 'Text', text: exact('second') }))?.props.dimColor).toBe(false)
    await ui.unmount()
  }
})

test('below 40 columns the kind column is dropped', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({
    result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-6' },
  }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 5', description: 'dormir', run_in_background: true })
  const narrow = { ...PANE, props: { ...PANE.props, bodyColumns: 39 } }
  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...narrow })
  expect(await ui.find({ type: 'Text', text: exact('●') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('dormir') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'shell' })).toBeUndefined()
  await ui.unmount()
})

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

const STEP_RESULT = {
  turnId: 't1',
  index: 0,
  answer: '',
  toolUses: [],
  stopReason: 'tool_use',
  usage: {
    input_tokens: 10_000,
    output_tokens: 1_500,
    cache_read_input_tokens: 800_000,
    cache_creation_input_tokens: 500,
    model: 'claude-opus-5-5',
  },
} as const

test('a subagent step passes through unchanged and adds its tokens (cache reads excluded) to its row', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Agent' }, () => ({
    result: { status: 'async_launched', agentId: 'a1', description: 'scanner le moteur' },
  }))
  on('turn.step', async function* () {
    yield { kind: 'text', index: 0, text: 'chunk' }
    return STEP_RESULT
  })
  await $.tool.call({ tool: 'Agent', description: 'scanner', prompt: 'go', subagent_type: 'Explore' })

  const { chunks, result } = await drain(
    $.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 3, agentId: 'a1' }),
  )
  expect(chunks).toEqual([{ kind: 'text', index: 0, text: 'chunk' }])
  expect(result).toEqual(STEP_RESULT)
  // A main-loop step is passed on too, and counted nowhere.
  const main = await drain($.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 4 }))
  expect(main.result).toEqual(STEP_RESULT)

  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('Explore · scanner le moteur') })).toBeDefined()
  const detail = await ui.find({ type: 'Text', text: exact(' · 12k') })
  expect(detail?.props.dimColor).toBe(true)
  await ui.unmount()
})

test('a tool call of any name passes through unchanged', async ($, on) => {
  const answer = { file: { filePath: '/x', content: 'hi' } }
  on('tool.call', { tool: 'Read' }, () => ({ result: answer }))
  // The kit's $.tool.call carries no agentId: a main-loop call (per-agent
  // tools: board.test.ts).
  expect(await $.tool.call({ tool: 'Read', file_path: '/x' })).toEqual({ result: answer })
})

const OPEN_COMMAND = {
  command: 'task-board',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 80 },
} as const

// One running shell and `finished` shells stopped at 1 000, then the pane
// opened at `openAt` (the open sets the pane's clock).
async function board(
  $: Parameters<TestBody>[0],
  on: Parameters<TestBody>[1],
  finished: number,
  openAt: number,
): Promise<void> {
  const clock = mock.clock(on, { now: 1_000 })
  let n = 0
  on('tool.call', { tool: 'Bash' }, () => {
    n += 1
    return { result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: `bg-${n}` } }
  })
  on('tool.call', { tool: 'TaskStop' }, () => ({ result: { message: 'stopped' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  for (let i = 1; i <= finished; i += 1) {
    await $.tool.call({ tool: 'Bash', command: 'true', description: `fini ${i}`, run_in_background: true })
    await $.tool.call({ tool: 'TaskStop', task_id: `bg-${i}` })
  }
  await $.tool.call({ tool: 'Bash', command: 'sleep 600', description: 'en vie', run_in_background: true })
  await clock.advance(openAt - 1_000)
  await $.command.run(OPEN_COMMAND)
}

test('past 30 s, finished shells beyond five fold into "+2 terminées"', async ($, on) => {
  await board($, on, 7, 60_000)
  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('en vie') })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: exact('\\+2 terminées') }))?.props.dimColor).toBe(true)
  expect(await ui.find({ type: 'Text', text: exact('fini 3') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('fini 2') })).toBeUndefined()
  expect((await ui.find({ key: 'toggle' }))?.props.label).toBe('tout afficher')
  expect((await ui.find({ key: 'toggle' }))?.props.hotkey).toBe('t')
  expect((await ui.find({ key: 'clear-done' }))?.props.hotkey).toBe('x')
  await ui.unmount()
})

test('within 30 s every finished shell is shown, no fold line', async ($, on) => {
  await board($, on, 7, 20_000)
  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('fini 1') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\+\d+ terminée/ })).toBeUndefined()
  expect(await ui.find({ key: 'toggle' })).toBeUndefined()
  await ui.unmount()
})

test('[t] shows every finished shell then folds them again', async ($, on) => {
  await board($, on, 7, 60_000)
  let ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  await ui.press({ key: 'toggle' })
  await ui.unmount()
  ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('fini 1') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\+\d+ terminée/ })).toBeUndefined()
  expect((await ui.find({ key: 'toggle' }))?.props.label).toBe('replier')
  await ui.press({ key: 'toggle' })
  await ui.unmount()
  ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('fini 1') })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: exact('\\+2 terminées') })).toBeDefined()
  await ui.unmount()
})

test('[x] clears every finished shell, keeps the running one; no button left to press', async ($, on) => {
  await board($, on, 7, 60_000)
  let ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  await ui.press({ key: 'clear-done' })
  await ui.unmount()
  ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: exact('1 en cours') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('en vie') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /fini/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /terminée/ })).toBeUndefined()
  expect(await ui.find({ key: 'clear-done' })).toBeUndefined()
  expect(await ui.find({ key: 'toggle' })).toBeUndefined()
  await ui.unmount()
})
