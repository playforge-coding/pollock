# pollock

An abstract 2D graphics API for Nim, in the spirit of [piet](https://github.com/linebender/piet). You draw paths, shapes, gradients, clips and images against one API, and a backend turns that into a native renderer's calls.

**Documentation: [playforge-coding.github.io/pollock](https://playforge-coding.github.io/pollock/)**

> [!WARNING]
> pollock is young. The API, the two pure-Nim backends (CPU and SVG) and the Cairo backend work; the other native backends and text are still to come. See the [roadmap](https://playforge-coding.github.io/pollock/roadmap/).

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

- One drawing API over any backend: a `RenderContext` is a Nim concept, so calls dispatch statically and a backend can live in any package.
- Backends in the repository: a CPU rasterizer and an SVG writer, both pure Nim and running on all of Nim's targets (C, C++, Objective-C and JavaScript), and a Cairo backend for the C, C++ and Objective-C targets. Core Graphics, Direct2D and WebGL2 are planned.
- Geometry (points, rectangles, affine transforms, Bezier paths, flattening, stroke expansion), colors, gradients and PNG reading and writing, with no dependencies.

## Building

pollock pins Nim 2.4.0 with [mise](https://mise.jdx.dev).

```sh
mise plugin install nim https://github.com/elijahr/vfox-nim
mise install
nimble test     # the test suite under the C target
nimble testcpp  # the same under the C++ target
nimble testjs   # the same under the JavaScript target, with Node
nimble testcairo # the Cairo backend's tests, with Cairo's development package installed
nimble samples  # renders the sample scenes into out/
nimble window   # the interactive examples in a native window, with SDL3 installed
```

[Getting started](https://playforge-coding.github.io/pollock/getting-started/) walks through a first drawing, and [Examples](https://playforge-coding.github.io/pollock/examples/) covers the animated, interactive scenes in `examples/`.

## License

[BSD-3-Clause](LICENSE)
