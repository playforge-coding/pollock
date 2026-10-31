## Stroke styles, and the expansion of a stroked path into an outline that can
## be filled. Backends with native stroking (SVG, Cairo, Core Graphics,
## Direct2D) pass the style through; the CPU and GPU backends fill the
## outline from `strokeOutline` instead.

import std/math
import ./geometry

type
  LineCap* = enum
    lcButt
    lcRound
    lcSquare

  LineJoin* = enum
    ljMiter
    ljRound
    ljBevel

  StrokeStyle* = object
    width*: float64
    cap*: LineCap
    join*: LineJoin
    miterLimit*: float64
      ## Ratio of miter length to stroke width above which a miter becomes a bevel.
    dashes*: seq[float64] ## On/off lengths in user units. Empty means solid.
    dashOffset*: float64

func strokeStyle*(
    width = 1.0,
    cap = lcButt,
    join = ljMiter,
    miterLimit = 4.0,
    dashes: openArray[float64] = [],
    dashOffset = 0.0,
): StrokeStyle =
  StrokeStyle(
    width: width,
    cap: cap,
    join: join,
    miterLimit: miterLimit,
    dashes: @dashes,
    dashOffset: dashOffset,
  )

func isDashed*(s: StrokeStyle): bool =
  if s.dashes.len == 0:
    return false
  for d in s.dashes:
    if d > 0:
      return true
  false

# Dashing

func dash*(
    poly: Polyline, pattern: openArray[float64], offset: float64
): seq[Polyline] =
  ## Splits a polyline into the "on" pieces of a dash pattern. Negative
  ## lengths count as zero. An odd-length pattern repeats to even itself out,
  ## as in SVG.
  var pat: seq[float64]
  for d in pattern:
    pat.add max(0.0, d)
  if pat.len mod 2 == 1:
    pat.add pat
  var total = 0.0
  for d in pat:
    total += d
  if total <= 0:
    return @[poly]

  var pts = poly.points
  if poly.closed and pts.len > 1:
    pts.add pts[0]
  if pts.len < 2:
    return

  # Find where the pattern starts after the offset. An offset that lands
  # exactly on the end of an entry moves past it, but with no offset the
  # pattern starts at its first entry even when that has zero length, so a
  # dotted line gets its first dot.
  var index = 0
  var remaining = offset mod total
  if remaining < 0:
    remaining += total
  while remaining > 0 and remaining >= pat[index]:
    remaining -= pat[index]
    index = (index + 1) mod pat.len
  var left = pat[index] - remaining # length left in the current entry
  var on = index mod 2 == 0

  var current: Polyline
  if on:
    current.points.add pts[0]

  # Called whenever the current entry runs out at `p`. Loops so that
  # zero-length entries are handled: a zero-length "on" entry becomes a
  # two-point dash at `p`, which strokes as a dot.
  template boundary(p: Point) =
    while left <= 0:
      if on:
        current.points.add p
        result.add current
        current = Polyline()
      else:
        current = Polyline(points: @[p])
      on = not on
      index = (index + 1) mod pat.len
      left = pat[index]

  boundary(pts[0])
  for i in 1 ..< pts.len:
    var a = pts[i - 1]
    let b = pts[i]
    var segLen = distance(a, b)
    while left < segLen:
      let p = lerp(a, b, left / segLen)
      segLen -= left
      a = p
      left = 0
      boundary(p)
    left -= segLen
    # When the entry ends exactly at `b`, the next boundary adds `b`.
    if on and left > 0:
      current.points.add b
  # Entries that end exactly at the end of the path: finish the last dash and
  # emit any zero-length dots there. A dash that would start at the very end
  # has no length and is dropped.
  boundary(pts[^1])
  if on and current.points.len > 1:
    result.add current

func dash*(polylines: openArray[Polyline], style: StrokeStyle): seq[Polyline] =
  for poly in polylines:
    result.add dash(poly, style.dashes, style.dashOffset)

# Expansion

func dedupe(points: seq[Point]): seq[Point] =
  for p in points:
    if result.len == 0 or not (result[^1] ~= p):
      result.add p

func addPolygon(path: var BezPath, pts: openArray[Point]) =
  # Every piece of the outline winds the same way so a nonzero fill unions
  # them.
  if pts.len < 3:
    return
  if signedArea(pts) >= 0:
    path.extend polygonPath(pts)
  else:
    var rev = newSeq[Point](pts.len)
    for i in 0 ..< pts.len:
      rev[i] = pts[pts.len - 1 - i]
    path.extend polygonPath(rev)

