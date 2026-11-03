## Geometry: points, vectors, rectangles, shapes, affine transforms and
## Bezier paths, all in `float64`. Pure Nim with no backend knowledge, so it
## compiles for every target.
##
## A `Shape` is any type that can turn itself into a `BezPath` with `toPath`
## and report a `boundingBox`. Backends draw paths; the shapes here exist so
## code can say `circle(c, r)` instead of spelling out four cubics.
##
## Paths hold lines, quadratic and cubic curves and elliptical arcs. Arcs are
## stored the way SVG's `A` command gives them (`peArcTo`) and stay arcs
## under `transform`; `toArc` converts one to its center and angles, `flatten`
## samples the ellipse itself, and `toCubics` approximates arcs for renderers
## that have none. `boundingBox` of a path is exact for every element.

import std/math

type
  Point* = object
    x*, y*: float64

  Vec2* = object
    x*, y*: float64

  Size* = object
    width*, height*: float64

  Rect* = object
    ## Axis-aligned rectangle with `x0 <= x1` and `y0 <= y1` once normalized.
    x0*, y0*, x1*, y1*: float64

  RoundedRect* = object
    rect*: Rect
    radius*: float64

  Circle* = object
    center*: Point
    radius*: float64

  Ellipse* = object
    center*: Point
    radii*: Vec2

  Line* = object
    p0*, p1*: Point

  Arc* = object
    ## An elliptical arc in center parameterization: the part of the ellipse
    ## with `radii` around `center`, its x axis turned by `rotation`, from
    ## `startAngle` through `sweepAngle`. Angles are in radians and are the
    ## parameter of the ellipse (see `pointAt`), with positive angles turning
    ## clockwise on screen like everything else, and a negative sweep runs
    ## the other way. A sweep of `2 * PI` is the whole ellipse.
    center*: Point
    radii*: Vec2
    startAngle*, sweepAngle*: float64
    rotation*: float64

  Affine* = object
    ## The matrix `[a c e; b d f; 0 0 1]`: a point maps to
    ## `(a*x + c*y + e, b*x + d*y + f)`.
    a*, b*, c*, d*, e*, f*: float64

  PathElKind* = enum
    peMoveTo
    peLineTo
    peQuadTo
    peCubicTo
    peArcTo
    peClosePath

  PathEl* = object
    case kind*: PathElKind
    of peMoveTo, peLineTo:
      to*: Point
    of peQuadTo:
      ctrl*: Point
      quadEnd*: Point
    of peCubicTo:
      ctrl1*, ctrl2*: Point
      cubicEnd*: Point
    of peArcTo:
      ## An elliptical arc in SVG's endpoint parameterization: from the
      ## current point to `arcEnd` along an ellipse with `radii` whose x axis
      ## is turned by `rotation` radians. Of the four arcs through the two
      ## points, `largeArc` picks the longer pair and `sweep` the one that
      ## turns in the positive angle direction (clockwise on screen). Radii
      ## too small to reach both points are scaled up until they do; a zero
      ## radius makes the arc a straight line.
      radii*: Vec2
      rotation*: float64
      largeArc*, sweep*: bool
      arcEnd*: Point
    of peClosePath:
      discard

  BezPath* = object
    elements*: seq[PathEl]

  Polyline* = object ## A flattened subpath.
    points*: seq[Point]
    closed*: bool

  Shape* = concept
    proc toPath(s: Self): BezPath
    proc boundingBox(s: Self): Rect

const
  # Distance of the control points of a cubic that approximates a quarter
  # circle of radius 1.
  kappa = 0.5522847498307936

# Points and vectors

func point*(x, y: float64): Point =
  Point(x: x, y: y)

func vec2*(x, y: float64): Vec2 =
  Vec2(x: x, y: y)

func size*(width, height: float64): Size =
  Size(width: width, height: height)

func toVec*(p: Point): Vec2 =
  Vec2(x: p.x, y: p.y)

func toPoint*(v: Vec2): Point =
  Point(x: v.x, y: v.y)

func `+`*(p: Point, v: Vec2): Point =
  Point(x: p.x + v.x, y: p.y + v.y)

func `-`*(p: Point, v: Vec2): Point =
  Point(x: p.x - v.x, y: p.y - v.y)

func `-`*(a, b: Point): Vec2 =
  Vec2(x: a.x - b.x, y: a.y - b.y)

func `+`*(a, b: Vec2): Vec2 =
  Vec2(x: a.x + b.x, y: a.y + b.y)

func `-`*(a, b: Vec2): Vec2 =
  Vec2(x: a.x - b.x, y: a.y - b.y)

func `-`*(v: Vec2): Vec2 =
  Vec2(x: -v.x, y: -v.y)

func `*`*(v: Vec2, s: float64): Vec2 =
  Vec2(x: v.x * s, y: v.y * s)

func `*`*(s: float64, v: Vec2): Vec2 =
  Vec2(x: v.x * s, y: v.y * s)

func `/`*(v: Vec2, s: float64): Vec2 =
  Vec2(x: v.x / s, y: v.y / s)

