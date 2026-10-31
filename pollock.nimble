# Package

version = "0.1.0"
author = "playforge-coding"
description = "An abstract 2D graphics API for Nim, in the spirit of piet"
license = "BSD-3-Clause"
srcDir = "src"

# Dependencies

requires "nim >= 2.4.0"

# Only the examples' native window uses SDL3, so it's a development
# dependency: installing pollock as a library doesn't pull it in.
dev:
  requires "sdl3 >= 1.1"

# Tasks

import std/[os, strutils]

task testjs, "Run the tests under the JavaScript target with Node":
  for path in listFiles("tests"):
    let name = path.extractFilename
    if name.startsWith("t") and name.endsWith(".nim"):
      exec "nim js -r -d:nodejs --hints:off --outdir:tests/jsout " & path

task testcpp, "Run the tests under the C++ target":
  for path in listFiles("tests"):
    let name = path.extractFilename
    if name.startsWith("t") and name.endsWith(".nim"):
      exec "nim cpp -r --hints:off --outdir:tests/cppout " & path

task testcairo, "Run the Cairo backend tests (needs cairo through pkg-config)":
  # Under ORC and refc, since the destroy hook's signature differs between
  # them, and under C++, which needs the enum types the bindings declare.
  for target in ["c", "cpp"]:
    for mm in ["orc", "refc"]:
      exec "nim " & target & " -r --hints:off --mm:" & mm &
        " -d:pollockCairo --outdir:tests/bin tests/tcairo.nim"

task samples, "Render the sample scenes with every backend that can run here into out/":
  # The Cairo backend joins in when pkg-config finds cairo.
  let cairo =
    if gorgeEx("pkg-config --exists cairo").exitCode == 0:
      " -d:pollockCairo"
    else:
      ""
  exec "nim r -d:release --hints:off" & cairo & " tools/rendersamples.nim out"

task window, "Open the example scenes in a native window (needs SDL3)":
  # `config.nims` reads the paths to the locked dependencies (the sdl3
  # binding) from nimble.paths, which `nimble setup` writes.
  if not fileExists("nimble.paths"):
    exec "nimble -y setup"
  # With Cairo found too, B in the window switches between the backends.
  let cairo =
    if gorgeEx("pkg-config --exists cairo").exitCode == 0:
      " -d:pollockCairo"
    else:
      ""
  exec "nim r -d:release --hints:off" & cairo & " examples/window.nim"

task goldens, "Rewrite the golden files in tests/golden from the current output":
  exec "nim r --hints:off -d:pollockUpdateGoldens tests/tsamples.nim"
