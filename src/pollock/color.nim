## Colors. sRGB with straight (not premultiplied) alpha, components in 0..1.

import std/[math, strutils]

type
  Color* = object
    r*, g*, b*, a*: float64

  Rgba8* = object ## Eight bits per channel, straight alpha.
    r*, g*, b*, a*: uint8

func rgba*(r, g, b, a: float64): Color =
  Color(r: r, g: g, b: b, a: a)

func rgb*(r, g, b: float64): Color =
  Color(r: r, g: g, b: b, a: 1.0)

func rgba8*(r, g, b, a: uint8): Color =
  Color(r: r.float64 / 255, g: g.float64 / 255, b: b.float64 / 255, a: a.float64 / 255)

func rgb8*(r, g, b: uint8): Color =
  rgba8(r, g, b, 255)

func gray*(level: float64, alpha = 1.0): Color =
  Color(r: level, g: level, b: level, a: alpha)

func withAlpha*(c: Color, a: float64): Color =
  Color(r: c.r, g: c.g, b: c.b, a: a)

func clamp01(x: float64): float64 =
  min(1.0, max(0.0, x))

func clamped*(c: Color): Color =
  Color(r: clamp01(c.r), g: clamp01(c.g), b: clamp01(c.b), a: clamp01(c.a))

func toUint8(x: float64): uint8 =
  uint8(round(clamp01(x) * 255))

func toRgba8*(c: Color): Rgba8 =
  Rgba8(r: toUint8(c.r), g: toUint8(c.g), b: toUint8(c.b), a: toUint8(c.a))

func toColor*(c: Rgba8): Color =
  rgba8(c.r, c.g, c.b, c.a)

func premultiplied*(c: Color): Color =
  ## The color with its alpha multiplied into the channels, which is what
  ## compositing math wants.
  Color(r: c.r * c.a, g: c.g * c.a, b: c.b * c.a, a: c.a)

func unpremultiplied*(c: Color): Color =
  if c.a <= 0:
    Color(r: 0, g: 0, b: 0, a: 0)
  else:
    Color(r: c.r / c.a, g: c.g / c.a, b: c.b / c.a, a: c.a)

func lerp*(a, b: Color, t: float64): Color =
  ## Interpolates straight-alpha channels, which is how gradients are
  ## specified in SVG and the native renderers.
  Color(
    r: a.r + (b.r - a.r) * t,
    g: a.g + (b.g - a.g) * t,
    b: a.b + (b.b - a.b) * t,
    a: a.a + (b.a - a.a) * t,
  )

func `~=`*(a, b: Color): bool =
  abs(a.r - b.r) < 1e-9 and abs(a.g - b.g) < 1e-9 and abs(a.b - b.b) < 1e-9 and
    abs(a.a - b.a) < 1e-9

func toHex*(c: Color): string =
  ## `#rrggbb`, or `#rrggbbaa` when the color is not opaque.
  let p = c.toRgba8
  result =
    "#" & p.r.toHex(2).toLowerAscii & p.g.toHex(2).toLowerAscii &
    p.b.toHex(2).toLowerAscii
  if p.a != 255:
    result.add p.a.toHex(2).toLowerAscii

func parseHex*(s: string): Color =
  ## Parses `#rgb`, `#rgba`, `#rrggbb` and `#rrggbbaa`, with or without the
  ## hash. Raises `ValueError` for anything else.
  var h = s
  if h.len > 0 and h[0] == '#':
    h = h[1 ..^ 1]
  func nibble(ch: char): int =
    case ch
    of '0' .. '9':
      ord(ch) - ord('0')
    of 'a' .. 'f':
      ord(ch) - ord('a') + 10
    of 'A' .. 'F':
      ord(ch) - ord('A') + 10
    else:
      raise newException(ValueError, "not a hex digit: " & ch)

  var bytes: array[4, uint8] = [0'u8, 0, 0, 255]
  case h.len
  of 3, 4:
    for i in 0 ..< h.len:
      let n = nibble(h[i])
      bytes[i] = uint8(n * 17)
  of 6, 8:
    for i in 0 ..< h.len div 2:
      bytes[i] = uint8(nibble(h[2 * i]) * 16 + nibble(h[2 * i + 1]))
  else:
    raise newException(ValueError, "not a hex color: " & s)
  rgba8(bytes[0], bytes[1], bytes[2], bytes[3])

const
  transparent* = Color(r: 0, g: 0, b: 0, a: 0)
  black* = Color(r: 0, g: 0, b: 0, a: 1)
  white* = Color(r: 1, g: 1, b: 1, a: 1)
  red* = Color(r: 1, g: 0, b: 0, a: 1)
  green* = Color(r: 0, g: 1, b: 0, a: 1)
  blue* = Color(r: 0, g: 0, b: 1, a: 1)
  yellow* = Color(r: 1, g: 1, b: 0, a: 1)
  cyan* = Color(r: 0, g: 1, b: 1, a: 1)
  magenta* = Color(r: 1, g: 0, b: 1, a: 1)
