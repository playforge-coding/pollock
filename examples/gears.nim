## A train of meshing gears. Drag any gear to turn the whole train; let go
## and it keeps spinning, then settles back to its idle speed.
##
## Shows: procedural paths (teeth with rounded tips and roots from quadratic
## curves), holes cut with the even-odd fill rule, paths transformed in user
## space so the lighting gradient stays put while the gear turns, and drop
## shadows from the same path drawn offset.

import std/math
import ./scene

type
  Gear = object
    center: Point
    teeth: int
    radius: float64 ## Pitch radius, where two gears touch.
    hue: float64
    shape: BezPath ## Around the origin, unrotated.
    k, b: float64 ## This gear's angle is `k * driver + b`.

  Gears* = object
    gears: seq[Gear]
    angle, speed: float64 ## The driver gear's.
    hover, drag: int
    grab: float64 ## The dragged gear's angle minus the pointer's.

const
  origin = point(0, 0)
  module = 5.0 ## Pitch radius per tooth, times two. Gears that mesh share it.
  idleSpeed = 0.45
  shadowOffset = vec2(5, 7)

func gearShape(teeth: int, radius: float64, spokes: int): BezPath =
  let step = 2 * PI / teeth.float64
  let root = radius - 1.25 * module
  let tip = radius + module
  # A quadratic through the middle of an arc of `span` radians at radius
  # `r` needs its control point this far out.
  func arcControl(r, span: float64): float64 =
    r / cos(span / 2)

  for i in 0 ..< teeth:
    let a = i.float64 * step
    let rootL = polar(origin, root, a - 0.27 * step)
    if i == 0:
      result.moveTo rootL
    result.lineTo polar(origin, tip, a - 0.13 * step)
    result.quadTo polar(origin, arcControl(tip, 0.26 * step), a),
      polar(origin, tip, a + 0.13 * step)
    result.lineTo polar(origin, root, a + 0.27 * step)
    result.quadTo polar(origin, arcControl(root, 0.46 * step), a + 0.5 * step),
      polar(origin, root, a + 0.73 * step)
  result.closePath()

  # The axle hole, and windows between spokes on the larger gears. With the
  # even-odd rule, every closed subpath inside the outline is a hole.
  result.extend circle(origin, max(4.0, 0.1 * radius)).toPath
  if spokes > 0:
    let inner = 0.32 * radius
    let outer = root - 0.16 * radius
    let spokeHalf = 5.0
    for s in 0 ..< spokes:
      let a0 = s.float64 * 2 * PI / spokes.float64
      let a1 = a0 + 2 * PI / spokes.float64
      var pts: seq[Point]
      let n = 16
      for j in 0 .. n:
        let a =
          a0 + spokeHalf / outer +
          (a1 - a0 - 2 * spokeHalf / outer) * j.float64 / n.float64
        pts.add polar(origin, outer, a)
      for j in countdown(n, 0):
        let a =
          a0 + spokeHalf / inner +
          (a1 - a0 - 2 * spokeHalf / inner) * j.float64 / n.float64
        pts.add polar(origin, inner, a)
      result.extend polygonPath(pts)

proc addGear(g: var Gears, teeth: int, hue: float64, parent = -1, direction = 0.0) =
  ## Adds a gear meshing with `parent`, placed in `direction` from it, or the
  ## driver when there is no parent.
  let radius = module * teeth.float64 / 2
  var gear = Gear(
    teeth: teeth,
    radius: radius,
    hue: hue,
    shape: gearShape(teeth, radius, if radius >= 40: 5 else: 0),
  )
  if parent < 0:
    gear.center = point(230, 200)
    gear.k = 1
  else:
    let p = g.gears[parent]
    gear.center = polar(p.center, p.radius + radius, direction)
    # When the parent has a tooth pointing at this gear (its angle equals
    # `direction`), this one needs the middle of a gap pointing back. From
    # there they turn the other way, slower by the ratio of their teeth.
    let ratio = p.teeth.float64 / teeth.float64
    gear.k = -ratio * p.k
    gear.b = -ratio * (p.b - direction) + direction + PI - PI / teeth.float64
  g.gears.add gear

