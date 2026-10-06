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
