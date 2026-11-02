## A word set from a font file, glyph by glyph. Moving the pointer along it
## magnifies the letters nearby, like a dock, and clicking changes the word.
##
## Shows: loading a font and laying text out, drawing a layout whole with
## `drawText`, drawing its glyphs one at a time through `drawGlyphs` so each
## gets its own transform and paint, a glyph's outline from the engine, and
## what a layout measures: the baseline, the ascent and descent, and the
## kerned advances (compare the ticks under "AVATAR" with those under
## "pollock").

import std/math
import pollock/engines/opentype
import ./scene
import ../tests/fontdata

const
  words = ["pollock", "AVATAR", "Añejo", "fjord café"]
  headlineSize = 110.0
  baselineY = 215.0
  reach = 110.0 ## How far from the pointer the magnification is felt.

type Lettering* = object
  font: Font
  word: int
  headline: TextLayout
  caption: TextLayout
  time: float64
  pointer: Point
  hover: bool
  lift: seq[float64] ## Per glyph, 0 to 1, smoothed over time.

let engine = defaultTextEngine()

proc setWord(s: var Lettering) =
  s.headline = engine.layout(words[s.word], textStyle(s.font, headlineSize))
  s.lift = newSeq[float64](s.headline.runs[0].glyphs.len)

proc newLettering*(): Lettering =
  result = Lettering(font: newFont(trueTypeData), pointer: point(-1000, -1000))
  result.setWord()
  result.caption = engine.layout(
    "Source Sans 3, read from its TrueType file. Click for another word.",
    textStyle(result.font, 17, rgb8(150, 155, 170)),
  )

func origin(s: Lettering): Point =
  ## Where the headline's baseline starts: centered.
  point((sceneWidth - s.headline.width) / 2, baselineY)

func cellCenter(s: Lettering, i: int): float64 =
  ## The middle of a glyph's advance, in scene coordinates.
  let glyphs = s.headline.runs[0].glyphs
  let next =
    if i + 1 < glyphs.len:
      glyphs[i + 1].pos.x
    else:
      s.headline.width
  s.origin.x + (glyphs[i].pos.x + next) / 2

proc update*(s: var Lettering, dt: float64, input: Input) =
  s.time += dt
  s.hover = input.inside
  if input.inside:
    s.pointer = input.pos
  if input.pressed:
    s.word = (s.word + 1) mod words.len
    s.setWord()
  for i in 0 ..< s.lift.len:
    let target =
      if s.hover:
        max(0.0, 1 - abs(s.pointer.x - s.cellCenter(i)) / reach)
      else:
        0.0
    s.lift[i] = approach(s.lift[i], target, 14, dt)

proc render*[C: RenderContext](s: Lettering, ctx: var C) =
  ctx.fill(sceneBounds, rgb8(24, 26, 34))
  let origin = s.origin
  let run = s.headline.runs[0]
  let guide = rgb8(90, 95, 115)

  # What the layout measures: the baseline, how far the line reaches above
  # and below it, and where each glyph's advance starts.
  ctx.stroke(
    line(origin.x - 30, origin.y, origin.x + s.headline.width + 30, origin.y),
    rgb8(220, 80, 90),
    1.0,
  )
  for y in [origin.y - s.headline.ascent, origin.y + s.headline.descent]:
    ctx.stroke(
      line(origin.x - 30, y, origin.x + s.headline.width + 30, y),
      guide,
      strokeStyle(width = 1, dashes = [4.0, 4.0]),
    )
  for g in run.glyphs:
    let x = origin.x + g.pos.x
    ctx.stroke(line(x, origin.y + 4, x, origin.y + 14), guide, 1.0)
  let endX = origin.x + s.headline.width
  ctx.stroke(line(endX, origin.y + 4, endX, origin.y + 14), guide, 1.0)

  # The glyphs, each as a run of its own so it can rise and grow on its
  # own, and ride a slow wave.
  for i, g in run.glyphs:
    let lift = s.lift[i]
    let wave = sin(s.time * 1.6 + i.float64 * 0.7) * 3
    let at = point(origin.x + g.pos.x, origin.y - wave - lift * 26)
    let grow = 1 + 0.4 * lift
    let one = GlyphRun(font: run.font, size: run.size, glyphs: @[Glyph(id: g.id)])
    ctx.withTransform(translate(at.toVec) * scale(grow)):
      ctx.drawGlyphs(
        one, solid(hsl(0.56 + i.float64 * 0.045 + lift * 0.12, 0.75, 0.62 + lift * 0.1))
      )
      # The outline's own box, from the engine's drawing in em units.
      if lift > 0.6:
        let box = engine.cachedDrawing(run.font, g.id).path.boundingBox
        ctx.stroke(
          rect(
            box.x0 * run.size, box.y0 * run.size, box.x1 * run.size, box.y1 * run.size
          ),
          white.withAlpha((lift - 0.6) * 2),
          strokeStyle(width = 1 / grow, dashes = [3.0, 3.0]),
        )

  ctx.drawText(s.caption, point((sceneWidth - s.caption.width) / 2, 332))
  let numbers = engine.layout(
    "ascent " & $int(round(s.headline.ascent)) & "  descent " &
      $int(round(s.headline.descent)) & "  width " & $int(round(s.headline.width)),
    textStyle(s.font, 14, guide),
  )
  ctx.drawText(numbers, point((sceneWidth - numbers.width) / 2, 358))