func addDisc(path: var BezPath, center: Point, radius: float64) =
  # `Circle.toPath` winds positively under `signedArea`, matching
  # `addPolygon`.
  path.extend circle(center, radius).toPath

func addJoin(
    path: var BezPath, v: Point, dIn, dOut: Vec2, hw: float64, style: StrokeStyle
) =
  # `dIn` is the unit direction arriving at `v`, `dOut` the one leaving it.
  let turn = cross(dIn, dOut)
  if abs(turn) < 1e-12 and dot(dIn, dOut) > 0:
    return # straight on, nothing to fill
  case style.join
  of ljRound:
    path.addDisc(v, hw)
  of ljBevel, ljMiter:
    # The outer side is opposite to the turn direction.
    let side = if turn > 0: -1.0 else: 1.0
    let n1 = dIn.perp * (hw * side)
    let n2 = dOut.perp * (hw * side)
    let a = v + n1
    let b = v + n2
    var mitered = false
    if style.join == ljMiter:
      let cosTheta = dot(dIn, dOut)
      # Miter length over stroke width is 1 / sin(theta / 2), where theta is
      # the angle between the segments; cos(theta) is -dot(dIn, dOut).
      let halfAngleSin = sqrt(max(0.0, (1.0 + cosTheta) * 0.5))
      let ratio =
        if halfAngleSin <= 1e-12:
          Inf
        else:
          1.0 / halfAngleSin
      if ratio <= style.miterLimit:
        let bisector = (n1 + n2)
        let denom = dot(bisector, bisector)
        if denom > 1e-18:
          let tip = v + bisector * (hw * hw * 2.0 / denom)
          path.addPolygon([v, a, tip, b])
          mitered = true
    if not mitered:
      path.addPolygon([v, a, b])

func addCap(path: var BezPath, p: Point, dir: Vec2, hw: float64, cap: LineCap) =
  # `dir` points outwards from the stroke at its end.
  case cap
  of lcButt:
    discard
  of lcRound:
    path.addDisc(p, hw)
  of lcSquare:
    let n = dir.perp * hw
    let e = dir * hw
    path.addPolygon([p + n, p + n + e, p - n + e, p - n])

func strokeOutline*(polylines: openArray[Polyline], style: StrokeStyle): BezPath =
  ## The outline of the stroke as a union of pieces: one quad per segment,
  ## joins between them and caps at the ends. Fill it with the nonzero rule.
  let hw = style.width * 0.5
  if hw <= 0:
    return
  for raw in polylines:
    var pts = dedupe(raw.points)
    var closed = raw.closed
    if closed and pts.len > 1 and pts[^1] ~= pts[0]:
      pts.setLen(pts.len - 1)
    if pts.len == 1:
      # A dot: round caps give a disc, square caps a square, butt nothing.
      case style.cap
      of lcRound:
        result.addDisc(pts[0], hw)
      of lcSquare:
        result.addPolygon(
          [
            pts[0] + vec2(-hw, -hw),
            pts[0] + vec2(hw, -hw),
            pts[0] + vec2(hw, hw),
            pts[0] + vec2(-hw, hw),
          ]
        )
      of lcButt:
        discard
      continue
    if pts.len < 2:
      continue
    if closed and pts.len < 3:
      closed = false
    let n = pts.len
    let segCount =
      if closed:
        n
      else:
        n - 1
    var dirs = newSeq[Vec2](segCount)
    for i in 0 ..< segCount:
      dirs[i] = (pts[(i + 1) mod n] - pts[i]).normalized
      let a = pts[i]
      let b = pts[(i + 1) mod n]
      let off = dirs[i].perp * hw
      result.addPolygon([a + off, b + off, b - off, a - off])
    if closed:
      for i in 0 ..< n:
        let prev = dirs[(i + segCount - 1) mod segCount]
        result.addJoin(pts[i], prev, dirs[i], hw, style)
    else:
      for i in 1 ..< n - 1:
        result.addJoin(pts[i], dirs[i - 1], dirs[i], hw, style)
      result.addCap(pts[0], -dirs[0], hw, style.cap)
      result.addCap(pts[^1], dirs[^1], hw, style.cap)

func strokeOutline*(path: BezPath, style: StrokeStyle, tolerance = 0.1): BezPath =
  ## Flattens `path`, applies the dash pattern and expands the result.
  var polylines = path.flatten(tolerance)
  if style.isDashed:
    polylines = dash(polylines, style)
  strokeOutline(polylines, style)
