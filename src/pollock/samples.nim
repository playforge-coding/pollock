## Sample scenes that every backend renders. The conformance tests compare
## their output with the golden files in `tests/golden/`, and `nimble
## samples` writes them to `out/` for a look. A new backend should render
## all of them before it is called done.

import std/math
import ./draw

export draw

const
  sampleWidth* = 400
  sampleHeight* = 300
  sampleNames* = ["shapes", "strokes", "gradients", "clipping", "fillrules", "images"]

func checkerboard*(cells, cellSize: int, a, b: Color): ImageData =
  ## A square test image.
  result = newImage(cells * cellSize, cells * cellSize)
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      let on = ((x div cellSize) + (y div cellSize)) mod 2 == 0
      result[x, y] = if on: a else: b

func pentagramPath*(center: Point, radius: float64): BezPath =
  ## A five-pointed star drawn as one self-intersecting polygon through every
  ## second corner of a pentagon. The middle winds twice, so it fills
  ## differently under the two fill rules.
  for i in 0 ..< 5:
    let angle = -PI / 2 + i.float64 * 4 * PI / 5
    let p = center + vec2(cos(angle), sin(angle)) * radius
    if i == 0:
      result.moveTo p
    else:
      result.lineTo p
  result.closePath()

func starPath*(center: Point, outer, inner: float64, points = 5): BezPath =
  ## A simple (not self-intersecting) star with `points` tips at radius
  ## `outer` and the notches between them at radius `inner`. Needs at least
  ## two points.
  for i in 0 ..< 2 * points:
    let angle = -PI / 2 + i.float64 * PI / points.float64
    let r = if i mod 2 == 0: outer else: inner
    let p = center + vec2(cos(angle), sin(angle)) * r
    if i == 0:
      result.moveTo p
    else:
      result.lineTo p
  result.closePath()

proc sampleShapes[C: RenderContext](ctx: var C) =
  ctx.clear(rgb8(250, 250, 248))
  ctx.fill(rect(20, 20, 140, 120), rgb8(220, 60, 60))
  ctx.fill(roundedRect(170, 20, 300, 120, 24), rgb8(60, 130, 220))
  ctx.fill(circle(350, 70, 45), rgb8(60, 180, 90))
  ctx.fill(ellipse(point(110, 210), 90, 50), rgb8(240, 180, 40))
  ctx.fill(rect(150, 170, 300, 280), rgb8(120, 60, 200).withAlpha(0.5))
  ctx.fill(circle(300, 225, 60), rgb8(0, 0, 0).withAlpha(0.3))
  var triangle = newPath()
  triangle.moveTo 330, 280
  triangle.lineTo 390, 280
  triangle.lineTo 360, 180
  triangle.closePath()
  ctx.fill(triangle, rgb8(30, 30, 30))

proc sampleStrokes[C: RenderContext](ctx: var C) =
  ctx.clear(white)
  let caps = [lcButt, lcRound, lcSquare]
  for i, cap in caps:
    let y = 40.0 + i.float64 * 40
    ctx.stroke(
      line(40, y, 180, y), rgb8(40, 40, 40), strokeStyle(width = 18, cap = cap)
    )
    ctx.stroke(line(40, y, 180, y), red, 1.0)
  let joins = [ljMiter, ljRound, ljBevel]
  for i, join in joins:
    let x = 230.0 + i.float64 * 55
    var zig = newPath()
    zig.moveTo x, 150
    zig.lineTo x + 20, 30
    zig.lineTo x + 40, 150
    ctx.stroke(zig, rgb8(40, 90, 160), strokeStyle(width = 14, join = join))
  ctx.stroke(
    circle(100, 230, 50),
    rgb8(200, 80, 30),
    strokeStyle(width = 6, dashes = [12.0, 8.0], cap = lcRound),
  )
  for i in 0 .. 5:
    let y = 180.0 + i.float64 * 20
    ctx.stroke(line(200, y, 380, y + 10), black, 0.5 + i.float64 * 1.0)
  var tri = newPath()
  tri.moveTo 320, 180
  tri.lineTo 380, 280
  tri.lineTo 260, 280
  tri.closePath()
  ctx.stroke(
    tri, rgb8(30, 150, 90), strokeStyle(width = 8, join = ljMiter, miterLimit = 10)
  )

