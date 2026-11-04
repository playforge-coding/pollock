## The pure Nim text engine: reads OpenType fonts and lays out text with no
## library behind it, so it runs on every target.
##
## What it reads: the table directory (and TrueType collections), `head`,
## `hhea`, `hmtx`, `maxp`, `cmap` (formats 4 and 12), TrueType outlines from
## `glyf` and `loca` (simple and composite glyphs) and CFF outlines (Type 2
## charstrings with local and global subroutines, not CID-keyed fonts or
## CFF2), and pair kerning from `GPOS` (pair adjustment lookups in both
## formats, also behind extension lookups). Layout is one line, left to
## right, one glyph per character with the kerning applied: no ligatures,
## no bidirectional text, no line breaking and no variations yet. The
## shaper will become a seam of its own when HarfBuzz joins as one.
##
## Parsing happens the first time a `Font` is used and is cached on it. A
## font the engine can't read makes `layout` raise `FontError`; its glyphs
## draw as nothing, so drawing never raises.

import std/[strutils, tables, unicode]
import ../[geometry, text]

export text

type
  OpenTypeEngine* = object ## Stateless so far: everything parsed lives on the fonts.

  Bytes = seq[uint8]

  Coverage = object ## A GPOS coverage table, searched in place.
    format: int ## 1 for a list of glyphs, 2 for ranges.
    at: int ## The list or the ranges.
    count: int

  ClassDef = object ## A GPOS class definition, searched in place.
    format: int ## 1 for a run of glyphs from `startGlyph`, 2 for ranges.
    at: int ## The classes or the ranges.
    count: int
    startGlyph: int

  PairLookup = object ## A pair adjustment subtable, read in place.
    coverage: Coverage ## The first glyphs it adjusts.
    valueFormat: int ## The first glyph's value format, which holds the x advance.
    recordSize: int ## Both value records together, in bytes.
    case classed: bool
    of false:
      base: int ## The subtable, which the pair set offsets count from.
      pairSets: int ## The pair set offsets, one per coverage index.
      setCount: int
    of true:
      class1, class2: ClassDef
      class1Count, class2Count: int
      records: int ## The `class1Count` by `class2Count` value records.

  CharMap = object
    ## Where the chosen `cmap` subtable's arrays are; looked up on demand.
    format: int ## 4 or 12; 0 before it is read.
    at: int ## The first array: the end codes (format 4) or the groups (format 12).
    count: int ## Segments or groups.
    limit: int ## Format 4: where the subtable, and so its glyph array, ends.

  CffFont = object
    charStrings: seq[(int, int)] ## Offset and length of each glyph's charstring.
    globalSubrs, localSubrs: seq[(int, int)]

  ParsedFont = ref object of RootObj
    data: Bytes
    tables: Table[string, (int, int)] ## Tag to offset and length.
    unitsPerEm: int
    ascender, descender, lineGap: int
    numGlyphs: int
    advances: seq[uint16]
    cmap: CharMap
    loca: seq[int] ## Glyph offsets into `glyf`, `numGlyphs + 1` of them; empty for CFF.
    glyf: (int, int)
    cff: CffFont
    hasCff: bool
    kerning: seq[seq[PairLookup]] ## The kern lookups, each a list of subtables.

proc defaultTextEngine*(): OpenTypeEngine =
  ## The engine the backends pair with by default.
  OpenTypeEngine()

# Reading big-endian fields with bounds checks that raise `FontError`

func check(data: Bytes, pos, size: int) =
  # Compared without adding, which could overflow `int` on JavaScript.
  if pos < 0 or size < 0 or pos > data.len or size > data.len - pos:
    raise newException(FontError, "font data ends early")

func checkArray(data: Bytes, pos, count, itemSize: int) =
  ## Checks that `count` items of `itemSize` bytes fit at `pos`, without
  ## computing their total size, which could overflow.
  data.check(pos, 0)
  if count < 0 or (itemSize > 0 and count > (data.len - pos) div itemSize):
    raise newException(FontError, "font data ends early")

func u8(data: Bytes, pos: int): int =
  data.check(pos, 1)
  int(data[pos])

func i8(data: Bytes, pos: int): int =
  let v = data.u8(pos)
  if v >= 0x80:
    v - 0x100
  else:
    v

func u16(data: Bytes, pos: int): int =
  data.check(pos, 2)
  int(data[pos]) shl 8 or int(data[pos + 1])

func i16(data: Bytes, pos: int): int =
  let v = data.u16(pos)
  if v >= 0x8000:
    v - 0x10000
  else:
    v

func u32(data: Bytes, pos: int): int =
  ## An unsigned 32-bit field as an `int`, which is 32 bits on JavaScript. No
  ## offset, length, count or code point in a font reaches 2^31, so a value
  ## that does raises `FontError` rather than coming out negative there.
  data.check(pos, 4)
  if data[pos] >= 0x80:
    raise newException(FontError, "font field out of range")
  int(data[pos]) shl 24 or int(data[pos + 1]) shl 16 or int(data[pos + 2]) shl 8 or
    int(data[pos + 3])

func offset32(data: Bytes, pos: int): int =
  ## A 32-bit offset, length or count, which can't exceed the file's size.
  ## Checking that keeps sums of two of them within `int` on every target.
  result = data.u32(pos)
  if result > data.len:
    raise newException(FontError, "font offset past the end of the data")

func fixed(data: Bytes, pos: int): float64 =
  ## A signed 16.16 fixed-point number.
  data.i16(pos).float64 + data.u16(pos + 2).float64 / 65536.0

func tag(data: Bytes, pos: int): string =
  data.check(pos, 4)
  result = newString(4)
  for i in 0 .. 3:
    result[i] = char(data[pos + i])

func f2dot14(data: Bytes, pos: int): float64 =
  data.i16(pos).float64 / 16384.0

# The table directory

