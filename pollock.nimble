# Package

version = "0.1.0"
author = "playforge-coding"
description = "An abstract 2D graphics API for Nim, in the spirit of piet"
license = "BSD-3-Clause"
srcDir = "src"

# Dependencies

requires "nim >= 2.4.0"

# Tasks

import std/[os, strutils]

task testjs, "Run the tests under the JavaScript target with Node":
  for path in listFiles("tests"):
    let name = path.extractFilename
    if name.startsWith("t") and name.endsWith(".nim"):
      exec "nim js -r -d:nodejs --hints:off --outdir:tests/jsout " & path

task testcairo, "Run the Cairo backend tests (needs cairo through pkg-config)":
  # Under ORC and refc, since the destroy hook's signature differs between them.
  for mm in ["orc", "refc"]:
    exec "nim c -r --hints:off --mm:" & mm &
      " -d:pollockCairo --outdir:tests/bin tests/tcairo.nim"

task samples, "Render the sample scenes with every backend that can run here into out/":
  # The Cairo backend joins in when pkg-config finds cairo.
  let cairo =
    if gorgeEx("pkg-config --exists cairo").exitCode == 0:
      " -d:pollockCairo"
    else:
      ""
  exec "nim r -d:release --hints:off" & cairo & " tools/rendersamples.nim out"

task goldens, "Rewrite the golden files in tests/golden from the current output":
  exec "nim r --hints:off -d:pollockUpdateGoldens tests/tsamples.nim"
