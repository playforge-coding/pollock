## The Cairo backend: draws through libcairo. Cairo is found through
## `pkg-config` at compile time, so it needs the development package
## (`libcairo2-dev` on Debian, `cairo` from Homebrew). It compiles under the
## C and Objective-C targets, not JavaScript, and not in NimScript, whose VM
## can't call C functions.
##
## A `CairoContext` either owns an offscreen ARGB32 image surface
## (`newCairoContext(width, height)`), which `toImage` reads back, or wraps a
## `cairo_t` the caller already has (`newCairoContext(cr)`), such as the one
## GTK hands a draw function. In the second case pollock's user space is the
## cairo_t's user space at the time it was wrapped.
##
## Cairo's own state stack holds the clip: `save` and `restore` call
## `cairo_save` and `cairo_restore`, and `clear` resets the clip inside a
## save/restore pair. The transform is mirrored in Nim and set on the
## cairo_t before every drawing call, so a singular or non-finite transform
## (which would put the cairo_t into a permanent error state) can be skipped
## instead. Each drawing call runs inside its own save/restore pair, so a
## wrapped cairo_t keeps the matrix, source and line settings its owner set.
## Cairo's
## errors are sticky: once a call fails the cairo_t stays unusable, so
## `finish` reports the failure and the caller makes a new context.
##
## Bindings cover only what the backend calls.

import std/[math, strutils]
import ../context

export context

when defined(js):
  {.error: "the Cairo backend needs the C target".}
elif defined(nimscript):
  {.
    error:
      "the Cairo backend calls libcairo, which NimScript can't do; compile a .nim " &
      "file with `nim c -r` instead, or use the CPU backend in a script"
  .}

const cairoCflags = gorgeEx("pkg-config --cflags cairo")
const cairoLibs = gorgeEx("pkg-config --libs cairo")
when cairoCflags.exitCode != 0 or cairoLibs.exitCode != 0:
  {.
    error:
      "the Cairo backend needs cairo through pkg-config: " & cairoCflags.output &
      cairoLibs.output
  .}
{.passc: cairoCflags.output.strip.}
{.passl: cairoLibs.output.strip.}

# Bindings

const cairoHeader = "cairo.h"

type
  CairoObj {.importc: "cairo_t", header: cairoHeader, incompleteStruct.} = object
  CairoHandle = ptr CairoObj
  CairoSurfaceObj {.importc: "cairo_surface_t", header: cairoHeader, incompleteStruct.} = object
  CairoSurface = ptr CairoSurfaceObj
  CairoPatternObj {.importc: "cairo_pattern_t", header: cairoHeader, incompleteStruct.} = object
  CairoPattern = ptr CairoPatternObj
  CairoMatrix {.importc: "cairo_matrix_t", header: cairoHeader, bycopy.} = object
    xx, yx, xy, yy, x0, y0: cdouble

const
  cairoStatusSuccess = 0.cint
  cairoFormatArgb32 = 0.cint
  cairoFormatRgb24 = 1.cint
  cairoSurfaceTypeImage = 0.cint
  cairoOperatorSource = 1.cint
  cairoFillRuleWinding = 0.cint
  cairoFillRuleEvenOdd = 1.cint
  cairoLineCapButt = 0.cint
  cairoLineCapRound = 1.cint
  cairoLineCapSquare = 2.cint
  cairoLineJoinMiter = 0.cint
  cairoLineJoinRound = 1.cint
  cairoLineJoinBevel = 2.cint
  cairoExtendRepeat = 1.cint
  cairoExtendReflect = 2.cint
  cairoExtendPad = 3.cint
  cairoFilterNearest = 3.cint
  cairoFilterBilinear = 4.cint

{.push cdecl, header: cairoHeader.}
proc cairoImageSurfaceCreate(
  format: cint, width, height: cint
): CairoSurface {.importc: "cairo_image_surface_create".}

proc cairoImageSurfaceGetData(
  surface: CairoSurface
): ptr UncheckedArray[uint8] {.importc: "cairo_image_surface_get_data".}

