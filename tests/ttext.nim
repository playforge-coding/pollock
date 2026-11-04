## The text API and the pure Nim engine, checked with Source Sans 3 in both
## its TrueType and its CFF form (see `fontdata`; `nimble fonts` downloads
## them). The text scene has goldens like the sample scenes; `nimble
## goldens` rewrites them.

import std/[math, strutils, tables, unicode, unittest]
import pollock/[draw, recording, samples, testing]
import pollock/backends/[cpu, svg]
import ./fontdata

when not defined(js):
  import std/[os, strformat]
  import pollock/png

  const
    updateGoldens = defined(pollockUpdateGoldens)
    goldenDir = currentSourcePath().parentDir / "golden"

let
  trueType = newFont(trueTypeData)
  cff = newFont(cffData)
  fonts = [("TrueType", trueType), ("CFF", cff)]
  engine = defaultTextEngine()

type SquareEngine = object ## Draws every glyph as the same square.

proc layout(e: SquareEngine, text: string, style: TextStyle): TextLayout =
  discard

proc glyphDrawing(e: SquareEngine, font: Font, glyph: GlyphId): GlyphDrawing =
  GlyphDrawing(kind: gkOutline, path: rect(0, -1, 1, 0).toPath)

func near(a, b: float64, tolerance = 0.01): bool =
  abs(a - b) <= tolerance

func near(a, b: Rect, tolerance = 0.01): bool =
  near(a.x0, b.x0, tolerance) and near(a.y0, b.y0, tolerance) and
    near(a.x1, b.x1, tolerance) and near(a.y1, b.y1, tolerance)

func subpaths(path: BezPath): int =
  for el in path.elements:
    if el.kind == peMoveTo:
      inc result

proc width(font: Font, text: string, size = 100.0): float64 =
  engine.layout(text, textStyle(font, size)).width

