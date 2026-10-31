## What the example scenes share: their size, the pointer input they react
## to, and a few helpers. A scene is an object with an `update` proc that
## advances it by a time step and a `render` proc that draws it on any
## backend, so the native window and the tests run the same code. `render`
## covers the whole scene with an opaque background first, since a host
## doesn't clear between frames.

import std/math
import pollock/draw

export draw

const
  sceneWidth* = 640.0
  sceneHeight* = 400.0
  sceneBounds* = Rect(x0: 0, y0: 0, x1: sceneWidth, y1: sceneHeight)

type Input* = object
  ## The pointer, in scene coordinates. A host fills this in every frame.
  pos*: Point
  inside*: bool ## The pointer is over the scene.
  down*: bool ## A button or a finger is pressed.
  pressed*: bool ## The press started this frame.

func hsl*(hue, saturation, lightness: float64, alpha = 1.0): Color =
  ## A color from a hue in turns (0 is red, 1/3 green, 2/3 blue; any value
  ## wraps), a saturation and a lightness, each 0..1.
  let h = (hue - floor(hue)) * 6
  let c = (1 - abs(2 * lightness - 1)) * saturation
  let x = c * (1 - abs(floorMod(h, 2.0) - 1))
  let (r, g, b) =
    if h < 1:
      (c, x, 0.0)
    elif h < 2:
      (x, c, 0.0)
    elif h < 3:
      (0.0, c, x)
    elif h < 4:
      (0.0, x, c)
    elif h < 5:
      (x, 0.0, c)
    else:
      (c, 0.0, x)
  let m = lightness - c / 2
  rgba(r + m, g + m, b + m, alpha)

func polar*(center: Point, radius, angle: float64): Point =
  ## The point at `radius` from `center` in direction `angle`, clockwise on
  ## screen from the positive x axis.
  center + vec2(cos(angle), sin(angle)) * radius

func approach*(value, target, rate, dt: float64): float64 =
  ## Moves `value` toward `target` smoothly, covering the same fraction of
  ## the distance per second whatever the frame rate.
  target + (value - target) * exp(-rate * dt)

func wrapAngle*(a: float64): float64 =
  ## `a` brought into -PI..PI.
  a - 2 * PI * floor((a + PI) / (2 * PI))
