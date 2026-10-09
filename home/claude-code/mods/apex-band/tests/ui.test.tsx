import { expect, mock, test } from 'claude-code/testing'
import type { Plugin } from 'claude-code/testing'
import type { AgentInfo, On } from 'claude-code'

// The poll and the 1 s tick, with the pane closed: what they read and write.

const NOW = 1_000_000_000
const HOME = '/home/u'
const RUN_DIR = '/work/.claude/output/apex/my-run'

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

type Agent = AgentInfo

type World = {
  // The run's context written `ageMs` before NOW, or no apex folder at all.
  files?: { ageMs: number } | null
  // .git/HEAD, missing when undefined.
  head?: string
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
}

const RUNNING: Agent = { id: 'a1', description: 'scan engine types', type: 'Explore', status: 'running' }

test('idle: no 1 s tick', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, { reads })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const atStart = reads.agents
  // Short of the 5 s poll: only a 1 s tick could read the agent list again.
  await clock.advance(3000)
  expect(reads.agents).toBe(atStart)
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
})

// Reads the pane's clock atom from beside the plugin (a test hook has no
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

test('pane closed: the clock is never written, a live run or work in flight alike', { plugins: [CLOCK_PROBE] }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const reads = { agents: 0 }
  world(on, { reads, agents: [RUNNING] })
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await clock.settle()
  const atStart = reads.agents
  await clock.advance(3 * 60_000)
  // The poll and the tick did run (the check can fail): only the clock stood still.
  expect(reads.agents).toBeGreaterThan(atStart)
  expect((await $.command.run(PROBE_NOW)).text).toBe('0')
})
