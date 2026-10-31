# Backends

A backend is a type that satisfies [`RenderContext`](context.md). pollock ships three: two pure Nim ones and one over Cairo. The `pollock` module exports the default one (currently `cpu` everywhere). Import a backend module directly to use a specific one, or set `-d:pollockBackend=<module path>` to change the default.

| Backend | Module | Target | Status |
| --- | --- | --- | --- |
| CPU | `pollock/backends/cpu` | any | done, no text |
| SVG | `pollock/backends/svg` | any | done, no text |
| Recording | `pollock/recording` | any | done |
| Cairo | `pollock/backends/cairo` | C, C++ and Objective-C, where Cairo is installed | done, no text |
| Core Graphics | `pollock/backends/coregraphics` | macOS | planned |
| Direct2D | `pollock/backends/direct2d` | Windows | planned |
| WebGL2 | `pollock/backends/webgl2` | browsers | planned |

## CPU

A software rasterizer that renders into a premultiplied RGBA float buffer. It runs on every Nim target (C, C++, Objective-C and JavaScript), and it is the reference renderer: the sample scenes are compared against its output pixel for pixel.

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

Each `fillPath` and `strokePath` becomes a `<path>` with the transform as a `matrix(...)` attribute, so the output is readable and the transforms are exact. Gradients go into `<defs>` with `gradientUnits="userSpaceOnUse"`, which SVG resolves in the referencing element's own coordinate system, including its transform attribute, so they line up with the element. A clip becomes a `<clipPath>` definition and a `<g clip-path>` that stays open until the matching `restore`; `toSvg` closes any group that is still open. `clear` closes the open groups around its rectangle and reopens them after it, so like on every backend it paints the whole picture whatever the clip. Images are embedded as PNG data URIs.

Numbers are rounded to about seven significant digits, never more coarsely than to three decimal places, and trailing zeros are dropped (`1.2` stays `1.2`). That keeps transform coefficients like a scale of 0.0004 intact. A miter limit below 1, which SVG would ignore, is written as a bevel join, matching what such a limit means.

## Recording

`pollock/recording` records the primitive calls into a `seq[Command]` instead of drawing. It exists for tests of code that draws, and as the smallest example of a backend.

```nim
import pollock/[draw, recording]

var ctx = newRecordingContext()
ctx.fill(rect(0, 0, 10, 10), red)
assert ctx.kinds == @[ckFillPath]
assert ctx.commands[0].paint == solid(red)
```

## Cairo

Draws through [Cairo](https://www.cairographics.org). The module finds Cairo through `pkg-config` when it compiles, so the development package has to be installed: `libcairo2-dev` on Debian and Ubuntu, `cairo-devel` on Fedora, `cairo` from Homebrew. It compiles under the C, C++ and Objective-C targets, not JavaScript, and it can't run in a NimScript (`.nims`) file: NimScript runs in the compiler's VM, which can't call C functions, so importing the module there stops with an error that says so. Put the drawing code in a `.nim` file and run it with `nim c -r`.

The module exports the primitives, not the `fill`, `stroke` and `clip` helpers, so import `pollock` (or `pollock/draw`) next to it, as in the example below.

```nim
import pollock
import pollock/backends/cairo

var ctx = newCairoContext(width, height)   # an offscreen ARGB32 image surface, transparent black
# ... draw ...
let img = ctx.toImage()                    # ImageData, straight-alpha RGBA8 by default
let c = ctx.pixel(x, y)                    # one pixel as a Color
```

The other constructor wraps a `cairo_t` the caller already has, such as the one GTK passes to a draw function, as a plain `pointer` so it works with any Cairo binding:

```nim
var ctx = newCairoContext(cr)   # cr: pointer to a cairo_t
```

pollock's user space is then the cairo_t's user space at the time it was wrapped. The context keeps a reference to the cairo_t and drops it when the context is destroyed. `ctx.cairoHandle` hands the cairo_t back for calls the backend doesn't cover. Each drawing call runs inside its own `cairo_save`/`cairo_restore` pair, so the cairo_t's matrix, source and line settings are as the host left them once the call returns, and destroying the context pops any `save` it didn't `restore`. `toImage` and `pixel` work when the target is an ARGB32 or RGB24 image surface; for other targets, and for a context whose surface couldn't be made, `toImage` returns an empty image and `pixel` returns transparent, as it does for a pixel outside the target. A `CairoContext` can't be copied; move it or pass it by `var`.

How it draws: Cairo has native paths, both fill rules, stroking with caps, joins, miter limits and dashes, clipping, gradients with all three extend modes, and image patterns, so every primitive is a few Cairo calls. Quadratic curves are raised to cubics, which Cairo has. The transform is mirrored in Nim and set on the cairo_t before each drawing call; a singular or non-finite transform skips the call, since it draws nothing and would otherwise put the cairo_t into a permanent error state (a clip under one clips everything). The clip lives in Cairo's own state stack: `save` and `restore` call `cairo_save` and `cairo_restore`, and `clear` resets the clip inside a save/restore pair and paints with the `SOURCE` operator, so a transparent color really clears. A linear gradient with no length or a radial one with no radius paints its last stop, as the rules say, without relying on Cairo's own handling of those. Images are copied into an ARGB32 surface (premultiplied, in Cairo's native byte order) and painted as a pattern with `EXTEND_PAD` and the `NEAREST` or `BILINEAR` filter.

Errors: Cairo's status is sticky, so the first failing call leaves the cairo_t unusable. `finish` reports it, and the caller makes a new context, as the [rules](context.md#the-rules) say for a lost device.

Differences from the CPU backend: antialiasing differs by a few levels along edges, and Cairo measures dash phases along the exact curve rather than the flattened polyline, so dash ends on curves can shift by a fraction of a pixel. The conformance test allows 0.5% of the pixels in each sample scene to differ by more than 32 levels, which the current samples stay well under. Gradients interpolate straight alpha, as the rules require; a test checks it. `clear` on a wrapped cairo_t also drops any clip the host had set, since `cairo_reset_clip` is the only way out of Cairo's clip; a draw handler that needs to keep the host's clip should fill a rectangle instead.

Not supported yet: text. Once the text API exists, Cairo will draw Pango's glyph runs natively and fonts from the other engines through FreeType; see the [text design](architecture.md#text-planned).

## Planned native backends

The [roadmap](roadmap.md) has the order. The plan for each, so that the shape of the code is settled before it is written:

- **Core Graphics**: Core Graphics and Core Text are C APIs, so the drawing works under both `nim c` and `nim objc`. The Objective-C parts (getting a `CGContextRef` from a view, `CALayer` and `NSImage` bridging) sit behind one small interface: `importobjc` under the Objective-C target, a `.m` shim compiled with `{.compile.}` under the C target.
- **Direct2D**: COM calls through vtables, which work the same from C and C++, with DirectWrite for text and WIC for bitmaps.
- **WebGL2**: shapes go through a shared GPU tessellation layer (flattened outlines to triangles, stencil-then-cover fills, batching), antialiasing through a multisampled renderbuffer, text from the pure Nim engine through a glyph atlas texture. The tessellation layer is meant to be reusable by a WebGPU backend.

Text engines and backends will combine freely: any backend can draw the layout of any engine on the same platform, so Core Graphics can draw Parley's text and the CPU backend can draw Core Text's. The [text design](architecture.md#text-planned) has the full table.