proc cairoImageSurfaceGetWidth(
  surface: CairoSurface
): cint {.importc: "cairo_image_surface_get_width".}

proc cairoImageSurfaceGetHeight(
  surface: CairoSurface
): cint {.importc: "cairo_image_surface_get_height".}

proc cairoImageSurfaceGetStride(
  surface: CairoSurface
): cint {.importc: "cairo_image_surface_get_stride".}

proc cairoImageSurfaceGetFormat(
  surface: CairoSurface
): cint {.importc: "cairo_image_surface_get_format".}

proc cairoSurfaceGetType(
  surface: CairoSurface
): cint {.importc: "cairo_surface_get_type".}

proc cairoSurfaceStatus(surface: CairoSurface): cint {.importc: "cairo_surface_status".}
proc cairoSurfaceFlush(surface: CairoSurface) {.importc: "cairo_surface_flush".}
proc cairoSurfaceMarkDirty(
  surface: CairoSurface
) {.importc: "cairo_surface_mark_dirty".}

proc cairoSurfaceDestroy(surface: CairoSurface) {.importc: "cairo_surface_destroy".}

proc cairoCreate(target: CairoSurface): CairoHandle {.importc: "cairo_create".}
proc cairoReference(cr: CairoHandle): CairoHandle {.importc: "cairo_reference".}
proc cairoDestroy(cr: CairoHandle) {.importc: "cairo_destroy".}
proc cairoStatus(cr: CairoHandle): cint {.importc: "cairo_status".}
proc cairoStatusToString(status: cint): cstring {.importc: "cairo_status_to_string".}
proc cairoGetTarget(cr: CairoHandle): CairoSurface {.importc: "cairo_get_target".}
proc cairoSave(cr: CairoHandle) {.importc: "cairo_save".}
proc cairoRestore(cr: CairoHandle) {.importc: "cairo_restore".}
proc cairoGetMatrix(
  cr: CairoHandle, matrix: ptr CairoMatrix
) {.importc: "cairo_get_matrix".}

proc cairoSetMatrix(
  cr: CairoHandle, matrix: ptr CairoMatrix
) {.importc: "cairo_set_matrix".}

proc cairoIdentityMatrix(cr: CairoHandle) {.importc: "cairo_identity_matrix".}
proc cairoNewPath(cr: CairoHandle) {.importc: "cairo_new_path".}
proc cairoMoveTo(cr: CairoHandle, x, y: cdouble) {.importc: "cairo_move_to".}
proc cairoLineTo(cr: CairoHandle, x, y: cdouble) {.importc: "cairo_line_to".}
proc cairoCurveTo(
  cr: CairoHandle, x1, y1, x2, y2, x3, y3: cdouble
) {.importc: "cairo_curve_to".}

proc cairoClosePath(cr: CairoHandle) {.importc: "cairo_close_path".}
proc cairoRectangle(
  cr: CairoHandle, x, y, width, height: cdouble
) {.importc: "cairo_rectangle".}

proc cairoSetFillRule(cr: CairoHandle, rule: cint) {.importc: "cairo_set_fill_rule".}
proc cairoGetFillRule(cr: CairoHandle): cint {.importc: "cairo_get_fill_rule".}
proc cairoFill(cr: CairoHandle) {.importc: "cairo_fill".}
proc cairoClip(cr: CairoHandle) {.importc: "cairo_clip".}
proc cairoResetClip(cr: CairoHandle) {.importc: "cairo_reset_clip".}
proc cairoSetLineWidth(
  cr: CairoHandle, width: cdouble
) {.importc: "cairo_set_line_width".}

proc cairoSetLineCap(cr: CairoHandle, cap: cint) {.importc: "cairo_set_line_cap".}
proc cairoSetLineJoin(cr: CairoHandle, join: cint) {.importc: "cairo_set_line_join".}
proc cairoSetMiterLimit(
  cr: CairoHandle, limit: cdouble
) {.importc: "cairo_set_miter_limit".}