proc readTables(f: ParsedFont, index: int) =
  var base = 0
  if f.data.tag(0) == "ttcf":
    let count = f.data.offset32(8)
    if index < 0 or index >= count:
      raise newException(FontError, "no face " & $index & " in the collection")
    base = f.data.offset32(12 + index * 4)
  if f.data.tag(base) notin ["\0\x01\0\0", "OTTO", "true"]:
    raise newException(FontError, "not an OpenType font")
  let numTables = f.data.u16(base + 4)
  for i in 0 ..< numTables:
    let rec = base + 12 + i * 16
    let tag = f.data.tag(rec)
    let offset = f.data.offset32(rec + 8)
    let length = f.data.offset32(rec + 12)
    f.data.check(offset, length)
    f.tables[tag] = (offset, length)

func table(f: ParsedFont, tag: string): int =
  if tag notin f.tables:
    raise newException(FontError, "font has no " & tag & " table")
  f.tables[tag][0]

# Metrics

proc readMetrics(f: ParsedFont) =
  let head = f.table("head")
  f.unitsPerEm = f.data.u16(head + 18)
  if f.unitsPerEm == 0:
    raise newException(FontError, "font has no em size")
  let hhea = f.table("hhea")
  f.ascender = f.data.i16(hhea + 4)
  f.descender = f.data.i16(hhea + 6)
  f.lineGap = f.data.i16(hhea + 8)
  let numberOfHMetrics = f.data.u16(hhea + 34)
  f.numGlyphs = f.data.u16(f.table("maxp") + 4)
  let hmtx = f.table("hmtx")
  f.advances = newSeq[uint16](numberOfHMetrics)
  for i in 0 ..< numberOfHMetrics:
    f.advances[i] = uint16(f.data.u16(hmtx + i * 4))

func advance(f: ParsedFont, glyph: GlyphId): int =
  # Glyphs past the last metric share it, as the spec says.
  if f.advances.len == 0:
    return 0
  int(f.advances[min(int(uint16(glyph)), f.advances.len - 1)])

# Character map

proc readCmapFormat4(f: ParsedFont, sub, available: int) =
  # Four arrays of `segCount` 16-bit values (end codes, start codes, deltas
  # and range offsets) with a reserved field after the first. The glyph array
  # follows them and ends with the subtable: at its length, unless that is
  # too small to hold the arrays or runs past the room it has.
  let segCountX2 = f.data.u16(sub + 6)
  f.data.check(sub + 14, segCountX2 * 4 + 2)
  let length = f.data.u16(sub + 2)
  let limit =
    if length >= 16 + segCountX2 * 4:
      min(sub + length, available)
    else:
      available
  f.cmap = CharMap(format: 4, at: sub + 14, count: segCountX2 div 2, limit: limit)

proc readCmapFormat12(f: ParsedFont, sub: int) =
  # Groups of start code, end code and start glyph, 32 bits each. Every field
  # is read once here, so the lookups that follow can't fail.
  let numGroups = f.data.offset32(sub + 12)
  f.data.checkArray(sub + 16, numGroups, 12)
  for i in 0 ..< numGroups * 3:
    discard f.data.u32(sub + 16 + i * 4)
  f.cmap = CharMap(format: 12, at: sub + 16, count: numGroups)

proc readCmap(f: ParsedFont) =
  let cmap = f.table("cmap")
  let numTables = f.data.u16(cmap + 2)
  # A Unicode full-repertoire subtable (format 12) beats a BMP one (format
  # 4); among those, any Unicode or Windows platform will do.
  var best = -1
  var bestScore = 0
  for i in 0 ..< numTables:
    let rec = cmap + 4 + i * 8
    let platform = f.data.u16(rec)
    let encoding = f.data.u16(rec + 2)
    let offset = cmap + f.data.offset32(rec + 4)
    let format = f.data.u16(offset)
    let unicode = platform == 0 or (platform == 3 and encoding in {1, 10})
    if not unicode:
      continue
    let score =
      case format
      of 12: 2
      of 4: 1
      else: 0
    if score > bestScore:
      best = offset
      bestScore = score
  if best < 0:
    raise newException(FontError, "font has no Unicode character map")
  if bestScore == 2:
    f.readCmapFormat12(best)
  else:
    # All the room it has: up to the next subtable or the end of the table.
    var available = cmap + f.tables["cmap"][1]
    for i in 0 ..< numTables:
      let offset = cmap + f.data.offset32(cmap + 4 + i * 8 + 4)
      if offset > best and offset < available:
        available = offset
    f.readCmapFormat4(best, available)

func glyphFor(f: ParsedFont, c: int): GlyphId =
  ## Looks the character up with a binary search, as the spec intends: the
  ## segments and groups are sorted. A table that isn't gives wrong glyphs,
  ## but never more work than that search.
  let m = f.cmap
  case m.format
  of 4:
    if c < 0 or c >= 0xFFFF:
      return notdef
    let ends = m.at
    let starts = ends + m.count * 2 + 2
    let deltas = starts + m.count * 2
    let rangeOffsets = deltas + m.count * 2
    # The first segment that ends at or after `c`.
    var lo = 0
    var hi = m.count
    while lo < hi:
      let mid = (lo + hi) div 2
      if f.data.u16(ends + mid * 2) < c:
        lo = mid + 1
      else:
        hi = mid
    if lo == m.count:
      return notdef
    let startCode = f.data.u16(starts + lo * 2)
    if c < startCode:
      return notdef
    let delta = f.data.u16(deltas + lo * 2)
    let rangeOffset = f.data.u16(rangeOffsets + lo * 2)
    var g: int
    if rangeOffset == 0:
      g = (c + delta) and 0xFFFF
    else:
      # An index into the glyph array that follows, which is only checked
      # here: an entry past the end of the subtable maps to nothing.
      let at = rangeOffsets + lo * 2 + rangeOffset + (c - startCode) * 2
      if at + 2 > m.limit:
        return notdef
      g = f.data.u16(at)
      if g != 0:
        g = (g + delta) and 0xFFFF
    GlyphId(g)
  of 12:
    if c < 0 or c > 0x10FFFF:
      return notdef
    # The last group that starts at or before `c`.
    var lo = 0
    var hi = m.count
    while lo < hi:
      let mid = (lo + hi) div 2
      if f.data.u32(m.at + mid * 12) <= c:
        lo = mid + 1
      else:
        hi = mid
    if lo == 0:
      return notdef
    let group = m.at + (lo - 1) * 12
    let startChar = f.data.u32(group)
    if c > f.data.u32(group + 4):
      return notdef
    let startGlyph = f.data.u32(group + 8)
    if startGlyph > 0xFFFF:
      return notdef
    let g = startGlyph + (c - startChar)
    if g > 0xFFFF:
      notdef
    else:
      GlyphId(g)
  else:
    notdef

