import std/[strutils, unittest]
import pollock/draw
import pollock/backends/svg

proc count(s, sub: string): int =
  strutils.count(s, sub)

suite "svg backend":
  test "document shape":
    var ctx = newSvgContext(100, 50)
    ctx.clear(white)
    ctx.fill(rect(10, 10, 50, 50), red)
    let doc = ctx.toSvg
    check doc.startsWith(
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\" viewBox=\"0 0 100 50\">"
    )
    check doc.endsWith("</svg>\n")
    check "<rect width=\"100\" height=\"50\" fill=\"#ffffff\"/>" in doc
    check "<path d=\"M10 10 L50 10 L50 50 L10 50 Z\" fill=\"#ff0000\"/>" in doc
    check "<defs>" notin doc

  test "numbers are short":
    var ctx = newSvgContext(10, 10)
    ctx.fill(rect(0.5, 1.25, 2.0001, 3.14159), black)
    check "M0.5 1.25 L2.0001 1.25 L2.0001 3.14159" in ctx.toSvg
    var round = newSvgContext(10, 10)
    round.fill(rect(0, 0, 1.0 / 3, 1234.56789), black)
    check "L0.3333333 0 L0.3333333 1234.568" in round.toSvg

  test "small transform coefficients keep their precision":
    var ctx = newSvgContext(40, 40)
    ctx.scale(0.0004)
    ctx.fill(rect(0, 0, 100000, 100000), black)
    check "transform=\"matrix(0.0004 0 0 0.0004 0 0)\"" in ctx.toSvg
    var rot = newSvgContext(10, 10)
    rot.rotate(0.1)
    rot.fill(rect(0, 0, 1, 1), black)
    check "matrix(0.9950042 0.09983342 -0.09983342 0.9950042 0 0)" in rot.toSvg

  test "a miter limit below 1 bevels":
    var ctx = newSvgContext(10, 10)
    ctx.stroke(line(0, 0, 10, 10), black, strokeStyle(miterLimit = 0.5))
    ctx.stroke(line(0, 0, 10, 10), black, strokeStyle(miterLimit = 10))
    let doc = ctx.toSvg
    check "stroke-miterlimit=\"0.5\"" notin doc
    check "stroke-linejoin=\"bevel\"" in doc
    check "stroke-miterlimit=\"10\"" in doc

  test "a negative radial radius is written as zero":
    var ctx = newSvgContext(10, 10)
    ctx.fill(rect(0, 0, 10, 10), radialGradient(point(5, 5), -3, red, blue))
    check " r=\"0\"" in ctx.toSvg

  test "alpha and fill rule":
    var ctx = newSvgContext(10, 10)
    ctx.fill(rect(0, 0, 1, 1), red.withAlpha(0.5), frEvenOdd)
    let doc = ctx.toSvg
    check "fill=\"#ff0000\" fill-opacity=\"0.5\" fill-rule=\"evenodd\"" in doc

  test "transform attribute":
    var ctx = newSvgContext(10, 10)
    ctx.withTransform(translate(5, 6) * scale(2)):
      ctx.fill(rect(0, 0, 1, 1), black)
    ctx.fill(rect(0, 0, 1, 1), black)
    let doc = ctx.toSvg
    check "transform=\"matrix(2 0 0 2 5 6)\"" in doc
    check doc.count("transform=") == 1

  test "strokes":
    var ctx = newSvgContext(10, 10)
    ctx.stroke(
      line(0, 0, 10, 10),
      blue,
      strokeStyle(
        width = 2, cap = lcRound, join = ljBevel, dashes = [4.0, 2.0], dashOffset = 1
      ),
    )
    ctx.stroke(line(0, 0, 10, 10), blue, 1.0)
    let doc = ctx.toSvg
    check "fill=\"none\" stroke=\"#0000ff\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"bevel\" stroke-dasharray=\"4 2\" stroke-dashoffset=\"1\"" in
      doc
    check "stroke-width=\"1\"/>" in doc

  test "gradients go in defs":
    var ctx = newSvgContext(10, 10)
    ctx.fill(
      rect(0, 0, 10, 10),
      linearGradient(point(0, 0), point(10, 0), red, blue.withAlpha(0.5), exReflect),
    )
    ctx.fill(circle(5, 5, 5), radialGradient(point(5, 5), 5, white, black))
    let doc = ctx.toSvg
    check "<linearGradient id=\"g1\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"10\" y2=\"0\" spreadMethod=\"reflect\">" in
      doc
    check "<stop offset=\"1\" stop-color=\"#0000ff\" stop-opacity=\"0.5\"/>" in doc
    check "<radialGradient id=\"g2\" gradientUnits=\"userSpaceOnUse\" cx=\"5\" cy=\"5\" r=\"5\" spreadMethod=\"pad\">" in
      doc
    check "fill=\"url(#g1)\"" in doc
    check "fill=\"url(#g2)\"" in doc

  test "clips open groups that restore closes":
    var ctx = newSvgContext(10, 10)
    ctx.withClip(circle(5, 5, 5)):
      ctx.withTransform(scale(2)):
        ctx.withClip(rect(0, 0, 2, 2)):
          ctx.fill(rect(0, 0, 1, 1), black)
      ctx.fill(rect(0, 0, 1, 1), black)
    ctx.fill(rect(0, 0, 1, 1), black)
    let doc = ctx.toSvg
    check doc.count("<g clip-path=") == 2
    check doc.count("</g>") == 2
    check "<clipPath id=\"c1\">" in doc
    check "<clipPath id=\"c2\"><path d=\"M0 0 L2 0 L2 2 L0 2 Z\" transform=\"matrix(2 0 0 2 0 0)\"/></clipPath>" in
      doc
    # The last fill is outside both groups.
    check doc.find("</g>\n  </g>") < doc.rfind("<path")

  test "unbalanced clips are closed in the output":
    var ctx = newSvgContext(10, 10)
    ctx.clip(circle(5, 5, 5))
    let doc = ctx.toSvg
    check doc.count("<g clip-path=") == 1
    check doc.count("</g>") == 1

  test "images are embedded":
    var ctx = newSvgContext(10, 10)
    var img = newImage(1, 1)
    img[0, 0] = red
    ctx.drawImage(img, rect(1, 2, 3, 4), ipNearest)
    let doc = ctx.toSvg
    check "<image x=\"1\" y=\"2\" width=\"2\" height=\"2\" preserveAspectRatio=\"none\" style=\"image-rendering:pixelated\" href=\"data:image/png;base64,iVBORw0KGgo" in
      doc

  test "finish succeeds":
    var ctx = newSvgContext(1, 1)
    check ctx.finish().ok
