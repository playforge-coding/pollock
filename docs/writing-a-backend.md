# Writing a backend

A backend is a type with the ten procs of [`RenderContext`](context.md). It can live in pollock's repository or in a package of its own; nothing in pollock needs to know about it.

## The shape of it

```nim
import pollock/context

type MyContext* = object
  transform: Affine
  stack: seq[Affine]
  error: string
  # ... whatever the native API needs

proc newMyContext*(...): MyContext =
  MyContext(transform: affineIdentity)

proc clear*(ctx: var MyContext, color: Color) = ...
proc fillPath*(ctx: var MyContext, path: BezPath, paint: Paint, rule: FillRule) = ...
proc strokePath*(ctx: var MyContext, path: BezPath, paint: Paint, style: StrokeStyle) = ...
proc clipPath*(ctx: var MyContext, path: BezPath, rule: FillRule) = ...
proc save*(ctx: var MyContext) = ctx.stack.add ctx.transform
proc restore*(ctx: var MyContext) =
  if ctx.stack.len > 0: ctx.transform = ctx.stack.pop()
proc transform*(ctx: var MyContext, affine: Affine) = ctx.transform = ctx.transform * affine
proc currentTransform*(ctx: MyContext): Affine = ctx.transform
proc drawImage*(ctx: var MyContext, image: ImageData, dst: Rect, interp: Interpolation) = ...
proc finish*(ctx: var MyContext): RenderResult =
  if ctx.error.len > 0: failure(ctx.error) else: success()

static:
  doAssert MyContext is RenderContext
```

The `static` assertion at the end is worth keeping: it turns a missing or mistyped proc into a compile error in the backend's own module, with a message about the concept, instead of an error at some call site in a user's program.

Export your constructor and anything the user needs to get the result out (`toImage`, `toSvg`, a `present`). Keep the primitives themselves exported too; the concept needs to see them.

## What pollock gives you

You do not have to write a path flattener or a stroker:

- `path.flatten(tolerance)` turns a `BezPath` into polylines.
- `strokeOutline(path, style, tolerance)` turns a stroke into a fillable outline (fill it with `frNonZero`). Use it when the native API has no stroking, or when its stroking does not match the [rules](context.md#the-rules).
- `dash(polylines, style)` applies a dash pattern on its own.
- `transform(affine, path)` and `affine.scaleFactor` convert between user and device space; the CPU backend divides its device-space tolerance by `scaleFactor` to get a user-space one.
- `colorAt(stops, t)` and `applyExtend(t, extend)` evaluate gradients.
- `ImageData.convert(format)` converts pixel formats, and `pollock/png` reads and writes PNG.

If the native API has fast paths for simple shapes, check for them: `fillPath` receives a `BezPath`, and `path.elements` makes an axis-aligned rectangle easy to recognize (a move, three lines and a close).

## Device resources

Brushes, textures and layouts that belong to a device (Direct2D, WebGL) must be created by the backend from the `Paint` and `ImageData` values it is given. Cache them keyed by the value if creating them is slow; a backend owns its cache and drops it in `finish` or when the device is lost.

Own native handles with `=destroy` hooks so a context can be dropped without leaking, and disable `=copy` for types that hold a handle.

## Errors

Drawing calls must not raise. Record the first failure in the context and report it from `finish`:

```nim
proc fail(ctx: var MyContext, message: string) =
  if ctx.error.len == 0:
    ctx.error = message
```

## Checking the result

`pollock/samples` has the scenes every backend renders:

```nim
import pollock/samples

for i, name in sampleNames:
  var ctx = newMyContext(sampleWidth, sampleHeight)
  ctx.drawSample(i)
  doAssert ctx.finish().ok
  # save the result as name.png and look at it
```

If the backend can hand back pixels, compare them with the CPU backend's goldens in `tests/golden/cpu/` using `compareImages(a, b, tolerance)` from `pollock/testing`. Antialiasing differs between renderers, so expect to allow a few levels of difference along edges; large differences mean something is wrong.

## Making it the default

Users can select any backend module with `-d:pollockBackend=<module path>`; `import pollock` then exports it. A backend package called `pollock_webgpu` is picked with `-d:pollockBackend=pollock_webgpu`. The module must export its constructor and the primitives.

## Testing on targets you cannot run

`nim check --os:windows yourbackend.nim` and `nim check --os:linux yourbackend.nim` type-check platform code from any machine, and `nim js` does the same for a browser backend. Run whichever applies before you push.
