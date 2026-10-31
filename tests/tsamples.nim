## Renders the sample scenes with every pure-Nim backend and compares them
## with the golden files. `nimble goldens` (or `-d:pollockUpdateGoldens`)
## rewrites the goldens; look at the new files before committing them.

import std/unittest
import pollock/[samples, testing]
import pollock/backends/[cpu, svg]

when not defined(js):
  import std/[os, strformat]
  import pollock/png

  const
    updateGoldens = defined(pollockUpdateGoldens)
    goldenDir = currentSourcePath().parentDir / "golden"

proc renderCpu(index: int): ImageData =
  var ctx = newCpuContext(sampleWidth, sampleHeight)
  ctx.drawSample(index)
  doAssert ctx.finish().ok
  ctx.toImage()

proc renderSvg(index: int): string =
  var ctx = newSvgContext(sampleWidth.float64, sampleHeight.float64)
  ctx.drawSample(index)
  doAssert ctx.finish().ok
  ctx.toSvg()

suite "samples":
  test "every sample renders on every backend":
    for i in 0 ..< sampleNames.len:
      let img = renderCpu(i)
      check img.width == sampleWidth
      check renderSvg(i).len > 100

  when not defined(js):
    test "cpu goldens":
      createDir(goldenDir / "cpu")
      for i, name in sampleNames:
        let path = goldenDir / "cpu" / &"{name}.png"
        let img = renderCpu(i)
        if updateGoldens or not fileExists(path):
          writePng(img, path)
          echo "wrote ", path
        let golden = readPng(path)
        let diff = compareImages(img, golden)
        checkpoint(
          &"{name}: {diff.differingPixels} pixels differ, max channel diff {diff.maxChannelDiff}"
        )
        check diff.matches

    test "svg goldens":
      createDir(goldenDir / "svg")
      for i, name in sampleNames:
        let path = goldenDir / "svg" / &"{name}.svg"
        let doc = renderSvg(i)
        if updateGoldens or not fileExists(path):
          writeFile(path, doc)
          echo "wrote ", path
        checkpoint(name)
        check doc == readFile(path)
