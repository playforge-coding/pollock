## Paints: what a fill or stroke is painted with. A `Paint` is a plain value
## with no backend state; backends turn it into whatever device resource they
## need and may cache that.

import ./[color, geometry]

type
  PaintKind* = enum
    pkSolid
    pkLinearGradient
    pkRadialGradient

  Extend* = enum
    ## What a gradient does outside its 0..1 range.
    exPad
    exRepeat
    exReflect

  GradientStop* = object
    offset*: float64 ## Position along the gradient, 0..1.
    color*: Color

  Paint* = object
    case kind*: PaintKind
    of pkSolid:
      color*: Color
    of pkLinearGradient:
      start*, stop*: Point
      linearStops*: seq[GradientStop]
      linearExtend*: Extend
    of pkRadialGradient:
      center*: Point
      radius*: float64
      radialStops*: seq[GradientStop]
      radialExtend*: Extend

func `==`*(a, b: Paint): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of pkSolid:
    a.color == b.color
  of pkLinearGradient:
    a.start == b.start and a.stop == b.stop and a.linearStops == b.linearStops and
      a.linearExtend == b.linearExtend
  of pkRadialGradient:
    a.center == b.center and a.radius == b.radius and a.radialStops == b.radialStops and
      a.radialExtend == b.radialExtend

func solid*(color: Color): Paint =
  Paint(kind: pkSolid, color: color)

func stop*(offset: float64, color: Color): GradientStop =
  GradientStop(offset: offset, color: color)

func linearGradient*(
    p0, p1: Point, stops: openArray[GradientStop], extend = exPad
): Paint =
  ## A gradient along the line from `p0` to `p1`, in user space.
  Paint(
    kind: pkLinearGradient,
    start: p0,
    stop: p1,
    linearStops: @stops,
    linearExtend: extend,
  )

func linearGradient*(p0, p1: Point, c0, c1: Color, extend = exPad): Paint =
  linearGradient(p0, p1, [stop(0.0, c0), stop(1.0, c1)], extend)

func radialGradient*(
    center: Point, radius: float64, stops: openArray[GradientStop], extend = exPad
): Paint =
  ## A gradient from `center` out to `radius`, in user space.
  Paint(
    kind: pkRadialGradient,
    center: center,
    radius: radius,
    radialStops: @stops,
    radialExtend: extend,
  )

func radialGradient*(
    center: Point, radius: float64, c0, c1: Color, extend = exPad
): Paint =
  radialGradient(center, radius, [stop(0.0, c0), stop(1.0, c1)], extend)

func stops*(p: Paint): seq[GradientStop] =
  case p.kind
  of pkSolid:
    @[stop(0.0, p.color), stop(1.0, p.color)]
  of pkLinearGradient:
    p.linearStops
  of pkRadialGradient:
    p.radialStops

func extend*(p: Paint): Extend =
  case p.kind
  of pkSolid: exPad
  of pkLinearGradient: p.linearExtend
  of pkRadialGradient: p.radialExtend

func isOpaque*(p: Paint): bool =
  for s in p.stops:
    if s.color.a < 1.0:
      return false
  true

func applyExtend*(t: float64, extend: Extend): float64 =
  ## Maps any `t` into 0..1 according to the extend mode.
  case extend
  of exPad:
    min(1.0, max(0.0, t))
  of exRepeat:
    let f = t - float64(int(t))
    if f < 0:
      f + 1.0
    else:
      f
  of exReflect:
    let period = abs(t) - 2.0 * float64(int(abs(t) / 2.0))
    if period > 1.0:
      2.0 - period
    else:
      period

func colorAt*(stops: openArray[GradientStop], t: float64): Color =
  ## The gradient color at `t` in 0..1. Stops are expected sorted by offset.
  if stops.len == 0:
    return transparent
  if t <= stops[0].offset:
    return stops[0].color
  for i in 1 ..< stops.len:
    if t <= stops[i].offset:
      let span = stops[i].offset - stops[i - 1].offset
      let f =
        if span <= 0:
          1.0
        else:
          (t - stops[i - 1].offset) / span
      return lerp(stops[i - 1].color, stops[i].color, f)
  stops[^1].color
