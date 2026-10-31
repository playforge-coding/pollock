## A backend that records the primitive calls instead of drawing. Tests use
## it to check what the high-level API asks a backend to do, and it is the
## smallest possible example of a `RenderContext`.

import ./context

type
  CommandKind* = enum
    ckClear
    ckFillPath
    ckStrokePath
    ckClipPath
    ckSave
    ckRestore
    ckTransform
    ckDrawImage
    ckFinish

  Command* = object
    kind*: CommandKind
    color*: Color ## `ckClear`
    path*: BezPath ## `ckFillPath`, `ckStrokePath`, `ckClipPath`
    paint*: Paint ## `ckFillPath`, `ckStrokePath`
    rule*: FillRule ## `ckFillPath`, `ckClipPath`
    style*: StrokeStyle ## `ckStrokePath`
    affine*: Affine ## `ckTransform`
    image*: ImageData ## `ckDrawImage`
    dst*: Rect ## `ckDrawImage`
    interp*: Interpolation ## `ckDrawImage`

  RecordingContext* = object
    commands*: seq[Command]
    transform: Affine
    stack: seq[Affine]

proc newRecordingContext*(): RecordingContext =
  RecordingContext(transform: affineIdentity)

proc clear*(ctx: var RecordingContext, color: Color) =
  ctx.commands.add Command(kind: ckClear, color: color)

proc fillPath*(ctx: var RecordingContext, path: BezPath, paint: Paint, rule: FillRule) =
  ctx.commands.add Command(kind: ckFillPath, path: path, paint: paint, rule: rule)

proc strokePath*(
    ctx: var RecordingContext, path: BezPath, paint: Paint, style: StrokeStyle
) =
  ctx.commands.add Command(kind: ckStrokePath, path: path, paint: paint, style: style)

proc clipPath*(ctx: var RecordingContext, path: BezPath, rule: FillRule) =
  ctx.commands.add Command(kind: ckClipPath, path: path, rule: rule)

proc save*(ctx: var RecordingContext) =
  ctx.stack.add ctx.transform
  ctx.commands.add Command(kind: ckSave)

proc restore*(ctx: var RecordingContext) =
  if ctx.stack.len > 0:
    ctx.transform = ctx.stack.pop()
  ctx.commands.add Command(kind: ckRestore)

proc transform*(ctx: var RecordingContext, affine: Affine) =
  ctx.transform = ctx.transform * affine
  ctx.commands.add Command(kind: ckTransform, affine: affine)

proc currentTransform*(ctx: RecordingContext): Affine =
  ctx.transform

proc drawImage*(
    ctx: var RecordingContext, image: ImageData, dst: Rect, interp: Interpolation
) =
  ctx.commands.add Command(kind: ckDrawImage, image: image, dst: dst, interp: interp)

proc finish*(ctx: var RecordingContext): RenderResult =
  ctx.commands.add Command(kind: ckFinish)
  success()

proc kinds*(ctx: RecordingContext): seq[CommandKind] =
  for c in ctx.commands:
    result.add c.kind

static:
  doAssert RecordingContext is RenderContext