func dot*(a, b: Vec2): float64 =
  a.x * b.x + a.y * b.y

func cross*(a, b: Vec2): float64 =
  ## The z component of the 3D cross product, positive when `b` is a
  ## clockwise turn from `a` on a y-down screen.
  a.x * b.y - a.y * b.x

func length*(v: Vec2): float64 =
  sqrt(v.x * v.x + v.y * v.y)

func lengthSquared*(v: Vec2): float64 =
  v.x * v.x + v.y * v.y

func normalized*(v: Vec2): Vec2 =
  ## The unit vector in the direction of `v`, or `v` itself when it has
  ## no length.
  let len = v.length
  if len == 0:
    v
  else:
    v / len

func perp*(v: Vec2): Vec2 =
  ## `v` rotated a quarter turn: `(-y, x)`.
  Vec2(x: -v.y, y: v.x)

func distance*(a, b: Point): float64 =
  (a - b).length

func lerp*(a, b: Point, t: float64): Point =
  Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)

func midpoint*(a, b: Point): Point =
  lerp(a, b, 0.5)

func isFinite*(p: Point): bool =
  p.x.classify in {fcNormal, fcSubnormal, fcZero, fcNegZero} and
    p.y.classify in {fcNormal, fcSubnormal, fcZero, fcNegZero}

func `~=`*(a, b: float64): bool =
  ## Approximate equality for tests and degenerate-case checks.
  abs(a - b) <= 1e-9 * max(1.0, max(abs(a), abs(b)))

func `~=`*(a, b: Point): bool =
  a.x ~= b.x and a.y ~= b.y

# Rectangles

func rect*(x0, y0, x1, y1: float64): Rect =
  Rect(x0: x0, y0: y0, x1: x1, y1: y1)

func rect*(origin: Point, size: Size): Rect =
  Rect(
    x0: origin.x, y0: origin.y, x1: origin.x + size.width, y1: origin.y + size.height
  )

func rectXywh*(x, y, width, height: float64): Rect =
  Rect(x0: x, y0: y, x1: x + width, y1: y + height)

func rectFromPoints*(a, b: Point): Rect =
  Rect(x0: min(a.x, b.x), y0: min(a.y, b.y), x1: max(a.x, b.x), y1: max(a.y, b.y))

func normalized*(r: Rect): Rect =
  rectFromPoints(point(r.x0, r.y0), point(r.x1, r.y1))

func width*(r: Rect): float64 =
  r.x1 - r.x0

func height*(r: Rect): float64 =
  r.y1 - r.y0

func size*(r: Rect): Size =
  size(r.width, r.height)

func origin*(r: Rect): Point =
  point(r.x0, r.y0)

func center*(r: Rect): Point =
  point((r.x0 + r.x1) * 0.5, (r.y0 + r.y1) * 0.5)

func area*(r: Rect): float64 =
  r.width * r.height

func isEmpty*(r: Rect): bool =
  r.x1 <= r.x0 or r.y1 <= r.y0

func contains*(r: Rect, p: Point): bool =
  p.x >= r.x0 and p.x < r.x1 and p.y >= r.y0 and p.y < r.y1

func union*(a, b: Rect): Rect =
  Rect(
    x0: min(a.x0, b.x0), y0: min(a.y0, b.y0), x1: max(a.x1, b.x1), y1: max(a.y1, b.y1)
  )

func union*(r: Rect, p: Point): Rect =
  Rect(x0: min(r.x0, p.x), y0: min(r.y0, p.y), x1: max(r.x1, p.x), y1: max(r.y1, p.y))

func intersect*(a, b: Rect): Rect =
  ## The overlap of two rectangles. Empty (zero width or height) when they
  ## don't touch.
  let x0 = max(a.x0, b.x0)
  let y0 = max(a.y0, b.y0)
  Rect(x0: x0, y0: y0, x1: max(x0, min(a.x1, b.x1)), y1: max(y0, min(a.y1, b.y1)))

func inflate*(r: Rect, dx, dy: float64): Rect =
  Rect(x0: r.x0 - dx, y0: r.y0 - dy, x1: r.x1 + dx, y1: r.y1 + dy)

func inset*(r: Rect, d: float64): Rect =
  r.inflate(-d, -d)

func translate*(r: Rect, v: Vec2): Rect =
  Rect(x0: r.x0 + v.x, y0: r.y0 + v.y, x1: r.x1 + v.x, y1: r.y1 + v.y)

func roundOut*(r: Rect): Rect =
  ## The smallest rectangle with integer edges that contains `r`.
  Rect(x0: floor(r.x0), y0: floor(r.y0), x1: ceil(r.x1), y1: ceil(r.y1))

func roundedRect*(r: Rect, radius: float64): RoundedRect =
  RoundedRect(rect: r, radius: radius)

func roundedRect*(x0, y0, x1, y1, radius: float64): RoundedRect =
  RoundedRect(rect: rect(x0, y0, x1, y1), radius: radius)

func circle*(center: Point, radius: float64): Circle =
  Circle(center: center, radius: radius)

