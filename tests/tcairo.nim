## The Cairo backend. It links libcairo, so this file does nothing unless
## compiled with `-d:pollockCairo`; `nimble testcairo` does that.

when defined(pollockCairo) and not defined(js):
  import std/[os, strformat, unittest]
  import pollock/[samples, testing, png]
  import pollock/backends/cairo

  const goldenDir = currentSourcePath().parentDir / "golden" / "cpu"

  func near(a, b: Color, tolerance = 0.02): bool =
    abs(a.r - b.r) < tolerance and abs(a.g - b.g) < tolerance and
      abs(a.b - b.b) < tolerance and abs(a.a - b.a) < tolerance

  suite "cairo backend":
    test "a new context is transparent black":
      let ctx = newCairoContext(4, 3)
      check ctx.width == 4
      check ctx.height == 3
      check ctx.pixel(0, 0) == transparent
      check ctx.toImage().width == 4

    test "fills at integer coordinates are exact":
      var ctx = newCairoContext(10, 10)
      ctx.fill(rect(2, 2, 6, 6), red)
      check ctx.pixel(3, 3) == red
      check ctx.pixel(5, 5) == red
      check ctx.pixel(1, 1) == transparent
      check ctx.pixel(6, 6) == transparent

    test "clear replaces the whole target":
      var ctx = newCairoContext(10, 10)
      ctx.clear(red)
      ctx.withClip(rect(0, 0, 2, 2)):
        ctx.withTransform(scale(0.1)):
          ctx.clear(blue)
      check ctx.pixel(8, 8) == blue
      ctx.clear(transparent)
      check ctx.pixel(8, 8) == transparent

    test "clips are intersected and restored":
      var ctx = newCairoContext(10, 10)
      ctx.withClip(rect(0, 0, 6, 6)):
        ctx.withClip(rect(3, 3, 10, 10)):
          ctx.fill(rect(0, 0, 10, 10), red)
      check ctx.pixel(4, 4) == red
      check ctx.pixel(1, 1) == transparent
      check ctx.pixel(8, 8) == transparent
      ctx.fill(rect(0, 0, 10, 10), blue)
      check ctx.pixel(8, 8) == blue

    test "save and restore cover the transform":
      var ctx = newCairoContext(10, 10)
      ctx.withTransform(translate(5, 5)):
        check ctx.currentTransform == translate(5, 5)
        ctx.fill(rect(0, 0, 2, 2), red)
      check ctx.currentTransform.isIdentity
      check ctx.pixel(6, 6) == red
      check ctx.pixel(0, 0) == transparent
      ctx.restore() # nothing saved: a no-op
      ctx.fill(rect(0, 0, 2, 2), blue)
      check ctx.pixel(0, 0) == blue

    test "a singular transform draws nothing and does no harm":
      var ctx = newCairoContext(10, 10)
      ctx.withTransform(scale(0.0)):
        ctx.fill(rect(0, 0, 10, 10), red)
        ctx.stroke(rect(0, 0, 10, 10), red, 2.0)
        ctx.withClip(rect(0, 0, 10, 10)):
          ctx.fill(rect(0, 0, 10, 10), red)
      ctx.fill(rect(0, 0, 10, 10), blue)
      check ctx.finish().ok
      check ctx.pixel(5, 5) == blue

    test "a non-finite transform draws nothing and does no harm":
      var ctx = newCairoContext(10, 10)
      ctx.withTransform(affine(NaN, 0, 0, 1, 0, 0)):
        ctx.fill(rect(0, 0, 10, 10), red)
        ctx.withClip(rect(0, 0, 10, 10)):
          ctx.fill(rect(0, 0, 10, 10), red)
      ctx.withTransform(scale(1e300)):
        ctx.withTransform(scale(1e300)):
          ctx.fill(rect(0, 0, 10, 10), red)
      ctx.drawImage(newImage(2, 2), rect(0, 0, 1e-320, 1e-320), ipNearest)
      ctx.fill(rect(0, 0, 10, 10), blue)
      check ctx.finish().ok
      check ctx.pixel(5, 5) == blue

    test "gradients interpolate straight alpha":
      var ctx = newCairoContext(100, 1)
      ctx.fill(
        rect(0, 0, 100, 1),
        linearGradient(point(0, 0), point(100, 0), red.withAlpha(0.0), blue),
      )
      check ctx.pixel(50, 0).near(rgba(0.5, 0, 0.5, 0.5))

    test "degenerate gradients paint the last stop":
      var ctx = newCairoContext(4, 4)
      ctx.fill(rect(0, 0, 2, 4), linearGradient(point(1, 1), point(1, 1), red, blue))
      ctx.fill(rect(2, 0, 4, 4), radialGradient(point(3, 2), -1, red, green))
      check ctx.pixel(1, 1) == blue
      check ctx.pixel(3, 1) == green

    test "quadratic curves are drawn":
      var ctx = newCairoContext(20, 20)
      var path = newPath()
      path.moveTo 0, 20
      path.quadTo point(10, -20), point(20, 20)
      path.closePath()
      ctx.fill(path, black)
      check ctx.pixel(10, 15) == black
      check ctx.pixel(1, 1) == transparent

    test "dashes with negative entries are clamped":
      var ctx = newCairoContext(20, 4)
      ctx.stroke(
        line(0, 2, 20, 2), black, strokeStyle(width = 4, dashes = [-1.0, 5.0, 5.0])
      )
      check ctx.finish().ok
      check ctx.pixel(2, 2) == transparent
      check ctx.pixel(7, 2) == black

    test "images are drawn with the pixel order right":
      var ctx = newCairoContext(10, 10)
      var img = newImage(2, 1)
      img[0, 0] = rgb8(10, 20, 30)
      img[1, 0] = rgba8(200, 100, 0, 128)
      ctx.drawImage(img, rect(0, 0, 10, 10), ipNearest)
      check ctx.pixel(2, 5) == rgb8(10, 20, 30)
      check ctx.pixel(7, 5).near(rgba8(200, 100, 0, 128), 0.01)

    test "a wrapped cairo_t draws into the same surface":
      var owner = newCairoContext(10, 10)
      owner.translate(5, 5)
      var wrapped = newCairoContext(owner.cairoHandle)
      check wrapped.width == 10
      check wrapped.currentTransform.isIdentity
      wrapped.fill(rect(0, 0, 2, 2), red)
      check wrapped.finish().ok
      check owner.pixel(1, 1) == red
      check wrapped.toImage()[1, 1] == red

    test "a wrapped cairo_t keeps its matrix and save stack":
      var owner = newCairoContext(10, 10)
      owner.translate(5, 5)
      owner.fill(rect(0, 0, 1, 1), blue)
      block:
        # Drawing through `owner` must not leave its transform on the
        # cairo_t, or this context would take it as its base.
        var wrapped = newCairoContext(owner.cairoHandle)
        wrapped.fill(rect(0, 0, 2, 2), red)
        check owner.pixel(1, 1) == red
        # Left unrestored: destroying the context pops it.
        wrapped.save()
        wrapped.clip(rect(0, 0, 1, 1))
      owner.fill(rect(0, 0, 5, 5), green)
      check owner.pixel(8, 8) == green

    test "a failure is reported from finish":
      var ctx = newCairoContext(-1, 5)
      ctx.fill(rect(0, 0, 1, 1), red)
      let res = ctx.finish()
      check not res.ok
      check res.message.len > 0
      # Reading back a failed context gives nothing rather than crashing.
      check ctx.pixel(0, 0) == transparent
      check ctx.toImage().isEmpty

    test "pixels outside the target are transparent":
      var ctx = newCairoContext(4, 4)
      ctx.clear(red)
      check ctx.pixel(-1, 0) == transparent
      check ctx.pixel(0, 4) == transparent
      check ctx.pixel(4, 0) == transparent
      check ctx.pixel(3, 3) == red

    test "samples match the CPU goldens within tolerance":
      # Antialiasing and dash phases differ between renderers, so a few edge
      # pixels may differ by a lot. Whole shapes differing means a bug.
      for i, name in sampleNames:
        var ctx = newCairoContext(sampleWidth, sampleHeight)
        ctx.drawSample(i)
        check ctx.finish().ok
        let golden = readPng(goldenDir / &"{name}.png")
        let diff = compareImages(ctx.toImage(), golden, tolerance = 32)
        checkpoint(
          &"{name}: {diff.differingPixels} pixels differ, max channel diff {diff.maxChannelDiff}"
        )
        check not diff.sizeMismatch
        check diff.differingPixels <= sampleWidth * sampleHeight div 200
else:
  echo "tcairo: skipped, compile with -d:pollockCairo (nimble testcairo)"
