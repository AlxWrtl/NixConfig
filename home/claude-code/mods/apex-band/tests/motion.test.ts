import type { ClientSurface } from 'claude-code'
import { describe, expect, test } from 'claude-code/testing'

import Elapsed, { TICK_MS, clockText } from '../hooks/elapsed.ts'
import type { ElapsedProps, ElapsedState } from '../hooks/elapsed.ts'
import Rail, { RAIL_GAP, STEP_MS, railFrame } from '../hooks/rail.ts'
import type { RailProps, RailState } from '../hooks/rail.ts'

// A surface module's surface, faked: its state, the setState calls and the
// timers it started; Text hands its props back so the drawn text reads.
type Timer = { ms: number; fn: () => void }
type Fake<S> = { surface: ClientSurface<S>; sets: () => number; timers: Timer[] }

function fake<S>(): Fake<S> {
  let state: S | undefined
  let sets = 0
  const timers: Timer[] = []
  const surface = {
    elements: { Text: (props: object) => ({ props }) },
    get state(): S | undefined {
      return state
    },
    setState: (next: S): void => {
      state = next
      sets += 1
    },
    columns: 0,
    rows: 0,
    every: (ms: number, fn: () => void): (() => void) => {
      timers.push({ ms, fn })
      return () => undefined
    },
    onPointer: () => () => undefined,
    onKey: () => () => undefined,
    post: (): void => undefined,
  } as unknown as ClientSurface<S>
  return { surface, sets: () => sets, timers }
}

const drawn = (el: unknown): string => String((el as { props: { children: unknown } }).props.children)
const fire = (timers: readonly Timer[]): void => {
  for (const t of timers) t.fn()
}

describe('railFrame', () => {
  test('the head advances one cell per phase, a • trail behind it', () => {
    expect(railFrame(10, [], 0)).toBe('●─────────')
    expect(railFrame(10, [], 1)).toBe('•●────────')
    expect(railFrame(10, [], 5)).toBe('────•●────')
  })

  test('the head wraps at cells + RAIL_GAP, off the rail in between', () => {
    expect(RAIL_GAP).toBe(24)
    expect(railFrame(10, [], 10 + RAIL_GAP)).toBe(railFrame(10, [], 0))
    expect(railFrame(10, [], 11)).toBe('──────────')
    expect(railFrame(10, [], 10)).toBe('─────────•')
    expect(railFrame(10, [], 10 + RAIL_GAP - 1)).toBe('──────────')
  })

  test('a drop is kept where no head is, under the trail too; the head covers it', () => {
    expect(railFrame(10, [2, 7], -1)).toBe('──┬────┬──')
    expect(railFrame(10, [2, 7], 3)).toBe('──┬●───┬──')
    expect(railFrame(10, [2, 7], 2)).toBe('─•●────┬──')
    // Drops off the rail are ignored.
    expect(railFrame(4, [-1, 4, 1.5], -1)).toBe('────')
    expect(railFrame(0, [0], 0)).toBe('')
  })

  test('the step is 110 ms', () => {
    expect(STEP_MS).toBe(110)
  })
})

describe('clockText', () => {
  test('m:ss under an hour, then XhYY, five cells', () => {
    expect(clockText(0)).toBe(' 0:00')
    expect(clockText(7_999)).toBe(' 0:07')
    expect(clockText(12 * 60_000 + 34_000)).toBe('12:34')
    expect(clockText(59 * 60_000 + 59_000)).toBe('59:59')
    expect(clockText(60 * 60_000)).toBe(' 1h00')
    expect(clockText(12 * 3_600_000 + 5 * 60_000)).toBe('12h05')
    expect(clockText(-5)).toBe(' 0:00')
    expect(clockText(Number.NaN)).toBe(' 0:00')
  })
})

describe('Rail surface module', () => {
  const props: RailProps = { cells: 8, drops: [3], active: true, tone: 'claude' }

  test('the first call sets state once and starts one timer; a redraw sets nothing', () => {
    const f = fake<RailState>()
    expect(drawn(Rail(props, f.surface))).toBe('●──┬────')
    expect(f.sets()).toBe(1)
    expect(f.timers.map(t => t.ms)).toEqual([STEP_MS])
    Rail(props, f.surface)
    Rail({ ...props, drops: [5] }, f.surface)
    expect(f.sets()).toBe(1)
    expect(f.timers).toHaveLength(1)
  })

  test('each tick moves the head while active; inactive, no state and no head', () => {
    const f = fake<RailState>()
    Rail(props, f.surface)
    fire(f.timers)
    fire(f.timers)
    expect(f.sets()).toBe(3)
    expect(drawn(Rail(props, f.surface))).toBe('─•●┬────')
    const idle = { ...props, active: false }
    expect(drawn(Rail(idle, f.surface))).toBe('───┬────')
    fire(f.timers)
    expect(f.sets()).toBe(3)
  })
})

describe('Elapsed surface module', () => {
  const props: ElapsedProps = { ms: 5_000, running: true, tone: null, dim: true }

  test('counts a second per tick from the base, starts over on a new base', () => {
    const f = fake<ElapsedState>()
    expect(drawn(Elapsed(props, f.surface))).toBe(' 0:05')
    expect(f.sets()).toBe(1)
    expect(f.timers.map(t => t.ms)).toEqual([TICK_MS])
    fire(f.timers)
    fire(f.timers)
    expect(drawn(Elapsed(props, f.surface))).toBe(' 0:07')
    // The host hands a new base: drawn as is, then counted from.
    const later = { ...props, ms: 60_000 }
    expect(drawn(Elapsed(later, f.surface))).toBe(' 1:00')
    fire(f.timers)
    expect(drawn(Elapsed(later, f.surface))).toBe(' 1:01')
    expect(f.sets()).toBe(4)
  })

  test('stopped: the base drawn, no tick sets state', () => {
    const f = fake<ElapsedState>()
    const stopped = { ...props, running: false }
    Elapsed(stopped, f.surface)
    fire(f.timers)
    fire(f.timers)
    expect(f.sets()).toBe(1)
    expect(drawn(Elapsed(stopped, f.surface))).toBe(' 0:05')
  })
})