func newGears*(): Gears =
  result = Gears(speed: idleSpeed, hover: -1, drag: -1)
  result.addGear(24, 0.09)
  result.addGear(12, 0.55, parent = 0, direction = -2.3)
  result.addGear(36, 0.12, parent = 0, direction = 0.15)
  result.addGear(16, 0.0, parent = 2, direction = -1.0)
  result.addGear(10, 0.6, parent = 2, direction = 0.9)
  result.addGear(20, 0.1, parent = 3, direction = -0.2)
  result.addGear(8, 0.0, parent = 0, direction = 2.2)

func angleOf(s: Gears, i: int): float64 =
  s.gears[i].k * s.angle + s.gears[i].b

proc update*(s: var Gears, dt: float64, input: Input) =
  s.hover = -1
  if input.inside:
    var best = Inf
    for i, g in s.gears:
      let d = distance(g.center, input.pos)
      if d < g.radius + module and d / g.radius < best:
        best = d / g.radius
        s.hover = i
  if input.pressed and s.hover >= 0:
    s.drag = s.hover
    let d = input.pos - s.gears[s.drag].center
    s.grab = s.angleOf(s.drag) - arctan2(d.y, d.x)
  if not input.down:
    s.drag = -1

  if s.drag >= 0:
    let g = s.gears[s.drag]
    let d = input.pos - g.center
    let delta = wrapAngle(arctan2(d.y, d.x) + s.grab - s.angleOf(s.drag)) / g.k
    s.angle += delta
    if dt > 0:
      # Remember how fast the hand was moving, so letting go flings it.
      s.speed = approach(s.speed, delta / dt, 20, dt)
  else:
    s.speed = approach(s.speed, idleSpeed, 0.7, dt)
    s.angle += s.speed * dt

proc render*[C: RenderContext](s: Gears, ctx: var C) =
  ctx.fill(
    sceneBounds,
    linearGradient(
      point(0, 0), point(sceneWidth, sceneHeight), rgb8(58, 52, 48), rgb8(26, 24, 24)
    ),
  )
  # Rings turned into the plate behind each axle.
  for g in s.gears:
    for r in countup(int(g.radius * 1.15), int(g.radius * 1.5), 7):
      ctx.stroke(circle(g.center, r.float64), white.withAlpha(0.04), 1.0)
  for corner in [point(18, 18), point(622, 18), point(18, 382), point(622, 382)]:
    ctx.fill(
      circle(corner, 7),
      radialGradient(corner - vec2(2, 2), 8, rgb8(200, 190, 170), rgb8(80, 70, 60)),
    )
    ctx.stroke(line(corner - vec2(4, 4), corner + vec2(4, 4)), rgb8(40, 36, 32), 1.5)

  var placed: seq[BezPath]
  for i, g in s.gears:
    placed.add (translate(g.center.toVec) * rotate(s.angleOf(i))).transform(g.shape)
  for path in placed:
    ctx.fill(translate(shadowOffset).transform(path), black.withAlpha(0.35), frEvenOdd)

  for i, g in s.gears:
    let r = g.radius + module
    # The gradient is in scene space, not the gear's, so the light stays
    # where it is while the teeth turn through it.
    let metal = linearGradient(
      g.center - vec2(r, r),
      g.center + vec2(r, r),
      [
        stop(0.0, hsl(g.hue, 0.45, 0.78)),
        stop(0.45, hsl(g.hue, 0.5, 0.55)),
        stop(1.0, hsl(g.hue, 0.55, 0.3)),
      ],
    )
    ctx.fill(placed[i], metal, frEvenOdd)
    ctx.stroke(
      placed[i], hsl(g.hue, 0.5, 0.18, 0.7), strokeStyle(width = 1, join = ljBevel)
    )
    ctx.fill(
      circle(g.center, max(4.0, 0.1 * g.radius) + 4),
      radialGradient(g.center - vec2(2, 2), 10, rgb8(230, 225, 215), rgb8(90, 85, 80)),
    )
    ctx.fill(circle(g.center, 2.5), rgb8(30, 28, 26))
    if i == s.hover or i == s.drag:
      ctx.stroke(
        circle(g.center, r + 6),
        white.withAlpha(if i == s.drag: 0.6 else: 0.3),
        strokeStyle(width = 2, dashes = [4.0, 4.0], dashOffset = s.angle * r),
      )
