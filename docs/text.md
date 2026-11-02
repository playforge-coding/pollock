# Text

Text is two jobs that pollock keeps apart. A **text engine** turns a string into positioned glyphs, a `TextLayout`, and a **backend** draws them. The two meet at the `GlyphRun`: one font at one size in one paint, with glyph ids and positions, and nothing that belongs to either side. So any engine pairs with any backend on the same platform, and `import pollock` brings in the text API (`pollock/text`) together with the default engine.

## Fonts

A `Font` is the bytes of a font file in memory, with a face index for collections (`.ttc`):

```nim
let font = newFont(readFile("Inter-Regular.ttf"))
let second = newFont(readFile("Family.ttc"), index = 1)
```

Nothing is parsed up front. The engine reads the font the first time it is used and keeps what it parsed on the `Font`, along with the glyph drawings it makes, so make a font once and share it. On the JavaScript target, where there is no `readFile`, embed the file with `staticRead` and hand the string to `newFont`. A font the engine can't read makes `layout` raise `FontError`; drawing its glyphs draws nothing, since drawing calls never raise.

pollock never looks for installed fonts. The application brings the files, and an engine that can find fonts (the native ones, when they exist) does so on its own terms.

## Laying text out

```nim
let style = textStyle(font, 24, rgb8(30, 30, 30))
let layout = ctx.engine.layout("Hello, pollock!", style)
```

A `TextStyle` is a font, a size in user units (the em) and a paint or color. Every pollock context has an `engine`, the text engine it was made with; `layout` is the engine's. The result:

| Field | Meaning |
| --- | --- |
| `runs` | The glyph runs, each with its font, size, paint and glyphs (`id`, `pos`, `cluster`). |
| `width` | The advance width. |
| `ascent`, `descent` | How far the line reaches above and below the baseline, both positive. |
| `lineGap` | The font's extra spacing between lines. |
| `height` | `ascent + descent`. |
| `bounds` | The rectangle from `(0, -ascent)` to `(width, descent)`. |

The layout's origin is the start of its baseline, so `bounds.y0` is negative. A glyph's `cluster` is the byte offset of the character it came from, which is what hit testing and cursors will build on.

## Drawing it

```nim
proc drawText(ctx, layout: TextLayout, at: Point)
proc drawText(ctx, layout: TextLayout, x, y: float64)
template drawText(ctx, text: string, style: TextStyle, at: Point)
```

Draws the layout with the start of its baseline at `at`, each run in its own paint. The third form lays the text out with the context's engine first. The transform and clip apply as they do to a path, and the paint is in user space, so a gradient runs across the whole line rather than restarting at every glyph:

```nim
import pollock

var ctx = newCpuContext(400, 120)
ctx.clear(white)
let font = newFont(readFile("Inter-Regular.ttf"))
ctx.drawText("Hello, pollock!", textStyle(font, 36), point(20, 60))
let layout = ctx.engine.layout("centered", textStyle(font, 20, rgb8(60, 90, 200)))
ctx.drawText(layout, point(200 - layout.width / 2, 100))
ctx.withTransform(rotateAbout(-0.2, point(300, 60))):
  ctx.drawText(
    "tilt",
    textStyle(font, 40, linearGradient(point(260, 0), point(340, 0), red, blue)),
    point(260, 75),
  )
writePng(ctx.toImage(), "text.png")
```

## The engine

The default engine is the pure Nim one, `OpenTypeEngine` from `pollock/engines/opentype`, which runs on every target with no library behind it. It reads TrueType and CFF outlines (simple and composite `glyf` glyphs, Type 2 charstrings with subroutines), the Unicode character map, the metrics, and pair kerning from `GPOS`, in both its formats and behind extension lookups. Layout is one line of left-to-right text with that kerning applied.

What it doesn't do yet, in the order it is likely to come: ligatures and other `GSUB` substitutions, mark placement, bidirectional text, line breaking, hit testing, variable fonts, color glyphs, CID-keyed CFF and CFF2 fonts, and the legacy `kern` table. The engine's `glyphFor(font, rune)` gives the glyph id for a character, and `defaultTextEngine()` makes an engine with its defaults.

Backends are generic over their engine: `CpuContext` is `CpuContextOf[OpenTypeEngine]`, and `newCpuContext(width, height, engine)` makes a context over any other engine, as do the SVG and Cairo constructors. The define `-d:pollockTextEngine=<module path>` changes the engine the plain `CpuContext`, `SvgContext` and `CairoContext` pair with; the module has to export `defaultTextEngine()`. The recording backend needs no engine, since it records the runs without drawing them.

## What a glyph looks like

An engine describes a glyph as a `GlyphDrawing`: an outline (`gkOutline`, a `BezPath`), color layers each with a paint (`gkLayers`) or a bitmap with the rectangle it covers (`gkBitmap`). All of it is in em units with y down and the baseline at 0, so a drawing is scaled by the run's size and moved to the glyph's position. `engine.glyphDrawing(font, id)` makes one and `engine.cachedDrawing(font, id)` keeps it on the font.

That is what lets every backend draw text: one without native glyph drawing fills the outlines with `fillPath` and the bitmaps with `drawImage` (`drawGlyphsAsPaths` in `pollock/context` does exactly that), and the pure Nim engine only ever produces outlines today. See [Writing a backend](writing-a-backend.md#text) for the backend side and [Architecture](architecture.md#text) for the design of the rest.
