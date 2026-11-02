## Text: fonts, glyph runs, what a glyph looks like, and the `TextEngine`
## concept that text engines implement.
##
## Layout and drawing are separate. An engine turns a string into a
## `TextLayout` (shaping, metrics, later line breaking and hit testing) and
## describes any glyph as a `GlyphDrawing`; a backend draws the layout's
## `GlyphRun`s through the `drawGlyphs` primitive, natively when it can make
## a font from the run's bytes and otherwise with `drawGlyphsAsPaths` in
## `pollock/context`, which fills the engine's outlines. So every engine
## pairs with every backend on the same platform.
##
## A `Font` is the font's bytes, a face index and variation coordinates,
## never a platform handle, so any backend can build its own native font
## from it. Engines keep what they parse from it on the `Font` itself.

import std/[hashes, macros, strutils, tables]
import ./[color, geometry, image, paint]

type
  GlyphId* = distinct uint16

  FontVariation* = object
    tag*: string ## Four characters, like "wght".
    value*: float64

  FontError* = object of CatchableError
    ## Raised by an engine's `layout` for a font it can't read. Drawing
    ## calls never raise: a glyph from such a font draws nothing.

  Font* = ref object
    ## A font file in memory. Make one with `newFont` and treat it as
    ## immutable afterwards: engines cache what they parse from it in
    ## `cache`, and `cachedDrawing` keeps their drawings in `drawings`.
    data*: seq[uint8]
    index*: int ## The face in a collection (`ttcf`); 0 otherwise.
    variations*: seq[FontVariation]
    cache*: RootRef ## Engine-private parsed form.
    drawings*: Table[(string, GlyphId), ref GlyphDrawing]
      ## By the name of the engine's type and the glyph.

  Glyph* = object
    id*: GlyphId
    pos*: Point ## Where the glyph's origin goes, on the baseline.
    cluster*: int ## Byte offset of the character it came from in the text.

  GlyphRun* = object
    ## Glyphs from one font at one size in one paint, with positions in
    ## user space (the transform applies to them like to a path).
    font*: Font
    size*: float64
    paint*: Paint
    glyphs*: seq[Glyph]

  GlyphKind* = enum
    gkOutline
    gkLayers
    gkBitmap

  GlyphLayer* = object
    path*: BezPath
    paint*: Paint
    usesRunPaint*: bool ## COLR's "foreground": draw in the run's paint instead.

  GlyphDrawing* = object
    ## What one glyph looks like, in em units: 1.0 is the font size, y points
    ## down and the baseline is at 0, so drawing code scales it by the run's
    ## size and moves it to the glyph's position.
    case kind*: GlyphKind
    of gkOutline:
      path*: BezPath
    of gkLayers:
      layers*: seq[GlyphLayer]
    of gkBitmap:
      image*: ImageData
      bounds*: Rect

  TextStyle* = object
    font*: Font
    size*: float64 ## In user units: the em.
    paint*: Paint

  TextLayout* = object
    ## Laid-out text. Its origin is the start of the baseline; `ascent` is
    ## how far the line reaches above it and `descent` below, both positive,
    ## in the same units as the size.
    text*: string
    runs*: seq[GlyphRun]
    width*: float64 ## The advance width.
    ascent*, descent*, lineGap*: float64

  TextEngine* = concept
    proc layout(e: Self, text: string, style: TextStyle): TextLayout
    proc glyphDrawing(e: Self, font: Font, glyph: GlyphId): GlyphDrawing

func `==`*(a, b: GlyphId): bool {.borrow.}
func `$`*(g: GlyphId): string {.borrow.}
func hash*(g: GlyphId): Hash {.borrow.}

const notdef* = GlyphId(0) ## The glyph a font shows for characters it lacks.

proc newFont*(data: seq[uint8], index = 0): Font =
  ## A font from the bytes of a font file. Nothing is parsed here; an engine
  ## reads it the first time it is used, and `layout` raises `FontError` if
  ## it can't.
  Font(data: data, index: index)

proc newFont*(data: string, index = 0): Font =
  ## The same from a string, as `readFile` and `staticRead` give it.
  var bytes = newSeq[uint8](data.len)
  for i, c in data:
    bytes[i] = uint8(c)
  newFont(bytes, index)

func textStyle*(font: Font, size: float64, paint: Paint): TextStyle =
  TextStyle(font: font, size: size, paint: paint)

func textStyle*(font: Font, size: float64, color = black): TextStyle =
  TextStyle(font: font, size: size, paint: solid(color))

func height*(layout: TextLayout): float64 =
  ## From the top of the ascent to the bottom of the descent.
  layout.ascent + layout.descent

func bounds*(layout: TextLayout): Rect =
  ## The box the line takes up, with the origin on the baseline.
  rect(0, -layout.ascent, layout.width, layout.descent)

proc cachedDrawing*[E](engine: E, font: Font, glyph: GlyphId): ref GlyphDrawing =
  ## The engine's drawing for a glyph, kept on the font so it is made once
  ## however many runs use it. Backends draw from this. Each engine type
  ## keeps its own drawings, so two engines can share a font. The drawing is
  ## shared rather than copied, so don't change it.
  mixin glyphDrawing
  let key = ($E, glyph)
  result = font.drawings.getOrDefault(key)
  if result == nil:
    result = new GlyphDrawing
    result[] = engine.glyphDrawing(font, glyph)
    font.drawings[key] = result

# The default engine

const pollockTextEngine* {.strdefine.} = "pollock/engines/opentype"
  ## The module of the engine the backends pair with by default, set with
  ## `-d:pollockTextEngine=<module path>`. It must export
  ## `defaultTextEngine()`, which makes an engine with its defaults.

macro importTextEngine*(): untyped =
  ## Imports the module named by `pollockTextEngine` and exports it. A
  ## backend calls this and defines its default context over
  ## `typeof(defaultTextEngine())`.
  let name = pollockTextEngine.rsplit('/', 1)[^1]
  result = newStmtList(
    newNimNode(nnkImportStmt).add(newLit(pollockTextEngine)),
    newNimNode(nnkExportStmt).add(ident(name)),
  )
