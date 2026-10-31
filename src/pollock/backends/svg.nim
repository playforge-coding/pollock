## The SVG backend: builds an SVG document as a string. Pure Nim, so it runs
## on every target, and it is the easiest way to see what a drawing does.
##
## Transforms go on each element as a `matrix(...)` attribute. Clips become
## `<clipPath>` definitions referenced from a `<g>` that stays open until the
## matching `restore`. Gradients go in `<defs>` with `userSpaceOnUse`
## coordinates, which SVG resolves in the referencing element's own space,
## so they line up with the element's transform. Images are embedded as PNG
## data URIs.

import std/[base64, math, strutils]
import ../[context, png]

export context

type
  SvgState = object
    transform: Affine
    groups: int ## `<g>` elements open at this level.

  SvgContext* = object
    width*, height*: float64
    defs: seq[string]
    body: seq[string]
    state: SvgState
    stack: seq[SvgState]
    nextId: int

proc newSvgContext*(width, height: float64): SvgContext =
  SvgContext(width: width, height: height, state: SvgState(transform: affineIdentity))

func fmt(x: float64): string =
  ## Short decimal: integers without a point, otherwise about seven
  ## significant digits and never fewer than three places. Small values keep
  ## their precision, which matters for transform coefficients: a scale of
  ## 0.0004 must not round to 0.
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

proc newId(ctx: var SvgContext, prefix: string): string =
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

proc paintAttrs(ctx: var SvgContext, paint: Paint, attr: string): string =
  ## `fill="..."` or `stroke="..."` plus the matching opacity attribute,
  ## defining a gradient when needed.
  case paint.kind
  of pkSolid:
    result = " " & attr & "=\"" & colorHex(paint.color) & "\""
    if paint.color.a < 1.0:
      result.add " " & attr & "-opacity=\"" & fmt(paint.color.a) & "\""
  of pkLinearGradient:
    let id = ctx.newId("g")
    ctx.defs.add "<linearGradient id=\"" & id &
      "\" gradientUnits=\"userSpaceOnUse\" x1=\"" & fmt(paint.start.x) & "\" y1=\"" &
      fmt(paint.start.y) & "\" x2=\"" & fmt(paint.stop.x) & "\" y2=\"" &
      fmt(paint.stop.y) & "\" spreadMethod=\"" & spreadMethod(paint.linearExtend) & "\">" &
      stopsMarkup(paint.linearStops) & "</linearGradient>"
    result = " " & attr & "=\"url(#" & id & ")\""
  of pkRadialGradient:
    let id = ctx.newId("g")
    ctx.defs.add "<radialGradient id=\"" & id &
      "\" gradientUnits=\"userSpaceOnUse\" cx=\"" & fmt(paint.center.x) & "\" cy=\"" &
      fmt(paint.center.y) & "\" r=\"" & fmt(max(0.0, paint.radius)) &
      "\" spreadMethod=\"" & spreadMethod(paint.radialExtend) & "\">" &
      stopsMarkup(paint.radialStops) & "</radialGradient>"
    result = " " & attr & "=\"url(#" & id & ")\""

proc clear*(ctx: var SvgContext, color: Color) =
  ## Paints the whole picture. Inside an open clip the SVG rectangle is still
  ## clipped; the contract's "ignores the clip" holds only at the top level.
  let attrs = ctx.paintAttrs(solid(color), "fill")
  ctx.body.add "<rect width=\"" & fmt(ctx.width) & "\" height=\"" & fmt(ctx.height) &
    "\"" & attrs & "/>"

proc fillPath*(ctx: var SvgContext, path: BezPath, paint: Paint, rule: FillRule) =
  var el = "<path d=\"" & pathData(path) & "\"" & ctx.paintAttrs(paint, "fill")
  if rule == frEvenOdd:
    el.add " fill-rule=\"evenodd\""
  el.add transformAttr(ctx.state.transform)
  el.add "/>"
  ctx.body.add el

proc strokePath*(ctx: var SvgContext, path: BezPath, paint: Paint, style: StrokeStyle) =
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

proc clipPath*(ctx: var SvgContext, path: BezPath, rule: FillRule) =
  let id = ctx.newId("c")
  var inner = "<path d=\"" & pathData(path) & "\""
  if rule == frEvenOdd:
    inner.add " clip-rule=\"evenodd\""
  inner.add transformAttr(ctx.state.transform)
  inner.add "/>"
  ctx.defs.add "<clipPath id=\"" & id & "\">" & inner & "</clipPath>"
  ctx.body.add "<g clip-path=\"url(#" & id & ")\">"
  inc ctx.state.groups

proc save*(ctx: var SvgContext) =
  ctx.stack.add ctx.state

proc restore*(ctx: var SvgContext) =
  if ctx.stack.len == 0:
    return
  let prev = ctx.stack.pop()
  for _ in prev.groups ..< ctx.state.groups:
    ctx.body.add "</g>"
  ctx.state = prev

proc transform*(ctx: var SvgContext, affine: Affine) =
  ctx.state.transform = ctx.state.transform * affine

proc currentTransform*(ctx: SvgContext): Affine =
  ctx.state.transform

proc drawImage*(
    ctx: var SvgContext, image: ImageData, dst: Rect, interp: Interpolation
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

proc finish*(ctx: var SvgContext): RenderResult =
  success()

proc toSvg*(ctx: SvgContext): string =
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
  for _ in 0 ..< ctx.state.groups:
    result.add "  </g>\n"
  result.add "</svg>\n"

static:
  doAssert SvgContext is RenderContext