proc sampleGradients[C: RenderContext](ctx: var C) =
  ctx.clear(rgb8(30, 30, 36))
  ctx.fill(
    rect(20, 20, 380, 90),
    linearGradient(
      point(20, 0),
      point(380, 0),
      [
        stop(0.0, rgb8(240, 80, 60)),
        stop(0.5, rgb8(250, 220, 90)),
        stop(1.0, rgb8(70, 160, 240)),
      ],
    ),
  )
  ctx.fill(
    circle(90, 200, 70), radialGradient(point(70, 180), 70, white, rgb8(40, 90, 200))
  )
  ctx.fill(
    rect(190, 130, 380, 200),
    linearGradient(
      point(190, 0), point(230, 0), rgb8(255, 255, 255), rgb8(20, 20, 20), exRepeat
    ),
  )
  ctx.fill(
    rect(190, 215, 380, 285),
    linearGradient(
      point(190, 0), point(230, 0), rgb8(255, 120, 0), rgb8(0, 120, 255), exReflect
    ),
  )
  ctx.fill(
    roundedRect(20, 120, 150, 140, 10),
    linearGradient(point(0, 120), point(0, 140), white.withAlpha(0.0), white),
  )

proc sampleClipping[C: RenderContext](ctx: var C) =
  ctx.clear(rgb8(245, 240, 230))
  ctx.withClip(circle(110, 150, 90)):
    for i in 0 .. 5:
      ctx.withTransform(rotateAbout(i.float64 * PI / 6, point(110, 150))):
        ctx.fill(
          rect(60, 140, 160, 160),
          rgb8(uint8(40 + i * 30), 90, uint8(180 - i * 20)).withAlpha(0.7),
        )
  ctx.withClip(rect(220, 40, 380, 260)):
    ctx.withClip(circle(300, 150, 100)):
      ctx.fill(rect(0, 0, 400, 300), rgb8(230, 120, 60))
      ctx.withTransform(translate(300, 150) * scale(1.5, 0.6)):
        ctx.fill(circle(0, 0, 60), rgb8(60, 40, 120))
  ctx.withSave:
    ctx.translate(20, 20)
    ctx.scale(0.5)
    ctx.fill(rect(0, 0, 60, 60), black)
    ctx.stroke(rect(0, 0, 60, 60), red, 4.0)
  ctx.stroke(circle(110, 150, 90), black, 1.0)

proc sampleFillRules[C: RenderContext](ctx: var C) =
  ctx.clear(white)
  ctx.fill(pentagramPath(point(100, 110), 85), rgb8(220, 100, 40), frNonZero)
  ctx.fill(pentagramPath(point(300, 110), 85), rgb8(40, 100, 220), frEvenOdd)
  var rings = newPath()
  for r in [70.0, 55.0, 40.0, 25.0, 10.0]:
    rings.extend circle(point(100, 230), r).toPath
  ctx.fill(rings, rgb8(60, 60, 60), frEvenOdd)
  var squares = newPath()
  squares.extend rect(230, 170, 370, 290).toPath
  squares.extend rect(260, 200, 340, 260).toPath
  ctx.fill(squares, rgb8(90, 170, 90), frEvenOdd)
  ctx.stroke(squares, black, 1.0)

proc sampleImages[C: RenderContext](ctx: var C) =
  ctx.clear(rgb8(240, 240, 240))
  let board = checkerboard(8, 1, rgb8(30, 30, 30), rgb8(230, 200, 60))
  ctx.drawImage(board, rect(20, 20, 180, 180), ipNearest)
  ctx.drawImage(board, rect(220, 20, 380, 180), ipBilinear)
  ctx.withTransform(rotateAbout(PI / 8, point(100, 250))):
    ctx.drawImage(board, rect(60, 210, 140, 290), ipNearest)
  var photo = newImage(4, 4, ifRgb8)
  for y in 0 .. 3:
    for x in 0 .. 3:
      photo[x, y] = rgb(x.float64 / 3, y.float64 / 3, 0.5)
  ctx.drawImage(photo, rect(220, 200, 380, 290), ipBilinear)

proc drawSample*[C: RenderContext](ctx: var C, index: int) =
  ## Draws sample `index` (see `sampleNames`) on any backend.
  case index
  of 0:
    ctx.sampleShapes()
  of 1:
    ctx.sampleStrokes()
  of 2:
    ctx.sampleGradients()
  of 3:
    ctx.sampleClipping()
  of 4:
    ctx.sampleFillRules()
  of 5:
    ctx.sampleImages()
  else:
    raise newException(IndexDefect, "no sample " & $index)