# TrueType outlines

proc readLoca(f: ParsedFont) =
  let head = f.table("head")
  let longOffsets = f.data.i16(head + 50) != 0
  let loca = f.table("loca")
  f.loca = newSeq[int](f.numGlyphs + 1)
  for i in 0 .. f.numGlyphs:
    f.loca[i] =
      if longOffsets:
        f.data.offset32(loca + i * 4)
      else:
        f.data.u16(loca + i * 2) * 2
  f.glyf = f.tables["glyf"]

type TtPoint = object
  x, y: float64
  onCurve: bool

proc addContour(path: var BezPath, pts: openArray[TtPoint]) =
  # TrueType contours are quadratic splines where two off-curve points in a
  # row imply an on-curve point between them.
  if pts.len == 0:
    return
  var start = 0
  while start < pts.len and not pts[start].onCurve:
    inc start
  var first: Point
  if start == pts.len:
    # No on-curve point at all: start at the midpoint of the last point and
    # the first, so the walk below begins with the first as a control point.
    start = pts.len - 1
    first = point((pts[0].x + pts[^1].x) * 0.5, (pts[0].y + pts[^1].y) * 0.5)
  else:
    first = point(pts[start].x, pts[start].y)
  path.moveTo first
  var control: Point
  var haveControl = false
  for k in 1 .. pts.len:
    let p = pts[(start + k) mod pts.len]
    let q = point(p.x, p.y)
    if p.onCurve:
      if haveControl:
        path.quadTo control, q
        haveControl = false
      else:
        path.lineTo q
    else:
      if haveControl:
        path.quadTo control, midpoint(control, q)
      control = q
      haveControl = true
  if haveControl:
    path.quadTo control, first
  path.closePath()

const maxGlyphWork = 1 shl 17
  ## How many points and components one glyph may take, counted over all its
  ## components and theirs. `maxp` caps a composite at 65535 points, so this
  ## is generous for real fonts, but it stops a font whose composites repeat
  ## composites that repeat others, which would grow exponentially with the
  ## depth.

proc spend(budget: var int, work: int) =
  budget -= work
  if budget < 0:
    raise newException(FontError, "glyph is too complex to draw")

proc glyfPart(f: ParsedFont, glyph, depth: int, budget: var int): BezPath

proc simpleGlyph(f: ParsedFont, at, contours: int, budget: var int): BezPath =
  var ends = newSeq[int](contours)
  var pos = at + 10
  for i in 0 ..< contours:
    ends[i] = f.data.u16(pos)
    pos += 2
    # The last point of each contour, so they increase; the last one sets the
    # number of points, which the slices below rely on.
    if i > 0 and ends[i] <= ends[i - 1]:
      raise newException(FontError, "glyph contours out of order")
  let numPoints =
    if contours == 0:
      0
    else:
      ends[^1] + 1
  budget.spend(numPoints)
  let instructionLength = f.data.u16(pos)
  pos += 2 + instructionLength
  var flags = newSeq[int](numPoints)
  var i = 0
  while i < numPoints:
    let flag = f.data.u8(pos)
    inc pos
    flags[i] = flag
    inc i
    if (flag and 8) != 0:
      var repeats = f.data.u8(pos)
      inc pos
      while repeats > 0 and i < numPoints:
        flags[i] = flag
        inc i
        dec repeats
  var pts = newSeq[TtPoint](numPoints)
  var v = 0
  for i in 0 ..< numPoints:
    let flag = flags[i]
    if (flag and 2) != 0:
      let d = f.data.u8(pos)
      inc pos
      v += (if (flag and 16) != 0: d else: -d)
    elif (flag and 16) == 0:
      v += f.data.i16(pos)
      pos += 2
    pts[i].x = v.float64
    pts[i].onCurve = (flag and 1) != 0
  v = 0
  for i in 0 ..< numPoints:
    let flag = flags[i]
    if (flag and 4) != 0:
      let d = f.data.u8(pos)
      inc pos
      v += (if (flag and 32) != 0: d else: -d)
    elif (flag and 32) == 0:
      v += f.data.i16(pos)
      pos += 2
    pts[i].y = v.float64
  var first = 0
  for c in 0 ..< contours:
    result.addContour(pts[first .. ends[c]])
    first = ends[c] + 1

proc compositeGlyph(f: ParsedFont, at, depth: int, budget: var int): BezPath =
  var pos = at + 10
  while true:
    budget.spend(1)
    let flags = f.data.u16(pos)
    let glyphIndex = f.data.u16(pos + 2)
    pos += 4
    var dx, dy: float64
    if (flags and 1) != 0:
      if (flags and 2) != 0:
        dx = f.data.i16(pos).float64
        dy = f.data.i16(pos + 2).float64
      # Point matching (the flag off) is rare and treated as no offset.
      pos += 4
    else:
      if (flags and 2) != 0:
        dx = f.data.i8(pos).float64
        dy = f.data.i8(pos + 1).float64
      pos += 2
    var m = affine(1, 0, 0, 1, dx, dy)
    if (flags and 8) != 0:
      let s = f.data.f2dot14(pos)
      pos += 2
      m.a = s
      m.d = s
    elif (flags and 0x40) != 0:
      m.a = f.data.f2dot14(pos)
      m.d = f.data.f2dot14(pos + 2)
      pos += 4
    elif (flags and 0x80) != 0:
      m.a = f.data.f2dot14(pos)
      m.b = f.data.f2dot14(pos + 2)
      m.c = f.data.f2dot14(pos + 4)
      m.d = f.data.f2dot14(pos + 6)
      pos += 8
    result.extend m.transform(f.glyfPart(glyphIndex, depth + 1, budget))
    if (flags and 0x20) == 0:
      break

