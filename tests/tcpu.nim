import std/[math, unittest]
import pollock/[draw, samples, testing]
import pollock/backends/cpu

proc near(a, b: Color, tolerance = 1.0 / 255): bool =
  abs(a.r - b.r) <= tolerance and abs(a.g - b.g) <= tolerance and
    abs(a.b - b.b) <= tolerance and abs(a.a - b.a) <= tolerance

suite "cpu backend":
  test "aligned rect is exact":
    var ctx = newCpuContext(10, 10)
    ctx.clear(white)
    ctx.fill(rect(2, 3, 6, 8), red)
    check ctx.pixel(2, 3) == red
    check ctx.pixel(5, 7) == red
    check ctx.pixel(1, 3) == white
    check ctx.pixel(6, 7) == white
    check ctx.pixel(2, 8) == white
    for y in 0 ..< 10:
      for x in 0 ..< 10:
        let inside = x >= 2 and x < 6 and y >= 3 and y < 8
        check ctx.pixel(x, y) == (if inside: red else: white)

  test "half pixel coverage":
    var ctx = newCpuContext(4, 4)
    ctx.clear(white)
    ctx.fill(rect(0.5, 0, 2.5, 4), black)
    check near(ctx.pixel(0, 0), gray(0.5))
    check near(ctx.pixel(1, 0), black)
    check near(ctx.pixel(2, 0), gray(0.5))
    check near(ctx.pixel(3, 0), white)

  test "diagonal edge coverage":
    var ctx = newCpuContext(4, 4)
    ctx.clear(white)
    var tri = newPath()
    tri.moveTo 0, 0
    tri.lineTo 4, 0
    tri.lineTo 0, 4
    tri.closePath()
    ctx.fill(tri, black)
    check near(ctx.pixel(0, 0), black)
    check near(ctx.pixel(3, 0), gray(0.5))
    check near(ctx.pixel(1, 1), black)
    check near(ctx.pixel(2, 1), gray(0.5))
    check near(ctx.pixel(3, 3), white)

  test "translucent compositing":
    var ctx = newCpuContext(2, 2)
    ctx.clear(white)
    ctx.fill(rect(0, 0, 2, 2), blue.withAlpha(0.5))
    check near(ctx.pixel(0, 0), rgb(0.5, 0.5, 1))
    ctx.fill(rect(0, 0, 2, 2), red.withAlpha(0.5))
    check near(ctx.pixel(0, 0), rgb(0.75, 0.25, 0.5))

  test "transparent target":
    var ctx = newCpuContext(2, 2)
    ctx.fill(rect(0, 0, 2, 2), red.withAlpha(0.5))
    check near(ctx.pixel(0, 0), red.withAlpha(0.5))
    check ctx.toImage()[0, 0].toRgba8 == Rgba8(r: 255, g: 0, b: 0, a: 128)

  test "fill rules":
    var ctx = newCpuContext(20, 20)
    ctx.clear(white)
    var rings = newPath()
    rings.extend rect(2, 2, 18, 18).toPath
    rings.extend rect(6, 6, 14, 14).toPath
    ctx.fill(rings, black, frEvenOdd)
    check ctx.pixel(3, 3) == black
    check ctx.pixel(10, 10) == white
    ctx.clear(white)
    ctx.fill(rings, black, frNonZero)
    check ctx.pixel(10, 10) == black
    var opposite = newPath()
    opposite.extend rect(2, 2, 18, 18).toPath
    opposite.moveTo 6, 6
    opposite.lineTo 6, 14
    opposite.lineTo 14, 14
    opposite.lineTo 14, 6
    opposite.closePath()
    ctx.clear(white)
    ctx.fill(opposite, black, frNonZero)
    check ctx.pixel(10, 10) == white

  test "clip":
    var ctx = newCpuContext(10, 10)
    ctx.clear(white)
    ctx.withClip(rect(0, 0, 5, 10)):
      ctx.fill(rect(0, 0, 10, 10), black)
    check ctx.pixel(4, 5) == black
    check ctx.pixel(5, 5) == white
    ctx.fill(rect(0, 0, 10, 10), red)
    check ctx.pixel(5, 5) == red

  test "clips intersect":
    var ctx = newCpuContext(10, 10)
    ctx.clear(white)
    ctx.withClip(rect(0, 0, 6, 10)):
      ctx.withClip(rect(4, 0, 10, 10)):
        ctx.fill(rect(0, 0, 10, 10), black)
      ctx.fill(rect(0, 0, 10, 1), red)
    check ctx.pixel(3, 5) == white
    check ctx.pixel(4, 5) == black
    check ctx.pixel(5, 5) == black
    check ctx.pixel(6, 5) == white
    check ctx.pixel(0, 0) == red
    check ctx.pixel(7, 0) == white

  test "clear ignores the clip":
    var ctx = newCpuContext(4, 4)
    ctx.clip(rect(0, 0, 1, 1))
    ctx.clear(red)
    check ctx.pixel(3, 3) == red

  test "transform":
    var ctx = newCpuContext(10, 10)
    ctx.clear(white)
    ctx.withTransform(translate(5, 0) * scale(2)):
      ctx.fill(rect(0, 0, 2, 2), black)
    check ctx.pixel(5, 0) == black
    check ctx.pixel(8, 3) == black
    check ctx.pixel(4, 0) == white
    check ctx.pixel(9, 0) == white
    check ctx.currentTransform.isIdentity

  test "stroke width is in user space":
    var ctx = newCpuContext(20, 20)
    ctx.clear(white)
    ctx.withTransform(scale(1, 2)):
      ctx.stroke(line(0, 5, 20, 5), black, 2.0)
    # A 2-wide line scaled by 2 vertically covers rows 8 to 12.
    check ctx.pixel(10, 7) == white
    check ctx.pixel(10, 8) == black
    check ctx.pixel(10, 11) == black
    check ctx.pixel(10, 12) == white

  test "stroke covers whole pixels when aligned":
    var ctx = newCpuContext(10, 10)
    ctx.clear(white)
    ctx.stroke(line(0, 5, 10, 5), black, 4.0)
    check ctx.pixel(5, 2) == white
    check ctx.pixel(5, 3) == black
    check ctx.pixel(5, 6) == black
    check ctx.pixel(5, 7) == white

  test "geometry outside the target":
    var ctx = newCpuContext(10, 10)
    ctx.clear(white)
    ctx.fill(rect(-50, -50, 5, 5), black)
    check ctx.pixel(4, 4) == black
    check ctx.pixel(5, 5) == white
    ctx.fill(rect(5, -100, 100, 100), red)
    check ctx.pixel(5, 0) == red
    check ctx.pixel(4, 0) == black
    ctx.fill(rect(100, 100, 200, 200), blue)
    ctx.fill(circle(-1000, -1000, 10), blue)
    check ctx.pixel(9, 9) == red
    var huge = newPath()
    huge.moveTo -1e6, -1e6
    huge.lineTo 1e6, -1e6
    huge.lineTo 1e6, 1e6
    huge.lineTo -1e6, 1e6
    huge.closePath()
    ctx.fill(huge, green)
    check ctx.pixel(0, 0) == green
    check ctx.pixel(9, 9) == green

  test "a shape entirely left of the target has no effect":
    var ctx = newCpuContext(4, 4)
    ctx.clear(white)
    ctx.fill(rect(-10, 0, -2, 4), black)
    for x in 0 ..< 4:
      check ctx.pixel(x, 2) == white

  test "gradients":
    var ctx = newCpuContext(10, 1)
    ctx.fill(rect(0, 0, 10, 1), linearGradient(point(0, 0), point(10, 0), black, white))
    check near(ctx.pixel(0, 0), gray(0.05))
    check near(ctx.pixel(9, 0), gray(0.95))
    ctx.fill(rect(0, 0, 10, 1), linearGradient(point(20, 0), point(30, 0), red, blue))
    check ctx.pixel(5, 0) == red # pad
    ctx.fill(rect(0, 0, 10, 1), radialGradient(point(0, 0.5), 10, white, black))
    check ctx.pixel(0, 0).r > 0.9
    check ctx.pixel(9, 0).r < 0.1

  test "drawImage at natural size is exact":
    let img = checkerboard(4, 1, red, blue)
    var ctx = newCpuContext(4, 4)
    ctx.drawImage(img, point(0, 0), ipNearest)
    check compareImages(ctx.toImage(), img).matches
    var bilinear = newCpuContext(4, 4)
    bilinear.drawImage(img, point(0, 0), ipBilinear)
    check compareImages(bilinear.toImage(), img).matches

  test "drawImage scales":
    let img = checkerboard(2, 1, red, blue)
    var ctx = newCpuContext(4, 4)
    ctx.drawImage(img, rect(0, 0, 4, 4), ipNearest)
    check ctx.pixel(0, 0) == red
    check ctx.pixel(1, 1) == red
    check ctx.pixel(2, 0) == blue
    check ctx.pixel(3, 3) == red

  test "finish":
    var ctx = newCpuContext(1, 1)
    check ctx.finish().ok

  test "samples are deterministic":
    for i in 0 ..< sampleNames.len:
      var a = newCpuContext(sampleWidth, sampleHeight)
      var b = newCpuContext(sampleWidth, sampleHeight)
      a.drawSample(i)
      b.drawSample(i)
      check compareImages(a.toImage(), b.toImage()).matches

  test "stroked circle area":
    var ctx = newCpuContext(100, 100)
    ctx.stroke(circle(50, 50, 30), black, 10.0)
    var total = 0.0
    for y in 0 ..< 100:
      for x in 0 ..< 100:
        total += ctx.pixel(x, y).a
    # Ring between radius 25 and 35.
    check abs(total - PI * (35 * 35 - 25 * 25)) < 15

  test "a dashed stroke with zero gaps is solid":
    var ctx = newCpuContext(30, 20)
    ctx.stroke(line(0, 10, 20, 10), black, strokeStyle(width = 4, dashes = [5.0, 0.0]))
    for x in 0 ..< 20:
      check ctx.pixel(x, 10).a == 1.0
    check ctx.pixel(20, 10).a == 0.0

  test "a dotted stroke has a dot at the start":
    var ctx = newCpuContext(30, 20)
    ctx.stroke(
      line(4, 10, 24, 10),
      black,
      strokeStyle(width = 4, cap = lcRound, dashes = [0.0, 5.0]),
    )
    for x in [4, 9, 14, 19, 23]:
      check ctx.pixel(x, 10).a > 0.9
    check ctx.pixel(6, 10).a == 0.0

  test "a lone moveTo draws no dot":
    var p = newPath()
    p.moveTo 5, 10
    p.lineTo 15, 10
    p.moveTo 30, 10
    var ctx = newCpuContext(40, 20)
    ctx.stroke(p, black, strokeStyle(width = 6, cap = lcRound))
    check ctx.pixel(10, 10).a == 1.0
    check ctx.pixel(30, 10).a == 0.0

  test "degenerate gradients paint the last stop":
    var ctx = newCpuContext(4, 4)
    ctx.fill(rect(0, 0, 4, 4), linearGradient(point(2, 2), point(2, 2), red, blue))
    check ctx.pixel(1, 1) == blue
    ctx.fill(rect(0, 0, 4, 4), radialGradient(point(2, 2), 0, red, green, exRepeat))
    check ctx.pixel(1, 1) == green

  test "strokes stay smooth under a stretching transform":
    # The same stroke, once through the context's transform and once
    # expanded and flattened finely by hand, must agree along the stretched
    # axis too. A tolerance taken from the average scale instead of the
    # largest one leaves about 80 pixels off by more than 24 levels here;
    # the remaining differences come from where the stroke pieces overlap.
    let style = strokeStyle(width = 2)
    let m = translate(200, 20) * scale(20, 1)
    var a = newCpuContext(400, 40)
    a.withTransform(m):
      a.stroke(circle(0, 0, 9), black, style)
    var b = newCpuContext(400, 40)
    b.fillPath(
      m.transform(strokeOutline(circle(0, 0, 9).toPath, style, 0.0005)),
      solid(black),
      frNonZero,
    )
    let diff = compareImages(a.toImage(), b.toImage(), tolerance = 24)
    checkpoint($diff.differingPixels & " pixels differ")
    check diff.differingPixels < 30

  test "fills in separate columns don't disturb each other":
    var ctx = newCpuContext(100, 10)
    ctx.clear(white)
    ctx.fill(rect(2.5, 0, 6, 10), black)
    ctx.fill(rect(60, 0, 70.5, 10), red)
    check near(ctx.pixel(2, 5), gray(0.5))
    check ctx.pixel(4, 5) == black
    check ctx.pixel(6, 5) == white
    check ctx.pixel(30, 5) == white
    check ctx.pixel(60, 5) == red
    check near(ctx.pixel(70, 5), rgb(1, 0.5, 0.5))
    check ctx.pixel(71, 5) == white
    ctx.fill(rect(95, 0, 120, 10), blue)
    check ctx.pixel(99, 5) == blue
    check ctx.pixel(94, 5) == white

suite "sample helpers":
  test "starPath uses its inner radius and any point count":
    let thin = starPath(point(0, 0), 10, 3)
    let fat = starPath(point(0, 0), 10, 8)
    check abs(thin.area) < abs(fat.area)
    let six = starPath(point(0, 0), 10, 5, points = 6)
    check six.flatten(0.1)[0].points.len == 12
    for i, p in six.flatten(0.1)[0].points:
      check distance(p, point(0, 0)) ~= (if i mod 2 == 0: 10.0 else: 5.0)

  test "pentagram has a hole under even-odd":
    var ctx = newCpuContext(40, 40)
    ctx.fill(pentagramPath(point(20, 20), 18), black, frEvenOdd)
    check ctx.pixel(20, 20).a == 0.0
    ctx.fill(pentagramPath(point(20, 20), 18), black, frNonZero)
    check ctx.pixel(20, 20).a == 1.0
