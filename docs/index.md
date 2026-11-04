# pollock

pollock is an abstract 2D graphics API for Nim, modeled on [piet](https://github.com/linebender/piet). You draw paths, shapes, gradients, clips, images and text against one API, and a backend turns that into calls to a renderer. Swap the backend and the drawing code stays the same.

```nim
import pollock

var ctx = newCpuContext(200, 120)
ctx.clear(white)
ctx.fill(roundedRect(10, 10, 110, 110, 16), rgb8(60, 130, 220))
ctx.stroke(circle(150, 60, 40), black, 3.0)
ctx.withClip(circle(150, 60, 40)):
  ctx.fill(rect(150, 0, 200, 120), linearGradient(point(150, 0), point(200, 0), red, yellow))
writePng(ctx.toImage(), "out.png")
```

`newCpuContext` comes from the default backend, which `import pollock` brings in. For SVG, add `import pollock/backends/svg`, make the context with `newSvgContext(200, 120)` and write `ctx.toSvg()` to a file instead of the PNG: the drawing lines in between stay the same.

## What it gives you

- **One API.** `fill`, `stroke`, `clip`, transforms, `save`/`restore`, gradients and images, described in [Drawing](drawing.md), and [text](text.md) from a font file, laid out by a text engine that any backend can draw for.
- **Static dispatch.** A backend is any type that satisfies the `RenderContext` concept, so drawing code is generic and calls go straight to the backend with nothing in between. A backend can live in any package; see [Writing a backend](writing-a-backend.md).
- **Three backends today**: a CPU rasterizer with exact-area antialiasing and an SVG writer, both pure Nim and compiling for all of Nim's targets (C, C++, Objective-C and JavaScript), and a Cairo backend for the C, C++ and Objective-C targets. Core Graphics, Direct2D and WebGL2 are on the [roadmap](roadmap.md).
- **Geometry without dependencies.** Points, rectangles, rounded rectangles, circles, ellipses, arcs, affine transforms and Bezier paths, with flattening and stroke expansion, plus colors, gradients, PNG reading and writing, and an OpenType font reader.
- **[Examples](examples.md)** that animate and react to the mouse in a native window: an orrery, fireworks, a Bezier curve editor, meshing gears, a flow field and lettering that magnifies under the pointer.

## Status

pollock is young. The shape, paint, clip, transform and image parts of the API are in place and tested on the two pure-Nim backends and on Cairo. Text is in its first form: one line of left-to-right text with kerning, from TrueType and CFF fonts, drawn as outlines on every backend. Shaping beyond that, line breaking and the other native backends are still to come. The [roadmap](roadmap.md) says what comes next.
