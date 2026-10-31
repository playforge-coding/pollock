import std/unittest
import pollock/[draw, recording]

suite "high-level API on the recording backend":
  test "shapes become paths":
    var ctx = newRecordingContext()
    ctx.fill(rect(0, 0, 10, 10), red)
    ctx.fill(circle(5, 5, 2), solid(blue), frEvenOdd)
    check ctx.kinds == @[ckFillPath, ckFillPath]
    check ctx.commands[0].path == rect(0, 0, 10, 10).toPath
    check ctx.commands[0].paint == solid(red)
    check ctx.commands[0].rule == frNonZero
    check ctx.commands[1].rule == frEvenOdd

  test "stroke width shorthand":
    var ctx = newRecordingContext()
    ctx.stroke(line(0, 0, 1, 1), black, 3.0)
    ctx.stroke(line(0, 0, 1, 1), solid(black), strokeStyle(width = 2, cap = lcRound))
    check ctx.commands[0].style.width == 3.0
    check ctx.commands[0].style.cap == lcButt
    check ctx.commands[1].style.cap == lcRound

  test "withSave restores the transform":
    var ctx = newRecordingContext()
    ctx.withSave:
      ctx.translate(10, 20)
      check ctx.currentTransform == translate(10, 20)
      ctx.scale(2)
      check ctx.currentTransform == translate(10, 20) * scale(2)
    check ctx.currentTransform.isIdentity
    check ctx.kinds == @[ckSave, ckTransform, ckTransform, ckRestore]

  test "withTransform and withClip":
    var ctx = newRecordingContext()
    ctx.withTransform(rotate(1.0)):
      ctx.withClip(circle(0, 0, 1)):
        ctx.fill(rect(0, 0, 1, 1), green)
    check ctx.kinds ==
      @[ckSave, ckTransform, ckSave, ckClipPath, ckFillPath, ckRestore, ckRestore]
    check ctx.commands[3].rule == frNonZero
    check ctx.currentTransform.isIdentity

  test "restore runs when the body raises":
    var ctx = newRecordingContext()
    try:
      ctx.withSave:
        raise newException(ValueError, "boom")
    except ValueError:
      discard
    check ctx.kinds == @[ckSave, ckRestore]

  test "drawImage helpers":
    var ctx = newRecordingContext()
    let img = newImage(4, 2)
    ctx.drawImage(img, point(10, 20))
    ctx.drawImage(img, rect(0, 0, 8, 8))
    check ctx.commands[0].dst == rect(10, 20, 14, 22)
    check ctx.commands[0].interp == ipBilinear
    check ctx.commands[1].dst == rect(0, 0, 8, 8)

  test "clear and finish":
    var ctx = newRecordingContext()
    ctx.clear(white)
    check ctx.finish().ok
    check ctx.kinds == @[ckClear, ckFinish]
