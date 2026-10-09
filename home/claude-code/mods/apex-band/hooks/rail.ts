// The main loop's rail, a surface module (ClientModule): a ─ line with a ┬
// where each subagent leaves it and a ● head that runs along it every
// STEP_MS while something works. Self-contained: no runtime import, no wall
// clock; the head moves only on the surface's own timer.
// railFrame is pure, so the hooks module draws the same frame as static text
// where no Client exists.

import type { ClientModule, ClientSurface, ThemeKey } from 'claude-code'

// One step of the head, in milliseconds.
export const STEP_MS = 110

// Cells the head spends past the right end before it comes back.
export const RAIL_GAP = 24

// What the hooks module hands the rail: its cells, the drop columns (0 at
// the rail's left end), whether something works, and its tone.
export type RailProps = { cells: number; drops: number[]; active: boolean; tone: ThemeKey }

// The instance's local state: the head's phase and a box holding the latest
// props, so the timer reads them without a redraw of its own.
export type RailState = { phase: number; box: { props: RailProps } }

// The rail as text, `cells` wide: ─ everywhere, ┬ at each drop, the ● head
// at phase % (cells + RAIL_GAP) and a • trail just behind it. A negative
// phase draws no head; a drop under the trail stays a ┬, the head covers it.
export function railFrame(cells: number, drops: readonly number[], phase: number): string {
  const n = Math.max(0, Math.floor(cells))
  const out: string[] = Array.from({ length: n }, () => '─')
  for (const d of drops) if (Number.isInteger(d) && d >= 0 && d < n) out[d] = '┬'
  if (phase >= 0 && n > 0) {
    const head = Math.floor(phase) % (n + RAIL_GAP)
    const trail = head - 1
    if (trail >= 0 && trail < n && out[trail] !== '┬') out[trail] = '•'
    if (head < n) out[head] = '●'
  }
  return out.join('')
}

// Draws the rail; the first call starts the one timer, which moves the head
// only while the latest props say something works.
const Rail: ClientModule<RailProps, RailState> = (props, surface: ClientSurface<RailState>) => {
  const state = surface.state
  if (state === undefined) {
    const box = { props }
    surface.setState({ phase: 0, box })
    surface.every(STEP_MS, () => {
      const now = surface.state
      if (now === undefined || !now.box.props.active) return
      surface.setState({ phase: now.phase + 1, box: now.box })
    })
  } else {
    // The latest props, read by the next tick; no setState here.
    state.box.props = props
  }
  const phase = props.active ? (state?.phase ?? 0) : -1
  return surface.elements.Text({ color: props.tone, wrap: 'truncate', children: railFrame(props.cells, props.drops, phase) })
}

export default Rail