proc cairoSetDash(
  cr: CairoHandle, dashes: ptr cdouble, count: cint, offset: cdouble
) {.importc: "cairo_set_dash".}

proc cairoStroke(cr: CairoHandle) {.importc: "cairo_stroke".}
proc cairoSetOperator(cr: CairoHandle, op: cint) {.importc: "cairo_set_operator".}
proc cairoPaint(cr: CairoHandle) {.importc: "cairo_paint".}
proc cairoSetSourceRgba(
  cr: CairoHandle, r, g, b, a: cdouble
) {.importc: "cairo_set_source_rgba".}

proc cairoSetSource(
  cr: CairoHandle, source: CairoPattern
) {.importc: "cairo_set_source".}

proc cairoPatternCreateLinear(
  x0, y0, x1, y1: cdouble
): CairoPattern {.importc: "cairo_pattern_create_linear".}

proc cairoPatternCreateRadial(
  cx0, cy0, r0, cx1, cy1, r1: cdouble
): CairoPattern {.importc: "cairo_pattern_create_radial".}

proc cairoPatternCreateForSurface(
  surface: CairoSurface
): CairoPattern {.importc: "cairo_pattern_create_for_surface".}

proc cairoPatternAddColorStopRgba(
  pattern: CairoPattern, offset, r, g, b, a: cdouble
) {.importc: "cairo_pattern_add_color_stop_rgba".}

proc cairoPatternSetExtend(
  pattern: CairoPattern, extend: cint
) {.importc: "cairo_pattern_set_extend".}

proc cairoPatternSetFilter(
  pattern: CairoPattern, filter: cint
) {.importc: "cairo_pattern_set_filter".}

proc cairoPatternSetMatrix(
  pattern: CairoPattern, matrix: ptr CairoMatrix
) {.importc: "cairo_pattern_set_matrix".}

proc cairoPatternDestroy(pattern: CairoPattern) {.importc: "cairo_pattern_destroy".}
{.pop.}

# The context

type
  CairoState = object
    transform: Affine

  CairoContext* = object
    width*, height*: int
      ## The target's size in pixels; 0 when it isn't an image surface.
    cr: CairoHandle
    surface: CairoSurface ## The owned offscreen surface, or nil when wrapping.
    base: CairoMatrix ## The cairo_t's matrix when the context was made.
    state: CairoState
    stack: seq[CairoState]
    error: string

proc `=copy`(a: var CairoContext, b: CairoContext) {.error.}

template releaseHandles(ctx: CairoContext) =
  if ctx.cr != nil:
    # Pop the levels a missing `restore` left behind, so a wrapped cairo_t
    # goes back to its owner with the stack (and clip) it came with.
    for _ in 0 ..< ctx.stack.len:
      cairoRestore(ctx.cr)
    cairoDestroy(ctx.cr)
  if ctx.surface != nil:
    cairoSurfaceDestroy(ctx.surface)

when defined(gcDestructors):
  proc `=destroy`(ctx: CairoContext) =
    releaseHandles(ctx)
    `=destroy`(ctx.stack)
    `=destroy`(ctx.error)

else:
  # refc only accepts the older `var` signature, and its GC frees the seq
  # and the string. Clearing the handles keeps a second call harmless.
  proc `=destroy`(ctx: var CairoContext) =
    releaseHandles(ctx)
    ctx.cr = nil
    ctx.surface = nil

proc fail(ctx: var CairoContext, message: string) =
  if ctx.error.len == 0:
    ctx.error = message

proc checkStatus(ctx: var CairoContext) =
  let status = cairoStatus(ctx.cr)
  if status != cairoStatusSuccess:
    ctx.fail($cairoStatusToString(status))

