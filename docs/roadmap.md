# Roadmap

Finished items stay in their section with a check mark, so each section shows how far along it is.

## The core

- [x] Geometry: points, vectors, rectangles, rounded rectangles, circles, ellipses, lines, affine transforms, Bezier paths.
- [x] Flattening with a tolerance, and stroke expansion with caps, joins, miter limits and dashes.
- [x] Colors, solid paints, linear and radial gradients with pad, repeat and reflect.
- [x] The `RenderContext` concept and the contract rules.
- [x] The high-level API: `fill`, `stroke`, `clip`, transforms, `withSave`, `withTransform`, `withClip`, images.
- [x] PNG reading and writing with no dependencies.
- [x] Sample scenes and golden tests.
- [ ] Arcs and elliptical arcs as path elements.
- [ ] Exact bounding boxes for curves (today the box is around the control points).
- [ ] Text: the `TextEngine` concept, `GlyphRun`, the `drawGlyphs` primitive, layouts with ranged attributes, hit testing. Engines and backends combine freely; see the [text design](architecture.md#text-planned). The API grows only as fast as every engine and backend can implement it.
- [ ] A shared glyph cache, so every backend can draw text with the primitives it already has: outlines and color layers with `fillPath`, bitmap glyphs with `drawImage`.
- [ ] Color glyphs: COLR layers, sbix and CBDT bitmaps.
- [ ] The `RasterContext` concept, shared by the backends that render into memory.
- [ ] A type-erased `DynContext` for choosing a backend at runtime.
- [ ] Blend modes and group opacity (layers).

## Pure-Nim backends

- [x] Recording backend.
- [x] CPU backend: fills, strokes, clips, gradients, images, exact-area antialiasing.
- [x] SVG backend: everything the CPU backend does, as a document.
- [ ] Pure Nim text engine (`opentype`): OpenType parsing, shaping for Latin, Greek and Cyrillic, bidirectional text, line breaking.
- [ ] HarfBuzz as a shaper for the pure Nim engine: the native library under C, C++ and Objective-C, harfbuzzjs (WebAssembly) under JavaScript, so that every script works on every target.
- [ ] Pure Nim text engine: complex scripts in the Nim shaper.
- [ ] CPU backend: text, by filling glyph outlines.
- [ ] SVG backend: text as glyph paths.
- [ ] SVG backend: `<text>` elements as an option, for selectable text.

## Native backends and engines

- [x] Cairo: paths, strokes, clips, gradients and images, offscreen or wrapping a `cairo_t`.
- [ ] Pango text engine.
- [ ] Cairo: native glyph drawing, with Pango's runs and with fonts from any engine.
- [ ] Core Text text engine.
- [ ] DirectWrite text engine.
- [ ] Core Graphics under both the Objective-C and the C target.
- [ ] Direct2D with DirectWrite.
- [ ] A shared GPU tessellation layer (`pollock/gpu`).
- [ ] WebGL2 on the JavaScript target.
- [x] CI for the Cairo backend on Linux and macOS.
- [ ] Platform-specific CI for the rest: macOS for Core Graphics, Windows for Direct2D, headless Chromium for WebGL2.

## Rust packages

Separate packages, each a small crate with a C ABI and a cbindgen header, so pollock itself keeps no dependencies.

- [ ] `pollock-parley`: a text engine over Parley, fontique and skrifa.
- [ ] `pollock-tinyskia`: a CPU backend over tiny-skia.
- [ ] `pollock-vellocpu`: a CPU backend over vello_cpu.

## Project

- [x] Docs site on GitHub Pages.
- [x] CI on Linux, macOS and Windows under the C, C++ and JavaScript targets.
- [x] Interactive examples in a native window, through SDL3.
- [ ] The same examples in a browser, compiled with `nim js` and drawn into a canvas.
- [ ] A release on the Nimble package list.
