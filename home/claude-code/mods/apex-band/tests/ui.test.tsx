import { expect, mock, test } from 'claude-code/testing'
import type { ElementQuery, FoundElement, Plugin } from 'claude-code/testing'
import type { AgentInfo, On } from 'claude-code'

const NOW = 1_000_000_000
const HOME = '/home/u'
const RUN_DIR = '/work/.claude/output/apex/my-run'

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

const verdict = (word: string, findings: number): string =>
  JSON.stringify({ verdict: word, findings: Array.from({ length: findings }, (_, i) => ({ problem: `p${i}` })) })

type Agent = AgentInfo

type World = {
  // The run's context written `ageMs` before NOW, or no apex folder at all.
  files?: { ageMs: number } | null
  // .git/HEAD, missing when undefined.
  head?: string
  beneath?: 'text' | 'empty'
  // Names in ~/.claude/apex-correction-budget (the folder missing when undefined).
  budget?: string[]
  // Verify files in the run directory: name, mtime and body.
  verify?: { name: string; mtimeMs: number; body: string }[]
  agents?: Agent[]
  reads?: { agents: number }
}

// A fake machine beneath the plugin: /work with one run directory, HOME
// with its correction budget folder, the agent list and the session's cost.
function world(on: On, w: World = {}): void {
  const files = w.files === undefined ? { ageMs: 1000 } : w.files
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('env.get', ($, e) => (e.name === 'HOME' ? { value: HOME } : { value: undefined }))
  on('fs.list', ($, e) => {
    if (files !== null && e.path === '/work/.claude/output/apex')
      return { value: [{ name: 'my-run', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }
    if (files !== null && e.path === RUN_DIR) {
      const entries = (w.verify ?? []).map(v => ({
        name: v.name,
        kind: 'file' as const,
        size: 1,
        mtimeMs: v.mtimeMs,
        isLink: false,
      }))
      return { value: [{ name: '00-context.md', kind: 'file', size: 1, mtimeMs: 0, isLink: false }, ...entries] }
    }
    if (w.budget !== undefined && e.path === `${HOME}/.claude/apex-correction-budget`)
      return { value: w.budget.map(name => ({ name, kind: 'file' as const, size: 0, mtimeMs: 0, isLink: false })) }
    return { deny: 'ENOENT' }
  })
  on('fs.stat', () => ({
    value: { kind: 'file', size: CONTEXT.length, mtimeMs: NOW - (files?.ageMs ?? 0), isLink: false },
  }))
  on('fs.read', ($, e) => {
    if (e.path === '/work/.git/HEAD') return w.head === undefined ? { deny: 'ENOENT' } : { value: w.head }
    const file = (w.verify ?? []).find(v => e.path === `${RUN_DIR}/${v.name}`)
    if (file !== undefined) return { value: file.body }
    if (e.path.endsWith('/00-context.md')) return { value: CONTEXT }
    return { deny: 'ENOENT' }
  })
  on('agent.list', () => {
    if (w.reads !== undefined) w.reads.agents += 1
    return { value: w.agents ?? [] }
  })
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 1.5 } },
  }))
  // A later mod's (or the engine's) band beneath the plugin.
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    return w.beneath === 'empty' ? <Box /> : <Text>other band</Text>
  })
}

const RUNNING: Agent = { id: 'a1', description: 'scan engine types', type: 'Explore', status: 'running' }

type Mounted = { findAll: (q: ElementQuery) => Promise<FoundElement[]> }

// Room for the agents block as cards (L1, the rail, a 4-row card).
const TALL = { ...BAND, props: { ...BAND.props, maxRows: 8, scroll: { offset: 0, bodyRows: 8 } } } as const

// What a Client's surface module drew, as text.
async function drawn(ui: Mounted, key: string): Promise<string> {
  return (await ui.findAll({ type: 'Text', in: key })).map(t => t.text).join('')
}

// The band's rows, as shown text.
async function rows(ui: Mounted): Promise<string[]> {
  const boxes = await ui.findAll({ type: 'Box' })
  return boxes.filter(b => b.props.flexDirection === 'row').map(b => b.text)
}

test("a later mod's band is kept under a live run", async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...BAND })
    expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
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
  world(on, { beneath: 'empty' })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
  await ui.unmount()
})

