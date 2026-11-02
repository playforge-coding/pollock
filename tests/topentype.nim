## The OpenType engine's internals, for the parts the test font doesn't
## exercise: the module is included, not imported, so its private procs are
## in reach.

import std/[tables, unittest]

include pollock/engines/opentype

func be16(v: int): seq[uint8] =
  @[uint8(v shr 8 and 0xFF), uint8(v and 0xFF)]

func be32(v: int): seq[uint8] =
  @[
    uint8(v shr 24 and 0xFF),
    uint8(v shr 16 and 0xFF),
    uint8(v shr 8 and 0xFF),
    uint8(v and 0xFF),
  ]

func tagBytes(tag: string): seq[uint8] =
  for c in tag:
    result.add uint8(ord(c))

func squareGlyph(): seq[uint8] =
  ## A simple glyph: a 10 unit square of four on-curve points.
  result = be16(1) & be16(0) & be16(0) & be16(10) & be16(10) # one contour, box
  result.add be16(3) & be16(0) # its last point, no instructions
  result.add @[uint8(1), 1, 1, 1] # on-curve, with 16-bit deltas
  result.add be16(0) & be16(10) & be16(0) & be16((-10) and 0xFFFF)
  result.add be16(0) & be16(0) & be16(10) & be16(0)

func repeatedComponent(component, count: int): seq[uint8] =
  ## A composite glyph of `count` copies of `component`, all at the origin.
  result = be16(0xFFFF) & be16(0) & be16(0) & be16(0) & be16(0)
  for i in 0 ..< count:
    let more = if i + 1 < count: 0x20 else: 0 # MORE_COMPONENTS
    result.add be16(2 or more) & be16(component) & @[uint8(0), 0]

proc glyfFont(glyphs: seq[seq[uint8]]): ParsedFont =
  ## A font of just these TrueType glyphs, in `glyf` order.
  result = ParsedFont(numGlyphs: glyphs.len)
  for g in glyphs:
    result.loca.add result.data.len
    result.data.add g
  result.loca.add result.data.len
  result.glyf = (0, result.data.len)

