## The high-level drawing API, written once on top of the `RenderContext`
## primitives. Everything here works with every backend.

import ./context

export context

proc fill*[C: RenderContext](ctx: var C, shape: Shape, paint: Paint, rule = frNonZero) =
  ## Fills any shape.
  ctx.fillPath(shape.toPath, paint, rule)

proc fill*[C: RenderContext](ctx: var C, shape: Shape, color: Color, rule = frNonZero) =
  ctx.fillPath(shape.toPath, solid(color), rule)

proc stroke*[C: RenderContext](
    ctx: var C, shape: Shape, paint: Paint, style: StrokeStyle
) =
  ## Strokes the outline of any shape.
  ctx.strokePath(shape.toPath, paint, style)

proc stroke*[C: RenderContext](
    ctx: var C, shape: Shape, color: Color, style: StrokeStyle
) =
  ctx.strokePath(shape.toPath, solid(color), style)

proc stroke*[C: RenderContext](ctx: var C, shape: Shape, paint: Paint, width = 1.0) =
  ctx.strokePath(shape.toPath, paint, strokeStyle(width = width))

proc stroke*[C: RenderContext](ctx: var C, shape: Shape, color: Color, width = 1.0) =
  ctx.strokePath(shape.toPath, solid(color), strokeStyle(width = width))

proc clip*[C: RenderContext](ctx: var C, shape: Shape, rule = frNonZero) =
  ## Restricts later drawing to the inside of `shape`, intersected with any
  ## clip already in place. Undo it with `restore`.
  ctx.clipPath(shape.toPath, rule)

proc translate*[C: RenderContext](ctx: var C, x, y: float64) =
  ctx.transform(translate(x, y))

proc translate*[C: RenderContext](ctx: var C, v: Vec2) =
  ctx.transform(translate(v))

proc scale*[C: RenderContext](ctx: var C, s: float64) =
  ctx.transform(scale(s))

proc scale*[C: RenderContext](ctx: var C, sx, sy: float64) =
  ctx.transform(scale(sx, sy))

proc rotate*[C: RenderContext](ctx: var C, radians: float64) =
  ctx.transform(rotate(radians))

proc rotateAbout*[C: RenderContext](ctx: var C, radians: float64, center: Point) =
  ctx.transform(rotateAbout(radians, center))

proc drawImage*[C: RenderContext](
    ctx: var C, image: ImageData, at: Point, interp = ipBilinear
) =
  ## Draws an image at its natural size with its top-left corner at `at`.
  mixin drawImage
  ctx.drawImage(
    image, rect(at, size(image.width.float64, image.height.float64)), interp
  )

proc drawImage*[C: RenderContext](ctx: var C, image: ImageData, dst: Rect) =
  ## Draws an image stretched to `dst` with bilinear interpolation.
  mixin drawImage
  ctx.drawImage(image, dst, ipBilinear)

template withSave*(ctx: untyped, body: untyped) =
  ## Runs `body` between `save` and `restore`.
  ctx.save()
  try:
    body
  finally:
    ctx.restore()

template withTransform*(ctx: untyped, affine: Affine, body: untyped) =
  ## Runs `body` with `affine` applied on top of the current transform, then
  ## puts the transform back.
  ctx.save()
  try:
    ctx.transform(affine)
    body
  finally:
    ctx.restore()

template withClip*(ctx: untyped, shape: untyped, body: untyped) =
  ## Runs `body` clipped to `shape`, then removes the clip.
  ctx.save()
  try:
    ctx.clipPath(shape.toPath, frNonZero)
    body
  finally:
    ctx.restore()