test('a live idle run is one row: title, phase dots, phase word, cost', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...BAND })
    const shown = await rows(ui)
    expect(shown).toHaveLength(1)
    expect(shown[0]?.startsWith('APEX · run under test  ●●●◐○  exécution · ')).toBe(true)
    expect(shown[0]?.endsWith(' · $1.50')).toBe(true)
    expect((await ui.find({ type: 'Text', text: 'exécution' }))?.props.bold).toBe(true)
    expect((await ui.find({ type: 'Text', text: '◐' }))?.props.color).toBe('warning')
    expect((await ui.find({ type: 'Text', text: '●' }))?.props.color).toBe('success')
    expect((await ui.find({ type: 'Text', text: '○' }))?.props.dimColor).toBe(true)
    await ui.unmount()
  }
})

test('a narrow band is one row within the columns', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({
    plugin: 'apex-band',
    surface: 'terminal',
    ...BAND,
    props: { ...BAND.props, bodyColumns: 30, maxRows: 1 },
  })
  const shown = await rows(ui)
  expect(shown).toHaveLength(1)
  expect(shown[0]?.startsWith('APEX · ')).toBe(true)
  expect(Array.from(shown[0] ?? '').length <= 30).toBe(true)
  await ui.unmount()
})

test('budget spent: the correction budget alert row', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  // Another run sharing the prefix is not counted.
  world(on, { budget: ['my-run.round1', 'my-run.round2', 'my-run-x.round3'] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  const shown = await rows(ui)
  expect(shown).toHaveLength(2)
  expect(shown[1]).toBe('⚠ Budget de correction épuisé — tape « apex: +1 tour » ou livre avec les résiduels')
  expect((await ui.find({ type: 'Text', text: '⚠' }))?.props.color).toBe('warning')
  await ui.unmount()
})

for (const [name, budget] of [
  ['budget not spent: no alert row', ['my-run.round1']],
  ['budget granted one more round: no alert row', ['my-run.round1', 'my-run.round2', 'my-run.grant1']],
  ["another run's rounds: no alert row", ['my-run-x.round1', 'my-run-x.round2']],
] as const) {
  test(name, async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    world(on, { budget: [...budget] })
    await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
    await clock.settle()
    const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
    expect(await rows(ui)).toHaveLength(1)
    expect(await ui.find({ type: 'Text', text: /Budget/ })).toBeUndefined()
    await ui.unmount()
  })
}

type VerifyCase = readonly [string, readonly { name: string; mtimeMs: number; body: string }[], string | undefined]

const VERIFY_CASES: readonly VerifyCase[] = [
  [
    'both verify names: 04-external-verify.json newer wins (FAIL)',
    [
      { name: '04-external-verify.json', mtimeMs: 2, body: verdict('FAIL', 2) },
      { name: 'external-verify.json', mtimeMs: 1, body: verdict('PASS', 0) },
    ],
    '✗ Vérif externe FAIL · 2 constats',
  ],
  [
    'both verify names: external-verify.json newer wins (PASS, no alert)',
    [
      { name: '04-external-verify.json', mtimeMs: 1, body: verdict('FAIL', 2) },
      { name: 'external-verify.json', mtimeMs: 2, body: verdict('PASS', 0) },
    ],
    undefined,
  ],
  [
    'verify name external-verify.json alone is read',
    [{ name: 'external-verify.json', mtimeMs: 1, body: verdict('BLOCKED', 1) }],
    '✗ Vérif externe BLOCKED · 1 constat',
  ],
  [
    'verify name 04-external-verify.json alone is read',
    [{ name: '04-external-verify.json', mtimeMs: 1, body: verdict('ERROR', 3) }],
    '✗ Vérif externe ERROR · 3 constats',
  ],
]

for (const [name, verify, alert] of VERIFY_CASES) {
  test(name, async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    world(on, { verify: verify.map(v => ({ ...v })) })
    await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
    await clock.settle()
    const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
    const shown = await rows(ui)
    expect(shown[1]).toBe(alert)
    if (alert !== undefined) expect((await ui.find({ type: 'Text', text: '✗' }))?.props.color).toBe('error')
    await ui.unmount()
  })
}