suite "text engine":
  test "characters map to glyphs":
    for (name, font) in fonts:
      checkpoint(name)
      check engine.glyphFor(font, Rune('A')) != notdef
      check engine.glyphFor(font, Rune('A')) != engine.glyphFor(font, Rune('B'))
      check engine.glyphFor(font, Rune(0x1F600)) == notdef
      check engine.glyphFor(font, "é".runeAt(0)) != notdef

  test "layout metrics come from the font":
    for (name, font) in fonts:
      checkpoint(name)
      let layout = engine.layout("Hello", textStyle(font, 32))
      # Source Sans 3: 1000 units per em, ascender 1000, descender -326, no
      # gap, and "Hello" is 2200 units wide (as HarfBuzz measures it).
      check near(layout.ascent, 32)
      check near(layout.descent, 326 / 1000 * 32)
      check layout.lineGap == 0
      check near(layout.height, 1326 / 1000 * 32)
      check near(layout.width, 2200 / 1000 * 32)
      check near(layout.bounds, rect(0, -layout.ascent, layout.width, layout.descent))
      check layout.runs.len == 1
      let run = layout.runs[0]
      check run.font == font
      check run.size == 32
      check run.paint == solid(black)
      check run.glyphs.len == 5
      check run.glyphs[0].pos == point(0, 0)
      for i in 1 ..< run.glyphs.len:
        check run.glyphs[i].pos.x > run.glyphs[i - 1].pos.x
        check run.glyphs[i].pos.y == 0
        check run.glyphs[i].cluster == i
      let empty = engine.layout("", textStyle(font, 32))
      check empty.runs.len == 0
      check empty.width == 0
      check near(empty.ascent, layout.ascent)

  test "clusters are byte offsets":
    let layout = engine.layout("Añejo", textStyle(trueType, 20))
    var clusters: seq[int]
    for g in layout.runs[0].glyphs:
      clusters.add g.cluster
    check clusters == @[0, 1, 3, 4, 5]

  test "advances add up, and the size scales them":
    for (name, font) in fonts:
      checkpoint(name)
      check near(font.width("HH"), 2 * font.width("H"), 0.01)
      check near(font.width("H", 50), font.width("H") / 2, 0.01)

  test "pairs are kerned through GPOS as HarfBuzz kerns them":
    # Widths in font units (the size is the em, 1000 units), measured with
    # HarfBuzz shaping with only the `kern` feature on. The font keeps its
    # kerning in one lookup of many subtables, a glyph-pair one first and
    # class ones after; only the first subtable that covers a pair counts,
    # which "x," checks (adding both gives 695).
    const expected = {
      "x,": 702.0,
      "AVATAR": 3129.0,
      "To.": 1251.0,
      "LT": 902.0,
      "Wave": 2233.0,
      "Yoyo": 1978.0,
      "kerning": 3164.0,
    }
    for (name, font) in fonts:
      checkpoint(name)
      for (text, units) in expected:
        checkpoint(text)
        check near(font.width(text, 1000), units)
      check font.width("To", 1000) < font.width("T", 1000) + font.width("o", 1000) - 50

  test "outlines in em units with the baseline at zero":
    for (name, font) in fonts:
      checkpoint(name)
      let a = engine.glyphDrawing(font, engine.glyphFor(font, Rune('A')))
      check a.kind == gkOutline
      check not a.path.isEmpty
      let box = a.path.boundingBox
      # The cap height is 0.656 em; y points down.
      check near(box.y0, -0.656, 0.002)
      check near(box.y1, 0, 0.005)
      check box.x0 >= 0 and box.x1 < 1
      check a.path.subpaths == 2
      let o = engine.glyphDrawing(font, engine.glyphFor(font, Rune('o')))
      check o.path.subpaths == 2
      check o.path.boundingBox.y1 > 0 # the overshoot below the baseline
      let space = engine.glyphDrawing(font, engine.glyphFor(font, Rune(' ')))
      check space.path.isEmpty
      check engine.glyphDrawing(font, GlyphId(60000)).path.isEmpty

  test "composite glyphs put their parts together":
    # In the TrueType font the accented letters are composites.
    let e = engine.glyphDrawing(trueType, engine.glyphFor(trueType, Rune('e')))
    let eacute =
      engine.glyphDrawing(trueType, engine.glyphFor(trueType, "é".runeAt(0)))
    check eacute.path.subpaths == e.path.subpaths + 1
    check eacute.path.boundingBox.y0 < e.path.boundingBox.y0 - 0.1
    check near(eacute.path.boundingBox.y1, e.path.boundingBox.y1)

  test "the two outline formats agree":
    for c in "HBgé".runes:
      checkpoint($c)
      let t = engine.glyphDrawing(trueType, engine.glyphFor(trueType, c))
      let o = engine.glyphDrawing(cff, engine.glyphFor(cff, c))
      check near(t.path.boundingBox, o.path.boundingBox, 0.01)
      # The formats wind their contours the opposite way, so the signs
      # differ; both fill the same under the nonzero rule. The quadratic
      # outlines are a conversion of the cubic ones, so the areas differ a
      # little (1.5% for the g).
      check near(abs(t.path.area(0.0001)), abs(o.path.area(0.0001)), 0.004)

  test "drawings are cached on the font":
    let font = newFont(trueTypeData)
    check font.drawings.len == 0
    let id = engine.glyphFor(font, Rune('x'))
    discard engine.cachedDrawing(font, id)
    discard engine.cachedDrawing(font, id)
    check font.drawings.len == 1
    check engine.cachedDrawing(font, id) == engine.cachedDrawing(font, id)
    var ctx = newCpuContext(40, 40)
    ctx.drawText("xx", textStyle(font, 20), point(0, 30))
    check font.drawings.len == 1

  test "each engine type keeps its own drawings of a font":
    let font = newFont(trueTypeData)
    let id = engine.glyphFor(font, Rune('x'))
    let outline = engine.cachedDrawing(font, id)
    let square = SquareEngine().cachedDrawing(font, id)
    check outline.path != square.path
    check square.path == SquareEngine().glyphDrawing(font, id).path
    check engine.cachedDrawing(font, id) == outline
    check font.drawings.len == 2

  test "a font the engine can't read raises from layout and draws nothing":
    let bad = newFont("this is not a font")
    expect FontError:
      discard engine.layout("hi", textStyle(bad, 12))
    let cut = newFont(trueTypeData[0 ..< 2000])
    expect FontError:
      discard engine.glyphFor(cut, Rune('A'))
    check engine.glyphDrawing(bad, GlyphId(3)).path.isEmpty
    var ctx = newCpuContext(20, 20)
    let run = GlyphRun(font: bad, size: 12, glyphs: @[Glyph(id: GlyphId(3))])
    ctx.drawGlyphs(run, solid(black))
    ctx.drawGlyphs(GlyphRun(size: 12, glyphs: @[Glyph(id: GlyphId(3))]), solid(black))
    check ctx.finish().ok
    check ctx.pixel(10, 10).a == 0

