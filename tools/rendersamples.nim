## Renders every sample scene with the CPU and SVG backends into a directory:
## `nim r tools/rendersamples.nim out`. With `-d:pollockCairo` the Cairo
## backend renders them too, as `<name>-cairo.png`.

import std/[os, strformat]
import pollock/[samples, png]
import pollock/backends/[cpu, svg]

when defined(pollockCairo):
  import pollock/backends/cairo

proc main() =
  let dir =
    if paramCount() >= 1:
      paramStr(1)
    else:
      "out"
  createDir(dir)
  for i, name in sampleNames:
    var c = newCpuContext(sampleWidth, sampleHeight)
    c.drawSample(i)
    doAssert c.finish().ok
    writePng(c.toImage(), dir / &"{name}.png")

    var s = newSvgContext(sampleWidth.float64, sampleHeight.float64)
    s.drawSample(i)
    doAssert s.finish().ok
    writeFile(dir / &"{name}.svg", s.toSvg())
    var files = &"{dir}/{name}.png, {dir}/{name}.svg"

    when defined(pollockCairo):
      var k = newCairoContext(sampleWidth, sampleHeight)
      k.drawSample(i)
      doAssert k.finish().ok
      writePng(k.toImage(), dir / &"{name}-cairo.png")
      files.add &", {dir}/{name}-cairo.png"
    echo &"{name}: {files}"

main()
