## A cubic Bezier curve to edit by dragging its four control points, with de
## Casteljau's construction animated along it.
##
## Shows: building curves from points, a gradient along a wide stroke,
## dashes that march by animating the dash offset, the vertices `flatten`
## chooses for a curve (more where it bends harder), splitting a curve at a
## parameter, and the osculating circle computed from the derivatives.

import std/math
import ./scene

type Beziers* = object
  pts: array[4, Point]
  hover, drag: int ## Control point indexes, or -1.
  time: float64

const grabRadius = 16.0

func newBeziers*(): Beziers =
  Beziers(
    pts: [point(90, 320), point(170, 60), point(470, 370), point(560, 90)],
    hover: -1,
    drag: -1,
  )

proc update*(s: var Beziers, dt: float64, input: Input) =
  s.time += dt
  s.hover = -1
  if input.inside:
    var best = grabRadius
    for i, p in s.pts:
      let d = distance(p, input.pos)
      if d < best:
        best = d
        s.hover = i
  if input.pressed and s.hover >= 0:
    s.drag = s.hover
  if not input.down:
    s.drag = -1
  if s.drag >= 0:
    s.pts[s.drag] = point(
      clamp(input.pos.x, 8, sceneWidth - 8), clamp(input.pos.y, 8, sceneHeight - 8)
    )

func curve(s: Beziers): BezPath =
  result.moveTo s.pts[0]
  result.cubicTo s.pts[1], s.pts[2], s.pts[3]

proc render*[C: RenderContext](s: Beziers, ctx: var C) =
  ctx.fill(sceneBounds, rgb8(248, 246, 240))
  var grid = newPath()
  for i in 0 .. int(sceneWidth / 20):
    grid.moveTo point(i.float64 * 20, 0)
    grid.lineTo point(i.float64 * 20, sceneHeight)
  for i in 0 .. int(sceneHeight / 20):
    grid.moveTo point(0, i.float64 * 20)
    grid.lineTo point(sceneWidth, i.float64 * 20)
  ctx.stroke(grid, rgb8(40, 40, 60).withAlpha(0.07), 1.0)

  let (p0, p1, p2, p3) = (s.pts[0], s.pts[1], s.pts[2], s.pts[3])
  let path = s.curve

  # The curve as a wide band shading from one end to the other.
  ctx.stroke(
    path,
    linearGradient(p0, p3, hsl(0.58, 0.7, 0.6, 0.35), hsl(0.95, 0.7, 0.6, 0.35)),
    strokeStyle(width = 18, cap = lcRound),
  )

  # The control polygon, with its dashes marching from start to end.
  ctx.stroke(
    polygonPath([p0, p1, p2, p3], closed = false),
    rgb8(90, 90, 110),
    strokeStyle(width = 1.5, dashes = [6.0, 5.0], dashOffset = -s.time * 18),
  )

  # The points `flatten` picks at a coarse tolerance, as a polyline would
  # approximate the curve.
  for poly in path.flatten(1.0):
    for q in poly.points:
      ctx.fill(circle(q, 1.8), rgb8(60, 60, 80).withAlpha(0.6))

  # De Casteljau at t: three levels of interpolation down to the point.
  let t = 0.5 - 0.5 * cos(s.time * 0.9)
  let q0 = lerp(p0, p1, t)
  let q1 = lerp(p1, p2, t)
  let q2 = lerp(p2, p3, t)
  let r0 = lerp(q0, q1, t)
  let r1 = lerp(q1, q2, t)
  let at = lerp(r0, r1, t)
  let level1 = hsl(0.38, 0.6, 0.45)
  let level2 = hsl(0.08, 0.8, 0.5)
  ctx.stroke(polygonPath([q0, q1, q2], closed = false), level1, 1.5)
  ctx.stroke(line(r0, r1), level2, 1.5)
  for q in [q0, q1, q2]:
    ctx.fill(circle(q, 3.5), level1)
  for q in [r0, r1]:
    ctx.fill(circle(q, 3.5), level2)

  # The construction's points are also the control points of the curve's
  # first part, from the start up to t.
  var done = newPath()
  done.moveTo p0
  done.cubicTo q0, r0, at
  ctx.stroke(done, rgb8(30, 30, 50), strokeStyle(width = 3.5, cap = lcRound))
  var rest = newPath()
  rest.moveTo at
  rest.cubicTo r1, q2, p3
  ctx.stroke(rest, rgb8(30, 30, 50).withAlpha(0.35), 1.5)

  # The osculating circle: the circle that matches the curve's bend at t.
  let d1 = (r1 - r0) * 3
  let d2 = (((p2 - p1) - (p1 - p0)) * (1 - t) + ((p3 - p2) - (p2 - p1)) * t) * 6
  let speed = d1.length
  let bend = cross(d1, d2)
  if speed > 1e-6 and abs(bend) > 1e-9:
    let radius = speed * speed * speed / bend
    if abs(radius) < 2000:
      let center = at + d1.normalized.perp * radius
      ctx.stroke(
        circle(center, abs(radius)),
        hsl(0.75, 0.5, 0.5, 0.5),
        strokeStyle(width = 1.2, dashes = [2.0, 4.0]),
      )
      ctx.stroke(line(at, center), hsl(0.75, 0.5, 0.5, 0.3), 1.0)
  if speed > 1e-6:
    let tangent = d1.normalized * 46
    ctx.stroke(
      line(at - tangent, at + tangent),
      rgb8(200, 50, 60),
      strokeStyle(width = 2, cap = lcRound),
    )
  ctx.fill(circle(at, 6), rgb8(200, 50, 60))
  ctx.stroke(circle(at, 6), white, 2.0)

  for i, p in s.pts:
    let active = i == s.drag or i == s.hover
    let radius = if active: 9.0 else: 7.0
    ctx.fill(
      circle(p, radius),
      if i == s.drag:
        hsl(0.58, 0.7, 0.55)
      else:
        white,
    )
    ctx.stroke(circle(p, radius), rgb8(40, 40, 60), if active: 2.5 else: 1.5)
