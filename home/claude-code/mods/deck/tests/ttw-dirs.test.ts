// The run folders and the budget dir, through the hooks only (no import of the run reader,
// whatever its file is called): runs are read from `.claude/output/ttw` alone, the correction
// budget from `~/.claude/ttw-correction-budget` alone, a run only under `.claude/output/apex`
// draws nothing, writes under `.claude/output/ttw/` are plan, and /ttw-pane opens the pane.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = 1_000_000_000

// `ttw` is the run folder; `apex` is the pre-rename folder, which must stay unread.
type Dir = 'apex' | 'ttw'

const pane = (bodyColumns: number) => ({
  plugin: 'deck',
  component: 'Pane' as const,
  requestId: 'deck',
  surface: 'terminal' as const,
  props: {
    title: 'Deck',
    isFocused: true,
    bodyColumns,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 70 },
    view: {},
  },
})

const command = (name: string) =>
  ({ command: name, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } }) as const

const exact = (text: string): RegExp => new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)

// A run's 00-context.md, a Branch line unless `branch` is null.
const context = (title: string, branch: string | null) => `# TTW: ${title}
Tier: Standard
${branch === null ? '' : `Branch: ${branch}\n`}
## Progress
| Step | Status | Notes |
|------|--------|-------|
| 00-init | complete | |
| 03-execute | in progress | |
| 09-finish | pending | |
`

type Run = { dir: Dir; name: string; text: string; mtimeMs: number; verdict?: string }

// Budget files in the ttw dir: `<run>.round<N>` / `<run>.grant<N>` names.
// `head`: the branch .git/HEAD names; unset, there is no HEAD.
type World = { runs: Run[]; budget: readonly string[]; opened: unknown[]; head?: string }

const root = (dir: Dir) => `/work/.claude/output/${dir}`
const BUDGET_DIR = '/home/u/.claude/ttw-correction-budget'

// /work, HOME /home/u, .git/HEAD only when `head` is set (unset, the branch is unknown: every
// run is on it). A path the world does not hold throws, as a missing file does.
function world(on: On, w: World): void {
  on('session.start', () => ({ cwd: '/work' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('env.get', () => ({ value: '/home/u' }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 1.5 } } }))
  on('agent.list', () => ({ value: [] }))
  on('fs.list', (_$, e) => {
    for (const dir of ['apex', 'ttw'] as const) {
      const here = w.runs.filter(r => r.dir === dir)
      if (e.path === root(dir) && here.length > 0)
        return { value: here.map(r => ({ name: r.name, kind: 'dir' as const, size: 0, mtimeMs: r.mtimeMs, isLink: false })) }
      const run = here.find(r => e.path === `${root(dir)}/${r.name}`)
      if (run !== undefined)
        return {
          value: [
            { name: '00-context.md', kind: 'file' as const, size: 1, mtimeMs: run.mtimeMs, isLink: false },
            ...(run.verdict === undefined ? [] : [{ name: 'external-verify.json', kind: 'file' as const, size: 1, mtimeMs: run.mtimeMs, isLink: false }]),
          ],
        }
    }
    if (e.path === BUDGET_DIR && w.budget.length > 0)
      return { value: w.budget.map(name => ({ name, kind: 'file' as const, size: 0, mtimeMs: 0, isLink: false })) }
    throw new Error('ENOENT')
  })
  on('fs.stat', (_$, e) => {
    for (const r of w.runs) {
      if (e.path === `${root(r.dir)}/${r.name}` || e.path === `${root(r.dir)}/${r.name}/00-context.md`)
        return { value: { kind: e.path.endsWith('.md') ? 'file' : 'dir', size: 1, mtimeMs: r.mtimeMs, isLink: false } }
    }
    throw new Error('ENOENT')
  })
  on('fs.read', (_$, e) => {
    if (w.head !== undefined && e.path === '/work/.git/HEAD') return { value: `ref: refs/heads/${w.head}\n` }
    for (const r of w.runs) {
      if (e.path === `${root(r.dir)}/${r.name}/00-context.md`) return { value: r.text }
      if (r.verdict !== undefined && e.path === `${root(r.dir)}/${r.name}/external-verify.json`) return { value: r.verdict }
    }
    throw new Error('ENOENT')
  })
  on('ui.open', (_$, e) => {
    w.opened.push({ id: e.id, title: e.title })
    return { value: { isPlaced: true } }
  })
  on('ui.close', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('session.end', () => ({ sessionId: 's1' }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
}

const fresh = (runs: Run[], budget: readonly string[] = []): World => ({ runs, budget, opened: [] })

const START = { cwd: '/work', surface: 'terminal', isInteractive: true } as const

// The block's header: `TTW · <rest>`.
const header = (rest: string): RegExp => new RegExp(`^TTW · ${rest.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)

test('a live run under .claude/output/ttw draws the block; a `# TTW:` title reads as its title', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'ttw', name: 'ttw-run', text: context('renamed run', null), mtimeMs: NOW - 1000 }]))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: header('renamed run · Standard') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /TTW: renamed run/ })).toBeUndefined()
  await ui.unmount()
})

test('a run only under .claude/output/apex draws nothing', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'apex', name: 'old-run', text: context('old run', 'feat/old'), mtimeMs: NOW - 1000 }], ['old-run.round1', 'old-run.round2']))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ text: /^TTW/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /old run|feat\/old/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /correction budget spent/ })).toBeUndefined()
  await ui.unmount()
})

