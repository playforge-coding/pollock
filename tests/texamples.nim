## Runs every example scene without a window: a few seconds of simulated
## time with a scripted pointer, drawn on the CPU, SVG and recording
## backends. The scenes have no goldens (they are animations, and some are
## simulations), so this checks that they draw without failing, that they
## move, and that they react to the pointer.

import std/[math, strutils, unittest]
import pollock/[recording, testing, backends/cpu, backends/svg]
import scenes

const
  fps = 30.0
  seconds = 3.0
  frameCount = int(fps * seconds)

func grabPoint(kind: SceneKind): Point =
  ## Somewhere the scene has something to grab when it starts: a control
  ## point of the Bezier curve, the middle of the driving gear, and any
  ## point for the scenes that react anywhere.
  case kind
  of skBeziers:
    point(170, 60)
  of skGears:
    point(230, 200)
  else:
    point(sceneWidth / 3, sceneHeight / 3)

func scriptedInput(kind: SceneKind, frame: int): Input =
  ## A pointer that moves from the middle to the scene's grab point over a
  ## second, presses there, drags along half a circle for a second, and
  ## lets go.
  let t = frame.float64 / fps
  let grab = grabPoint(kind)
  let pos =
    if t < 1:
      lerp(point(sceneWidth / 2, sceneHeight / 2), grab, t)
    else:
      let a = PI * min(t - 1, 1.0)
      grab + vec2(40 * (cos(a) - 1), 40 * sin(a))
  Input(pos: pos, inside: true, down: t >= 1 and t < 2, pressed: frame == int(fps))

proc renderSmall(s: Scene): ImageData =
  # Half size keeps the test fast, under JavaScript too.
  var ctx = newCpuContext(int(sceneWidth / 2), int(sceneHeight / 2))
  ctx.withTransform(scale(0.5)):
    s.render(ctx)
  let res = ctx.finish()
  doAssert res.ok, res.message
  ctx.toImage()

proc run(kind: SceneKind, frames: int, withPointer: bool): Scene =
  result = newScene(kind)
  for i in 0 ..< frames:
    let input =
      if withPointer:
        scriptedInput(kind, i)
      else:
        Input()
    result.update(1 / fps, input)

suite "example scenes":
  test "every scene draws on every pure-Nim backend":
    for kind in SceneKind:
      checkpoint kind.name
      let s = run(kind, frameCount, withPointer = true)
      check renderSmall(s).width == int(sceneWidth / 2)

      var svg = newSvgContext(sceneWidth, sceneHeight)
      s.render(svg)
      check svg.finish().ok
      # Something was drawn. A length threshold would fail a simple scene.
      check "<path " in svg.toSvg()

      # Every save is matched by a restore.
      var rec = newRecordingContext()
      s.render(rec)
      var depth = 0
      for k in rec.kinds:
        if k == ckSave:
          inc depth
        elif k == ckRestore:
          dec depth
        check depth >= 0
      check depth == 0

  test "every scene moves on its own":
    for kind in SceneKind:
      checkpoint kind.name
      let before = renderSmall(run(kind, 1, withPointer = false))
      let after = renderSmall(run(kind, 20, withPointer = false))
      check not compareImages(before, after).matches

  test "every scene reacts to the pointer":
    for kind in SceneKind:
      checkpoint kind.name
      let idle = renderSmall(run(kind, frameCount, withPointer = false))
      let touched = renderSmall(run(kind, frameCount, withPointer = true))
      check not compareImages(idle, touched).matches

  test "a scene starts the same every time":
    # The simulations seed their own random numbers, so a run can be
    # repeated exactly.
    for kind in SceneKind:
      checkpoint kind.name
      let a = renderSmall(run(kind, 15, withPointer = true))
      let b = renderSmall(run(kind, 15, withPointer = true))
      check compareImages(a, b).matches