proc glyfPart(f: ParsedFont, glyph, depth: int, budget: var int): BezPath =
  ## A glyph or a component of one, drawn from what is left of `budget`.
  if glyph < 0 or glyph >= f.numGlyphs or depth > 8:
    return
  let start = f.glyf[0] + f.loca[glyph]
  let length = f.loca[glyph + 1] - f.loca[glyph]
  if length < 10:
    return # an empty glyph, like a space
  f.data.check(start, length)
  let contours = f.data.i16(start)
  if contours >= 0:
    f.simpleGlyph(start, contours, budget)
  else:
    f.compositeGlyph(start, depth, budget)

proc glyfOutline(f: ParsedFont, glyph: int): BezPath =
  ## The outline in font units, y up, as the font stores it. Raises
  ## `FontError` for a glyph that takes more than `maxGlyphWork`.
  var budget = maxGlyphWork
  f.glyfPart(glyph, 0, budget)

# CFF outlines

proc readIndex(data: Bytes, pos: int, items: var seq[(int, int)]): int =
  ## Reads an INDEX at `pos` into offset and length pairs; returns the
  ## position after it.
  let count = data.u16(pos)
  if count == 0:
    return pos + 2
  let offSize = data.u8(pos + 2)
  if offSize < 1 or offSize > 4:
    raise newException(FontError, "bad CFF index")
  let offsets = pos + 3
  let base = offsets + (count + 1) * offSize - 1
  func offset(i: int): int =
    result = 0
    for b in 0 ..< offSize:
      result = result shl 8 or data.u8(offsets + i * offSize + b)
    # Four bytes can come out negative on JavaScript, or past any data.
    if result < 0 or result > data.len:
      raise newException(FontError, "bad CFF index")
  items = newSeqOfCap[(int, int)](count)
  for i in 0 ..< count:
    let start = base + offset(i)
    let stop = base + offset(i + 1)
    if stop < start:
      raise newException(FontError, "bad CFF index")
    data.check(start, stop - start)
    items.add (start, stop - start)
  base + offset(count)

proc readDict(data: Bytes, start, length: int): Table[int, seq[float64]] =
  ## A CFF DICT: operators (escaped ones as `1200 + op`) to their operands.
  var operands: seq[float64]
  var pos = start
  let stop = start + length
  while pos < stop:
    let b0 = data.u8(pos)
    if b0 <= 21:
      var op = b0
      inc pos
      if b0 == 12:
        op = 1200 + data.u8(pos)
        inc pos
      result[op] = operands
      operands = @[]
    elif b0 == 28:
      operands.add data.i16(pos + 1).float64
      pos += 3
    elif b0 == 29:
      # A signed 32-bit integer.
      operands.add data.i16(pos + 1).float64 * 65536.0 + data.u16(pos + 3).float64
      pos += 5
    elif b0 == 30:
      # A real number in nibbles.
      var text = ""
      inc pos
      var done = false
      while not done:
        let b = data.u8(pos)
        inc pos
        for nibble in [b shr 4, b and 15]:
          case nibble
          of 0 .. 9:
            text.add char(ord('0') + nibble)
          of 0xa:
            text.add '.'
          of 0xb:
            text.add 'E'
          of 0xc:
            text.add "E-"
          of 0xe:
            text.add '-'
          of 0xf:
            done = true
            break
          else:
            discard
      try:
        operands.add parseFloat(text)
      except ValueError:
        operands.add 0.0
    elif b0 >= 32 and b0 <= 246:
      operands.add float64(b0 - 139)
      inc pos
    elif b0 >= 247 and b0 <= 250:
      operands.add float64((b0 - 247) * 256 + data.u8(pos + 1) + 108)
      pos += 2
    elif b0 >= 251 and b0 <= 254:
      operands.add float64(-(b0 - 251) * 256 - data.u8(pos + 1) - 108)
      pos += 2
    else:
      inc pos

func dictInt(data: Bytes, v: float64): int =
  ## A DICT operand used as an offset or a size. Operands are reals, so one
  ## too large to be either (or not a number at all) raises `FontError`
  ## instead of a conversion that could fail or overflow.
  if not (v >= 0 and v <= data.len.float64):
    raise newException(FontError, "CFF offset out of range")
  int(v)

proc readCff(f: ParsedFont) =
  let (cff, _) = f.tables["CFF "]
  let hdrSize = f.data.u8(cff + 2)
  var names, topDicts, strings: seq[(int, int)]
  var pos = f.data.readIndex(cff + hdrSize, names)
  pos = f.data.readIndex(pos, topDicts)
  pos = f.data.readIndex(pos, strings)
  discard f.data.readIndex(pos, f.cff.globalSubrs)
  if topDicts.len == 0:
    raise newException(FontError, "CFF font has no top dict")
  let top = f.data.readDict(topDicts[0][0], topDicts[0][1])
  if 1230 in top:
    raise newException(FontError, "CID-keyed CFF fonts aren't supported yet")
  if 1206 in top and top[1206].len > 0 and top[1206][0] != 2:
    raise newException(FontError, "only Type 2 charstrings are supported")
  if 17 notin top or top[17].len == 0:
    raise newException(FontError, "CFF font has no charstrings")
  discard f.data.readIndex(cff + f.data.dictInt(top[17][0]), f.cff.charStrings)
  if 18 in top and top[18].len >= 2:
    let privSize = f.data.dictInt(top[18][0])
    let privOffset = cff + f.data.dictInt(top[18][1])
    let priv = f.data.readDict(privOffset, privSize)
    if 19 in priv and priv[19].len > 0:
      discard
        f.data.readIndex(privOffset + f.data.dictInt(priv[19][0]), f.cff.localSubrs)