suite "drawing text":
  test "drawText puts ink where the layout says":
    var ctx = newCpuContext(120, 60)
    let layout = engine.layout("Hg", textStyle(trueType, 40))
    ctx.drawText(layout, point(10, 45))
    var inked = rect(1e9, 1e9, -1e9, -1e9)
    for y in 0 ..< 60:
      for x in 0 ..< 120:
        if ctx.pixel(x, y).a > 0.5:
          inked = inked.union(point(x.float64, y.float64))
    check inked.x0 >= 10 and inked.x0 < 16
    check inked.x1 < 10 + layout.width
    check inked.y0 > 45 - layout.ascent and inked.y0 < 20
    check inked.y1 > 45 # the descender of g
    check inked.y1 < 45 + layout.descent + 1

  test "the paint is in user space, not per glyph":
    var ctx = newCpuContext(200, 40)
    let width = engine.layout("IIIIIIII", textStyle(trueType, 40)).width
    ctx.drawText(
      "IIIIIIII",
      textStyle(trueType, 40, linearGradient(point(0, 0), point(width, 0), red, blue)),
      point(0, 36),
    )
    var first, last: Color
    var seen = false
    for x in 0 ..< 200:
      let c = ctx.pixel(x, 20)
      if c.a > 0.9:
        if not seen:
          first = c
          seen = true
        last = c
    check seen
    check first.r > 0.8 and last.b > 0.5

  test "a transform applies to the glyph positions":
    var a = newCpuContext(80, 40)
    a.withTransform(scale(2)):
      a.drawText("H", textStyle(trueType, 15), point(5, 15))
    var b = newCpuContext(80, 40)
    b.drawText("H", textStyle(trueType, 30), point(10, 30))
    check compareImages(a.toImage(), b.toImage(), tolerance = 8).differingPixels == 0

  test "the svg backend writes one path per glyph":
    var ctx = newSvgContext(100, 40)
    ctx.drawText("Hi there", textStyle(trueType, 20), point(0, 20))
    check ctx.toSvg().count("<path d=\"M") == 7

  test "the recording backend records runs":
    var ctx = newRecordingContext()
    let layout = engine.layout("ab", textStyle(trueType, 10, red))
    ctx.drawText(layout, point(5, 5))
    check ctx.kinds == @[ckDrawGlyphs]
    check ctx.commands[0].paint == solid(red)
    check ctx.commands[0].run.glyphs.len == 2
    check ctx.commands[0].run.glyphs[0].pos == point(5, 5)

  test "every backend draws the text scene":
    var cpu = newCpuContext(sampleWidth, sampleHeight)
    cpu.drawTextSample(trueType, cff)
    check cpu.finish().ok
    var svg = newSvgContext(sampleWidth.float64, sampleHeight.float64)
    svg.drawTextSample(trueType, cff)
    check svg.toSvg().len > 1000

  when not defined(js):
    test "text goldens":
      var cpu = newCpuContext(sampleWidth, sampleHeight)
      cpu.drawTextSample(trueType, cff)
      let img = cpu.toImage()
      let pngPath = goldenDir / "cpu" / "text.png"
      var svg = newSvgContext(sampleWidth.float64, sampleHeight.float64)
      svg.drawTextSample(trueType, cff)
      let doc = svg.toSvg()
      let svgPath = goldenDir / "svg" / "text.svg"
      if updateGoldens:
        writePng(img, pngPath)
        echo "wrote ", pngPath
        writeFile(svgPath, doc)
        echo "wrote ", svgPath
      if not fileExists(pngPath) or not fileExists(svgPath):
        fail()
      else:
        let diff = compareImages(img, readPng(pngPath))
        checkpoint(
          &"text: {diff.differingPixels} pixels differ, max channel diff {diff.maxChannelDiff}"
        )
        check diff.matches
        check doc == readFile(svgPath)
