## Hundreds of particles drifting through a slowly changing flow field,
## each leaving a fading trail. The pointer stirs a whirlpool into the
## field; holding the button down turns it into a drain that pulls
## everything in.
##
## Shows: many long strokes per frame, a linear gradient along each trail
## that fades it from tail to head, color from the direction of travel, and
## a dashed ring whose dashes turn with the stirring.

import std/[math, random]
import ./scene

type
  Agent = object
    trail: seq[Point] ## Oldest first; the last point is the head.
    age, life: float64

  FlowField* = object
    rng: Rand
    time, stir, pull: float64
    agents: seq[Agent]
    pointer: Point

const
  agentCount = 260
  trailLength = 26
  speed = 70.0
  stirRadius = 130.0

func fieldAngle(p: Point, t: float64): float64 =
  ## The direction of the flow at `p`: a few sine waves at different
  ## scales, drifting over time. Smooth everywhere, never repeating quickly.
  let x = p.x
  let y = p.y
  1.6 * sin(x * 0.009 + t * 0.21) + 1.4 * cos(y * 0.011 - t * 0.17) +
    0.8 * sin((x + y) * 0.006 + t * 0.13) + 0.5 * cos((x - 2 * y) * 0.013 + t * 0.29)

proc spawn(s: var FlowField): Agent =
  result.trail = @[point(s.rng.rand(sceneWidth), s.rng.rand(sceneHeight))]
  result.life = s.rng.rand(4.0 .. 9.0)

func newFlowField*(): FlowField =
  result = FlowField(rng: initRand(99), pointer: point(sceneWidth / 2, sceneHeight / 2))
  for _ in 0 ..< agentCount:
    var a = result.spawn()
    # Start partway through their lives so they don't all fade at once.
    a.age = result.rng.rand(a.life)
    result.agents.add a

proc update*(s: var FlowField, dt: float64, input: Input) =
  s.time += dt
  s.stir = approach(s.stir, (if input.inside: 1.0 else: 0.0), 3, dt)
  s.pull = approach(s.pull, (if input.inside and input.down: 1.0 else: 0.0), 4, dt)
  if input.inside:
    s.pointer = input.pos
  for a in s.agents.mitems:
    let head = a.trail[^1]
    let angle = fieldAngle(head, s.time)
    var v = vec2(cos(angle), sin(angle)) * speed
    let toPointer = s.pointer - head
    let d = toPointer.length
    if d > 1 and d < stirRadius * 1.6:
      # Swirl around the pointer, strongest close in, and with the button
      # down also fall toward it.
      let falloff = exp(-(d / stirRadius) ^ 2)
      let around = toPointer.perp / d
      v =
        v + around * (170 * falloff * s.stir) + toPointer / d * (160 * falloff * s.pull)
    a.trail.add head + v * dt
    if a.trail.len > trailLength:
      a.trail.delete 0
    a.age += dt
    let p = a.trail[^1]
    let outside =
      p.x < -20 or p.y < -20 or p.x > sceneWidth + 20 or p.y > sceneHeight + 20
    if a.age > a.life or outside or (s.pull > 0.5 and d < 6):
      a = s.spawn()

proc render*[C: RenderContext](s: FlowField, ctx: var C) =
  ctx.fill(
    sceneBounds,
    radialGradient(
      point(sceneWidth / 2, sceneHeight / 2), 400, rgb8(22, 26, 40), rgb8(8, 9, 14)
    ),
  )
  let style = strokeStyle(width = 1.7, cap = lcRound, join = ljBevel)
  for a in s.agents:
    if a.trail.len < 2:
      continue
    let head = a.trail[^1]
    let tail = a.trail[0]
    let dir = head - a.trail[^2]
    # Fade in at birth and out at the end of life.
    let alpha = min(1.0, min(a.age, a.life - a.age) * 1.5).max(0)
    let hue = 0.55 + 0.18 * sin(arctan2(dir.y, dir.x))
    ctx.stroke(
      polygonPath(a.trail, closed = false),
      linearGradient(
        tail, head, hsl(hue, 0.8, 0.6, 0), hsl(hue, 0.85, 0.65, 0.9 * alpha)
      ),
      style,
    )
  if s.stir > 0.01:
    let ring = stirRadius * (0.55 - 0.25 * s.pull)
    ctx.stroke(
      circle(s.pointer, ring),
      white.withAlpha(0.25 * s.stir),
      strokeStyle(width = 1.5, dashes = [10.0, 8.0], dashOffset = -s.time * 40),
    )
    ctx.fill(circle(s.pointer, 3 + 3 * s.pull), white.withAlpha(0.5 * s.stir))