proc newCairoContext*(cr: pointer): CairoContext =
  ## Wraps a `cairo_t` from any other binding, keeping a reference to it.
  ## pollock's user space is the cairo_t's user space at this point; `toImage`
  ## works when its target is an image surface. Drawing calls leave the
  ## cairo_t's matrix, source and line settings as they found them.
  doAssert cr != nil, "newCairoContext needs a cairo_t, not nil"
  result = CairoContext(
    cr: cairoReference(cast[CairoHandle](cr)),
    state: CairoState(transform: affineIdentity),
  )
  cairoGetMatrix(result.cr, addr result.base)
  let target = cairoGetTarget(result.cr)
  if cairoSurfaceGetType(target) == cairoSurfaceTypeImage:
    result.width = cairoImageSurfaceGetWidth(target).int
    result.height = cairoImageSurfaceGetHeight(target).int
  result.checkStatus()

proc newCairoContext*(width, height: int): CairoContext =
  ## A transparent black ARGB32 image surface of the given size in pixels.
  let surface = cairoImageSurfaceCreate(cairoFormatArgb32, width.cint, height.cint)
  let cr = cairoCreate(surface)
  result = CairoContext(
    width: width,
    height: height,
    cr: cr,
    surface: surface,
    state: CairoState(transform: affineIdentity),
  )
  cairoGetMatrix(cr, addr result.base)
  let status = cairoSurfaceStatus(surface)
  if status != cairoStatusSuccess:
    result.fail($cairoStatusToString(status))
  result.checkStatus()

proc cairoHandle*(ctx: CairoContext): pointer =
  ## The underlying `cairo_t`, for calls the backend doesn't cover. It stays
  ## owned by the context.
  ctx.cr

func toCairo(m: Affine): CairoMatrix =
  CairoMatrix(xx: m.a, yx: m.b, xy: m.c, yy: m.d, x0: m.e, y0: m.f)

func toAffine(m: CairoMatrix): Affine =
  affine(m.xx, m.yx, m.xy, m.yy, m.x0, m.y0)

func isUsable(m: Affine): bool =
  ## Finite and invertible. Cairo rejects any other matrix by putting the
  ## cairo_t (or pattern) into a permanent error state.
  for v in [m.a, m.b, m.c, m.d, m.e, m.f, m.determinant]:
    if v.classify in {fcNan, fcInf, fcNegInf}:
      return false
  m.determinant != 0

proc applyTransform(ctx: var CairoContext): bool =
  ## Sets the cairo_t's matrix to the base matrix times the current
  ## transform. False when the result is singular or not finite, which draws
  ## nothing and would put the cairo_t into a permanent error state.
  let m = ctx.base.toAffine * ctx.state.transform
  if not m.isUsable:
    return false
  var cm = m.toCairo
  cairoSetMatrix(ctx.cr, addr cm)
  true

func toCubic(p0, ctrl, p1: Point): tuple[c1, c2: Point] =
  ## The cubic control points of a quadratic curve, which Cairo lacks.
  (p0 + (ctrl - p0) * (2.0 / 3.0), p1 + (ctrl - p1) * (2.0 / 3.0))

proc buildPath(ctx: var CairoContext, path: BezPath) =
  cairoNewPath(ctx.cr)
  var current, start: Point
  for el in path.elements:
    case el.kind
    of peMoveTo:
      cairoMoveTo(ctx.cr, el.to.x, el.to.y)
      current = el.to
      start = el.to
    of peLineTo:
      cairoLineTo(ctx.cr, el.to.x, el.to.y)
      current = el.to
    of peQuadTo:
      let (c1, c2) = toCubic(current, el.ctrl, el.quadEnd)
      cairoCurveTo(ctx.cr, c1.x, c1.y, c2.x, c2.y, el.quadEnd.x, el.quadEnd.y)
      current = el.quadEnd
    of peCubicTo:
      cairoCurveTo(
        ctx.cr, el.ctrl1.x, el.ctrl1.y, el.ctrl2.x, el.ctrl2.y, el.cubicEnd.x,
        el.cubicEnd.y,
      )
      current = el.cubicEnd
    of peClosePath:
      cairoClosePath(ctx.cr)
      current = start

func toCairo(rule: FillRule): cint =
  case rule
  of frNonZero: cairoFillRuleWinding
  of frEvenOdd: cairoFillRuleEvenOdd

