// A running clock, a surface module (ClientModule): the hooks module hands a
// base duration (ms), the instance adds a second per tick of its own timer
// while `running`, and starts over from each new base. Self-contained: no
// runtime import, no wall clock. clockText is pure, so the hooks module
// draws the same text where no Client exists.

import type { ClientModule, ClientSurface } from 'claude-code'

// One tick of the clock, in milliseconds.
export const TICK_MS = 1000

// What the hooks module hands the clock: the duration so far, whether it
// still runs, and its style (a theme key or null, dim or not).
export type ElapsedProps = { ms: number; running: boolean; tone: string | null; dim: boolean }

// The base last read, the ticks counted since, and a box holding the latest
// props for the timer.
export type ElapsedState = { base: number; ticks: number; box: { props: ElapsedProps } }

const pad2 = (n: number): string => String(n).padStart(2, '0')

// A duration as five cells: ` 0:07`, `12:34`, `59:59`, then ` 1h00`, `12h05`.
export function clockText(ms: number): string {
  const seconds = Math.floor(Math.max(0, Number.isFinite(ms) ? ms : 0) / 1000)
  const minutes = Math.floor(seconds / 60)
  const text = minutes < 60 ? `${minutes}:${pad2(seconds % 60)}` : `${Math.floor(minutes / 60)}h${pad2(minutes % 60)}`
  return text.padStart(5)
}

// Draws the clock; the first call starts the one timer, which counts only
// while the latest props run, and restarts from a base the host changed.
const Elapsed: ClientModule<ElapsedProps, ElapsedState> = (props, surface: ClientSurface<ElapsedState>) => {
  const state = surface.state
  if (state === undefined) {
    const box = { props }
    surface.setState({ base: props.ms, ticks: 0, box })
    surface.every(TICK_MS, () => {
      const now = surface.state
      if (now === undefined || !now.box.props.running) return
      const base = now.box.props.ms
      surface.setState({ base, ticks: base === now.base ? now.ticks + 1 : 1, box: now.box })
    })
  } else {
    state.box.props = props
  }
  const shown = state !== undefined && state.base === props.ms && props.running ? state.base + state.ticks * TICK_MS : props.ms
  return surface.elements.Text({
    ...(props.tone === null ? {} : { color: props.tone }),
    ...(props.dim ? { dimColor: true } : {}),
    children: clockText(shown),
  })
}

export default Elapsed
