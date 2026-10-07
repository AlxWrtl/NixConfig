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
// context file was written `ageMs` before NOW, or no apex folder at all;
// `.git/HEAD` holds `head`, or is missing when `head` is undefined.
function world(on: On, files: { ageMs: number } | null, head?: string, beneath: 'text' | 'empty' = 'text'): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('fs.list', ($, e) => {
    if (files === null || e.path !== '/work/.claude/output/apex') return { deny: 'ENOENT' }
    return { value: [{ name: 'my-run', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
  })
  on('fs.stat', () => ({
    value: { kind: 'file', size: CONTEXT.length, mtimeMs: NOW - (files?.ageMs ?? 0), isLink: false },
  }))
  on('fs.read', ($, e) => {
    if (e.path !== '/work/.git/HEAD') return { value: CONTEXT }
    return head === undefined ? { deny: 'ENOENT' } : { value: head }
  })
  // A later mod's (or the engine's) band beneath the plugin.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    return beneath === 'empty' ? <Box /> : <Text>other band</Text>
  })
}

test("a later mod's band is kept under a live run", async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'other band' })).toBeDefined()
    // Ours first, theirs after the last of our segments.
    const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
    const theirs = texts.indexOf('other band')
    const lastOurs = texts.reduce((at, t, i) => (t === 'other band' ? at : i), -1)
    expect(theirs > 0).toBe(true)
    expect(theirs > lastOurs).toBe(true)
    await ui.unmount()
  }
})

test('an empty band beneath still draws ours', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 }, undefined, 'empty')
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a narrow band is one degraded line within the columns', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({
    plugin: 'apex-band',
    surface: 'terminal',
    ...BAND,
    props: { ...BAND.props, bodyColumns: 30, maxRows: 1 },
  })
  const rows = (await ui.findAll({ type: 'Box' })).filter(b => b.props.flexDirection === 'row')
  expect(rows).toHaveLength(1)
  const shown = rows[0]?.text ?? ''
  expect(shown.startsWith('APEX · ')).toBe(true)
  expect(shown.length <= 30).toBe(true)
  expect(shown.includes(' › ')).toBe(false)
  expect(shown.includes('init')).toBe(false)
  await ui.unmount()
})

test('a live run is drawn above the prompt', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: 'exec' }))?.props.bold).toBe(true)
    expect((await ui.find({ type: 'Text', text: '●' }))?.props.color).toBe('warning')
    expect((await ui.find({ type: 'Text', text: 'init' }))?.props.dimColor).toBe(true)
    expect((await ui.find({ type: 'Text', text: '✓' }))?.props.color).toBe('success')
    expect((await ui.find({ type: 'Text', text: '○' }))?.props.dimColor).toBe(true)
    expect(await ui.find({ type: 'Text', text: 'finish' })).toBeDefined()
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
  expect(await ui.find({ type: 'Text', text: 'other band' })).toBeDefined()
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

test('nothing is drawn for a run on another branch', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 }, 'ref: refs/heads/master\n')
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  await ui.unmount()
})

test('a run on the checked-out branch is drawn', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { ageMs: 1000 }, 'ref: refs/heads/feat/test\n')
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
  await ui.unmount()
})