func bias(subrs: seq[(int, int)]): int =
  if subrs.len < 1240:
    107
  elif subrs.len < 33900:
    1131
  else:
    32768

type CharstringState = object
  path: BezPath
  x, y: float64
  stack: seq[float64]
  nStems: int
  widthParsed: bool
  open: bool
  ended: bool ## Set by `endchar`, which ends the glyph from any subroutine depth.
  depth: int
  budget: int
    ## Operands and operators left to run, over the glyph and every
    ## subroutine it calls: subroutines that call others many times would
    ## otherwise grow exponentially with the depth.

const maxCharstringWork = 1 shl 16 ## Real glyphs run a few hundred to a few thousand.

proc moveTo(s: var CharstringState, dx, dy: float64) =
  if s.open:
    s.path.closePath()
  s.x += dx
  s.y += dy
  s.path.moveTo point(s.x, s.y)
  s.open = true

proc lineTo(s: var CharstringState, dx, dy: float64) =
  s.x += dx
  s.y += dy
  s.path.lineTo point(s.x, s.y)

proc curveTo(s: var CharstringState, dx1, dy1, dx2, dy2, dx3, dy3: float64) =
  let c1 = point(s.x + dx1, s.y + dy1)
  let c2 = point(c1.x + dx2, c1.y + dy2)
  s.x = c2.x + dx3
  s.y = c2.y + dy3
  s.path.cubicTo c1, c2, point(s.x, s.y)

proc takeWidth(s: var CharstringState, even: int) =
  # The first stack-clearing operator may carry the advance width as an
  # extra leading argument; it is of no use here, so it is dropped.
  if not s.widthParsed:
    s.widthParsed = true
    if s.stack.len mod 2 == 1 and even >= 0 and s.stack.len > even:
      s.stack.delete(0)

