// The ttw rename, phase 3, through the hooks only (no import of the run reader, whatever its
// file is called): runs are read from BOTH `.claude/output/apex` and `.claude/output/ttw` (the
// newest of the union wins), the correction budget from both `~/.claude/apex-correction-budget`
// and `~/.claude/ttw-correction-budget` (rounds summed), a `# TTW:` title reads like `# APEX:`,
// writes under `.claude/output/ttw/` are plan, and /apex-pane keeps opening the pane next to
// /ttw-pane.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = 1_000_000_000
const HOUR = 60 * 60 * 1000

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

// A run's 00-context.md: heading word APEX or TTW, a Branch line unless `branch` is null.
const context = (word: 'APEX' | 'TTW', title: string, branch: string | null) => `# ${word}: ${title}
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

// Budget files per dir: `<run>.round<N>` / `<run>.grant<N>` names.
type World = { runs: Run[]; budget: Partial<Record<Dir, readonly string[]>>; opened: unknown[] }

const root = (dir: Dir) => `/work/.claude/output/${dir}`
const budgetDir = (dir: Dir) => `/home/u/.claude/${dir}-correction-budget`

// /work, HOME /home/u, no .git/HEAD (branch unknown: every run is on it). A path the world does
// not hold throws, as a missing file does.
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
      const names = w.budget[dir]
      if (e.path === budgetDir(dir) && names !== undefined)
        return { value: names.map(name => ({ name, kind: 'file' as const, size: 0, mtimeMs: 0, isLink: false })) }
    }
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

const fresh = (runs: Run[], budget: World['budget'] = {}): World => ({ runs, budget, opened: [] })

const START = { cwd: '/work', surface: 'terminal', isInteractive: true } as const

// The block's header: its first word is the run label (APEX today, maybe TTW after the rename);
// only what follows it is asserted here.
const header = (rest: string): RegExp => new RegExp(`^[A-Z]+ · ${rest.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)

test('a live run under .claude/output/ttw alone draws the block; a `# TTW:` title reads as its title', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'ttw', name: 'ttw-run', text: context('TTW', 'renamed run', null), mtimeMs: NOW - 1000 }]))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: header('renamed run · Standard') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /TTW: renamed run/ })).toBeUndefined()
  await ui.unmount()
})

test('runs are the union of both dirs: the newest wins, from either side', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const w = fresh([
    { dir: 'apex', name: 'old-apex', text: context('APEX', 'apex side', 'feat/apex-side'), mtimeMs: NOW - HOUR },
    { dir: 'ttw', name: 'new-ttw', text: context('TTW', 'ttw side', 'feat/ttw-side'), mtimeMs: NOW - 1000 },
  ])
  world(on, w)
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ttwNewer = await $.ui.mount(pane(120))
  expect(await ttwNewer.find({ type: 'Text', text: header('feat/ttw-side · Standard') })).toBeDefined()
  expect(await ttwNewer.find({ type: 'Text', text: header('feat/apex-side · Standard') })).toBeUndefined()
  await ttwNewer.unmount()

  // The other way round: the apex run moves past the ttw one, the apex dir is still read.
  w.runs = [
    { dir: 'apex', name: 'old-apex', text: context('APEX', 'apex side', 'feat/apex-side'), mtimeMs: NOW + 4000 },
    { dir: 'ttw', name: 'new-ttw', text: context('TTW', 'ttw side', 'feat/ttw-side'), mtimeMs: NOW - HOUR },
  ]
  await clock.advance(5000)
  const apexNewer = await $.ui.mount(pane(120))
  expect(await apexNewer.find({ type: 'Text', text: header('feat/apex-side · Standard') })).toBeDefined()
  expect(await apexNewer.find({ type: 'Text', text: header('feat/ttw-side · Standard') })).toBeUndefined()
  await apexNewer.unmount()
})

test('a ttw run reads its external verify from its own folder', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const verdict = JSON.stringify({ verdict: 'FAIL', findings: [{ problem: 'a' }] })
  world(on, fresh([{ dir: 'ttw', name: 'ttw-run', text: context('TTW', 'v', 'feat/v'), mtimeMs: NOW - 1000, verdict }]))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect((await ui.find({ type: 'Text', text: exact('✗ external verify FAIL · 1 finding') }))?.props.color).toBe('error')
  await ui.unmount()
})

for (const [label, budget] of [
  ['one round in each dir', { apex: ['my-run.round1'], ttw: ['my-run.round2'] }],
  ['both rounds in the ttw dir only', { ttw: ['my-run.round1', 'my-run.round2'] }],
] as const) {
  test(`budget stamps are read from both dirs: ${label} → spent`, async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    world(on, fresh([{ dir: 'apex', name: 'my-run', text: context('APEX', 'b', 'feat/b'), mtimeMs: NOW - 1000 }], budget))
    await $.session.start(START)
    await $.command.run(command('deck'))
    await clock.settle()
    const ui = await $.ui.mount(pane(80))
    expect((await ui.find({ type: 'Text', text: exact('∅ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
    await ui.unmount()
  })
}

test('control: the same world draws an apex-only run, both rounds in the apex dir → spent', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'apex', name: 'my-run', text: context('APEX', 'b', 'feat/b'), mtimeMs: NOW - 1000 }], { apex: ['my-run.round1', 'my-run.round2'] }))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: header('feat/b · Standard') })).toBeDefined()
  expect((await ui.find({ type: 'Text', text: exact('∅ correction budget spent · 2/2 rounds') }))?.props.color).toBe('error')
  await ui.unmount()
})

test('control: one round in the apex dir alone is not spent', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([{ dir: 'apex', name: 'my-run', text: context('APEX', 'b', 'feat/b'), mtimeMs: NOW - 1000 }], { apex: ['my-run.round1'] }))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  const ui = await $.ui.mount(pane(80))
  expect(await ui.find({ type: 'Text', text: /correction budget spent/ })).toBeUndefined()
  await ui.unmount()
})

for (const dir of ['apex', 'ttw'] as const) {
test(`writes under .claude/output/${dir}/ are plan, not edit`, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on, fresh([]))
  on('tool.call', () => ({ result: { ok: true } }))
  await $.session.start(START)
  await $.command.run(command('deck'))
  await clock.settle()
  await $.tool.call({ tool: 'Skill', skill: 'ttw', args: 'brief 1', tool_use_id: 'tu-skill-1' })
  await $.tool.call({ tool: 'Write', file_path: `/work/.claude/output/${dir}/r/02-plan.md`, content: 'x' })
  await clock.advance(5000)
  const ui = await $.ui.mount(pane(120))
  expect(await ui.find({ type: 'Text', text: exact('◐ plan') })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: exact('○ edit') })).toBeDefined()
  await ui.unmount()
})
}

for (const name of ['ttw-pane', 'apex-pane']) {
  test(`/${name} opens the deck pane (the old name stays an alias)`, async ($, on) => {
    const clock = mock.clock(on, { now: NOW })
    const w = fresh([])
    world(on, w)
    const answer = await $.command.run(command(name))
    expect(answer.text).toBe('Deck opened. Focus it with ctrl+x tab; 1-6 expand cards.')
    expect(w.opened).toEqual([{ id: 'deck', title: 'Deck' }])
    await clock.settle()
  })
}
