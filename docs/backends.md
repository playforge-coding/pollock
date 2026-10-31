# Backends

A backend is a type that satisfies [`RenderContext`](context.md). pollock ships two, both pure Nim, and the `pollock` module exports the default one (currently `cpu` everywhere). Import a backend module directly to use a specific one, or set `-d:pollockBackend=<module path>` to change the default.

| Backend | Module | Target | Status |
| --- | --- | --- | --- |
| CPU | `pollock/backends/cpu` | any | done, no text |
| SVG | `pollock/backends/svg` | any | done, no text |
| Recording | `pollock/recording` | any | done |
| Cairo | `pollock/backends/cairo` | Linux and others | planned |
| Core Graphics | `pollock/backends/coregraphics` | macOS | planned |
| Direct2D | `pollock/backends/direct2d` | Windows | planned |
| WebGL2 | `pollock/backends/webgl2` | browsers | planned |

## CPU

A software rasterizer that renders into a premultiplied RGBA float buffer. It runs on the C, Objective-C and JavaScript targets, and it is the reference renderer: the sample scenes are compared against its output pixel for pixel.

```nim
import pollock/backends/cpu

var ctx = newCpuContext(width, height)   # transparent black
ctx.tolerance = 0.1                      # flattening tolerance in pixels; the default
# ... draw ...
let img = ctx.toImage()                  # ImageData, straight-alpha RGBA8 by default
let c = ctx.pixel(x, y)                  # one pixel as a Color
```

`writePng(img, path)` from `pollock/png` saves the result.

How it draws: paths are transformed to device space and flattened; the edges are accumulated into a signed-area coverage buffer (the method font rasterizers such as font-rs use), which gives exact antialiasing for non-overlapping edges; each covered pixel is then composited with source-over. Strokes are expanded into an outline by `pollock/stroke` and filled with the nonzero rule. Clips are coverage masks that multiply into later fills. Gradients and images are sampled per pixel by mapping the pixel center back to user space.

Known limits: where a path overlaps itself with the same winding direction, partially covered pixels along the overlap can come out slightly darker than ideal (coverage is clamped, not exact, there). Images are sampled without mipmaps, so shrinking an image a lot aliases.

## SVG

Builds an SVG document in memory.

```nim
import pollock/backends/svg

var ctx = newSvgContext(width, height)   # in user units
# ... draw ...
writeFile("out.svg", ctx.toSvg())
```

Each `fillPath` and `strokePath` becomes a `<path>` with the transform as a `matrix(...)` attribute, so the output is readable and the transforms are exact. Gradients go into `<defs>` with `gradientUnits="userSpaceOnUse"`, which SVG resolves in the referencing element's own coordinate system, including its transform attribute, so they line up with the element. A clip becomes a `<clipPath>` definition and a `<g clip-path>` that stays open until the matching `restore`; `toSvg` closes any group that is still open. Images are embedded as PNG data URIs.

Known limits: `clear` inside an open clip is clipped, since it is an SVG `<rect>` like any other element (at the top level it behaves as the contract says). Numbers are written with three decimals.

## Recording

`pollock/recording` records the primitive calls into a `seq[Command]` instead of drawing. It exists for tests of code that draws, and as the smallest example of a backend.

```nim
import pollock/[draw, recording]

var ctx = newRecordingContext()
ctx.fill(rect(0, 0, 10, 10), red)
assert ctx.kinds == @[ckFillPath]
assert ctx.commands[0].paint == solid(red)
```

## Planned native backends

The [roadmap](roadmap.md) has the order. The plan for each, so that the shape of the code is settled before it is written:

- **Cairo**: hand-written FFI to `cairo.h`, with Pango for text, linked through `pkg-config`.
- **Core Graphics**: Core Graphics and Core Text are C APIs, so the drawing works under both `nim c` and `nim objc`. The Objective-C parts (getting a `CGContextRef` from a view, `CALayer` and `NSImage` bridging) sit behind one small interface: `importobjc` under the Objective-C target, a `.m` shim compiled with `{.compile.}` under the C target.
- **Direct2D**: COM calls through vtables from C, with DirectWrite for text and WIC for bitmaps.
- **WebGL2**: shapes go through a shared GPU tessellation layer (flattened outlines to triangles, stencil-then-cover fills, batching), antialiasing through a multisampled renderbuffer, text through Canvas 2D on an `OffscreenCanvas`. The tessellation layer is meant to be reusable by a WebGPU backend.
