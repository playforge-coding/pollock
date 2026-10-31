## Helpers for checking rendered output, for pollock's own tests and for
## anyone writing a backend.

import ./image

type ImageDiff* = object
  differingPixels*: int ## Pixels where any channel differs by more than the tolerance.
  maxChannelDiff*: int ## The largest difference seen in any channel.
  sizeMismatch*: bool

func compareImages*(a, b: ImageData, tolerance = 0): ImageDiff =
  ## Compares two images channel by channel as 8-bit RGBA.
  if a.width != b.width or a.height != b.height:
    return ImageDiff(sizeMismatch: true)
  let pa = a.convert(ifRgba8)
  let pb = b.convert(ifRgba8)
  for i in 0 ..< pa.width * pa.height:
    var worst = 0
    for c in 0 .. 3:
      let d = abs(int(pa.data[i * 4 + c]) - int(pb.data[i * 4 + c]))
      worst = max(worst, d)
    result.maxChannelDiff = max(result.maxChannelDiff, worst)
    if worst > tolerance:
      inc result.differingPixels

func matches*(diff: ImageDiff): bool =
  not diff.sizeMismatch and diff.differingPixels == 0