proc runCharstring(f: ParsedFont, s: var CharstringState, start, length: int) =
  if s.depth > 10:
    raise newException(FontError, "charstring subroutines nest too deeply")
  var pos = start
  let stop = start + length
  while pos < stop:
    s.budget.spend(1)
    let b0 = f.data.u8(pos)
    inc pos
    if b0 >= 32 or b0 == 28:
      # An operand.
      if b0 == 28:
        s.stack.add f.data.i16(pos).float64
        pos += 2
      elif b0 <= 246:
        s.stack.add float64(b0 - 139)
      elif b0 <= 250:
        s.stack.add float64((b0 - 247) * 256 + f.data.u8(pos) + 108)
        inc pos
      elif b0 <= 254:
        s.stack.add float64(-(b0 - 251) * 256 - f.data.u8(pos) - 108)
        inc pos
      else:
        s.stack.add f.data.fixed(pos)
        pos += 4
      if s.stack.len > 48:
        raise newException(FontError, "charstring stack overflow")
      continue
    case b0
    of 1, 3, 18, 23: # hstem vstem hstemhm vstemhm
      s.takeWidth(0)
      s.nStems += s.stack.len div 2
      s.stack.setLen(0)
    of 19, 20: # hintmask cntrmask
      s.takeWidth(0)
      s.nStems += s.stack.len div 2
      s.stack.setLen(0)
      pos += (s.nStems + 7) div 8
    of 21: # rmoveto
      s.takeWidth(2)
      if s.stack.len >= 2:
        s.moveTo(s.stack[0], s.stack[1])
      s.stack.setLen(0)
    of 22: # hmoveto
      if not s.widthParsed:
        s.widthParsed = true
        if s.stack.len > 1:
          s.stack.delete(0)
      if s.stack.len >= 1:
        s.moveTo(s.stack[0], 0)
      s.stack.setLen(0)
    of 4: # vmoveto
      if not s.widthParsed:
        s.widthParsed = true
        if s.stack.len > 1:
          s.stack.delete(0)
      if s.stack.len >= 1:
        s.moveTo(0, s.stack[0])
      s.stack.setLen(0)
    of 5: # rlineto
      var i = 0
      while i + 1 < s.stack.len:
        s.lineTo(s.stack[i], s.stack[i + 1])
        i += 2
      s.stack.setLen(0)
    of 6, 7: # hlineto vlineto: alternating horizontal and vertical
      var horizontal = b0 == 6
      for v in s.stack:
        if horizontal:
          s.lineTo(v, 0)
        else:
          s.lineTo(0, v)
        horizontal = not horizontal
      s.stack.setLen(0)
    of 8: # rrcurveto
      var i = 0
      while i + 5 < s.stack.len:
        s.curveTo(
          s.stack[i],
          s.stack[i + 1],
          s.stack[i + 2],
          s.stack[i + 3],
          s.stack[i + 4],
          s.stack[i + 5],
        )
        i += 6
      s.stack.setLen(0)
    of 24: # rcurveline
      var i = 0
      while s.stack.len - i >= 8:
        s.curveTo(
          s.stack[i],
          s.stack[i + 1],
          s.stack[i + 2],
          s.stack[i + 3],
          s.stack[i + 4],
          s.stack[i + 5],
        )
        i += 6
      if i + 1 < s.stack.len:
        s.lineTo(s.stack[i], s.stack[i + 1])
      s.stack.setLen(0)
    of 25: # rlinecurve
      var i = 0
      while s.stack.len - i >= 8:
        s.lineTo(s.stack[i], s.stack[i + 1])
        i += 2
      if i + 5 < s.stack.len:
        s.curveTo(
          s.stack[i],
          s.stack[i + 1],
          s.stack[i + 2],
          s.stack[i + 3],
          s.stack[i + 4],
          s.stack[i + 5],
        )
      s.stack.setLen(0)
    of 26, 27: # vvcurveto hhcurveto
      var i = 0
      var d1 = 0.0
      if s.stack.len mod 4 == 1:
        d1 = s.stack[0]
        i = 1
      while i + 3 < s.stack.len:
        if b0 == 26:
          s.curveTo(d1, s.stack[i], s.stack[i + 1], s.stack[i + 2], 0, s.stack[i + 3])
        else:
          s.curveTo(s.stack[i], d1, s.stack[i + 1], s.stack[i + 2], s.stack[i + 3], 0)
        d1 = 0
        i += 4
      s.stack.setLen(0)
    of 30, 31: # vhcurveto hvcurveto: alternating, the last may take a fifth
      var horizontal = b0 == 31
      var i = 0
      while i + 3 < s.stack.len:
        let last = s.stack.len - i == 5
        let dlast =
          if last:
            s.stack[i + 4]
          else:
            0.0
        if horizontal:
          s.curveTo(
            s.stack[i], 0, s.stack[i + 1], s.stack[i + 2], dlast, s.stack[i + 3]
          )
        else:
          s.curveTo(
            0, s.stack[i], s.stack[i + 1], s.stack[i + 2], s.stack[i + 3], dlast
          )
        horizontal = not horizontal
        i += 4
      s.stack.setLen(0)
    of 10, 29: # callsubr callgsubr
      if s.stack.len == 0:
        raise newException(FontError, "charstring calls a subroutine without an index")
      let subrs = if b0 == 10: f.cff.localSubrs else: f.cff.globalSubrs
      let index = int(s.stack.pop()) + bias(subrs)
      if index < 0 or index >= subrs.len:
        raise newException(FontError, "charstring calls a missing subroutine")
      inc s.depth
      f.runCharstring(s, subrs[index][0], subrs[index][1])
      dec s.depth
      if s.ended:
        # `endchar` in the subroutine, or in one it called: every level
        # returns, up to the glyph's own charstring.
        return
    of 11: # return
      return
    of 14: # endchar
      s.takeWidth(0)
      if s.open:
        s.path.closePath()
        s.open = false
      s.stack.setLen(0)
      s.ended = true
      return
    of 12:
      let b1 = f.data.u8(pos)
      inc pos
      case b1
      of 35: # flex
        if s.stack.len >= 13:
          s.curveTo(
            s.stack[0], s.stack[1], s.stack[2], s.stack[3], s.stack[4], s.stack[5]
          )
          s.curveTo(
            s.stack[6], s.stack[7], s.stack[8], s.stack[9], s.stack[10], s.stack[11]
          )
      of 34: # hflex
        if s.stack.len >= 7:
          let y0 = s.y
          s.curveTo(s.stack[0], 0, s.stack[1], s.stack[2], s.stack[3], 0)
          s.curveTo(s.stack[4], 0, s.stack[5], y0 - s.y, s.stack[6], 0)
      of 36: # hflex1
        if s.stack.len >= 9:
          let y0 = s.y
          s.curveTo(s.stack[0], s.stack[1], s.stack[2], s.stack[3], s.stack[4], 0)
          s.curveTo(
            s.stack[5], 0, s.stack[6], s.stack[7], s.stack[8], y0 - (s.y + s.stack[7])
          )
      of 37: # flex1
        if s.stack.len >= 11:
          let x0 = s.x
          let y0 = s.y
          var dx = 0.0
          var dy = 0.0
          for i in 0 ..< 5:
            dx += s.stack[i * 2]
            dy += s.stack[i * 2 + 1]
          s.curveTo(
            s.stack[0], s.stack[1], s.stack[2], s.stack[3], s.stack[4], s.stack[5]
          )
          let c1 = point(s.x + s.stack[6], s.y + s.stack[7])
          let c2 = point(c1.x + s.stack[8], c1.y + s.stack[9])
          # The last point takes one coordinate from the stack and the other
          # from the start, whichever moved less.
          if abs(dx) > abs(dy):
            s.x = c2.x + s.stack[10]
            s.y = y0
          else:
            s.x = x0
            s.y = c2.y + s.stack[10]
          s.path.cubicTo c1, c2, point(s.x, s.y)
      else:
        discard # arithmetic and other deprecated operators
      s.stack.setLen(0)
    else:
      s.stack.setLen(0)

proc cffOutline(f: ParsedFont, glyph: int): BezPath =
  if glyph < 0 or glyph >= f.cff.charStrings.len:
    return
  var s = CharstringState(budget: maxCharstringWork)
  let (start, length) = f.cff.charStrings[glyph]
  f.runCharstring(s, start, length)
  if s.open:
    s.path.closePath()
  s.path

# Kerning from GPOS

# The tables are read in place: parsing checks that their arrays fit in the
# data, and lookups binary-search them, since the spec sorts them. So a table
# that several others point to costs nothing extra, and one that isn't sorted
# gives wrong kerning but never more work than the search.

func lastAtOrBefore(data: Bytes, at, count, stride, key: int): int =
  ## The last of `count` records of `stride` bytes at `at` whose first 16-bit
  ## field is at most `key`, or -1.
  var lo = 0
  var hi = count
  while lo < hi:
    let mid = (lo + hi) div 2
    if data.u16(at + mid * stride) <= key:
      lo = mid + 1
    else:
      hi = mid
  lo - 1

proc readCoverage(data: Bytes, at: int): Coverage =
  let format = data.u16(at)
  let count = data.u16(at + 2)
  case format
  of 1:
    data.checkArray(at + 4, count, 2) # glyph ids
  of 2:
    data.checkArray(at + 4, count, 6) # start, end, coverage index of the start
  else:
    raise newException(FontError, "unknown coverage format")
  Coverage(format: format, at: at + 4, count: count)

