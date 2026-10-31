import std/unittest
import pollock/[color, paint, geometry]

suite "color":
  test "hex parsing":
    check parseHex("#ff0000") == red
    check parseHex("00ff00") == green
    check parseHex("#00f") == blue
    check parseHex("#0000ff80").toRgba8.a == 128
    check parseHex("#f00f").a == 1.0
    expect ValueError:
      discard parseHex("#12345")
    expect ValueError:
      discard parseHex("#gggggg")

  test "hex formatting":
    check red.toHex == "#ff0000"
    check rgba8(1, 2, 3, 4).toHex == "#01020304"
    check parseHex(rgb8(12, 200, 99).toHex) == rgb8(12, 200, 99)

  test "premultiply":
    let c = rgba(1, 0.5, 0, 0.5)
    check c.premultiplied == rgba(0.5, 0.25, 0, 0.5)
    check c.premultiplied.unpremultiplied ~= c
    check transparent.unpremultiplied == transparent

  test "8-bit conversion rounds":
    check rgba(1, 0.5, 0, 1).toRgba8 == Rgba8(r: 255, g: 128, b: 0, a: 255)
    check rgba(2, -1, 0.5, 1).toRgba8 == Rgba8(r: 255, g: 0, b: 128, a: 255)

  test "lerp":
    check lerp(black, white, 0.5) == gray(0.5)

suite "paint":
  test "gradient stops":
    let stops = [stop(0.0, black), stop(0.5, red), stop(1.0, white)]
    check colorAt(stops, -1) == black
    check colorAt(stops, 0.25) == rgb(0.5, 0, 0)
    check colorAt(stops, 0.5) == red
    check colorAt(stops, 0.75) == rgb(1, 0.5, 0.5)
    check colorAt(stops, 2) == white
    check colorAt([], 0.5) == transparent

  test "extend modes":
    check applyExtend(1.5, exPad) == 1.0
    check applyExtend(-0.5, exPad) == 0.0
    check applyExtend(1.25, exRepeat) == 0.25
    check applyExtend(-0.25, exRepeat) == 0.75
    check applyExtend(1.25, exReflect) == 0.75
    check applyExtend(2.25, exReflect) == 0.25
    check applyExtend(-0.25, exReflect) == 0.25

  test "constructors":
    let p = linearGradient(point(0, 0), point(10, 0), red, blue)
    check p.kind == pkLinearGradient
    check p.stops.len == 2
    check p.isOpaque
    check not solid(red.withAlpha(0.5)).isOpaque
    check solid(red).stops[0].color == red
