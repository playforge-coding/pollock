# Getting started

## Installing

pollock needs Nim 2.4.0 or later and nothing else for the CPU and SVG backends, which are pure Nim. The Cairo backend needs Cairo's development package (see [Backends](backends.md#cairo)). The repository pins Nim through [mise](https://mise.jdx.dev):

```sh
mise plugin install nim https://github.com/elijahr/vfox-nim
mise install
```

To use pollock from your own project, add it to your `.nimble` file:

```nim
requires "pollock"
```

and `import pollock`.

## A first drawing

`import pollock` brings in the drawing API, PNG support and the default backend. The default is the CPU backend on every platform until the native ones exist.

```nim
import pollock

var ctx = newCpuContext(320, 200)
ctx.clear(rgb8(250, 250, 248))

# Shapes take a paint or a plain color.
ctx.fill(rect(20, 20, 140, 100), rgb8(220, 60, 60))
ctx.fill(circle(230, 70, 50), linearGradient(point(180, 20), point(280, 120), blue, cyan))

# Strokes take a width, or a full style.
ctx.stroke(line(20, 150, 300, 150), black, 2.0)
ctx.stroke(
  roundedRect(20, 120, 300, 180, 12),
  rgb8(60, 60, 60),
  strokeStyle(width = 3, dashes = [8.0, 4.0], cap = lcRound),
)

# Transforms and clips are scoped.
ctx.withTransform(rotateAbout(0.3, point(230, 70))):
  ctx.withClip(circle(230, 70, 50)):
    ctx.fill(rect(230, 20, 300, 120), white.withAlpha(0.4))

doAssert ctx.finish().ok
writePng(ctx.toImage(), "first.png")
```

Compile and run it with `nim r first.nim`. The coordinate system has its origin at the top left with y pointing down, in pixels for the CPU backend.

## The same drawing as SVG

Replace the first and last lines:

```nim
import pollock
import pollock/backends/svg

var ctx = newSvgContext(320, 200)
# ... the same drawing calls ...
writeFile("first.svg", ctx.toSvg())
```

Everything between them is unchanged, because the drawing calls are generic over the backend.

## The same drawing through Cairo

With Cairo's development package installed, the Cairo backend renders the same calls through libcairo:

```nim
import pollock
import pollock/backends/cairo

var ctx = newCairoContext(320, 200)
# ... the same drawing calls ...
doAssert ctx.finish().ok
writePng(ctx.toImage(), "first-cairo.png")
```

`newCairoContext` also accepts a pointer to a `cairo_t` you already have, so the same code can draw into a GTK widget.

## Writing code that works with any backend

Make the procedure generic over `RenderContext`:

```nim
import pollock

proc drawLogo[C: RenderContext](ctx: var C, at: Point) =
  ctx.withTransform(translate(at.toVec)):
    ctx.fill(circle(0, 0, 20), red)
    ctx.stroke(circle(0, 0, 20), black, 2.0)
```

`drawLogo` then works on a `CpuContext`, an `SvgContext` or any backend written later, and the compiler checks that each one provides what the body uses.

## Choosing the default backend

`import pollock` exports one backend. Pick a different one at compile time with a define:

```sh
nim r -d:pollockBackend=pollock/backends/svg first.nim
```

The value is a module path, so a backend from another package works too (`-d:pollockBackend=pollock_webgpu`). You can always import a backend module directly instead, as the SVG example above does.