test('a running subagent: the rail and its card, the rail and the clock moving on their own timers', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { agents: [RUNNING] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'apex-band', surface, ...TALL })
    const shown = await rows(ui)
    expect(shown).toHaveLength(6)
    expect(shown[1]).toBe('◆ main ')
    expect(shown[2]).toMatch(/^╭─ ● scan engine types ─+╮$/)
    expect(shown[3]).toMatch(/^│ Explore +│$/)
    expect(shown[5]).toMatch(/^╰─ 0 step ─+ +─╯$/)
    expect(await ui.find({ type: 'Client', key: 'rail' })).toBeDefined()
    expect(await ui.find({ type: 'Client', key: 'clock:a1' })).toBeDefined()
    const rail = await drawn(ui, 'rail')
    expect(rail.startsWith('●─')).toBe(true)
    expect(rail).toContain('┬')
    expect(await drawn(ui, 'clock:a1')).toBe(' 0:00')
    // One rail step: the head moves on, a trail behind it.
    await ui.advance(110)
    const moved = await drawn(ui, 'rail')
    expect(moved).not.toBe(rail)
    expect(moved.startsWith('•●')).toBe(true)
    // One second: the clock counts on, the host clock untouched.
    await ui.advance(890)
    expect(await drawn(ui, 'clock:a1')).toBe(' 0:01')
    await ui.unmount()
  }
})

test('idle: no agents block, no Client, and no 1 s tick', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, { reads })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const atStart = reads.agents
  // Short of the 5 s poll: only a 1 s tick could read the agent list again.
  await clock.advance(3000)
  expect(reads.agents).toBe(atStart)
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...TALL })
  expect(await rows(ui)).toHaveLength(1)
  expect(await ui.find({ type: 'Text', text: /◆ main/ })).toBeUndefined()
  expect(await ui.findAll({ type: 'Client' })).toEqual([])
  await ui.unmount()
})

test('a running subagent arms the 1 s tick (the idle check can fail)', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, { reads, agents: [RUNNING] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const atStart = reads.agents
  await clock.advance(3000)
  expect(reads.agents).toBeGreaterThan(atStart)
})

test('an unknown agent listed idle: nothing at work, no 1 s tick', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, { reads, agents: [{ ...RUNNING, status: 'idle' }] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const atStart = reads.agents
  await clock.advance(3000)
  expect(reads.agents).toBe(atStart)
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...TALL })
  expect(await ui.find({ type: 'Text', text: /◆ main/ })).toBeUndefined()
  expect(await ui.findAll({ type: 'Client' })).toEqual([])
  await ui.unmount()
})

test('an agent already finished when first listed is « terminé », never a card beside the one at work', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { agents: [RUNNING, { id: 'a9', description: 'déjà fini', type: 'Explore', status: 'completed' }] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...TALL })
  const shown = await rows(ui)
  expect(shown.filter(r => r.startsWith('╭─ '))).toEqual([expect.stringMatching(/^╭─ ● scan engine types ─+╮$/)])
  expect(await ui.find({ type: 'Text', text: /déjà fini/ })).toBeUndefined()
  expect(await ui.find({ type: 'Client', key: 'clock:a9' })).toBeUndefined()
  await ui.unmount()
})

test('an Agent launched with model haiku shows haiku before its first step', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: null })
  on('tool.call', { tool: 'Agent' }, () => ({ result: { status: 'async_launched', agentId: 'a1', description: 'scan' } }))
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await $.tool.call({ tool: 'Agent', description: 'scan', prompt: 'go', subagent_type: 'Explore', model: 'haiku' })
  // Four rows: the rail and one lane.
  let ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await rows(ui)).toEqual(['◆ main ', expect.stringMatching(/^● scan +haiku /)])
  await ui.unmount()
  // Eight rows: the rail and one card.
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...TALL })
  expect((await rows(ui))[2]).toMatch(/^│ Explore · haiku +│$/)
  await ui.unmount()
})

test('a fork loop (steps under an id no agent list names) is not grouped', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: null })
  on('turn.step', async function* () {
    return { turnId: 't1', index: 0, answer: '', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const stream = $.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 1, agentId: 'f1' })
  for (let s = await stream.next(); s.done !== true; s = await stream.next()) {
    // Drained: the step's chunks are not under test.
  }
  await clock.advance(1000)
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...TALL })
  expect(await rows(ui)).toEqual([])
  expect(await ui.findAll({ type: 'Client' })).toEqual([])
  await ui.unmount()
})

