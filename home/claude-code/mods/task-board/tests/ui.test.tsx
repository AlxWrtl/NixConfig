import { expect, mock, test } from 'claude-code/testing'

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

test('an empty board says so', async $ => {
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'task-board', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: /Aucune tâche/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a background shell shows "en cours", its result passes through unchanged', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  const answer = { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-1' }
  on('tool.call', { tool: 'Bash' }, () => ({ result: answer }))

  const ran = await $.tool.call({ tool: 'Bash', command: 'sleep 5', description: 'dormir', run_in_background: true })
  expect(ran.deny).toBeUndefined()
  expect(ran.result).toEqual(answer)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'task-board', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: 'en cours' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /dormir/ })).toBeDefined()
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

for (const [status, word] of [
  ['completed', 'fini'],
  ['failed', 'échoué'],
] as const) {
  test(`a task notification (${status}) turns the shell "${word}"`, async ($, on) => {
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
    expect(await ui.find({ type: 'Text', text: word })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'en cours' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: '5s' })).toBeDefined()
    await ui.unmount()
  })
}

test('a TaskStop of a background shell turns it "échoué", its result passes through unchanged', async ($, on) => {
  mock.clock(on, { now: 1_000 })
  on('tool.call', { tool: 'Bash' }, () => ({
    result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'bg-3' },
  }))
  const stopped = { message: 'Successfully stopped task: bg-3', task_id: 'bg-3', task_type: 'local_bash' }
  on('tool.call', { tool: 'TaskStop' }, () => ({ result: stopped }))
  await $.tool.call({ tool: 'Bash', command: 'sleep 60', description: 'attendre', run_in_background: true })

  const ran = await $.tool.call({ tool: 'TaskStop', task_id: 'bg-3' })
  expect(ran.result).toEqual(stopped)

  const ui = await $.ui.mount({ plugin: 'task-board', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: 'échoué' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'en cours' })).toBeUndefined()
  await ui.unmount()
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
  expect(await ui.find({ type: 'Text', text: 'en cours' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: 'échoué' })).toBeUndefined()
  await ui.unmount()
})

const subagentRow = (id: string) =>
  `[SYSTEM NOTIFICATION - NOT USER INPUT]\n\n<task-notification>\n<task-id>${id}</task-id>\n<status>completed</status>\n<summary>Background command "x" completed (exit code 0)</summary>\n</task-notification>`

for (const [name, extra, word] of [
  ['a subagent\'s notification row turns its shell "fini"', { agentId: 'a1', origin: { kind: 'task-notification' } }, 'fini'],
  ['a main-loop notification row is left to ui.render', { origin: { kind: 'task-notification' } }, 'en cours'],
  ['a subagent row of another origin is ignored', { agentId: 'a1', origin: { kind: 'model', model: 'm' } }, 'en cours'],
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
    expect(await ui.find({ type: 'Text', text: word })).toBeDefined()
    await ui.unmount()
  })
}
