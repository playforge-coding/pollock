import std/[math, unittest]
import pollock/geometry

func near(a, b: Rect): bool =
  a.x0 ~= b.x0 and a.y0 ~= b.y0 and a.x1 ~= b.x1 and a.y1 ~= b.y1

suite "points and vectors":
  test "arithmetic":
    let p = point(1, 2) + vec2(3, 4)
    check p == point(4, 6)
    check point(4, 6) - point(1, 2) == vec2(3, 4)
    check vec2(3, 4).length == 5
    check vec2(3, 4).normalized.toPoint ~= point(0.6, 0.8)
    check dot(vec2(1, 0), vec2(0, 1)) == 0
    check cross(vec2(1, 0), vec2(0, 1)) == 1
    check perp(vec2(1, 0)) == vec2(0, 1)
    check lerp(point(0, 0), point(10, 20), 0.25) == point(2.5, 5)

suite "rectangles":
  test "construction and measures":
    let r = rectXywh(10, 20, 30, 40)
    check r == rect(10, 20, 40, 60)
    check r.width == 30
    check r.height == 40
    check r.center == point(25, 40)
    check r.area == 1200
    check rect(point(1, 2), size(3, 4)) == rect(1, 2, 4, 6)
    check rect(5, 5, 0, 0).normalized == rect(0, 0, 5, 5)

  test "set operations":
    let a = rect(0, 0, 10, 10)
    let b = rect(5, 5, 20, 20)
    check a.union(b) == rect(0, 0, 20, 20)
    check a.intersect(b) == rect(5, 5, 10, 10)
    check a.intersect(rect(50, 50, 60, 60)).isEmpty
    check not a.intersect(b).isEmpty
    check a.contains(point(0, 0))
    check not a.contains(point(10, 10))
    check a.inflate(1, 2) == rect(-1, -2, 11, 12)
    check rect(0.2, 0.7, 3.1, 4.0).roundOut == rect(0, 0, 4, 4)

suite "affine":
  test "ordering":
    # `m * n` applies n first.
    let m = translate(10, 0) * scale(2)
    check m * point(1, 1) == point(12, 2)
    let n = scale(2) * translate(10, 0)
    check n * point(1, 1) == point(22, 2)

  test "rotation direction":
    let p = rotate(PI / 2) * point(1, 0)
    check p ~= point(0, 1)

  test "inverse":
    let m = translate(3, 4) * rotate(0.7) * scale(2, 3)
    let round = m * m.inverse
    check round.a ~= 1.0
    check round.d ~= 1.0
    check abs(round.b) < 1e-12
    check abs(round.c) < 1e-12
    check abs(round.e) < 1e-12
    check abs(round.f) < 1e-12
    check (m.inverse * (m * point(5, 6))) ~= point(5, 6)

  test "rotateAbout keeps the center":
    let c = point(50, 60)
    check (rotateAbout(1.0, c) * c) ~= c

  test "rect bounds":
    let r = rotate(PI / 4).transform(rect(-1, -1, 1, 1))
    check r.x0 ~= -sqrt(2.0)
    check r.x1 ~= sqrt(2.0)

  test "scale factor":
    check scale(2, 8).scaleFactor == 4
    check rotate(1.0).scaleFactor ~= 1.0

suite "paths":
  test "rect path":
    let p = rect(0, 0, 10, 5).toPath
    check p.len == 5
    check p.elements[0].kind == peMoveTo
    check p.elements[^1].kind == peClosePath
    check p.boundingBox == rect(0, 0, 10, 5)

  test "flatten rect":
    let polys = rect(0, 0, 10, 5).toPath.flatten(0.1)
    check polys.len == 1
    check polys[0].closed
    check polys[0].points.len == 4

  test "circle area and tolerance":
    let c = circle(0, 0, 10)
    # Four cubics approximate a circle to about 0.03% in area.
    check abs(c.toPath.area(0.01) - PI * 100) < 0.5
    for poly in c.toPath.flatten(0.05):
      for p in poly.points:
        check abs(distance(p, point(0, 0)) - 10) < 0.05

  test "transform path":
    let p = translate(5, 5).transform(circle(0, 0, 1).toPath)
    check p.boundingBox.center ~= point(5, 5)

  test "rounded rect clamps its radius":
    let p = roundedRect(0, 0, 10, 10, 100).toPath
    check p.boundingBox == rect(0, 0, 10, 10)
    check abs(p.area - PI * 25) < 0.3

  test "open subpaths":
    var p = newPath()
    p.moveTo 0, 0
    p.lineTo 10, 0
    p.moveTo 0, 5
    p.lineTo 10, 5
    let polys = p.flatten(0.1)
    check polys.len == 2
    check not polys[0].closed

  test "a lone moveTo is left out, a zero-length segment is kept":
    var p = newPath()
    p.moveTo 5, 10
    p.lineTo 15, 10
    p.moveTo 30, 10
    check p.flatten(0.1).len == 1
    var dot = newPath()
    dot.moveTo 30, 10
    dot.lineTo 30, 10
    check dot.flatten(0.1).len == 1
    var closedDot = newPath()
    closedDot.moveTo 30, 10
    closedDot.closePath()
    check closedDot.flatten(0.1).len == 1

  test "maxScale is the largest stretch":
    check maxScale(scale(20, 0.05)) ~= 20.0
    check maxScale(scale(-3, 2)) ~= 3.0
    check maxScale(rotate(0.7) * scale(5, 1)) ~= 5.0
    check maxScale(skew(1, 0)) ~= (1 + sqrt(5.0)) / 2
    check maxScale(scale(0)) == 0

  test "signed area orientation":
    let cw = [point(0, 0), point(10, 0), point(10, 10), point(0, 10)]
    let ccw = [point(0, 0), point(0, 10), point(10, 10), point(10, 0)]
    check signedArea(cw) == 100
    check signedArea(ccw) == -100

