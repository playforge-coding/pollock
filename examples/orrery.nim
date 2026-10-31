## A small solar system seen at an angle. Moving the pointer up and down
## tilts the view, and left and right changes how fast time runs.
##
## Shows: radial gradients for the sun's glow and the lit side of each
## planet, a clip that confines the night-side shadow to the planet, nested
## transforms and clips that draw a ring half behind and half in front of its
## planet, dashed ellipses, and drawing order sorted by depth.

import std/[algorithm, math, random]
import ./scene

type
  Star = object
    pos: Point
    radius, phase, rate: float64

  Planet = object
    orbit, period, size: float64
    light, dark: Color
    moon, ring: bool

  Orrery* = object
    time, speed, tilt: float64
    stars: seq[Star]

const
  sun = point(sceneWidth / 2, sceneHeight / 2)
  planets = [
    Planet(
      orbit: 62, period: 4, size: 5, light: rgb8(200, 190, 180), dark: rgb8(80, 70, 65)
    ),
    Planet(
      orbit: 100,
      period: 7,
      size: 9,
      light: rgb8(250, 205, 130),
      dark: rgb8(150, 85, 40),
    ),
    Planet(
      orbit: 145,
      period: 11,
      size: 10,
      light: rgb8(120, 180, 255),
      dark: rgb8(20, 55, 130),
      moon: true,
    ),
    Planet(
      orbit: 195,
      period: 17,
      size: 7,
      light: rgb8(245, 130, 90),
      dark: rgb8(115, 40, 30),
    ),
    Planet(
      orbit: 265,
      period: 29,
      size: 16,
      light: rgb8(235, 210, 160),
      dark: rgb8(125, 95, 60),
      ring: true,
    ),
  ]

func newOrrery*(): Orrery =
  result = Orrery(speed: 1, tilt: 0.4)
  var rng = initRand(7)
  for _ in 0 ..< 160:
    result.stars.add Star(
      pos: point(rng.rand(sceneWidth), rng.rand(sceneHeight)),
      radius: 0.4 + rng.rand(1.0) ^ 3 * 1.4,
      phase: rng.rand(2 * PI),
      rate: 0.5 + rng.rand(2.5),
    )

proc update*(s: var Orrery, dt: float64, input: Input) =
  let (targetTilt, targetSpeed) =
    if input.inside:
      (
        0.15 + 0.85 * clamp(input.pos.y / sceneHeight, 0, 1),
        0.2 + 4.8 * clamp(input.pos.x / sceneWidth, 0, 1) ^ 2,
      )
    else:
      (0.4, 1.0)
  s.tilt = approach(s.tilt, targetTilt, 4, dt)
  s.speed = approach(s.speed, targetSpeed, 3, dt)
  s.time += dt * s.speed

func onOrbit(s: Orrery, radius, angle: float64): Point =
  ## A point on a circular orbit around the sun, squashed by the view's tilt.
  sun + vec2(cos(angle) * radius, sin(angle) * radius * s.tilt)

proc drawPlanet[C: RenderContext](ctx: var C, s: Orrery, p: Planet, at: Point) =
  # The sun is off to one side of every planet. Light comes from there.
  let toSun = (sun - at).normalized
  let body = circle(at, p.size)
  ctx.fill(
    body, radialGradient(at + toSun * (p.size * 0.5), p.size * 1.6, p.light, p.dark)
  )
  ctx.withClip(body):
    ctx.fill(
      circle(at - toSun * (p.size * 1.1), p.size * 1.25), rgb8(5, 5, 20).withAlpha(0.6)
    )

proc drawRingHalf[C: RenderContext](
    ctx: var C, s: Orrery, p: Planet, at: Point, front: bool
) =
  # The ring is a circle squashed by the tilt, cut along its long axis so the
  # back half goes behind the planet and the front half over it.
  let half =
    if front:
      rect(-60, 0, 60, 60)
    else:
      rect(-60, -60, 60, 0)
  ctx.withTransform(translate(at.toVec) * rotate(-0.3)):
    ctx.withClip(half):
      ctx.withTransform(scale(1, max(s.tilt, 0.08))):
        ctx.stroke(
          circle(0, 0, p.size * 1.9), rgb8(230, 210, 170).withAlpha(0.55), p.size * 0.5
        )
        ctx.stroke(
          circle(0, 0, p.size * 2.35),
          rgb8(200, 180, 150).withAlpha(0.35),
          p.size * 0.18,
        )

proc drawSun[C: RenderContext](ctx: var C, s: Orrery) =
  let pulse = 1 + 0.04 * sin(s.time * 3)
  ctx.fill(
    circle(sun, 90 * pulse),
    radialGradient(
      sun,
      90 * pulse,
      [
        stop(0.0, rgba8(255, 230, 150, 230)),
        stop(0.25, rgba8(255, 170, 60, 110)),
        stop(1.0, rgba8(255, 110, 40, 0)),
      ],
    ),
  )
  ctx.fill(
    circle(sun, 24),
    radialGradient(
      sun - vec2(7, 7),
      30,
      [stop(0.0, white), stop(0.5, rgb8(255, 230, 120)), stop(1.0, rgb8(255, 150, 40))],
    ),
  )

