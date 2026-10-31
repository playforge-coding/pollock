import std/[math, unittest]
import pollock/[geometry, stroke]

suite "dashing":
  test "even pattern":
    let poly = Polyline(points: @[point(0, 0), point(100, 0)])
    let pieces = dash(poly, [10.0, 10.0], 0)
    check pieces.len == 5
    for piece in pieces:
      check piece.points.len == 2
      check abs(distance(piece.points[0], piece.points[1]) - 10) < 1e-9
    check pieces[0].points[0] == point(0, 0)
    check pieces[^1].points[1] == point(90, 0)

  test "offset":
    let poly = Polyline(points: @[point(0, 0), point(100, 0)])
    let pieces = dash(poly, [10.0, 10.0], 5)
    check pieces.len == 6
    check abs(distance(pieces[0].points[0], pieces[0].points[1]) - 5) < 1e-9

  test "odd pattern repeats":
    let poly = Polyline(points: @[point(0, 0), point(60, 0)])
    # [10, 20] becomes [10, 20, 10, 20]: on 0..10, off 10..30, on 30..40, off 40..60
    let pieces = dash(poly, [10.0, 20.0], 0)
    check pieces.len == 2

  test "dash across corners":
    let poly = Polyline(points: @[point(0, 0), point(15, 0), point(15, 15)])
    let pieces = dash(poly, [20.0, 5.0], 0)
    check pieces.len == 2
    check pieces[0].points.len == 3 # goes around the corner

  test "no pattern is a no-op":
    let poly = Polyline(points: @[point(0, 0), point(100, 0)])
    check dash(poly, [], 0) == @[poly]
    check dash(poly, [0.0, 0.0], 0) == @[poly]

suite "outline":
  test "butt caps":
    let outline = strokeOutline(line(0, 0, 100, 0).toPath, strokeStyle(width = 10))
    check abs(outline.area - 1000) < 1e-9
    check outline.boundingBox == rect(0, -5, 100, 5)

  test "square caps":
    let outline =
      strokeOutline(line(0, 0, 100, 0).toPath, strokeStyle(width = 10, cap = lcSquare))
    check abs(outline.area - 1100) < 1e-9
    check outline.boundingBox == rect(-5, -5, 105, 5)

  test "round caps":
    let outline =
      strokeOutline(line(0, 0, 100, 0).toPath, strokeStyle(width = 10, cap = lcRound))
    # Two half discs, drawn as two whole discs that overlap the quad.
    check abs(outline.area - (1000 + 2 * PI * 25)) < 0.5
    check outline.boundingBox.x0 ~= -5.0

  test "collinear segments add no join":
    var p = newPath()
    p.moveTo 0, 0
    p.lineTo 50, 0
    p.lineTo 100, 0
    let outline = strokeOutline(p, strokeStyle(width = 10))
    check abs(outline.area - 1000) < 1e-9

  test "miter reaches the corner, bevel does not":
    var p = newPath()
    p.moveTo 0, 100
    p.lineTo 0, 0
    p.lineTo 100, 0
    let miter = strokeOutline(p, strokeStyle(width = 10, join = ljMiter))
    let bevel = strokeOutline(p, strokeStyle(width = 10, join = ljBevel))
    check miter.boundingBox.x0 ~= -5.0
    check miter.boundingBox.y0 ~= -5.0
    check bevel.boundingBox.y0 ~= -5.0
    # The bevel piece and the quads together never reach the miter corner.
    var reachesCorner = false
    for poly in bevel.flatten(0.01):
      for pt in poly.points:
        if pt ~= point(-5, -5):
          reachesCorner = true
    check not reachesCorner

  test "miter limit falls back to bevel":
    var p = newPath()
    p.moveTo 0, 100
    p.lineTo 0, 0
    p.lineTo 1, 100
    let limited =
      strokeOutline(p, strokeStyle(width = 10, join = ljMiter, miterLimit = 2))
    let unlimited =
      strokeOutline(p, strokeStyle(width = 10, join = ljMiter, miterLimit = 1000))
    check unlimited.boundingBox.y0 < limited.boundingBox.y0 - 100

  test "all pieces wind the same way":
    let outline =
      strokeOutline(circle(0, 0, 20).toPath, strokeStyle(width = 4, join = ljRound))
    for poly in outline.flatten(0.01):
      check signedArea(poly.points) >= -1e-9

  test "zero width is empty":
    check strokeOutline(line(0, 0, 1, 1).toPath, strokeStyle(width = 0)).isEmpty

  test "a dot with round caps is a disc":
    var p = newPath()
    p.moveTo 10, 10
    p.lineTo 10, 10
    let outline = strokeOutline(p, strokeStyle(width = 10, cap = lcRound))
    check abs(outline.area - PI * 25) < 0.2
