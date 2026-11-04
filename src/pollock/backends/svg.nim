## The SVG backend: builds an SVG document as a string. Pure Nim, so it runs
## on every target, and it is the easiest way to see what a drawing does.
##
## Transforms go on each element as a `matrix(...)` attribute. Clips become
## `<clipPath>` definitions referenced from a `<g>` that stays open until the
## matching `restore`; `clear` closes the open groups around its rectangle and
## reopens them, so it ignores the clip as the contract says. Gradients go in
## `<defs>` with `userSpaceOnUse`
## coordinates, which SVG resolves in the referencing element's own space,
## so they line up with the element's transform. Images are embedded as PNG
## data URIs. Text is one `<path>` per glyph from the engine's outlines.
##
## The context is generic over its text engine: `SvgContext` pairs it with
## the default engine, and `newSvgContext(width, height, engine)` makes an
## `SvgContextOf` over any other.

import std/[base64, math, strutils, tables]
import ../[context, png]

export context

importTextEngine()

type
  SvgState = object
    transform: Affine
    clips: seq[string] ## Ids of the open `<g clip-path>` groups, outermost first.

  SvgContextOf*[E] = object
    width*, height*: float64
    engine*: E ## The text engine whose glyphs it draws.
    defs: seq[string]
    body: seq[string]
    gradients: Table[string, string]
      ## The markup of each gradient already in `defs`, without its id, to the id.
    state: SvgState
    stack: seq[SvgState]
    nextId: int

  SvgContext* = SvgContextOf[typeof(defaultTextEngine())]
    ## The SVG backend with the default text engine.

proc newSvgContext*[E](width, height: float64, engine: E): SvgContextOf[E] =
  ## A document of the given size in user units, drawing text with `engine`.
  SvgContextOf[E](
    width: width,
    height: height,
    engine: engine,
    state: SvgState(transform: affineIdentity),
  )

proc newSvgContext*(width, height: float64): SvgContext =
  ## A document of the given size in user units, with the default text
  ## engine.
  newSvgContext(width, height, defaultTextEngine())

func fmt(x: float64): string =
  ## Short decimal: integers without a point, otherwise rounded to about
  ## seven significant digits (but never more coarsely than to three decimal
  ## places), with trailing zeros removed, so 1.2 stays `1.2`. Small values
  ## keep their precision, which matters for transform coefficients: a scale
  ## of 0.0004 must not round to 0.
  if abs(x) < 1e-12:
    return "0"
  if x == round(x) and abs(x) < 1e15:
    return $int(x)
  let decimals = min(15, max(3, 6 - int(floor(log10(abs(x))))))
  result = formatFloat(x, ffDecimal, decimals)
  result = result.strip(leading = false, chars = {'0'})
  result = result.strip(leading = false, chars = {'.'})

func pathData(path: BezPath): string =
  for el in path.elements:
    if result.len > 0:
      result.add ' '
    case el.kind
    of peMoveTo:
      result.add "M" & fmt(el.to.x) & " " & fmt(el.to.y)
    of peLineTo:
      result.add "L" & fmt(el.to.x) & " " & fmt(el.to.y)
    of peQuadTo:
      result.add "Q" & fmt(el.ctrl.x) & " " & fmt(el.ctrl.y) & " " & fmt(el.quadEnd.x) &
        " " & fmt(el.quadEnd.y)
    of peCubicTo:
      result.add "C" & fmt(el.ctrl1.x) & " " & fmt(el.ctrl1.y) & " " & fmt(el.ctrl2.x) &
        " " & fmt(el.ctrl2.y) & " " & fmt(el.cubicEnd.x) & " " & fmt(el.cubicEnd.y)
    of peArcTo:
      # The same parameterization as SVG's, with the rotation in degrees.
      result.add "A" & fmt(el.radii.x) & " " & fmt(el.radii.y) & " " &
        fmt(radToDeg(el.rotation)) & " " & (if el.largeArc: "1" else: "0") & " " &
        (if el.sweep: "1" else: "0") & " " & fmt(el.arcEnd.x) & " " & fmt(el.arcEnd.y)
    of peClosePath:
      result.add "Z"

func transformAttr(m: Affine): string =
  if m.isIdentity:
    ""
  else:
    " transform=\"matrix(" & fmt(m.a) & " " & fmt(m.b) & " " & fmt(m.c) & " " & fmt(m.d) &
      " " & fmt(m.e) & " " & fmt(m.f) & ")\""

