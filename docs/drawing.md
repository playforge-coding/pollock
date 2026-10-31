# Drawing

The drawing API is what application code uses. It is written once, in `pollock/draw`, on top of the backend primitives described in [The context](context.md), so everything here works with every backend. `import pollock` includes all of it.

Every proc here is generic over `C: RenderContext`: the first argument is `ctx: var C`.

## Shapes

A shape is anything with `toPath` and `boundingBox`. These come with pollock:

| Shape | Constructors |
| --- | --- |
| `Rect` | `rect(x0, y0, x1, y1)`, `rect(origin, size)`, `rectXywh(x, y, width, height)`, `rectFromPoints(a, b)` |
| `RoundedRect` | `roundedRect(rect, radius)`, `roundedRect(x0, y0, x1, y1, radius)` |
| `Circle` | `circle(center, radius)`, `circle(x, y, radius)` |
| `Ellipse` | `ellipse(center, rx, ry)` |
| `Line` | `line(p0, p1)`, `line(x0, y0, x1, y1)` |
| `BezPath` | `newPath()` then `moveTo`, `lineTo`, `quadTo`, `cubicTo`, `closePath`; `polygonPath(points)` |

A `BezPath` is a sequence of `PathEl` values. Build one like this:

```nim
var p = newPath()
p.moveTo 10, 10
p.lineTo 100, 10
p.quadTo point(120, 50), point(100, 90)
p.cubicTo point(80, 120), point(30, 120), point(10, 90)
p.closePath()
```

`extend` appends one path to another, which is how you make a path with several subpaths (rings, holes). `transform(affine, path)` returns a transformed copy, `boundingBox` the box around the control points, `flatten(path, tolerance)` the polylines within `tolerance` of the curves, and `area` the signed area.

Rectangles have the usual helpers: `width`, `height`, `size`, `origin`, `center`, `union`, `intersect`, `contains`, `inflate`, `inset`, `translate`, `normalized`, `roundOut`, `isEmpty`.

## Colors and paints

A `Color` is sRGB with straight alpha, components in 0..1: `rgb(r, g, b)`, `rgba(r, g, b, a)`, `rgb8(r, g, b)`, `rgba8(r, g, b, a)`, `gray(level)`, `parseHex("#rrggbb")`, and `withAlpha` to change the alpha. The constants `black`, `white`, `red`, `green`, `blue`, `yellow`, `cyan`, `magenta` and `transparent` are there too.

A `Paint` is what a fill or stroke is painted with:

- `solid(color)`. Everywhere a `Paint` is accepted, a `Color` works too.
- `linearGradient(p0, p1, c0, c1)` or `linearGradient(p0, p1, stops)`: from `p0` to `p1` in user space (that is, under the current transform).
- `radialGradient(center, radius, c0, c1)` or `radialGradient(center, radius, stops)`.

Stops are `stop(offset, color)` with offsets in 0..1, in order. The optional `extend` argument (`exPad`, `exRepeat`, `exReflect`) says what happens outside 0..1.

## Filling and stroking

```nim
proc fill(ctx, shape, paint: Paint, rule = frNonZero)
proc fill(ctx, shape, color: Color, rule = frNonZero)
```

Fills the shape. `rule` is `frNonZero` or `frEvenOdd`, which differ for self-intersecting paths and for paths with several subpaths.

```nim
proc stroke(ctx, shape, paint: Paint, width = 1.0)
proc stroke(ctx, shape, color: Color, width = 1.0)
proc stroke(ctx, shape, paint: Paint, style: StrokeStyle)
proc stroke(ctx, shape, color: Color, style: StrokeStyle)
```

Strokes the outline. The short forms stroke with butt caps and miter joins. A `StrokeStyle` has `width`, `cap` (`lcButt`, `lcRound`, `lcSquare`), `join` (`ljMiter`, `ljRound`, `ljBevel`), `miterLimit`, `dashes` (on and off lengths in user units) and `dashOffset`:

```nim
strokeStyle(width = 3, cap = lcRound, join = ljRound, dashes = [6.0, 3.0])
```

Stroke width is in user space: scale the context by two and a 1-wide stroke becomes 2 pixels wide.

## Clipping

```nim
proc clip(ctx, shape, rule = frNonZero)
```

Restricts later drawing to the inside of `shape`, intersected with any clip already in place. There is no way to remove a clip except `restore`, so clips almost always go inside `withSave` or `withClip`.

## Transforms

```nim
proc translate(ctx, x, y)
proc translate(ctx, v: Vec2)
proc scale(ctx, s)
proc scale(ctx, sx, sy)
proc rotate(ctx, radians)
proc rotateAbout(ctx, radians, center)
```

Each one multiplies the current transform. `ctx.transform(affine)` applies any `Affine`, and `ctx.currentTransform` reads it back. Positive rotation turns clockwise on the screen, because y points down.

`Affine` values compose with `*`, where `a * b` applies `b` first: `translate(100, 0) * rotate(0.5)` rotates, then moves. `inverse`, `apply` (also spelled `m * point`), `determinant` and `scaleFactor` are there for your own math.

## Scopes

```nim
template withSave(ctx, body)
template withTransform(ctx, affine, body)
template withClip(ctx, shape, body)
```

Each runs `body` between `save` and `restore`, so the transform and the clip go back to what they were, even if `body` raises. `withTransform` applies `affine` first and `withClip` clips to `shape` first.

```nim
ctx.withTransform(translate(50, 50) * scale(2)):
  ctx.withClip(circle(0, 0, 20)):
    ctx.fill(rect(-20, -20, 20, 20), blue)
```

## Images

An `ImageData` is pixels in memory: `width`, `height`, a `format` (`ifGray8`, `ifRgb8`, `ifRgba8`, `ifRgba8Premul`) and the bytes. Make one with `newImage(width, height, format)` and set pixels with `img[x, y] = color`, or load a PNG with `readPng(path)` (`decodePng(bytes)` for data already in memory).

```nim
proc drawImage(ctx, image, at: Point, interp = ipBilinear)
proc drawImage(ctx, image, dst: Rect)
proc drawImage(ctx, image, dst: Rect, interp: Interpolation)
```

Draws the image at its natural size, or stretched into `dst`. `ipNearest` keeps pixels sharp, `ipBilinear` smooths them. The current transform and clip apply.

## Clearing and finishing

`ctx.clear(color)` paints the whole target, ignoring the transform and the clip. `ctx.finish()` returns a `RenderResult` whose `ok` is false if any drawing call failed since the last `finish`; backends never raise from drawing calls.