suite "arcs":
  test "the flags pick one of the four arcs through two points":
    let s = point(0, 0)
    let e = point(10, 0)
    for large in [false, true]:
      for sweep in [false, true]:
        let a = arcTo(vec2(10, 10), 0.0, large, sweep, e).toArc(s)
        check a.radii.x ~= 10.0
        check a.radii.y ~= 10.0
        check a.startPoint ~= s
        check a.endPoint ~= e
        check abs(a.sweepAngle) ~= (if large: 5 * PI / 3 else: PI / 3)
        check (a.sweepAngle > 0) == sweep
    # Left to right with a positive sweep turns clockwise on screen, so the
    # short arc bulges upward and its center sits below the chord.
    let small = arcTo(vec2(10, 10), 0.0, false, true, e).toArc(s)
    check small.center ~= point(5, 5 * sqrt(3.0))
    check small.pointAt(small.startAngle + small.sweepAngle / 2) ~=
      point(5, 5 * sqrt(3.0) - 10)
    let other = arcTo(vec2(10, 10), 0.0, false, false, e).toArc(s)
    check other.center ~= point(5, -5 * sqrt(3.0))

  test "radii too small to reach both points are scaled up":
    let a = arcTo(vec2(1, 1), 0.0, false, true, point(10, 0)).toArc(point(0, 0))
    check a.radii.x ~= 5.0
    check a.radii.y ~= 5.0
    check a.center ~= point(5, 0)
    check abs(a.sweepAngle) ~= PI
    # Negative radii count as positive.
    check arcTo(vec2(-7, 7), 0.0, false, true, point(1, 1)).radii == vec2(7, 7)

  test "a zero radius is a line, and an arc back to its start is nothing":
    var p = newPath()
    p.moveTo 0, 0
    p.arcTo(vec2(0, 5), 0.0, false, true, point(10, 0))
    check p.flatten(0.1)[0].points == @[point(0, 0), point(10, 0)]
    var line = newPath()
    line.moveTo 0, 0
    line.lineTo 10, 0
    check p.toCubics == line
    check near(p.boundingBox, rect(0, 0, 10, 0))
    var same = newPath()
    same.moveTo 5, 5
    same.arcTo(3.0, point(5, 5))
    check same.flatten(0.1).len == 0
    check same.toCubics.len == 1
    check same.boundingBox == rect(5, 5, 5, 5)

  test "only an arc that ends exactly at its start is nothing":
    # Half a unit apart at this size is within the tolerance of `~=`, but it
    # is still an arc: SVG draws it, so the other paths have to as well.
    var far = newPath()
    far.moveTo 1e9, 0
    far.arcTo(10.0, point(1e9 + 0.5, 0))
    check far.flatten(0.0001)[0].points.len > 2
    check far.toCubics.elements[1].kind == peCubicTo
    check far.boundingBox.y1 - far.boundingBox.y0 > 0.001
    # Closer than anything `toArc` can solve for, on either arc: a line to
    # the end, not a half circle a radius away from it.
    for largeArc in [false, true]:
      var tiny = newPath()
      tiny.moveTo 0, 0
      tiny.arcTo(10.0, point(1e-200, 0), largeArc = largeArc)
      check tiny.elements[1].toArc(point(0, 0)).isDegenerate
      check tiny.flatten(0.1)[0].points == @[point(0, 0), point(1e-200, 0)]
      check tiny.toCubics.elements[1] == lineTo(point(1e-200, 0))
      check tiny.boundingBox == rect(0, 0, 1e-200, 0)

  test "flattened arcs lie on the circle":
    var p = newPath()
    p.moveTo 0, 0
    p.arcTo(12.0, point(10, 0), largeArc = true)
    let a = p.elements[1].toArc(point(0, 0))
    let polys = p.flatten(0.01)
    check polys.len == 1
    check polys[0].points.len > 10
    for q in polys[0].points:
      check abs(distance(q, a.center) - 12) < 0.01
    check polys[0].points[^1] == point(10, 0)

  test "the arc shape":
    let full = arc(point(10, 10), 5, 0, 2 * PI)
    check full.toPath.len == 3
    # Flattened at 0.01, the polygon inside the circle loses about two thirds
    # of the tolerance times the perimeter.
    check abs(full.toPath.area - PI * 25) < 0.25
    check near(full.toPath.boundingBox, rect(5, 5, 15, 15))
    let quarter = arc(point(0, 0), 10, 0, PI / 2)
    check quarter.startPoint ~= point(10, 0)
    check quarter.endPoint ~= point(0, 10)
    check near(quarter.boundingBox, rect(0, 0, 10, 10))
    check arc(point(0, 0), 10, 0, -PI / 2).endPoint ~= point(0, -10)
    # Round trip through an element.
    let again = quarter.toPath.elements[1].toArc(quarter.startPoint)
    check again.center ~= point(0, 0)
    check again.radii.x ~= 10.0
    check again.startAngle ~= 0.0
    check again.sweepAngle ~= PI / 2
    # The tilted ellipse's parameterization.
    let tilted = arc(point(1, 2), vec2(10, 5), 0, PI, PI / 2)
    check tilted.pointAt(0) ~= point(1, 12)
    check tilted.pointAt(PI / 2) ~= point(-4, 2)

  test "cubics approximate arcs closely":
    let a = arc(point(0, 0), 100, 0.2, 1.9 * PI)
    let cubics = a.toCubics
    check cubics.len == 4
    var p = newPath()
    p.moveTo a.startPoint
    for c in cubics:
      p.add c
    check p.elements[^1].cubicEnd ~= a.endPoint
    for q in p.flatten(0.01)[0].points:
      check abs(distance(q, point(0, 0)) - 100) < 0.05
    # A path without arcs comes back as it was.
    check rect(0, 0, 4, 4).toPath.toCubics == rect(0, 0, 4, 4).toPath
    var withArc = newPath()
    withArc.moveTo 0, 0
    withArc.arcTo(5.0, point(10, 0))
    withArc.closePath()
    let converted = withArc.toCubics
    check converted.len == 4
    check converted.elements[1].kind == peCubicTo
    check converted.elements[2].cubicEnd == point(10, 0)

  test "arcs stay arcs under a transform":
    let m = translate(3, 4) * rotate(0.5) * scale(2, 0.5)
    var p = newPath()
    p.moveTo 0, 0
    p.arcTo(vec2(10, 6), 0.3, false, true, point(12, 5))
    let t = m.transform(p)
    check t.elements[1].kind == peArcTo
    let a = p.elements[1].toArc(point(0, 0))
    let b = t.elements[1].toArc(m * point(0, 0))
    check b.center ~= m * a.center
    check b.pointAt(b.startAngle + b.sweepAngle / 2) ~=
      m * a.pointAt(a.startAngle + a.sweepAngle / 2)
    # Every point of the transformed arc maps back onto the original ellipse.
    let toUnit =
      scale(1 / a.radii.x, 1 / a.radii.y) * rotate(-a.rotation) *
      translate(-a.center.toVec) * m.inverse
    for q in t.flatten(0.001)[0].points:
      check abs((toUnit * q).toVec.length - 1) < 0.001
    # A reflection turns the arc the other way around, and the identity
    # keeps the element.
    check scale(-1, 1).transform(p).elements[1].sweep == false
    let same = affineIdentity.transform(p).elements[1]
    check same.radii.x ~= 10.0
    check same.radii.y ~= 6.0
    check same.rotation ~= 0.3
    check same.sweep
    # The smaller x radius stays the x radius.
    var tall = newPath()
    tall.moveTo 0, 0
    tall.arcTo(vec2(3, 8), 0.0, false, true, point(2, 2))
    let tallAgain = affineIdentity.transform(tall).elements[1]
    check tallAgain.radii.x ~= 3.0
    check tallAgain.radii.y ~= 8.0

  test "exact bounding boxes":
    var q = newPath()
    q.moveTo 0, 0
    q.quadTo point(10, 20), point(20, 0)
    check near(q.boundingBox, rect(0, 0, 20, 10))
    var c = newPath()
    c.moveTo 0, 0
    c.cubicTo point(0, 30), point(30, 30), point(30, 0)
    check near(c.boundingBox, rect(0, 0, 30, 22.5))
    var loop = newPath()
    loop.moveTo 0, 0
    loop.cubicTo point(40, 0), point(-30, 10), point(10, 10)
    let lb = loop.boundingBox
    check lb.x0 < 0 and lb.x0 > -30
    check lb.x1 > 10 and lb.x1 < 40
    check lb.y0 == 0 and lb.y1 == 10
    check near(circle(0, 0, 10).toPath.boundingBox, rect(-10, -10, 10, 10))
    var half = newPath()
    half.moveTo 0, 0
    half.arcTo(5.0, point(10, 0))
    check near(half.boundingBox, rect(0, -5, 10, 0))
    check near(
      arc(point(0, 0), vec2(10, 5), 0, 2 * PI, PI / 2).boundingBox, rect(-5, -10, 5, 10)
    )
    let short = arc(point(0, 0), 10, 0.1, 0.2)
    check near(short.boundingBox, rectFromPoints(short.startPoint, short.endPoint))
    var open = newPath()
    open.moveTo 1, 1
    open.lineTo 5, -2
    open.closePath()
    open.moveTo 7, 7
    check near(open.boundingBox, rect(1, -2, 7, 7))