func colorHex(c: Color): string =
  c.withAlpha(1.0).toHex

func spreadMethod(e: Extend): string =
  case e
  of exPad: "pad"
  of exRepeat: "repeat"
  of exReflect: "reflect"

proc newId[E](ctx: var SvgContextOf[E], prefix: string): string =
  inc ctx.nextId
  prefix & $ctx.nextId

proc stopsMarkup(stops: seq[GradientStop]): string =
  for s in stops:
    result.add "<stop offset=\"" & fmt(s.offset) & "\" stop-color=\"" & colorHex(
      s.color
    ) & "\""
    if s.color.a < 1.0:
      result.add " stop-opacity=\"" & fmt(s.color.a) & "\""
    result.add "/>"

proc gradientId[E](ctx: var SvgContextOf[E], paint: Paint): string =
  ## The id of the gradient's definition, added to `defs` the first time
  ## the paint is used, so text (one path per glyph) doesn't repeat it.
  ## Gradients are looked up by their markup without the id, so paints that
  ## would be written the same way share a definition.
  var element, markup: string
  case paint.kind
  of pkLinearGradient:
    element = "linearGradient"
    markup =
      " gradientUnits=\"userSpaceOnUse\" x1=\"" & fmt(paint.start.x) & "\" y1=\"" &
      fmt(paint.start.y) & "\" x2=\"" & fmt(paint.stop.x) & "\" y2=\"" &
      fmt(paint.stop.y) & "\" spreadMethod=\"" & spreadMethod(paint.linearExtend) & "\">" &
      stopsMarkup(paint.linearStops)
  of pkRadialGradient:
    element = "radialGradient"
    markup =
      " gradientUnits=\"userSpaceOnUse\" cx=\"" & fmt(paint.center.x) & "\" cy=\"" &
      fmt(paint.center.y) & "\" r=\"" & fmt(max(0.0, paint.radius)) &
      "\" spreadMethod=\"" & spreadMethod(paint.radialExtend) & "\">" &
      stopsMarkup(paint.radialStops)
  of pkSolid:
    return ""
  let key = element & markup
  result = ctx.gradients.getOrDefault(key)
  if result.len == 0:
    result = ctx.newId("g")
    ctx.defs.add "<" & element & " id=\"" & result & "\"" & markup & "</" & element & ">"
    ctx.gradients[key] = result

proc paintAttrs[E](ctx: var SvgContextOf[E], paint: Paint, attr: string): string =
  ## `fill="..."` or `stroke="..."` plus the matching opacity attribute,
  ## defining a gradient when needed.
  case paint.kind
  of pkSolid:
    result = " " & attr & "=\"" & colorHex(paint.color) & "\""
    if paint.color.a < 1.0:
      result.add " " & attr & "-opacity=\"" & fmt(paint.color.a) & "\""
  of pkLinearGradient, pkRadialGradient:
    result = " " & attr & "=\"url(#" & ctx.gradientId(paint) & ")\""

proc openClip[E](ctx: var SvgContextOf[E], id: string) =
  ctx.body.add "<g clip-path=\"url(#" & id & ")\">"

proc clear*[E](ctx: var SvgContextOf[E], color: Color) =
  ## Paints the whole picture, ignoring the clip: the open clip groups are
  ## closed around the rectangle and reopened after it.
  let attrs = ctx.paintAttrs(solid(color), "fill")
  for _ in ctx.state.clips:
    ctx.body.add "</g>"
  ctx.body.add "<rect width=\"" & fmt(ctx.width) & "\" height=\"" & fmt(ctx.height) &
    "\"" & attrs & "/>"
  for id in ctx.state.clips:
    ctx.openClip(id)

proc fillPath*[E](
    ctx: var SvgContextOf[E], path: BezPath, paint: Paint, rule: FillRule
) =
  var el = "<path d=\"" & pathData(path) & "\"" & ctx.paintAttrs(paint, "fill")
  if rule == frEvenOdd:
    el.add " fill-rule=\"evenodd\""
  el.add transformAttr(ctx.state.transform)
  el.add "/>"
  ctx.body.add el