func toCairo(extend: Extend): cint =
  case extend
  of exPad: cairoExtendPad
  of exRepeat: cairoExtendRepeat
  of exReflect: cairoExtendReflect

func toCairo(cap: LineCap): cint =
  case cap
  of lcButt: cairoLineCapButt
  of lcRound: cairoLineCapRound
  of lcSquare: cairoLineCapSquare

func toCairo(join: LineJoin): cint =
  case join
  of ljMiter: cairoLineJoinMiter
  of ljRound: cairoLineJoinRound
  of ljBevel: cairoLineJoinBevel

func toCairo(interp: Interpolation): cint =
  case interp
  of ipNearest: cairoFilterNearest
  of ipBilinear: cairoFilterBilinear

proc setSolid(ctx: var CairoContext, color: Color) =
  let c = color.clamped
  cairoSetSourceRgba(ctx.cr, c.r, c.g, c.b, c.a)

proc addStops(pattern: CairoPattern, stops: seq[GradientStop]) =
  for s in stops:
    let c = s.color.clamped
    cairoPatternAddColorStopRgba(pattern, s.offset, c.r, c.g, c.b, c.a)

proc setSource(ctx: var CairoContext, paint: Paint) =
  ## Sets the paint as the source. Must run after `applyTransform`: Cairo
  ## fixes a pattern's user space at the time it becomes the source.
  case paint.kind
  of pkSolid:
    ctx.setSolid(paint.color)
  of pkLinearGradient:
    if (paint.stop - paint.start).lengthSquared <= 0:
      # No direction: paint the last stop, as SVG specifies.
      ctx.setSolid(colorAt(paint.linearStops, 1.0))
    else:
      let pattern = cairoPatternCreateLinear(
        paint.start.x, paint.start.y, paint.stop.x, paint.stop.y
      )
      pattern.addStops(paint.linearStops)
      cairoPatternSetExtend(pattern, paint.linearExtend.toCairo)
      cairoSetSource(ctx.cr, pattern)
      cairoPatternDestroy(pattern)
  of pkRadialGradient:
    if paint.radius <= 0:
      ctx.setSolid(colorAt(paint.radialStops, 1.0))
    else:
      let pattern = cairoPatternCreateRadial(
        paint.center.x, paint.center.y, 0, paint.center.x, paint.center.y, paint.radius
      )
      pattern.addStops(paint.radialStops)
      cairoPatternSetExtend(pattern, paint.radialExtend.toCairo)
      cairoSetSource(ctx.cr, pattern)
      cairoPatternDestroy(pattern)

proc clear*(ctx: var CairoContext, color: Color) =
  ## Replaces the whole surface with `color` (the SOURCE operator, so a
  ## transparent color clears). Resets Cairo's clip for the duration, which
  ## also drops any clip a wrapped cairo_t came with.
  cairoSave(ctx.cr)
  cairoResetClip(ctx.cr)
  cairoIdentityMatrix(ctx.cr)
  cairoSetOperator(ctx.cr, cairoOperatorSource)
  ctx.setSolid(color)
  cairoPaint(ctx.cr)
  cairoRestore(ctx.cr)
  ctx.checkStatus()

template drawing(ctx: var CairoContext, body: untyped) =
  ## Runs a drawing call between `cairo_save` and `cairo_restore`, so the
  ## matrix, source and line settings it sets don't outlive it, which leaves
  ## a wrapped cairo_t's state as its owner set it. The body is skipped when
  ## the transform can't be used.
  cairoSave(ctx.cr)
  if ctx.applyTransform():
    body
  cairoRestore(ctx.cr)
  ctx.checkStatus()

