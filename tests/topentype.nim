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

  test "truncated data raises FontError, never a defect":
    let f = ParsedFont(data: @[uint8(0), 1, 0], tables: {"cmap": (0, 3)}.toTable)
    expect FontError:
      f.readCmap()
    expect FontError:
      discard f.data.u32(1)
    expect FontError:
      discard f.data.tag(0)

  test "dict operands":
    # 28 (int16), a one-byte number, a real, and operator 17 (CharStrings).
    let dict = @[uint8(28), 0x01, 0x00, 139 + 5, 30, 0x1a, 0x5f, 17]
    let parsed = readDict(dict, 0, dict.len)
    check parsed[17] == @[256.0, 5.0, 1.5]

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
