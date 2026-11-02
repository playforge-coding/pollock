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
    # Glyph 0 is a 10 unit square; glyph 1 places it at (-5, -3) with
    # one-byte offsets (ARG_1_AND_2_ARE_WORDS clear).
    var square = be16(1) & be16(0) & be16(0) & be16(10) & be16(10) # one contour
    square.add be16(3) & be16(0) # its last point, no instructions
    square.add @[uint8(1), 1, 1, 1] # four on-curve points with 16-bit deltas
    square.add be16(0) & be16(10) & be16(0) & be16((-10) and 0xFFFF)
    square.add be16(0) & be16(0) & be16(10) & be16(0)
    var composite = be16(0xFFFF) & be16(0) & be16(0) & be16(0) & be16(0)
    composite.add be16(2) & be16(0) & @[uint8(0xFB), 0xFD] # XY values, glyph 0
    let f = ParsedFont(data: square & composite, numGlyphs: 2)
    f.loca = @[0, square.len, square.len + composite.len]
    f.glyf = (0, f.data.len)
    check f.glyfOutline(1, 0).boundingBox == rect(-5, -3, 5, 7)

  test "contour ends out of order raise FontError, never a defect":
    # Two contours ending at points 10 and 5: the first would reach past
    # the six points the last one implies.
    var glyph = be16(2) & be16(0) & be16(0) & be16(0) & be16(0)
    glyph.add be16(10) & be16(5) & be16(0)
    glyph.add newSeq[uint8](40)
    let f = ParsedFont(data: glyph, numGlyphs: 1, loca: @[0, glyph.len])
    f.glyf = (0, glyph.len)
    expect FontError:
      discard f.glyfOutline(0, 0)

  test "class kerning counts have to fit in the data":
    # Class pair adjustment claiming 65535 by 65535 classes of x advances
    # in a few bytes: refused before allocating them.
    var sub = be16(2) & be16(16) & be16(4) & be16(0) & be16(20) & be16(20)
    sub.add be16(0xFFFF) & be16(0xFFFF)
    sub.add be16(1) & be16(0) # coverage: no glyphs
    sub.add be16(1) & be16(0) & be16(0) # class definition: no glyphs
    expect FontError:
      discard sub.readPairPos(0)

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
