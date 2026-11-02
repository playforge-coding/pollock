## The `RenderContext` concept: the primitives every backend implements.
##
## This is the contract between pollock and its backends, so it stays small.
## Anything that can be built from these primitives belongs in `draw.nim`,
## which is written once for every backend. The primitive names end in `Path`
## (`fillPath`, `strokePath`, `clipPath`) so they never collide with the
## shape-taking helpers in `draw.nim`.
##
## Rules every backend follows:
##
## - Coordinates have their origin at the top left with y pointing down, in
##   logical units.
## - Paints are plain values. Backends may cache the device resources they
##   make from them.
## - Drawing calls never raise. A backend records its first failure and
##   reports it from `finish`.
## - `save` and `restore` cover the transform and the clip, nothing else.
## - `clear` paints the whole target, ignoring the transform and the clip.
## - `drawGlyphs` draws a run in the paint it is given; the positions are in
##   user space, so the transform applies to them like to a path. A backend
##   that can't make a native font from the run's bytes draws the engine's
##   outlines with `drawGlyphsAsPaths`.

import ./[color, geometry, image, paint, stroke, text]

export color, geometry, image, paint, stroke, text

type
  FillRule* = enum
    frNonZero
    frEvenOdd

  Interpolation* = enum
    ipNearest
    ipBilinear

  RenderResult* = object
    ## What `finish` reports. `ok` is false when a drawing call failed since
    ## the context was created or last finished.
    ok*: bool
    message*: string

  RenderContext* = concept
    proc clear(ctx: var Self, color: Color)
    proc fillPath(ctx: var Self, path: BezPath, paint: Paint, rule: FillRule)
    proc strokePath(ctx: var Self, path: BezPath, paint: Paint, style: StrokeStyle)
    proc clipPath(ctx: var Self, path: BezPath, rule: FillRule)
    proc save(ctx: var Self)
    proc restore(ctx: var Self)
    proc transform(ctx: var Self, affine: Affine)
    proc currentTransform(ctx: Self): Affine
    proc drawImage(ctx: var Self, image: ImageData, dst: Rect, interp: Interpolation)
    proc drawGlyphs(ctx: var Self, run: GlyphRun, paint: Paint)
    proc finish(ctx: var Self): RenderResult

func success*(): RenderResult =
  RenderResult(ok: true)

func failure*(message: string): RenderResult =
  RenderResult(ok: false, message: message)

proc drawGlyphsAsPaths*[C, E](ctx: var C, engine: E, run: GlyphRun, paint: Paint) =
  ## Draws a glyph run with the primitives every backend has: outlines and
  ## color layers with `fillPath`, bitmaps with `drawImage`. The engine's
  ## drawings are in em units and cached on the font; each one is scaled
  ## by the run's size and moved to its glyph's position, so the paint
  ## stays in user space. Backends without native glyph drawing call this
  ## from their `drawGlyphs`.
  mixin fillPath, drawImage
  if run.font == nil or run.size <= 0:
    return
  for g in run.glyphs:
    let drawing = engine.cachedDrawing(run.font, g.id)
    let m = translate(g.pos.toVec) * scale(run.size)
    case drawing.kind
    of gkOutline:
      if not drawing.path.isEmpty:
        ctx.fillPath(m.transform(drawing.path), paint, frNonZero)
    of gkLayers:
      for layer in drawing.layers:
        let layerPaint = if layer.usesRunPaint: paint else: layer.paint
        ctx.fillPath(m.transform(layer.path), layerPaint, frNonZero)
    of gkBitmap:
      ctx.drawImage(drawing.image, m.transform(drawing.bounds), ipBilinear)