proc drawComet[C: RenderContext](ctx: var C, s: Orrery) =
  # A long ellipse with the sun near one end. The tail points away from it.
  let e = 2 * PI * s.time / 13
  let head = sun + vec2(170 + 300 * cos(e), 120 * sin(e) * s.tilt)
  let away = (head - sun).normalized
  # The direction the comet has come from, so the tail can trail behind.
  let velocity = vec2(-300 * sin(e), 120 * cos(e) * s.tilt)
  let behind =
    if dot(away.perp, velocity) > 0:
      -away.perp
    else:
      away.perp
  # The tail grows as the comet nears the sun and fans out away from the
  # head: a dust tail bending back along the orbit, and a thin, straight
  # ion tail. Narrower layers on top give the dust soft edges and a bright
  # core.
  let length = clamp(12000 / distance(head, sun), 30.0, 110.0)
  let dustEnd = head + away * length + behind * (length * 0.25)
  for (spread, alpha) in [
    (1.0, 26'u8), (0.75, 30'u8), (0.52, 36'u8), (0.32, 44'u8), (0.15, 56'u8)
  ]:
    let w = length * 0.16 * spread
    var dust = newPath()
    dust.moveTo head + behind * 2.2
    dust.quadTo head + away * (length * 0.55) + behind * (length * 0.12 + w),
      dustEnd + behind * w
    dust.quadTo dustEnd + away * w * 0.5, dustEnd - behind * w
    dust.quadTo head + away * (length * 0.55) + behind * (length * 0.12 - w),
      head - behind * 2.2
    dust.quadTo head - away * 3, head + behind * 2.2
    dust.closePath()
    ctx.fill(
      dust,
      linearGradient(
        head, dustEnd, rgba8(255, 240, 215, alpha), rgba8(255, 230, 200, 0)
      ),
    )
  let ionEnd = head + away * (length * 1.3)
  ctx.stroke(
    line(head, ionEnd),
    linearGradient(head, ionEnd, rgba8(150, 200, 255, 170), rgba8(120, 170, 255, 0)),
    1.2,
  )
  ctx.fill(
    circle(head, 9),
    radialGradient(head, 9, rgba8(220, 240, 255, 120), rgba8(220, 240, 255, 0)),
  )
  ctx.fill(circle(head, 2.2), white)

proc render*[C: RenderContext](s: Orrery, ctx: var C) =
  ctx.fill(sceneBounds, radialGradient(sun, 420, rgb8(30, 30, 64), rgb8(5, 5, 14)))
  for star in s.stars:
    let twinkle = 0.55 + 0.45 * sin(star.phase + s.time * star.rate)
    ctx.fill(circle(star.pos, star.radius), white.withAlpha(0.25 + 0.6 * twinkle))

  let orbitStyle = strokeStyle(width = 1, dashes = [3.0, 6.0])
  for p in planets:
    ctx.stroke(
      ellipse(sun, p.orbit, p.orbit * s.tilt), white.withAlpha(0.18), orbitStyle
    )

  # Everything with a lower `depth` is farther away and drawn first. A body
  # on the near half of its orbit (lower on screen) is in front of the sun.
  type Body = object
    depth: float64
    planet: int ## -1 for the sun, -2 for the comet
    at: Point

  var bodies = @[Body(depth: 0, planet: -1, at: sun), Body(depth: 0.01, planet: -2)]
  for i, p in planets:
    let angle = 2 * PI * s.time / p.period + i.float64 * 1.7
    bodies.add Body(depth: sin(angle), planet: i, at: s.onOrbit(p.orbit, angle))
  bodies.sort(
    proc(a, b: Body): int =
      cmp(a.depth, b.depth)
  )

  for b in bodies:
    if b.planet == -1:
      ctx.drawSun(s)
    elif b.planet == -2:
      ctx.drawComet(s)
    else:
      let p = planets[b.planet]
      # The moon orbits in the same tilted plane, so it passes in front of
      # its planet on the near side.
      let moonAngle = 2 * PI * s.time / 1.6
      let moonAt = b.at + vec2(cos(moonAngle) * 22, sin(moonAngle) * 22 * s.tilt)
      let moonInFront = sin(moonAngle) > 0
      if p.moon and not moonInFront:
        ctx.fill(circle(moonAt, 2.8), rgb8(190, 190, 200))
      if p.ring:
        ctx.drawRingHalf(s, p, b.at, front = false)
      ctx.drawPlanet(s, p, b.at)
      if p.ring:
        ctx.drawRingHalf(s, p, b.at, front = true)
      if p.moon and moonInFront:
        ctx.fill(circle(moonAt, 2.8), rgb8(220, 220, 230))
