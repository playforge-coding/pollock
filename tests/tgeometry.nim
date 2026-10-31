import std/[math, unittest]
import pollock/geometry

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