func index(c: Coverage, data: Bytes, glyph: int): int =
  ## The glyph's coverage index, or -1.
  if c.format == 1:
    let i = data.lastAtOrBefore(c.at, c.count, 2, glyph)
    if i >= 0 and data.u16(c.at + i * 2) == glyph: i else: -1
  else:
    let i = data.lastAtOrBefore(c.at, c.count, 6, glyph)
    if i < 0:
      return -1
    let rec = c.at + i * 6
    let start = data.u16(rec)
    if glyph <= data.u16(rec + 2):
      data.u16(rec + 4) + glyph - start
    else:
      -1

proc readClassDef(data: Bytes, at: int): ClassDef =
  let format = data.u16(at)
  case format
  of 1:
    # The classes of a run of glyphs from `startGlyph`.
    let count = data.u16(at + 4)
    data.checkArray(at + 6, count, 2)
    ClassDef(format: 1, startGlyph: data.u16(at + 2), at: at + 6, count: count)
  of 2:
    # Ranges: start, end and class.
    let count = data.u16(at + 2)
    data.checkArray(at + 4, count, 6)
    ClassDef(format: 2, at: at + 4, count: count)
  else:
    raise newException(FontError, "unknown class definition format")

func classOf(c: ClassDef, data: Bytes, glyph: int): int =
  ## The glyph's class; 0 for glyphs the table doesn't list.
  if c.format == 1:
    let i = glyph - c.startGlyph
    if i >= 0 and i < c.count:
      data.u16(c.at + i * 2)
    else:
      0
  else:
    let i = data.lastAtOrBefore(c.at, c.count, 6, glyph)
    if i >= 0 and glyph <= data.u16(c.at + i * 6 + 2):
      data.u16(c.at + i * 6 + 4)
    else:
      0

func valueSize(format: int): int =
  result = 0
  for bit in 0 .. 7:
    if (format and (1 shl bit)) != 0:
      result += 2

proc xAdvance(data: Bytes, at, format: int): int =
  ## The x advance of a value record, the part of pair kerning that matters
  ## for horizontal text.
  if (format and 4) == 0:
    return 0
  var pos = at
  if (format and 1) != 0:
    pos += 2
  if (format and 2) != 0:
    pos += 2
  data.i16(pos)

proc readPairPos(data: Bytes, at: int): PairLookup =
  let format = data.u16(at)
  let coverage = data.readCoverage(at + data.u16(at + 2))
  let vf1 = data.u16(at + 4)
  let vf2 = data.u16(at + 6)
  let recordSize = valueSize(vf1) + valueSize(vf2)
  case format
  of 1:
    # One pair set per covered first glyph, each checked when it is used.
    let setCount = data.u16(at + 8)
    data.checkArray(at + 10, setCount, 2)
    PairLookup(
      classed: false,
      coverage: coverage,
      valueFormat: vf1,
      recordSize: recordSize,
      base: at,
      pairSets: at + 10,
      setCount: setCount,
    )
  of 2:
    # A matrix of value records by first and second class. Both counts come
    # from the font, so the matrix has to fit in it. A row is at most 65535
    # records of 32 bytes, so its size fits in `int` everywhere, and once the
    # rows fit, any offset into them does too.
    let class1Count = data.u16(at + 12)
    let class2Count = data.u16(at + 14)
    data.checkArray(at + 16, class1Count, class2Count * recordSize)
    PairLookup(
      classed: true,
      coverage: coverage,
      valueFormat: vf1,
      recordSize: recordSize,
      class1: data.readClassDef(at + data.u16(at + 8)),
      class2: data.readClassDef(at + data.u16(at + 10)),
      class1Count: class1Count,
      class2Count: class2Count,
      records: at + 16,
    )
  else:
    raise newException(FontError, "unknown pair adjustment format")

func pairValue(data: Bytes, sub: PairLookup, a, b: int, value: var int): bool =
  ## Whether the subtable covers the pair, with its x advance adjustment in
  ## `value`. A glyph-pair subtable covers it when it lists the second glyph,
  ## a class subtable whenever it covers the first.
  let index = sub.coverage.index(data, a)
  if index < 0:
    return false
  if sub.classed:
    let c1 = sub.class1.classOf(data, a)
    let c2 = sub.class2.classOf(data, b)
    if c1 < sub.class1Count and c2 < sub.class2Count:
      let rec =
        sub.records + c1 * (sub.class2Count * sub.recordSize) + c2 * sub.recordSize
      value = data.xAdvance(rec, sub.valueFormat)
    return true
  if index >= sub.setCount:
    return false
  # The pair set: a count, then records of the second glyph and the values,
  # sorted by the second glyph.
  let pairSet = sub.base + data.u16(sub.pairSets + index * 2)
  let pairCount = data.u16(pairSet)
  let stride = 2 + sub.recordSize
  data.checkArray(pairSet + 2, pairCount, stride)
  let i = data.lastAtOrBefore(pairSet + 2, pairCount, stride, b)
  if i < 0 or data.u16(pairSet + 2 + i * stride) != b:
    return false
  value = data.xAdvance(pairSet + 4 + i * stride, sub.valueFormat)
  true

const maxKernSubtables = 1 shl 10
  ## Pair adjustment subtables kept across all kern lookups. Real fonts have a
  ## few dozen to a few hundred, but every glyph pair in a layout scans them,
  ## so the count can't be left to grow with the size of the font.

