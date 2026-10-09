import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = Date.parse('2026-10-09T12:00:00Z')

const HINT = {
  component: 'PromptHint',
  props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
} as const

// A session in /work/sub of a repo at /work on feat/x, 42% of its context,
// a 5h window at 61.5% resetting in 42 minutes; the engine's hint beneath.
function world(on: On): void {
  on('session.start', () => ({ cwd: '/work/sub' }))
  on('session.cwd', () => ({ value: '/work/sub' }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('session.usage', () => ({
    value: {
      startedAt: NOW,
      context: { tokens: 84_000, window: 200_000, percent: 42 },
      rateLimits: [{ kind: 'five_hour', percentUsed: 61.5, resetsAt: new Date(NOW + 42 * 60_000).toISOString() }],
    },
  }))
  on('fs.stat', ($, e) => {
    if (e.path !== '/work/.git') return { deny: 'ENOENT' }
    return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false } }
  })
  on('fs.read', ($, e) => (e.path === '/work/.git/HEAD' ? { value: 'ref: refs/heads/feat/x\n' } : { deny: 'ENOENT' }))
  on('ui.render', { component: 'PromptHint' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{e.props.hint}</Text>
  })
}

test('the status rows are drawn above the hint line, which is kept', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  world(on)
  await $.session.start({ cwd: '/work/sub', surface: 'terminal', isInteractive: true })
  await clock.settle()
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'status-bar', surface, ...HINT })
    expect((await ui.find({ type: 'Text', text: '🤖 Opus 5.5' }))?.props.color).toBe('#ff5f5f')
    expect(await ui.find({ type: 'Text', text: '📁 sub' })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: '⎇ feat/x' }))?.props.color).toBe('#ffd75f')
    expect(await ui.find({ type: 'Text', text: '📊 84,000/0' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: ' 42%' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: ' 62% · 42min' })).toBeDefined()
    expect((await ui.find({ type: 'Text', text: '██████' }))?.props.color).toBe('#ff8700')
    const hint = await ui.find({ type: 'Text', text: '? for shortcuts' })
    expect(hint?.props.dimColor).toBe(true)
    const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
    expect(texts.at(-1)).toBe('? for shortcuts')
    await ui.unmount()
  }
})