proc setStrokeStyle(ctx: var CairoContext, style: StrokeStyle) =
  cairoSetLineWidth(ctx.cr, style.width)
  cairoSetLineCap(ctx.cr, style.cap.toCairo)
  cairoSetLineJoin(ctx.cr, style.join.toCairo)
  cairoSetMiterLimit(ctx.cr, style.miterLimit)
  if style.isDashed:
    # Cairo rejects negative lengths, so they are clamped like everywhere
    # else in pollock. An all-zero pattern never gets here: `isDashed` is
    # false for it, and the line is solid.
    var dashes = newSeq[cdouble](style.dashes.len)
    for i, d in style.dashes:
      dashes[i] = max(0.0, d)
    cairoSetDash(ctx.cr, addr dashes[0], dashes.len.cint, style.dashOffset)
  else:
    cairoSetDash(ctx.cr, nil, 0, 0)

proc fillPath*(ctx: var CairoContext, path: BezPath, paint: Paint, rule: FillRule) =
  if path.isEmpty:
    return
  ctx.drawing:
    ctx.buildPath(path)
    ctx.setSource(paint)
    cairoSetFillRule(ctx.cr, rule.toCairo)
    cairoFill(ctx.cr)

proc strokePath*(
    ctx: var CairoContext, path: BezPath, paint: Paint, style: StrokeStyle
) =
  if path.isEmpty or style.width <= 0:
    return
  ctx.drawing:
    ctx.buildPath(path)
    ctx.setSource(paint)
    ctx.setStrokeStyle(style)
    cairoStroke(ctx.cr)

proc clipPath*(ctx: var CairoContext, path: BezPath, rule: FillRule) =
  # The clip has to outlive the call, so this one can't run inside a
  # save/restore pair. The matrix and fill rule are put back by hand.
  var matrix: CairoMatrix
  cairoGetMatrix(ctx.cr, addr matrix)
  let previousRule = cairoGetFillRule(ctx.cr)
  if not ctx.applyTransform():
    # A singular transform flattens the path to nothing, so nothing is
    # inside it: clip everything with an empty path.
    cairoNewPath(ctx.cr)
  else:
    ctx.buildPath(path)
  cairoSetFillRule(ctx.cr, rule.toCairo)
  cairoClip(ctx.cr)
  cairoSetFillRule(ctx.cr, previousRule)
  cairoSetMatrix(ctx.cr, addr matrix)
  ctx.checkStatus()

proc save*(ctx: var CairoContext) =
  cairoSave(ctx.cr)
  ctx.stack.add ctx.state

proc restore*(ctx: var CairoContext) =
  if ctx.stack.len == 0:
    return
  cairoRestore(ctx.cr)
  ctx.state = ctx.stack.pop()

proc transform*(ctx: var CairoContext, affine: Affine) =
  ctx.state.transform = ctx.state.transform * affine

proc currentTransform*(ctx: CairoContext): Affine =
  ctx.state.transform

proc uploadImage(image: ImageData): CairoSurface =
  ## A new ARGB32 image surface holding the image, premultiplied and in
  ## Cairo's native-endian pixel order.
  result =
    cairoImageSurfaceCreate(cairoFormatArgb32, image.width.cint, image.height.cint)
  if cairoSurfaceStatus(result) != cairoStatusSuccess:
    return
  cairoSurfaceFlush(result)
  let data = cairoImageSurfaceGetData(result)
  let stride = cairoImageSurfaceGetStride(result).int
  let src = image.convert(ifRgba8Premul)
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let s = (y * image.width + x) * 4
      let d = y * stride + x * 4
      when cpuEndian == littleEndian:
        data[d] = src.data[s + 2]
        data[d + 1] = src.data[s + 1]
        data[d + 2] = src.data[s]
        data[d + 3] = src.data[s + 3]
      else:
        data[d] = src.data[s + 3]
        data[d + 1] = src.data[s]
        data[d + 2] = src.data[s + 1]
        data[d + 3] = src.data[s + 2]
  cairoSurfaceMarkDirty(result)