proc readKerning(f: ParsedFont) =
  ## The pair adjustment lookups of the `kern` feature for the Latin script,
  ## or the default script.
  if "GPOS" notin f.tables:
    return
  let gpos = f.tables["GPOS"][0]
  let scriptList = gpos + f.data.u16(gpos + 4)
  let featureList = gpos + f.data.u16(gpos + 6)
  let lookupList = gpos + f.data.u16(gpos + 8)
  # The script: `latn` if present, else `DFLT`.
  var script = -1
  let scriptCount = f.data.u16(scriptList)
  for i in 0 ..< scriptCount:
    let rec = scriptList + 2 + i * 6
    let tag = f.data.tag(rec)
    if tag == "latn" or (tag == "DFLT" and script < 0):
      script = scriptList + f.data.u16(rec + 4)
  if script < 0:
    return
  let langSysOffset = f.data.u16(script)
  if langSysOffset == 0:
    return
  let langSys = script + langSysOffset
  let featureCount = f.data.u16(langSys + 4)
  # Each count here can be 65535 and the tables can point at each other, so
  # the work is limited by the size of the font: a real font's kerning takes
  # far less than one step per byte. Each feature and each lookup is read
  # once, however often it is listed.
  var budget = max(1 shl 16, f.data.len)
  var seenFeature = newSeq[bool](0x10000)
  var seenLookup = newSeq[bool](0x10000)
  var lookups: seq[int]
  for i in 0 ..< featureCount:
    budget.spend(1)
    let featureIndex = f.data.u16(langSys + 6 + i * 2)
    if seenFeature[featureIndex]:
      continue
    seenFeature[featureIndex] = true
    let rec = featureList + 2 + featureIndex * 6
    if f.data.tag(rec) != "kern":
      continue
    let feature = featureList + f.data.u16(rec + 4)
    let lookupCount = f.data.u16(feature + 2)
    for k in 0 ..< lookupCount:
      budget.spend(1)
      let lookupIndex = f.data.u16(feature + 4 + k * 2)
      if not seenLookup[lookupIndex]:
        seenLookup[lookupIndex] = true
        lookups.add lookupIndex
  var kept = 0
  for lookupIndex in lookups:
    if kept >= maxKernSubtables:
      break
    let lookup = lookupList + f.data.u16(lookupList + 2 + lookupIndex * 2)
    let lookupType = f.data.u16(lookup)
    let subCount = f.data.u16(lookup + 4)
    var subtables: seq[PairLookup]
    for i in 0 ..< subCount:
      if kept >= maxKernSubtables:
        break
      budget.spend(1)
      var sub = lookup + f.data.u16(lookup + 6 + i * 2)
      var kind = lookupType
      if kind == 9:
        kind = f.data.u16(sub + 2)
        sub = sub + f.data.offset32(sub + 4)
      if kind == 2:
        subtables.add f.data.readPairPos(sub)
        inc kept
    if subtables.len > 0:
      f.kerning.add subtables

func kerning(f: ParsedFont, first, second: GlyphId): int =
  ## The x advance adjustment between two glyphs, in font units. Every
  ## lookup applies, and within one the first subtable that covers the pair
  ## decides (see `pairValue`). A pair set that doesn't fit in the data
  ## counts as not covering the pair, so layout doesn't fail over one.
  let a = int(uint16(first))
  let b = int(uint16(second))
  for subtables in f.kerning:
    for sub in subtables:
      var value = 0
      var covered = false
      try:
        covered = f.data.pairValue(sub, a, b, value)
      except FontError:
        covered = false
      if covered:
        result += value
        break

# Loading

proc parse(font: Font): ParsedFont =
  result = ParsedFont(data: font.data)
  result.readTables(font.index)
  result.readMetrics()
  result.readCmap()
  if "CFF " in result.tables:
    result.hasCff = true
    result.readCff()
  elif "glyf" in result.tables and "loca" in result.tables:
    result.readLoca()
  else:
    raise newException(FontError, "font has neither TrueType nor CFF outlines")
  result.readKerning()

proc parsed(font: Font): ParsedFont =
  ## The parsed font, read on first use and kept on the `Font`.
  if font == nil:
    raise newException(FontError, "no font")
  if font.cache != nil and font.cache of ParsedFont:
    return ParsedFont(font.cache)
  result = font.parse()
  font.cache = result

# The engine

proc glyphFor*(e: OpenTypeEngine, font: Font, c: Rune): GlyphId =
  ## The glyph for a character, `notdef` when the font lacks it. Raises
  ## `FontError` for a font the engine can't read.
  font.parsed.glyphFor(int(c))

proc layout*(e: OpenTypeEngine, text: string, style: TextStyle): TextLayout =
  ## One line of left-to-right text in one style. Raises `FontError` for a
  ## font the engine can't read.
  let f = style.font.parsed
  let s = style.size / f.unitsPerEm.float64
  result.text = text
  result.ascent = f.ascender.float64 * s
  result.descent = -f.descender.float64 * s
  result.lineGap = f.lineGap.float64 * s
  var ids: seq[GlyphId]
  var clusters: seq[int]
  var i = 0
  while i < text.len:
    let r = text.runeAt(i)
    ids.add f.glyphFor(int(r))
    clusters.add i
    i += text.runeLenAt(i)
  if ids.len == 0:
    return
  var run = GlyphRun(font: style.font, size: style.size, paint: style.paint)
  # In `float64`, as a long run of a font's largest advances and kerning passes
  # 2^31, which is an overflow on JS.
  var x = 0.0
  for k in 0 ..< ids.len:
    run.glyphs.add Glyph(id: ids[k], pos: point(x * s, 0), cluster: clusters[k])
    x += f.advance(ids[k]).float64
    if k + 1 < ids.len:
      x += f.kerning(ids[k], ids[k + 1]).float64
  result.width = x * s
  result.runs = @[run]

proc glyphDrawing*(e: OpenTypeEngine, font: Font, glyph: GlyphId): GlyphDrawing =
  ## The glyph's outline in em units, y down. Empty for a glyph the font
  ## doesn't have and for a font the engine can't read.
  result = GlyphDrawing(kind: gkOutline)
  try:
    let f = font.parsed
    let outline =
      if f.hasCff:
        f.cffOutline(int(uint16(glyph)))
      else:
        f.glyfOutline(int(uint16(glyph)))
    let s = 1.0 / f.unitsPerEm.float64
    result.path = scale(s, -s).transform(outline)
  except FontError:
    discard

static:
  doAssert OpenTypeEngine is TextEngine