proc strokePath*[E](
    ctx: var SvgContextOf[E], path: BezPath, paint: Paint, style: StrokeStyle
) =
  var el =
    "<path d=\"" & pathData(path) & "\" fill=\"none\"" & ctx.paintAttrs(paint, "stroke")
  el.add " stroke-width=\"" & fmt(style.width) & "\""
  case style.cap
  of lcButt:
    discard
  of lcRound:
    el.add " stroke-linecap=\"round\""
  of lcSquare:
    el.add " stroke-linecap=\"square\""
  case style.join
  of ljMiter:
    discard
  of ljRound:
    el.add " stroke-linejoin=\"round\""
  of ljBevel:
    el.add " stroke-linejoin=\"bevel\""
  if style.join == ljMiter:
    # SVG ignores a miter limit below 1, but every miter is at least 1 long,
    # so such a limit bevels every join.
    if style.miterLimit < 1.0:
      el.add " stroke-linejoin=\"bevel\""
    elif style.miterLimit != 4.0:
      el.add " stroke-miterlimit=\"" & fmt(style.miterLimit) & "\""
  if style.isDashed:
    var dashes: seq[string]
    for d in style.dashes:
      dashes.add fmt(max(0.0, d))
    el.add " stroke-dasharray=\"" & dashes.join(" ") & "\""
    if style.dashOffset != 0:
      el.add " stroke-dashoffset=\"" & fmt(style.dashOffset) & "\""
  el.add transformAttr(ctx.state.transform)
  el.add "/>"
  ctx.body.add el

proc clipPath*[E](ctx: var SvgContextOf[E], path: BezPath, rule: FillRule) =
  let id = ctx.newId("c")
  var inner = "<path d=\"" & pathData(path) & "\""
  if rule == frEvenOdd:
    inner.add " clip-rule=\"evenodd\""
  inner.add transformAttr(ctx.state.transform)
  inner.add "/>"
  ctx.defs.add "<clipPath id=\"" & id & "\">" & inner & "</clipPath>"
  ctx.openClip(id)
  ctx.state.clips.add id

proc save*[E](ctx: var SvgContextOf[E]) =
  ctx.stack.add ctx.state

proc restore*[E](ctx: var SvgContextOf[E]) =
  if ctx.stack.len == 0:
    return
  let prev = ctx.stack.pop()
  for _ in prev.clips.len ..< ctx.state.clips.len:
    ctx.body.add "</g>"
  ctx.state = prev

proc transform*[E](ctx: var SvgContextOf[E], affine: Affine) =
  ctx.state.transform = ctx.state.transform * affine

proc currentTransform*[E](ctx: SvgContextOf[E]): Affine =
  ctx.state.transform

proc drawImage*[E](
    ctx: var SvgContextOf[E], image: ImageData, dst: Rect, interp: Interpolation
) =
  if image.isEmpty:
    return
  var el =
    "<image x=\"" & fmt(dst.x0) & "\" y=\"" & fmt(dst.y0) & "\" width=\"" &
    fmt(dst.width) & "\" height=\"" & fmt(dst.height) & "\" preserveAspectRatio=\"none\""
  if interp == ipNearest:
    el.add " style=\"image-rendering:pixelated\""
  el.add transformAttr(ctx.state.transform)
  el.add " href=\"data:image/png;base64," & encode(encodePng(image)) & "\"/>"
  ctx.body.add el

proc drawGlyphs*[E](ctx: var SvgContextOf[E], run: GlyphRun, paint: Paint) =
  ## One path per glyph, from the engine's outlines.
  ctx.drawGlyphsAsPaths(ctx.engine, run, paint)

proc finish*[E](ctx: var SvgContextOf[E]): RenderResult =
  success()

proc toSvg*[E](ctx: SvgContextOf[E]): string =
  ## The document so far. Clips still open are closed in the output.
  result =
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" & fmt(ctx.width) &
    "\" height=\"" & fmt(ctx.height) & "\" viewBox=\"0 0 " & fmt(ctx.width) & " " &
    fmt(ctx.height) & "\">\n"
  if ctx.defs.len > 0:
    result.add "  <defs>\n"
    for d in ctx.defs:
      result.add "    " & d & "\n"
    result.add "  </defs>\n"
  for el in ctx.body:
    result.add "  " & el & "\n"
  for _ in ctx.state.clips:
    result.add "  </g>\n"
  result.add "</svg>\n"

static:
  doAssert SvgContext is RenderContext
