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
- [ ] Text: a `Text` factory, layouts with ranged attributes, hit testing. The API grows only as fast as every backend can implement it.
- [ ] A type-erased `DynContext` for choosing a backend at runtime.
- [ ] Blend modes and group opacity (layers).

## Pure-Nim backends

- [x] Recording backend.
- [x] CPU backend: fills, strokes, clips, gradients, images, exact-area antialiasing.
- [x] SVG backend: everything the CPU backend does, as a document.
- [ ] CPU backend: text, through a font parser and glyph outlines.
- [ ] SVG backend: text as `<text>` elements.

## Native backends

- [x] Cairo: paths, strokes, clips, gradients and images, offscreen or wrapping a `cairo_t`.
- [ ] Cairo: text through Pango.
- [ ] Core Graphics under both the Objective-C and the C target.
- [ ] Direct2D with DirectWrite.
- [ ] A shared GPU tessellation layer (`pollock/gpu`).
- [ ] WebGL2 on the JavaScript target.
- [x] CI for the Cairo backend on Linux and macOS.
- [ ] Platform-specific CI for the rest: macOS for Core Graphics, Windows for Direct2D, headless Chromium for WebGL2.

## Project

- [x] Docs site on GitHub Pages.
- [x] CI on Linux, macOS and Windows under the C and JavaScript targets.
- [x] Interactive examples in a native window, through SDL3.
- [ ] The same examples in a browser, compiled with `nim js` and drawn into a canvas.
- [ ] A release on the Nimble package list.