test('no run and a subagent running: the agents block alone', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: null, agents: [RUNNING] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  const shown = await rows(ui)
  expect(shown).toHaveLength(2)
  expect(shown[0]).toBe('◆ main ')
  expect(shown[1]).toMatch(/^● scan engine t… agent /)
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'other band' })).toBeDefined()
  await ui.unmount()
})

test('no run and nothing running draws nothing of ours', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: null })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await rows(ui)).toEqual([])
  expect(await ui.find({ type: 'Text', text: 'other band' })).toBeDefined()
  await ui.unmount()
})

test('nothing is drawn for a stale run', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: { ageMs: 7 * 60 * 60 * 1000 } })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  await ui.unmount()
})

test('a survey takes the band: ours passes, the one beneath is drawn', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { agents: [RUNNING], budget: ['my-run.round1', 'my-run.round2'] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({
    plugin: 'apex-band',
    surface: 'terminal',
    ...BAND,
    props: { ...BAND.props, hasSurvey: true },
  })
  expect(await ui.find({ type: 'Text', text: /APEX|Budget|◆ main/ })).toBeUndefined()
  expect(await ui.findAll({ type: 'Client' })).toEqual([])
  expect(await ui.find({ type: 'Text', text: 'other band' })).toBeDefined()
  await ui.unmount()
})

test('nothing is drawn for a run on another branch', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { head: 'ref: refs/heads/master\n' })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX/ })).toBeUndefined()
  await ui.unmount()
})

test('a run on the checked-out branch is drawn', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { head: 'ref: refs/heads/feat/test\n' })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /APEX · run under test/ })).toBeDefined()
  await ui.unmount()
})

// Reads the band's clock atom from beside the plugin (a test hook has no
// state noun) and answers it as the command's text.
const CLOCK_PROBE: Plugin = {
  name: 'clock-probe',
  register(on) {
    on('command.run', { command: 'probe-now' }, async $ => {
      const { value = 0 } = await $.state.get({ plugin: 'apex-band', key: 'now' })
      return { text: String(value) }
    })
  },
}

const PROBE_NOW = {
  command: 'probe-now',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 80 },
} as const

test('idle, a live run: the 5 s poll moves the clock each minute, so elapsed advances', { plugins: [CLOCK_PROBE] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  let ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect((await rows(ui))[0]).toContain(' · 0m · ')
  await ui.unmount()
  // Within the minute the clock is not written again.
  await clock.advance(30_000)
  expect((await $.command.run(PROBE_NOW)).text).toBe(String(NOW))
  await clock.advance(30_000)
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect((await rows(ui))[0]).toContain(' · 1m · ')
  await ui.unmount()
  await clock.advance(2 * 60_000)
  ui = await $.ui.mount({ plugin: 'apex-band', surface: 'terminal', ...BAND })
  expect((await rows(ui))[0]).toContain(' · 3m · ')
  await ui.unmount()
})

test('no live run and nothing at work: the clock is never written', { plugins: [CLOCK_PROBE] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: null })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  await clock.advance(3 * 60_000)
  expect((await $.command.run(PROBE_NOW)).text).toBe('0')
})

test('busy with the pane closed: the host clock moves at most once per 5 s', { plugins: [CLOCK_PROBE] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { files: null, agents: [RUNNING] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const values: number[] = []
  for (let i = 0; i < 15; i++) {
    await clock.advance(1000)
    const value = Number((await $.command.run(PROBE_NOW)).text)
    if (values[values.length - 1] !== value) values.push(value)
  }
  // It does move (the check can fail), never twice within 5 s.
  expect(values.length >= 2).toBe(true)
  for (let i = 1; i < values.length; i++) expect((values[i] ?? 0) - (values[i - 1] ?? 0) >= 5000).toBe(true)
})

test('vscode: the rail and the clock as static text, no Client', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, { agents: [RUNNING] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const ui = await $.ui.mount({ plugin: 'apex-band', surface: 'vscode', ...TALL })
  const shown = await rows(ui)
  expect(shown[1]).toMatch(/^◆ main ─+┬─+$/)
  expect(shown[5]).toMatch(/^╰─ 0 step ─+  0:00 ─╯$/)
  expect(await ui.findAll({ type: 'Client' })).toEqual([])
  await ui.unmount()
})
