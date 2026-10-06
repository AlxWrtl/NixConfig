import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = 1_000_000_000

const BAND = {
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 4,
    bodyColumns: 120,
    scroll: { offset: 0, bodyRows: 4 },
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

// A fake working directory beneath the plugin: one run directory whose
// context file was written `ageMs` before NOW, or no apex folder at all.
function world(on: On, files: { ageMs: number } | null): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('fs.list', ($, e) => {
    if (files === null || e.path !== '/work/.claude/output/apex') return { deny: 'ENOENT' }
    return { value: [{ name: 'my-run', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
  })
  on('fs.stat', () => ({
    value: { kind: 'file', size: CONTEXT.length, mtimeMs: NOW - (files?.ageMs ?? 0), isLink: false },
  }))
  on('fs.read', () => ({ value: CONTEXT }))
  // The engine's own (empty) band beneath the plugin.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
}

test('a live run is drawn above the prompt', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /étape 03-execute/ })).toBeDefined()
    await ui.unmount()
  }
})

test('nothing is drawn without an apex folder', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, null)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  await ui.unmount()
})

test('nothing is drawn for a stale run', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 7 * 60 * 60 * 1000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  await ui.unmount()
})

test('a survey takes the band', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({
    plugin: 'apex-band',
    surface: 'terminal',
    ...BAND,
    props: { ...BAND.props, hasSurvey: true },
  })
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  await ui.unmount()
})