suite "opentype internals":
  test "a format 12 character map":
    # A cmap with one Unicode full-repertoire subtable of two groups.
    var cmap: seq[uint8]
    cmap.add be16(0) & be16(1) # version, one encoding record
    cmap.add be16(3) & be16(10) & be32(12) # Windows, full Unicode, at 12
    cmap.add be16(12) & be16(0) & be32(16 + 2 * 12) & be32(0) & be32(2)
    cmap.add be32(0x41) & be32(0x43) & be32(5) # A, B, C to 5, 6, 7
    cmap.add be32(0x1F600) & be32(0x1F600) & be32(9)
    let f = ParsedFont(data: cmap, tables: {"cmap": (0, cmap.len)}.toTable)
    f.readCmap()
    check f.glyphFor(0x41) == GlyphId(5)
    check f.glyphFor(0x43) == GlyphId(7)
    check f.glyphFor(0x1F600) == GlyphId(9)
    check f.glyphFor(0x44) == notdef

  test "a format 4 character map":
    # Three segments: A to C through a delta, a and b through the glyph
    # array, and the closing 0xFFFF one.
    var sub: seq[uint8]
    sub.add be16(4) & be16(0) & be16(0) & be16(6) & be16(0) & be16(0) & be16(0)
    sub.add be16(0x43) & be16(0x62) & be16(0xFFFF) # end codes
    sub.add be16(0) # reserved
    sub.add be16(0x41) & be16(0x61) & be16(0xFFFF) # start codes
    sub.add be16((5 - 0x41) and 0xFFFF) & be16(0) & be16(1) # deltas
    sub.add be16(0) & be16(4) & be16(0) # range offsets: the second points past them
    sub.add be16(20) & be16(0) # the glyph array: a to 20, b to nothing
    var cmap = be16(0) & be16(1) & be16(3) & be16(1) & be32(12) & sub
    let f = ParsedFont(data: cmap, tables: {"cmap": (0, cmap.len)}.toTable)
    f.readCmap()
    check f.glyphFor(0x41) == GlyphId(5)
    check f.glyphFor(0x43) == GlyphId(7)
    check f.glyphFor(0x61) == GlyphId(20)
    check f.glyphFor(0x62) == notdef
    check f.glyphFor(0x44) == notdef
    check f.glyphFor(0x60) == notdef
    check f.glyphFor(0xFFFF) == notdef
    check f.glyphFor(0x1F600) == notdef

  test "overlapping character map groups cost nothing up front":
    # Two thousand groups that each claim every code point. The groups are
    # looked up as they are, not expanded into a table of a billion entries.
    var cmap = be16(0) & be16(1) & be16(3) & be16(10) & be32(12)
    cmap.add be16(12) & be16(0) & be32(16 + 2000 * 12) & be32(0) & be32(2000)
    for i in 0 ..< 2000:
      cmap.add be32(0) & be32(0x10FFFF) & be32(1)
    let f = ParsedFont(data: cmap, tables: {"cmap": (0, cmap.len)}.toTable)
    f.readCmap()
    check f.glyphFor(0x41) != notdef

  test "truncated data raises FontError, never a defect":
    let f = ParsedFont(data: @[uint8(0), 1, 0], tables: {"cmap": (0, 3)}.toTable)
    expect FontError:
      f.readCmap()
    expect FontError:
      discard f.data.u32(1)
    expect FontError:
      discard f.data.tag(0)

  test "huge offsets and lengths raise FontError on every target":
    # Their sum overflows a 32-bit int, which is what `int` is on JavaScript.
    let data = newSeq[uint8](16)
    expect FontError:
      data.check(0x7FFFFFF0, 0x7FFFFFF0)
    expect FontError:
      data.checkArray(0, 0x7FFFFFF0, 0x7FFFFFF0)
    expect FontError:
      discard @[uint8(0x80), 0, 0, 0, 0, 0, 0, 0].u32(0)
    expect FontError:
      discard (be32(0x7FFFFFF0) & be32(0)).offset32(0)
    check (be32(8) & be32(0)).offset32(0) == 8

  test "dict operands":
    # 28 (int16), a one-byte number, a real, 29 (int32, negative here), and
    # operator 17 (CharStrings).
    let dict =
      @[uint8(28), 0x01, 0x00, 139 + 5, 30, 0x1a, 0x5f, 29, 0xFF, 0xFF, 0xFF, 0xFE, 17]
    let parsed = readDict(dict, 0, dict.len)
    check parsed[17] == @[256.0, 5.0, 1.5, -2.0]

  test "fixed-point charstring operands are signed":
    # rmoveto -0.5 10.5, both as 16.16 numbers, then endchar.
    let cs = @[uint8(255), 0xFF, 0xFF, 0x80, 0x00, 255, 0x00, 0x0A, 0x80, 0x00, 21, 14]
    let f = ParsedFont(data: cs)
    f.cff.charStrings = @[(0, cs.len)]
    check f.cffOutline(0).elements[0] == moveTo(point(-0.5, 10.5))

  test "endchar in a nested subroutine ends the glyph":
    # The charstring calls subroutine 0, which calls subroutine 1, which
    # ends the glyph; the line after the first call must not be drawn.
    let inner = @[uint8(14)] # endchar
    let outer = @[uint8(139 - 106), 29] # callgsubr 1
    var cs = @[uint8(139 + 10), 139 + 10, 21] # rmoveto 10 10
    cs.add @[uint8(139 - 107), 29] # callgsubr 0
    cs.add @[uint8(139 + 50), 139 + 0, 5, 14] # rlineto 50 0, endchar
    let f = ParsedFont(data: inner & outer & cs)
    f.cff.globalSubrs = @[(1, outer.len), (0, inner.len)]
    f.cff.charStrings = @[(1 + outer.len, cs.len)]
    let path = f.cffOutline(0)
    check path.elements == @[moveTo(point(10, 10)), closePath()]

  test "a contour of only off-curve points":
    # Each point is a control point, with the on-curve points implied
    # halfway between them, starting from between the last and the first.
    var path: BezPath
    path.addContour [
      TtPoint(x: 0, y: 0),
      TtPoint(x: 10, y: 0),
      TtPoint(x: 10, y: 10),
      TtPoint(x: 0, y: 10),
    ]
    check path.elements ==
      @[
        moveTo(point(0, 5)),
        quadTo(point(0, 0), point(5, 0)),
        quadTo(point(10, 0), point(10, 5)),
        quadTo(point(10, 10), point(5, 10)),
        quadTo(point(0, 10), point(0, 5)),
        closePath(),
      ]

  test "composite glyphs with byte offsets, negative ones too":
    # Glyph 1 places the square at (-5, -3) with one-byte offsets
    # (ARG_1_AND_2_ARE_WORDS clear).
    var composite = be16(0xFFFF) & be16(0) & be16(0) & be16(0) & be16(0)
    composite.add be16(2) & be16(0) & @[uint8(0xFB), 0xFD] # XY values, glyph 0
    let f = glyfFont(@[squareGlyph(), composite])
    check f.glyfOutline(1).boundingBox == rect(-5, -3, 5, 7)

  test "composites of composites are limited, not exponential":
    # Each glyph repeats the one before it twenty times, eight levels deep:
    # 20^8 squares if drawn out. Two levels draw; eight run out of budget.
    var glyphs = @[squareGlyph()]
    for level in 1 .. 8:
      glyphs.add repeatedComponent(level - 1, 20)
    let f = glyfFont(glyphs)
    check f.glyfOutline(2).elements.len == 400 * f.glyfOutline(0).elements.len
    expect FontError:
      discard f.glyfOutline(8)

  test "contour ends out of order raise FontError, never a defect":
    # Two contours ending at points 10 and 5: the first would reach past
    # the six points the last one implies.
    var glyph = be16(2) & be16(0) & be16(0) & be16(0) & be16(0)
    glyph.add be16(10) & be16(5) & be16(0)
    glyph.add newSeq[uint8](40)
    let f = glyfFont(@[glyph])
    expect FontError:
      discard f.glyfOutline(0)

  test "class kerning counts have to fit in the data":
    # Class pair adjustment claiming 65535 by 65535 classes of x advances
    # in a few bytes: refused before allocating them.
    var sub = be16(2) & be16(16) & be16(4) & be16(0) & be16(20) & be16(20)
    sub.add be16(0xFFFF) & be16(0xFFFF)
    sub.add be16(1) & be16(0) # coverage: no glyphs
    sub.add be16(1) & be16(0) & be16(0) # class definition: no glyphs
    expect FontError:
      discard sub.readPairPos(0)

  test "pair sets shared by many glyphs are read once, in place":
    # 30000 first glyphs all point at one pair set of 65535 second glyphs.
    # Expanded per first glyph, that would be two billion entries.
    const sets = 30000
    const coverage = 10 + sets * 2
    const pairSet = coverage + 10
    var sub = be16(1) & be16(coverage) & be16(4) & be16(0) & be16(sets)
    for i in 0 ..< sets:
      sub.add be16(pairSet)
    sub.add be16(2) & be16(1) & be16(0) & be16(sets - 1) & be16(0) # one range
    sub.add be16(0xFFFF)
    for second in 0 ..< 0xFFFF:
      sub.add be16(second) & be16((-(second mod 100)) and 0xFFFF)
    let f = ParsedFont(data: sub)
    f.kerning = @[@[sub.readPairPos(0)]]
    check f.kerning(GlyphId(7), GlyphId(1250)) == -50
    check f.kerning(GlyphId(sets - 1), GlyphId(0xFFFE)) == -34
    check f.kerning(GlyphId(sets), GlyphId(1250)) == 0

  test "kerning lookups listed many times are limited":
    # 8000 kern features, all the same table of 8000 lookups: 64 million
    # entries to go through, far more than the font's size allows.
    const features = 8000
    const lookups = 8000
    const scriptList = 10
    const langSys = scriptList + 12
    const lookupList = langSys + 6 + features * 2
    const featureList = lookupList + 10
    var gpos = be16(1) & be16(0) & be16(scriptList) & be16(featureList)
    gpos.add be16(lookupList)
    gpos.add be16(1) & tagBytes("DFLT") & be16(8) # one script, at 8
    gpos.add be16(4) & be16(0) # its default language system at 4, no others
    gpos.add be16(0) & be16(0xFFFF) & be16(features) # no required feature
    for i in 0 ..< features:
      gpos.add be16(i)
    gpos.add be16(1) & be16(4) # one lookup, at 4
    gpos.add be16(2) & be16(0) & be16(0) # pair adjustment, no subtables
    gpos.add be16(features)
    for i in 0 ..< features:
      gpos.add tagBytes("kern") & be16(2 + features * 6)
    gpos.add be16(0) & be16(lookups) # no parameters
    for i in 0 ..< lookups:
      gpos.add be16(0)
    let f = ParsedFont(data: gpos, tables: {"GPOS": (0, gpos.len)}.toTable)
    expect FontError:
      f.readKerning()

  test "subroutines that call subroutines are limited, not exponential":
    # Subroutine k calls subroutine k + 1 twenty times, and the last draws
    # a line: 20^8 lines from the first. Two levels draw; eight run out.
    var data: seq[uint8]
    var subrs: seq[(int, int)]
    for level in 0 ..< 8:
      var subr: seq[uint8]
      for i in 0 ..< 20:
        subr.add @[uint8(32 + level + 1), 29] # callgsubr level + 1 (bias 107)
      subr.add 11 # return
      subrs.add (data.len, subr.len)
      data.add subr
    let line = @[uint8(139 + 1), 139 + 0, 5, 11] # rlineto 1 0, return
    subrs.add (data.len, line.len)
    data.add line
    var charStrings: seq[(int, int)]
    for first in [6, 0]:
      let cs = @[uint8(139), 139, 21, uint8(32 + first), 29, 14] # rmoveto 0 0
      charStrings.add (data.len, cs.len)
      data.add cs
    let f = ParsedFont(data: data)
    f.cff.globalSubrs = subrs
    f.cff.charStrings = charStrings
    check f.cffOutline(0).elements.len == 1 + 400 + 1
    expect FontError:
      discard f.cffOutline(1)

  test "charstrings draw with subroutines and flex":
    # A square drawn by a global subroutine called from the charstring,
    # then a flex curve, with the width as a leading argument.
    var subr: seq[uint8]
    subr.add @[uint8(139 + 100), 139 + 0, 5] # rlineto 100 0
    subr.add @[uint8(139 + 0), 139 + 100, 5] # rlineto 0 100
    subr.add @[uint8(139 - 100), 139 + 0, 5] # rlineto -100 0
    subr.add 11 # return
    var cs: seq[uint8]
    cs.add @[uint8(139 + 50), 139 + 10, 139 + 10, 21] # width 50, rmoveto 10 10
    cs.add @[uint8(139 - 107), 29] # callgsubr 0 (bias 107)
    cs.add @[uint8(139 + 20), 139 + 20, 139 + 20, 139 + 20, 139 + 20, 139 + 20]
    cs.add @[uint8(139 + 20), 139 - 20, 139 + 20, 139 - 20, 139 + 20, 139 - 20]
    cs.add @[uint8(139 + 50), 12, 35] # flex with fd 50
    cs.add 14 # endchar
    var data = subr & cs
    let f = ParsedFont(data: data)
    f.cff.globalSubrs = @[(0, subr.len)]
    f.cff.charStrings = @[(subr.len, cs.len)]
    let path = f.cffOutline(0)
    check path.elements[0] == moveTo(point(10, 10))
    check path.elements[1] == lineTo(point(110, 10))
    check path.elements[2] == lineTo(point(110, 110))
    check path.elements[3] == lineTo(point(10, 110))
    check path.elements[4].kind == peCubicTo
    check path.elements[5].kind == peCubicTo
    check path.elements[5].cubicEnd == point(130, 110)
    check path.elements[^1].kind == peClosePath