proc drawImage*(
    ctx: var CairoContext, image: ImageData, dst: Rect, interp: Interpolation
) =
  if image.isEmpty or dst.isEmpty:
    return
  # The pattern matrix maps user space to image pixels. A tiny `dst` can
  # overflow it, and Cairo would reject it the way it rejects a singular
  # transform.
  let m =
    scale(image.width.float64 / dst.width, image.height.float64 / dst.height) *
    translate(-dst.x0, -dst.y0)
  if not m.isUsable:
    return
  let surface = uploadImage(image)
  let status = cairoSurfaceStatus(surface)
  if status != cairoStatusSuccess:
    ctx.fail($cairoStatusToString(status))
    cairoSurfaceDestroy(surface)
    return
  ctx.drawing:
    let pattern = cairoPatternCreateForSurface(surface)
    var cm = m.toCairo
    cairoPatternSetMatrix(pattern, addr cm)
    # Pad at the edges so bilinear sampling doesn't fade into transparency
    # at the border.
    cairoPatternSetExtend(pattern, cairoExtendPad)
    cairoPatternSetFilter(pattern, interp.toCairo)
    cairoSetSource(ctx.cr, pattern)
    cairoPatternDestroy(pattern)
    cairoNewPath(ctx.cr)
    cairoRectangle(ctx.cr, dst.x0, dst.y0, dst.width, dst.height)
    cairoSetFillRule(ctx.cr, cairoFillRuleWinding)
    cairoFill(ctx.cr)
  cairoSurfaceDestroy(surface)

proc finish*(ctx: var CairoContext): RenderResult =
  cairoSurfaceFlush(cairoGetTarget(ctx.cr))
  ctx.checkStatus()
  if ctx.error.len > 0:
    result = failure(ctx.error)
    ctx.error = ""
  else:
    result = success()

# Reading back

type PixelView = object
  ## The target's pixels, flushed and ready to read. `data` is nil when they
  ## can't be read.
  data: ptr UncheckedArray[uint8]
  stride, width, height: int
  opaque: bool ## RGB24, whose fourth byte is unused.

proc pixelView(ctx: CairoContext): PixelView =
  # The owned surface, not `cairo_get_target`: that returns an error surface
  # with no pixels once the cairo_t has failed.
  let target =
    if ctx.surface != nil:
      ctx.surface
    else:
      cairoGetTarget(ctx.cr)
  if cairoSurfaceStatus(target) != cairoStatusSuccess or
      cairoSurfaceGetType(target) != cairoSurfaceTypeImage:
    return
  let format = cairoImageSurfaceGetFormat(target)
  if format != cairoFormatArgb32 and format != cairoFormatRgb24:
    return
  cairoSurfaceFlush(target)
  PixelView(
    data: cairoImageSurfaceGetData(target),
    stride: cairoImageSurfaceGetStride(target).int,
    width: cairoImageSurfaceGetWidth(target).int,
    height: cairoImageSurfaceGetHeight(target).int,
    opaque: format == cairoFormatRgb24,
  )

func at(v: PixelView, x, y: int): Color =
  let i = y * v.stride + x * 4
  when cpuEndian == littleEndian:
    var (b, g, r, a) = (v.data[i], v.data[i + 1], v.data[i + 2], v.data[i + 3])
  else:
    var (a, r, g, b) = (v.data[i], v.data[i + 1], v.data[i + 2], v.data[i + 3])
  if v.opaque:
    a = 255
  rgba8(r, g, b, a).unpremultiplied

proc pixel*(ctx: CairoContext, x, y: int): Color =
  ## The straight-alpha color of one pixel. Transparent when `(x, y)` is
  ## outside the target, or the target isn't an ARGB32 or RGB24 image
  ## surface that can be read.
  let v = ctx.pixelView
  if v.data == nil or x < 0 or y < 0 or x >= v.width or y >= v.height:
    return transparent
  v.at(x, y)

proc toImage*(ctx: CairoContext, format = ifRgba8): ImageData =
  ## The rendered picture. Empty when the target isn't an ARGB32 or RGB24
  ## image surface that can be read.
  let v = ctx.pixelView
  if v.data == nil:
    return
  result = newImage(v.width, v.height, format)
  for y in 0 ..< v.height:
    for x in 0 ..< v.width:
      result[x, y] = v.at(x, y)

static:
  doAssert CairoContext is RenderContext
