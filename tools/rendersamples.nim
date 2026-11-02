## Renders every sample scene, and the text scene with the fonts in
## tests/fonts, with the CPU and SVG backends into a directory:
## `nim r tools/rendersamples.nim out`. With `-d:pollockCairo` the Cairo
## backend renders them too, as `<name>-cairo.png`.

import std/[os, strformat]
import pollock/[samples, png]
import pollock/backends/[cpu, svg]

when defined(pollockCairo):
  import pollock/backends/cairo

const fontDir = currentSourcePath().parentDir.parentDir / "tests" / "fonts"

proc main() =
  let dir =
    if paramCount() >= 1:
      paramStr(1)
    else:
      "out"
  createDir(dir)
  let trueType = newFont(readFile(fontDir / "SourceSans3-Regular.ttf"))
  let cff = newFont(readFile(fontDir / "SourceSans3-Regular.otf"))
  for i in 0 .. sampleNames.len:
    let text = i == sampleNames.len
    let name =
      if text:
        "text"
      else:
        sampleNames[i]
    template draw(ctx: untyped) =
      if text:
        ctx.drawTextSample(trueType, cff)
      else:
        ctx.drawSample(i)

    var c = newCpuContext(sampleWidth, sampleHeight)
    c.draw()
    doAssert c.finish().ok
    writePng(c.toImage(), dir / &"{name}.png")

    var s = newSvgContext(sampleWidth.float64, sampleHeight.float64)
    s.draw()
    doAssert s.finish().ok
    writeFile(dir / &"{name}.svg", s.toSvg())
    var files = &"{dir}/{name}.png, {dir}/{name}.svg"

    when defined(pollockCairo):
      var k = newCairoContext(sampleWidth, sampleHeight)
      k.draw()
      doAssert k.finish().ok
      writePng(k.toImage(), dir / &"{name}-cairo.png")
      files.add &", {dir}/{name}-cairo.png"
    echo &"{name}: {files}"

main()
