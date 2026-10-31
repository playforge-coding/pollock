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

task samples, "Render the sample scenes with every backend into out/":
  exec "nim r -d:release --hints:off tools/rendersamples.nim out"

task goldens, "Rewrite the golden files in tests/golden from the current output":
  exec "nim r --hints:off -d:pollockUpdateGoldens tests/tsamples.nim"
