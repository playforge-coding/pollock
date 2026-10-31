# Development

## Toolchain

Nim 2.4.0 and [nph](https://github.com/arnetheduck/nph) 0.7.0 are pinned in `mise.toml`:

```sh
mise plugin install nim https://github.com/elijahr/vfox-nim
mise install
```

Nimble ships with Nim. The package manifest is `pollock.nimble` at the root; `config.nims` holds the compiler settings for the whole project (`--styleCheck:error`).

## Commands

| Command | What it does |
| --- | --- |
| `nimble test` | Runs every `tests/t*.nim` under the C target. |
| `nimble testjs` | Runs the same tests under the JavaScript target with Node. |
| `nimble samples` | Renders the sample scenes with every backend into `out/`. |
| `nimble goldens` | Rewrites the golden files in `tests/golden/` from the current output. |
| `nph src tests tools` | Formats the code. Run it before committing. |
| `nim check src/pollock/backends/cpu.nim` | Type-checks one file quickly. |

## Tests

One `t*.nim` per area in `tests/`, using `std/unittest`:

- `tgeometry`, `tcolor`, `tstroke`: the value types.
- `tdraw`: the high-level API, checked through the recording backend.
- `tpng`: the PNG codec, including a zlib stream made by Python's `zlib` to exercise dynamic Huffman decoding.
- `tsvg`: the SVG writer's output.
- `tcpu`: the rasterizer, with exact pixel checks for aligned shapes, half-pixel coverage, compositing, fill rules, clips, transforms, strokes, geometry outside the target, gradients and images.
- `tsamples`: renders every sample scene with every backend and compares with the goldens.

Add a test with every behavior change. Tests that touch files skip themselves under JavaScript with `when not defined(js)`.

## Golden files

`tests/golden/cpu/*.png` and `tests/golden/svg/*.svg` are the expected output of the sample scenes. The CPU backend is deterministic, so its goldens must match exactly; the SVG goldens are compared as text.

When a change alters rendering on purpose, run `nimble goldens`, look at the new images (open the PNGs, and the SVGs in a browser), and say in the commit message why they changed. Never regenerate goldens to make a failing test pass without looking.

## Adding a sample scene

Add a proc to `src/pollock/samples.nim`, a name to `sampleNames` and a branch to `drawSample`, then run `nimble goldens` and commit the new golden files. A scene should exercise one area (a feature or an edge case) so a failure points somewhere.

## Documentation

The docs are a [Zensical](https://zensical.org) site: `zensical.toml` at the root, pages in `docs/`.

```sh
uvx zensical build --strict   # writes site/, fails on broken links and warnings
uvx zensical serve            # previews at http://localhost:8000
```

Update the docs with the code. The Docs workflow runs the strict build on pull requests that touch them, and the Pages workflow publishes the site on every push to `main` that does.

## Continuous integration

- **CI** (`ci.yml`): runs `nimble test`, `nimble testjs` and `nimble samples` on Linux, macOS and Windows, uploads the rendered samples as artifacts, and checks formatting with `nph --check`.
- **Docs** (`docs.yml`): builds the docs strictly when they change.
- **Pages** (`pages.yml`): deploys the docs to GitHub Pages from `main`.
