# The context

`RenderContext`, in `pollock/context`, is the contract between pollock and its backends. It is a Nim concept: a backend is any type with these procs. Application code rarely calls them directly, since [Drawing](drawing.md) wraps them, but their semantics are what every backend has to match.

```nim
type RenderContext* = concept
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
```

The primitive names end in `Path` so they never collide with the shape-taking helpers in `pollock/draw`: `fill(ctx, circle(...))` is the helper, `fillPath(ctx, path, ...)` the primitive it calls.

## The primitives

`clear(color)`
:   Paints the whole target with `color`, replacing what was there. Ignores the transform and the clip.

`fillPath(path, paint, rule)`
:   Fills `path` under the current transform and clip. `frNonZero` fills where the winding number is not zero, `frEvenOdd` where it is odd.

`strokePath(path, paint, style)`
:   Strokes `path`. The width, dashes and caps are in user space, so they scale with the transform.

`clipPath(path, rule)`
:   Intersects the clip with the inside of `path`, under the current transform. Only `restore` can widen the clip again.

`save` and `restore`
:   Push and pop the transform and the clip. Nothing else is saved; paints are passed per call. A `restore` with nothing saved does nothing.

`transform(affine)`
:   Multiplies the current transform by `affine`, so later coordinates are mapped by `affine` first.

`currentTransform`
:   The transform in effect.

`drawImage(image, dst, interp)`
:   Draws `image` stretched into `dst`, under the transform and clip, with nearest or bilinear sampling.

`drawGlyphs(run, paint)`
:   Draws a glyph run (one font at one size, glyph ids with positions in user space) in `paint`, under the transform and clip. The paint is passed explicitly, like every other paint, so a run can be drawn in a paint other than its own (a shadow, a highlight); `drawText` in `pollock/draw` passes each run's own. A backend that can make a native font from the run's bytes draws natively; otherwise it calls `drawGlyphsAsPaths(ctx, engine, run, paint)`, which fills the engine's outlines and color layers with `fillPath` and its bitmaps with `drawImage`.

`finish`
:   Ends a frame. Returns a `RenderResult` with `ok` false and a `message` if any call failed since the last `finish`, and clears that state. Backends that draw to a window present the frame here.

## The rules

These are the agreements every backend keeps, so that one drawing looks the same everywhere.

- **Coordinates** have their origin at the top left with y pointing down, in logical units. A positive rotation is clockwise on the screen. Backends whose native API disagrees (Core Graphics puts the origin at the bottom left) apply the correction once, when the context is made.
- **Colors** are sRGB. `Color` has straight alpha; images declare their format and backends convert. Gradients interpolate in sRGB with straight alpha, as the native renderers do.
- **Paints are values.** `Paint` carries no backend state. A backend may build a device resource (a Direct2D brush, a WebGL texture) from one and cache it.
- **Drawing calls never raise.** A backend records the first failure and reports it from `finish`. Losing the device is one of those failures; the caller makes a new context.
- **State is small.** `save` and `restore` cover the transform and the clip, nothing else.
- **`clear` is absolute.** It ignores the transform and the clip, so it is safe to call at the top of every frame.
- **Text is glyph runs.** Glyph positions are in user space, so the transform applies to them like to a path. A font is its bytes, face index and variation coordinates, never a platform handle, so any backend can build its own native font from it. Font lookup and fallback belong to the engine, not the backend. Glyphs are drawn unhinted with grayscale antialiasing, so every engine and backend pairing can be compared with the reference, the CPU backend with the pure Nim engine.

## Types

- `FillRule`: `frNonZero`, `frEvenOdd`.
- `Interpolation`: `ipNearest`, `ipBilinear`.
- `RenderResult`: `ok: bool`, `message: string`. `success()` and `failure(message)` make them.
- `GlyphRun`, `Glyph`, `GlyphId`, `Font`, `GlyphDrawing` and the `TextEngine` concept come from `pollock/text`, which the context re-exports; see [Text](text.md).
