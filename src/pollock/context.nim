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

import ./[color, geometry, image, paint, stroke]

export color, geometry, image, paint, stroke

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
    proc finish(ctx: var Self): RenderResult

func success*(): RenderResult =
  RenderResult(ok: true)

func failure*(message: string): RenderResult =
  RenderResult(ok: false, message: message)
