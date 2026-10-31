# Development

## Toolchain

Nim 2.4.0 and [nph](https://github.com/arnetheduck/nph) 0.7.0 are pinned in `mise.toml`:

```sh
mise plugin install nim https://github.com/elijahr/vfox-nim
mise install
```

Nimble ships with Nim. The package manifest is `pollock.nimble` at the root; `config.nims` holds the compiler settings for the whole project (`--styleCheck:error`).

The library has no dependencies. The [examples](examples.md) window uses the official [`sdl3`](https://github.com/nim-lang/sdl3) package, declared in a `dev:` block so only a checkout of pollock fetches it, and pinned in `nimble.lock`. `nimble setup` installs it and writes `nimble.paths` (ignored by git), which the Nimble block at the end of `config.nims` reads, so a plain `nim c` finds the locked version. Run it once after cloning and again when the lock file changes; `nimble window` runs it for you when `nimble.paths` is missing.

## Commands

| Command | What it does |
| --- | --- |
| `nimble test` | Runs every `tests/t*.nim` under the C target. |
| `nimble testjs` | Runs the same tests under the JavaScript target with Node. |
| `nimble testcairo` | Runs the Cairo backend's tests, once under ORC and once under refc. Needs Cairo's development package, found through `pkg-config`. |
| `nimble samples` | Renders the sample scenes with the CPU and SVG backends into `out/`, and with Cairo too (as `<name>-cairo.png`) when `pkg-config` finds it. |
| `nimble goldens` | Rewrites the golden files in `tests/golden/` from the current output. |
| `nimble setup` | Installs the locked development dependencies and writes `nimble.paths`. |
| `nimble window` | Opens the [example scenes](examples.md) in a native window. Needs SDL3; builds in the Cairo backend too when `pkg-config` finds it. |
| `nph src tests tools examples` | Formats the code. Run it before committing. |
| `nim check src/pollock/backends/cpu.nim` | Type-checks one file quickly. |

## Tests

One `t*.nim` per area in `tests/`, using `std/unittest`:

- `tgeometry`, `tcolor`, `tstroke`: the value types.
- `tdraw`: the high-level API, checked through the recording backend.
- `tpng`: the PNG codec, including a zlib stream made by Python's `zlib` to exercise dynamic Huffman decoding.
- `tsvg`: the SVG writer's output.
- `tcpu`: the rasterizer, with exact pixel checks for aligned shapes, half-pixel coverage, compositing, fill rules, clips, transforms, strokes, geometry outside the target, gradients and images.
- `tsamples`: renders every sample scene with the CPU and SVG backends and compares with the goldens.
- `texamples`: runs every [example scene](examples.md) without a window for a few seconds of simulated time with a scripted pointer, and checks that it draws on the CPU, SVG and recording backends with balanced `save` and `restore`, moves on its own, reacts to the pointer, and repeats exactly. The scenes are animations and simulations, so they have no goldens. `tests/config.nims` puts `examples/` on the path for it.
- `tcairo`: the Cairo backend, with pixel checks for the things Cairo does differently from the CPU backend (clear, clips, singular and non-finite transforms, degenerate gradients, dashes, image byte order, wrapping a `cairo_t` without disturbing its state, error reporting and reading back a failed context), and the sample scenes compared with the CPU goldens at a tolerance. The whole file is a no-op unless compiled with `-d:pollockCairo`, so `nimble test` and `nimble testjs` still run on machines without Cairo; `nimble testcairo` passes the define.

Add a test with every behavior change. Tests that touch files skip themselves under JavaScript with `when not defined(js)`. A test for a native backend guards its whole body with that backend's define, as `tcairo` does.

## Golden files

`tests/golden/cpu/*.png` and `tests/golden/svg/*.svg` are the expected output of the sample scenes. The CPU backend is deterministic, so its goldens must match exactly; the SVG goldens are compared as text. Native backends have no goldens of their own: they are compared with the CPU goldens at a tolerance, since their antialiasing differs along edges and can change between library versions. `.gitattributes` forces LF line endings, so a Windows checkout doesn't turn them into CRLF and break the comparison.

When a change alters rendering on purpose, run `nimble goldens`, look at the new images (open the PNGs, and the SVGs in a browser), and say in the commit message why they changed. Never regenerate goldens to make a failing test pass without looking.

## Adding a sample scene

Add a proc to `src/pollock/samples.nim`, a name to `sampleNames` and a branch to `drawSample`, then run `nimble goldens` and commit the new golden files. A normal test run never writes goldens, so a scene without them fails until they are committed. A scene should exercise one area (a feature or an edge case) so a failure points somewhere.

## Documentation

The docs are a [Zensical](https://zensical.org) site: `zensical.toml` at the root, pages in `docs/`.

```sh
uvx zensical build --strict   # writes site/, fails on broken links and warnings
uvx zensical serve            # previews at http://localhost:8000
```

Update the docs with the code. The Docs workflow runs the strict build on pull requests that touch them, and the Pages workflow publishes the site on every push to `main` that does.

## Continuous integration

- **CI** (`ci.yml`): runs `nimble test`, `nimble testjs` and `nimble samples` on Linux, macOS and Windows, builds the example window there (without running it, so SDL3 itself isn't needed), installs Cairo and runs `nimble testcairo` on Linux and macOS, uploads the rendered samples as artifacts, and checks formatting with `nph --check`.
- **Docs** (`docs.yml`): builds the docs strictly when they change.
- **Pages** (`pages.yml`): deploys the docs to GitHub Pages from `main`.