func circle*(x, y, radius: float64): Circle =
  Circle(center: point(x, y), radius: radius)

func ellipse*(center: Point, rx, ry: float64): Ellipse =
  Ellipse(center: center, radii: vec2(rx, ry))

func line*(p0, p1: Point): Line =
  Line(p0: p0, p1: p1)

func line*(x0, y0, x1, y1: float64): Line =
  Line(p0: point(x0, y0), p1: point(x1, y1))

func arc*(
    center: Point, radii: Vec2, startAngle, sweepAngle: float64, rotation = 0.0
): Arc =
  Arc(
    center: center,
    radii: vec2(abs(radii.x), abs(radii.y)),
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    rotation: rotation,
  )

func arc*(center: Point, radius, startAngle, sweepAngle: float64): Arc =
  ## A circular arc.
  arc(center, vec2(radius, radius), startAngle, sweepAngle)

# Affine transforms

func affine*(a, b, c, d, e, f: float64): Affine =
  Affine(a: a, b: b, c: c, d: d, e: e, f: f)

func identity*(_: typedesc[Affine]): Affine =
  Affine(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

const affineIdentity* = Affine(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0)

func translate*(v: Vec2): Affine =
  Affine(a: 1, b: 0, c: 0, d: 1, e: v.x, f: v.y)

func translate*(x, y: float64): Affine =
  Affine(a: 1, b: 0, c: 0, d: 1, e: x, f: y)

func scale*(s: float64): Affine =
  Affine(a: s, b: 0, c: 0, d: s, e: 0, f: 0)

func scale*(sx, sy: float64): Affine =
  Affine(a: sx, b: 0, c: 0, d: sy, e: 0, f: 0)

func rotate*(radians: float64): Affine =
  ## Rotation about the origin. Positive angles turn clockwise on a y-down
  ## screen.
  let s = sin(radians)
  let c = cos(radians)
  Affine(a: c, b: s, c: -s, d: c, e: 0, f: 0)

func rotateAbout*(radians: float64, center: Point): Affine

func skew*(sx, sy: float64): Affine =
  Affine(a: 1, b: sy, c: sx, d: 1, e: 0, f: 0)

func `*`*(m, n: Affine): Affine =
  ## Composition: `m * n` applies `n` first and `m` second, like matrix
  ## multiplication.
  Affine(
    a: m.a * n.a + m.c * n.b,
    b: m.b * n.a + m.d * n.b,
    c: m.a * n.c + m.c * n.d,
    d: m.b * n.c + m.d * n.d,
    e: m.a * n.e + m.c * n.f + m.e,
    f: m.b * n.e + m.d * n.f + m.f,
  )

func apply*(m: Affine, p: Point): Point =
  Point(x: m.a * p.x + m.c * p.y + m.e, y: m.b * p.x + m.d * p.y + m.f)

func `*`*(m: Affine, p: Point): Point =
  m.apply(p)

func applyVec*(m: Affine, v: Vec2): Vec2 =
  ## Transforms a direction, ignoring the translation.
  Vec2(x: m.a * v.x + m.c * v.y, y: m.b * v.x + m.d * v.y)

func determinant*(m: Affine): float64 =
  m.a * m.d - m.b * m.c

func inverse*(m: Affine): Affine =
  ## The inverse transform. A singular matrix gives non-finite values; check
  ## `determinant` first when that matters.
  let inv = 1.0 / m.determinant
  Affine(
    a: m.d * inv,
    b: -m.b * inv,
    c: -m.c * inv,
    d: m.a * inv,
    e: (m.c * m.f - m.d * m.e) * inv,
    f: (m.b * m.e - m.a * m.f) * inv,
  )

func isIdentity*(m: Affine): bool =
  m.a == 1 and m.b == 0 and m.c == 0 and m.d == 1 and m.e == 0 and m.f == 0

func isTranslation*(m: Affine): bool =
  m.a == 1 and m.b == 0 and m.c == 0 and m.d == 1

func scaleFactor*(m: Affine): float64 =
  ## The geometric mean of the scaling along both axes (the square root of
  ## the area scale).
  sqrt(abs(m.determinant))

func maxScale*(m: Affine): float64 =
  ## The most the transform stretches any direction: the largest singular
  ## value of the linear part. Divide a device-space tolerance by this to get
  ## a user-space tolerance that holds in every direction.
  let s = m.a * m.a + m.b * m.b + m.c * m.c + m.d * m.d
  let det = m.determinant
  sqrt(max(0.0, (s + sqrt(max(0.0, s * s - 4 * det * det))) * 0.5))

func rotateAbout*(radians: float64, center: Point): Affine =
  translate(center.toVec) * rotate(radians) * translate(-center.toVec)

func transform*(m: Affine, r: Rect): Rect =
  ## The bounding rectangle of the transformed corners.
  let p0 = m * point(r.x0, r.y0)
  let p1 = m * point(r.x1, r.y0)
  let p2 = m * point(r.x1, r.y1)
  let p3 = m * point(r.x0, r.y1)
  rectFromPoints(p0, p1).union(p2).union(p3)

# Paths

func moveTo*(p: Point): PathEl =
  PathEl(kind: peMoveTo, to: p)

func lineTo*(p: Point): PathEl =
  PathEl(kind: peLineTo, to: p)

func quadTo*(ctrl, to: Point): PathEl =
  PathEl(kind: peQuadTo, ctrl: ctrl, quadEnd: to)

func cubicTo*(ctrl1, ctrl2, to: Point): PathEl =
  PathEl(kind: peCubicTo, ctrl1: ctrl1, ctrl2: ctrl2, cubicEnd: to)

func arcTo*(radii: Vec2, rotation: float64, largeArc, sweep: bool, to: Point): PathEl =
  ## An arc element (see `peArcTo`). Negative radii count as positive, as in
  ## SVG.
  PathEl(
    kind: peArcTo,
    radii: vec2(abs(radii.x), abs(radii.y)),
    rotation: rotation,
    largeArc: largeArc,
    sweep: sweep,
    arcEnd: to,
  )

func closePath*(): PathEl =
  PathEl(kind: peClosePath)

func `==`*(a, b: PathEl): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of peMoveTo, peLineTo:
    a.to == b.to
  of peQuadTo:
    a.ctrl == b.ctrl and a.quadEnd == b.quadEnd
  of peCubicTo:
    a.ctrl1 == b.ctrl1 and a.ctrl2 == b.ctrl2 and a.cubicEnd == b.cubicEnd
  of peArcTo:
    a.radii == b.radii and a.rotation == b.rotation and a.largeArc == b.largeArc and
      a.sweep == b.sweep and a.arcEnd == b.arcEnd
  of peClosePath:
    true

func endPoint*(el: PathEl): Point =
  ## Where the pen is after this element. A `peClosePath` has no end point of
  ## its own and returns the origin; callers track the subpath start.
  case el.kind
  of peMoveTo, peLineTo:
    el.to
  of peQuadTo:
    el.quadEnd
  of peCubicTo:
    el.cubicEnd
  of peArcTo:
    el.arcEnd
  of peClosePath:
    point(0, 0)

func newPath*(): BezPath =
  BezPath()

func len*(path: BezPath): int =
  path.elements.len

func isEmpty*(path: BezPath): bool =
  path.elements.len == 0

func add*(path: var BezPath, el: PathEl) =
  path.elements.add el

func moveTo*(path: var BezPath, p: Point) =
  path.elements.add moveTo(p)

func moveTo*(path: var BezPath, x, y: float64) =
  path.moveTo point(x, y)

func lineTo*(path: var BezPath, p: Point) =
  path.elements.add lineTo(p)

func lineTo*(path: var BezPath, x, y: float64) =
  path.lineTo point(x, y)

func quadTo*(path: var BezPath, ctrl, to: Point) =
  path.elements.add quadTo(ctrl, to)

func cubicTo*(path: var BezPath, ctrl1, ctrl2, to: Point) =
  path.elements.add cubicTo(ctrl1, ctrl2, to)

func arcTo*(
    path: var BezPath, radii: Vec2, rotation: float64, largeArc, sweep: bool, to: Point
) =
  ## Adds an elliptical arc from the current point to `to`, as SVG's `A`
  ## command does; see `peArcTo` for the flags.
  path.elements.add arcTo(radii, rotation, largeArc, sweep, to)

func arcTo*(
    path: var BezPath, radius: float64, to: Point, largeArc = false, sweep = true
) =
  ## Adds a circular arc from the current point to `to`. The default flags
  ## pick the shorter arc that turns clockwise on screen. A radius of half
  ## the distance between the points gives a half circle.
  path.elements.add arcTo(vec2(radius, radius), 0.0, largeArc, sweep, to)

func closePath*(path: var BezPath) =
  path.elements.add closePath()

func extend*(path: var BezPath, other: BezPath) =
  path.elements.add other.elements

# Arcs

func ellipseTransform(a: Arc): Affine =
  # Maps the unit circle onto the arc's ellipse.
  translate(a.center.toVec) * rotate(a.rotation) * scale(a.radii.x, a.radii.y)

func pointAt*(a: Arc, angle: float64): Point =
  ## The point of the arc's ellipse at parameter `angle`:
  ## `center + rotate(rotation) * (rx * cos(angle), ry * sin(angle))`.
  a.ellipseTransform * point(cos(angle), sin(angle))

func startPoint*(a: Arc): Point =
  a.pointAt(a.startAngle)

func endPoint*(a: Arc): Point =
  a.pointAt(a.startAngle + a.sweepAngle)

func isDegenerate*(a: Arc): bool =
  ## True when a radius is zero, so the arc is a straight line.
  a.radii.x <= 0 or a.radii.y <= 0

func toArc*(el: PathEl, start: Point): Arc =
  ## The center parameterization of an arc element that begins at `start`,
  ## following SVG's rules: radii too small to reach both points are scaled
  ## up uniformly, and the flags pick one of the four arcs through them. A
  ## zero radius gives a degenerate arc (see `isDegenerate`), which draws as
  ## a line to `arcEnd`. So do endpoints too close to fix a center, whether
  ## they are the same point or so near that the squares below underflow.
  doAssert el.kind == peArcTo, "toArc needs an arc element"
  var rx = el.radii.x
  var ry = el.radii.y
  let mid = midpoint(start, el.arcEnd)
  if rx <= 0 or ry <= 0:
    return Arc(center: mid, rotation: el.rotation)
  let cosPhi = cos(el.rotation)
  let sinPhi = sin(el.rotation)
  # Half the chord, in the ellipse's own axes.
  let dx = (start.x - el.arcEnd.x) * 0.5
  let dy = (start.y - el.arcEnd.y) * 0.5
  let x1 = cosPhi * dx + sinPhi * dy
  let y1 = -sinPhi * dx + cosPhi * dy
  let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
  if lambda > 1:
    let s = sqrt(lambda)
    rx *= s
    ry *= s
  let rx2 = rx * rx
  let ry2 = ry * ry
  let denom = rx2 * y1 * y1 + ry2 * x1 * x1
  if denom < 1e-280:
    return Arc(center: mid, rotation: el.rotation)
  var coef = sqrt(max(0.0, (rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1) / denom))
  if el.largeArc == el.sweep:
    coef = -coef
  let cx1 = coef * rx * y1 / ry
  let cy1 = -coef * ry * x1 / rx
  let center =
    point(cosPhi * cx1 - sinPhi * cy1 + mid.x, sinPhi * cx1 + cosPhi * cy1 + mid.y)
  let u = vec2((x1 - cx1) / rx, (y1 - cy1) / ry)
  let v = vec2((-x1 - cx1) / rx, (-y1 - cy1) / ry)
  var sweep = arctan2(cross(u, v), dot(u, v))
  if el.sweep and sweep < 0:
    sweep += 2 * PI
  elif not el.sweep and sweep > 0:
    sweep -= 2 * PI
  Arc(
    center: center,
    radii: vec2(rx, ry),
    startAngle: arctan2(u.y, u.x),
    sweepAngle: sweep,
    rotation: el.rotation,
  )

func toPath*(a: Arc): BezPath =
  ## The arc as a path: a `moveTo` and one arc element per half turn, since
  ## an element can't span a whole one. A degenerate arc is a line.
  result.moveTo a.startPoint
  if a.isDegenerate or a.sweepAngle == 0:
    result.lineTo a.endPoint
    return
  let pieces = max(1, int(ceil(abs(a.sweepAngle) / PI - 1e-9)))
  for i in 1 .. pieces:
    let to =
      if i == pieces:
        a.endPoint
      else:
        a.pointAt(a.startAngle + a.sweepAngle * i.float64 / pieces.float64)
    result.arcTo(a.radii, a.rotation, false, a.sweepAngle > 0, to)

func toCubics*(a: Arc): seq[PathEl] =
  ## The arc as cubic curves, one per quarter turn at most, starting from
  ## `startPoint`. A quarter turn is off by 0.03% of the radius at worst. A
  ## degenerate arc gives a line.
  if a.isDegenerate or a.sweepAngle == 0:
    return @[lineTo(a.endPoint)]
  let n = max(1, int(ceil(abs(a.sweepAngle) / (PI / 2) - 1e-9)))
  let step = a.sweepAngle / n.float64
  # The control points sit this far along the tangents of the unit circle.
  let k = 4.0 / 3.0 * tan(step / 4)
  let m = a.ellipseTransform
  for i in 0 ..< n:
    let t0 = a.startAngle + step * i.float64
    let t1 = t0 + step
    let p0 = vec2(cos(t0), sin(t0))
    let p3 = vec2(cos(t1), sin(t1))
    let c1 = point(p0.x - k * p0.y, p0.y + k * p0.x)
    let c2 = point(p3.x + k * p3.y, p3.y - k * p3.x)
    let to =
      if i == n - 1:
        a.endPoint
      else:
        m * p3.toPoint
    result.add cubicTo(m * c1, m * c2, to)

func toCubics*(el: PathEl, start: Point): seq[PathEl] =
  ## The elements that stand in for an arc element beginning at `start`:
  ## cubics, a line when a radius is zero, nothing when the arc ends where it
  ## starts (SVG leaves such an arc out). Any other element is returned as
  ## it is.
  if el.kind != peArcTo:
    return @[el]
  if el.arcEnd == start:
    return
  let a = el.toArc(start)
  if a.isDegenerate:
    return @[lineTo(el.arcEnd)]
  result = a.toCubics
  result[^1].cubicEnd = el.arcEnd

func toCubics*(path: BezPath): BezPath =
  ## `path` with every arc replaced by cubics, for renderers whose paths have
  ## no arcs.
  var pen, start: Point
  for el in path.elements:
    case el.kind
    of peMoveTo:
      start = el.to
      pen = el.to
      result.elements.add el
    of peArcTo:
      result.elements.add el.toCubics(pen)
      pen = el.arcEnd
    of peClosePath:
      pen = start
      result.elements.add el
    else:
      pen = el.endPoint
      result.elements.add el

func containsAngle(a: Arc, angle: float64): bool =
  # Whether the ellipse's point at `angle` lies on the arc.
  let span = abs(a.sweepAngle)
  if span >= 2 * PI:
    return true
  let lower =
    if a.sweepAngle >= 0:
      a.startAngle
    else:
      a.startAngle + a.sweepAngle
  var d = (angle - lower) mod (2 * PI)
  if d < 0:
    d += 2 * PI
  d <= span

func boundingBox*(a: Arc): Rect =
  ## The exact bounds of the arc.
  result = rectFromPoints(a.startPoint, a.endPoint)
  if a.isDegenerate:
    return
  # The ellipse's tangent is vertical at `ax` and horizontal at `ay`, and
  # again half a turn on from each.
  let cosPhi = cos(a.rotation)
  let sinPhi = sin(a.rotation)
  let ax = arctan2(-a.radii.y * sinPhi, a.radii.x * cosPhi)
  let ay = arctan2(a.radii.y * cosPhi, a.radii.x * sinPhi)
  for base in [ax, ay]:
    for half in 0 .. 1:
      let angle = base + half.float64 * PI
      if a.containsAngle(angle):
        result = result.union(a.pointAt(angle))

func transformArc(m: Affine, el: PathEl): PathEl =
  # The ellipse is the image of the unit circle under `rotate(rotation) *
  # scale(radii)`. Composed with the linear part of `m` that is still an
  # affine image of the unit circle, so still an ellipse: its radii are the
  # singular values of the composition and its axis the first left singular
  # vector, both read off `N * N^T`. The chord scales along, so the radii
  # correction `toArc` applies commutes with the transform.
  let n = m * rotate(el.rotation) * scale(el.radii.x, el.radii.y)
  let p = n.a * n.a + n.c * n.c
  let q = n.a * n.b + n.c * n.d
  let r = n.b * n.b + n.d * n.d
  let mean = (p + r) * 0.5
  let spread = sqrt(((p - r) * 0.5) * ((p - r) * 0.5) + q * q)
  let major = sqrt(max(0.0, mean + spread))
  let minor = sqrt(max(0.0, mean - spread))
  var rotation = 0.5 * arctan2(2 * q, p - r)
  var radii = vec2(major, minor)
  if el.radii.x < el.radii.y:
    # Keep the x radius the smaller one, as it was given.
    radii = vec2(minor, major)
    rotation -= PI / 2
  # A reflection turns the arc the other way around.
  let sweep =
    if m.determinant < 0:
      not el.sweep
    else:
      el.sweep
  arcTo(radii, rotation, el.largeArc, sweep, m * el.arcEnd)

func transform*(m: Affine, path: BezPath): BezPath =
  ## The transformed path. Arcs stay arcs: their ellipse is transformed
  ## exactly (an affine image of an ellipse is an ellipse), though the
  ## rotation of an equivalent ellipse may come out differently.
  result.elements = newSeqOfCap[PathEl](path.elements.len)
  for el in path.elements:
    case el.kind
    of peMoveTo:
      result.elements.add moveTo(m * el.to)
    of peLineTo:
      result.elements.add lineTo(m * el.to)
    of peQuadTo:
      result.elements.add quadTo(m * el.ctrl, m * el.quadEnd)
    of peCubicTo:
      result.elements.add cubicTo(m * el.ctrl1, m * el.ctrl2, m * el.cubicEnd)
    of peArcTo:
      result.elements.add m.transformArc(el)
    of peClosePath:
      result.elements.add closePath()

# Points on curves

func quadPoint(p0, p1, p2: Point, t: float64): Point =
  let mt = 1.0 - t
  Point(
    x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
    y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y,
  )

func cubicPoint(p0, p1, p2, p3: Point, t: float64): Point =
  let mt = 1.0 - t
  let a = mt * mt * mt
  let b = 3 * mt * mt * t
  let c = 3 * mt * t * t
  let d = t * t * t
  Point(
    x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
    y: a * p0.y + b * p1.y + c * p2.y + d * p3.y,
  )

# Bounding boxes

func quadBounds(p0, p1, p2: Point): Rect =
  # The ends, plus the point where the derivative along an axis is zero.
  result = rectFromPoints(p0, p2)
  for axis in 0 .. 1:
    let (a0, a1, a2) =
      if axis == 0:
        (p0.x, p1.x, p2.x)
      else:
        (p0.y, p1.y, p2.y)
    let denom = a0 - 2 * a1 + a2
    if denom != 0:
      let t = (a0 - a1) / denom
      if t > 0 and t < 1:
        result = result.union(quadPoint(p0, p1, p2, t))

func cubicBounds(p0, p1, p2, p3: Point): Rect =
  result = rectFromPoints(p0, p3)
  for axis in 0 .. 1:
    let (a0, a1, a2, a3) =
      if axis == 0:
        (p0.x, p1.x, p2.x, p3.x)
      else:
        (p0.y, p1.y, p2.y, p3.y)
    # The derivative is the quadratic `a t^2 + b t + c`, solved in the form
    # that doesn't cancel when `b` is large.
    let a = -a0 + 3 * a1 - 3 * a2 + a3
    let b = 2 * (a0 - 2 * a1 + a2)
    let c = a1 - a0
    var roots: array[2, float64]
    var count = 0
    if a == 0:
      if b != 0:
        roots[0] = -c / b
        count = 1
    else:
      let disc = b * b - 4 * a * c
      if disc >= 0:
        let s = sqrt(disc)
        let q =
          if b >= 0:
            -0.5 * (b + s)
          else:
            -0.5 * (b - s)
        if q != 0:
          roots[0] = q / a
          roots[1] = c / q
          count = 2
    for i in 0 ..< count:
      let t = roots[i]
      if t > 0 and t < 1:
        result = result.union(cubicPoint(p0, p1, p2, p3, t))

func boundingBox*(path: BezPath): Rect =
  ## The exact bounding box of the path: the curves themselves, not their
  ## control points. Empty paths give an empty rectangle at the origin.
  var first = true
  var pen, start: Point
  template take(r: Rect) =
    if first:
      result = r
      first = false
    else:
      result = result.union(r)

  for el in path.elements:
    case el.kind
    of peMoveTo:
      take rect(el.to.x, el.to.y, el.to.x, el.to.y)
      start = el.to
      pen = el.to
    of peLineTo:
      take rectFromPoints(pen, el.to)
      pen = el.to
    of peQuadTo:
      take quadBounds(pen, el.ctrl, el.quadEnd)
      pen = el.quadEnd
    of peCubicTo:
      take cubicBounds(pen, el.ctrl1, el.ctrl2, el.cubicEnd)
      pen = el.cubicEnd
    of peArcTo:
      take rectFromPoints(pen, el.arcEnd)
      let a = el.toArc(pen)
      if not a.isDegenerate:
        take a.boundingBox
      pen = el.arcEnd
    of peClosePath:
      pen = start

func toPath*(path: BezPath): BezPath =
  path

func toPath*(r: Rect): BezPath =
  result.moveTo point(r.x0, r.y0)
  result.lineTo point(r.x1, r.y0)
  result.lineTo point(r.x1, r.y1)
  result.lineTo point(r.x0, r.y1)
  result.closePath()

func boundingBox*(r: Rect): Rect =
  r.normalized

func toPath*(rr: RoundedRect): BezPath =
  let r = rr.rect.normalized
  let radius = min(rr.radius, min(r.width, r.height) * 0.5)
  if radius <= 0:
    return r.toPath
  let k = radius * kappa
  result.moveTo point(r.x0 + radius, r.y0)
  result.lineTo point(r.x1 - radius, r.y0)
  result.cubicTo point(r.x1 - radius + k, r.y0),
    point(r.x1, r.y0 + radius - k), point(r.x1, r.y0 + radius)
  result.lineTo point(r.x1, r.y1 - radius)
  result.cubicTo point(r.x1, r.y1 - radius + k),
    point(r.x1 - radius + k, r.y1), point(r.x1 - radius, r.y1)
  result.lineTo point(r.x0 + radius, r.y1)
  result.cubicTo point(r.x0 + radius - k, r.y1),
    point(r.x0, r.y1 - radius + k), point(r.x0, r.y1 - radius)
  result.lineTo point(r.x0, r.y0 + radius)
  result.cubicTo point(r.x0, r.y0 + radius - k),
    point(r.x0 + radius - k, r.y0), point(r.x0 + radius, r.y0)
  result.closePath()

func boundingBox*(rr: RoundedRect): Rect =
  rr.rect.normalized

func toPath*(e: Ellipse): BezPath =
  ## Four cubics, the usual approximation.
  let c = e.center
  let rx = e.radii.x
  let ry = e.radii.y
  let kx = rx * kappa
  let ky = ry * kappa
  result.moveTo point(c.x + rx, c.y)
  result.cubicTo point(c.x + rx, c.y + ky),
    point(c.x + kx, c.y + ry), point(c.x, c.y + ry)
  result.cubicTo point(c.x - kx, c.y + ry),
    point(c.x - rx, c.y + ky), point(c.x - rx, c.y)
  result.cubicTo point(c.x - rx, c.y - ky),
    point(c.x - kx, c.y - ry), point(c.x, c.y - ry)
  result.cubicTo point(c.x + kx, c.y - ry),
    point(c.x + rx, c.y - ky), point(c.x + rx, c.y)
  result.closePath()

func boundingBox*(e: Ellipse): Rect =
  rect(
    e.center.x - e.radii.x,
    e.center.y - e.radii.y,
    e.center.x + e.radii.x,
    e.center.y + e.radii.y,
  )

func toPath*(c: Circle): BezPath =
  ellipse(c.center, c.radius, c.radius).toPath

func boundingBox*(c: Circle): Rect =
  rect(
    c.center.x - c.radius,
    c.center.y - c.radius,
    c.center.x + c.radius,
    c.center.y + c.radius,
  )

func toPath*(l: Line): BezPath =
  result.moveTo l.p0
  result.lineTo l.p1

func boundingBox*(l: Line): Rect =
  rectFromPoints(l.p0, l.p1)

# Flattening

func quadSegments(p0, p1, p2: Point, tolerance: float64): int =
  # Wang's formula: the number of segments that keeps the chord error below
  # `tolerance`.
  let dd = (p0.toVec - 2.0 * p1.toVec + p2.toVec).length
  max(1, int(ceil(sqrt(0.25 * dd / tolerance))))

func cubicSegments(p0, p1, p2, p3: Point, tolerance: float64): int =
  let d1 = (p0.toVec - 2.0 * p1.toVec + p2.toVec).length
  let d2 = (p1.toVec - 2.0 * p2.toVec + p3.toVec).length
  max(1, int(ceil(sqrt(0.75 * max(d1, d2) / tolerance))))

func arcSegments(a: Arc, tolerance: float64): int =
  # A chord spanning `step` of the parameter strays from the ellipse by at
  # most `r * (1 - cos(step / 2))` with `r` the larger radius, since the
  # ellipse is the unit circle stretched by at most that much.
  let r = max(a.radii.x, a.radii.y)
  let step = max(2 * arccos(clamp(1 - tolerance / r, -1.0, 1.0)), 1e-4)
  max(1, int(ceil(abs(a.sweepAngle) / step)))

func flatten*(path: BezPath, tolerance: float64): seq[Polyline] =
  ## Turns the curves into line segments that stay within `tolerance` of the
  ## curve. Each subpath becomes one polyline. Closed subpaths don't repeat
  ## their first point at the end. A subpath that is only a `moveTo` draws
  ## nothing and is left out; one with a zero-length segment (`M p L p`, or
  ## `M p Z`) is kept, since a stroke draws its caps as a dot. An arc that
  ## ends where it starts adds nothing, as in SVG.
  var current: Polyline
  var start = point(0, 0)
  var pen = point(0, 0)
  var open = false

  template flush() =
    if open:
      if current.points.len > 1 or current.closed:
        result.add current
      current = Polyline()
      open = false

  for el in path.elements:
    case el.kind
    of peMoveTo:
      flush()
      current.points.add el.to
      start = el.to
      pen = el.to
      open = true
    of peLineTo:
      if not open:
        current.points.add pen
        start = pen
        open = true
      current.points.add el.to
      pen = el.to
    of peQuadTo:
      if not open:
        current.points.add pen
        start = pen
        open = true
      let n = quadSegments(pen, el.ctrl, el.quadEnd, tolerance)
      for i in 1 .. n:
        current.points.add quadPoint(pen, el.ctrl, el.quadEnd, i / n)
      pen = el.quadEnd
    of peCubicTo:
      if not open:
        current.points.add pen
        start = pen
        open = true
      let n = cubicSegments(pen, el.ctrl1, el.ctrl2, el.cubicEnd, tolerance)
      for i in 1 .. n:
        current.points.add cubicPoint(pen, el.ctrl1, el.ctrl2, el.cubicEnd, i / n)
      pen = el.cubicEnd
    of peArcTo:
      if not open:
        current.points.add pen
        start = pen
        open = true
      if el.arcEnd != pen:
        let a = el.toArc(pen)
        if not a.isDegenerate:
          let n = arcSegments(a, tolerance)
          for i in 1 ..< n:
            current.points.add a.pointAt(a.startAngle + a.sweepAngle * (i / n))
        current.points.add el.arcEnd
      pen = el.arcEnd
    of peClosePath:
      if open:
        current.closed = true
        if current.points.len > 1 and current.points[^1] ~= current.points[0]:
          current.points.setLen(current.points.len - 1)
        flush()
      pen = start
  flush()

func signedArea*(points: openArray[Point]): float64 =
  ## Shoelace area of a closed polygon. Positive for one winding direction,
  ## negative for the other; which is which depends on the axes, so callers
  ## compare signs rather than relying on one.
  for i in 0 ..< points.len:
    let p = points[i]
    let q = points[(i + 1) mod points.len]
    result += p.x * q.y - q.x * p.y
  result *= 0.5

func area*(path: BezPath, tolerance = 0.01): float64 =
  ## Signed area enclosed by the path (every subpath treated as closed),
  ## computed from the flattened outline.
  for poly in path.flatten(tolerance):
    result += signedArea(poly.points)

func boundingBox*(polylines: openArray[Polyline]): Rect =
  var first = true
  for poly in polylines:
    for p in poly.points:
      if first:
        result = rect(p.x, p.y, p.x, p.y)
        first = false
      else:
        result = result.union(p)

func polygonPath*(points: openArray[Point], closed = true): BezPath =
  ## A path through the given points.
  if points.len == 0:
    return
  result.moveTo points[0]
  for i in 1 ..< points.len:
    result.lineTo points[i]
  if closed:
    result.closePath()

func toPath*(polylines: openArray[Polyline]): BezPath =
  for poly in polylines:
    result.extend polygonPath(poly.points, poly.closed)