test('a ttw run reads its external verify from its own folder', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const verdict = JSON.stringify({ verdict: 'FAIL', findings: [{ problem: 'a' }] })
  world(on, fresh([{ dir: 'ttw', name: 'ttw-run', text: context('v', 'feat/v'), mtimeMs: NOW - 1000, verdict }]))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect((await ui.find({ type: 'Text', text: exact('✗ external verify FAIL · 1 finding') }))?.props.color).toBe('error')
  await ui.unmount()
})

test('the budget is read from the ttw dir: both rounds → spent', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'ttw', name: 'my-run', text: context('b', 'feat/b'), mtimeMs: NOW - 1000 }], ['my-run.round1', 'my-run.round2']))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: header('feat/b · Standard') })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: exact('∅ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
  await ui.unmount()
})

test('control: one round alone is not spent', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'ttw', name: 'my-run', text: context('b', 'feat/b'), mtimeMs: NOW - 1000 }], ['my-run.round1']))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: /correction budget spent/ })).toBeUndefined()
  await ui.unmount()
})

test('a grant raises the cap: both rounds and one grant → 2/3, not spent', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'ttw', name: 'my-run', text: context('b', 'feat/b'), mtimeMs: NOW - 1000 }], ['my-run.round1', 'my-run.round2', 'my-run.grant1']))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: /correction budget spent/ })).toBeUndefined()
  await ui.unmount()
})

test('only the newest run of the folder is read: off-branch it draws nothing, an older on-branch run is not a fallback', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh([
    { dir: 'ttw', name: 'on-ttw', text: context('on branch', 'feat/on'), mtimeMs: NOW - 2000 },
    { dir: 'ttw', name: 'off-ttw', text: context('off branch', 'feat/off'), mtimeMs: NOW - 1000 },
  ])
  w.head = 'feat/on'
  world(on, w)
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ text: /^TTW/ })).toBeUndefined()
  await ui.unmount()

  // Control: on the newest run's branch the same world draws it.
  w.head = 'feat/off'
  await clock.advance(5000)
  const on2 = await $.ui.mount(pane(120))
  expect(await on2.find({ type: 'Text', text: header('feat/off · Standard') })).toBeDefined()
  await on2.unmount()
})

test('writes under .claude/output/ttw/ are plan, not edit', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([]))
  on('tool.call', () => ({ result: { ok: true } }))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  await $.tool.call({ tool: 'Skill', skill: 'ttw', args: 'brief 1', tool_use_id: 'tu-skill-1' })
  await $.tool.call({ tool: 'Write', file_path: '/work/.claude/output/ttw/r/02-plan.md', content: 'x' })
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: exact('◐ plan') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
  await ui.unmount()
})

test('/ttw-pane opens the deck pane', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh([])
  world(on, w)
  const answer = await $.command.run(command('ttw-pane'))
  expect(answer.text).toBe('Deck opened. Focus it with ctrl+x tab; 1-6 expand cards.')
  expect(w.opened).toEqual([{ id: 'deck', title: 'Deck' }])
  await clock.settle()
})
