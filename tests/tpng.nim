import std/unittest
import pollock/[color, image, png, testing]

proc testImage(format: ImageFormat): ImageData =
  result = newImage(13, 7, format)
  for y in 0 ..< result.height:
    for x in 0 ..< result.width:
      result[x, y] = rgba(
        x / 12,
        y / 6,
        0.25,
        if format == ifRgba8:
          (x + y) / 18
        else:
          1.0,
      )

suite "png":
  test "round trip":
    for format in [ifGray8, ifRgb8, ifRgba8]:
      let img = testImage(format)
      let back = decodePng(encodePng(img))
      check back.format == format
      check compareImages(img, back).matches

  test "premultiplied is written straight":
    var img = newImage(2, 1, ifRgba8Premul)
    img[0, 0] = rgba(1, 0, 0, 0.5)
    let back = decodePng(encodePng(img))
    check back.format == ifRgba8
    check back[0, 0].toRgba8 == Rgba8(r: 255, g: 0, b: 0, a: 128)

  test "empty image":
    let img = newImage(0, 0)
    check decodePng(encodePng(img)).width == 0

  test "inflate handles a real zlib stream":
    # zlib.compress(b"hello hello hello hello, pollock", 9) from Python
    let stream = @[
      0x78'u8, 0xDA, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x75, 0x14,
      0x0A, 0xF2, 0x81, 0x54, 0x72, 0x36, 0x00, 0xC4, 0xBC, 0x0B, 0xF1,
    ]
    let bytes = inflate(stream)
    var s = ""
    for b in bytes:
      s.add char(b)
    check s == "hello hello hello hello, pollock"

  test "rejects garbage":
    expect PngError:
      discard decodePng(@[1'u8, 2, 3])
    expect PngError:
      discard inflate(@[0'u8, 0])

  test "format conversion":
    let img = testImage(ifRgba8)
    let rgb = img.convert(ifRgb8)
    check rgb.format == ifRgb8
    check rgb[3, 2].withAlpha(1.0) ~= img[3, 2].withAlpha(1.0).toRgba8.toColor
    # Premultiplying loses precision at low alpha, so round-trip an opaque
    # image for an exact check and only compare alpha for the translucent one.
    let opaque = testImage(ifRgb8)
    check compareImages(opaque, opaque.convert(ifRgba8Premul)).matches
    let premul = img.convert(ifRgba8Premul)
    for y in 0 ..< img.height:
      for x in 0 ..< img.width:
        check premul[x, y].toRgba8.a == img[x, y].toRgba8.a
        check premul.data[(y * img.width + x) * 4] <=
          img.data[(y * img.width + x) * 4 + 3]

suite "png hardening":
  proc pngWith(chunks: openArray[(string, seq[uint8])]): seq[uint8] =
    # The decoder doesn't check CRCs, so these files carry zeros there.
    result = @[0x89'u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    for (kind, data) in chunks:
      let n = data.len
      result.add [
        uint8(n shr 24),
        uint8((n shr 16) and 0xFF),
        uint8((n shr 8) and 0xFF),
        uint8(n and 0xFF),
      ]
      for ch in kind:
        result.add uint8(ch)
      result.add data
      result.add [0'u8, 0, 0, 0]

  proc patchU32(bytes: var seq[uint8], pos: int, v: uint32) =
    bytes[pos] = uint8(v shr 24)
    bytes[pos + 1] = uint8((v shr 16) and 0xFF)
    bytes[pos + 2] = uint8((v shr 8) and 0xFF)
    bytes[pos + 3] = uint8(v and 0xFF)

  test "a short IHDR is a PngError":
    expect PngError:
      discard decodePng(pngWith([("IHDR", newSeq[uint8]()), ("IEND", newSeq[uint8]())]))
    expect PngError:
      discard decodePng(pngWith([("IHDR", @[0'u8, 0, 0, 1, 0, 0, 0, 1, 8])]))

  test "inflate stops at its output limit":
    let stream = @[
      0x78'u8, 0xDA, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x75, 0x14,
      0x0A, 0xF2, 0x81, 0x54, 0x72, 0x36, 0x00, 0xC4, 0xBC, 0x0B, 0xF1,
    ]
    check inflate(stream, maxOutput = 32).len == 32
    expect PngError:
      discard inflate(stream, maxOutput = 31)
    let stored = encodePng(newImage(4, 4))
    expect PngError:
      # The IDAT holds 68 bytes; a 1x1 header allows 5.
      var shrunk = stored
      shrunk.patchU32(16, 1)
      shrunk.patchU32(20, 1)
      discard decodePng(shrunk)

  test "dimensions past the PNG limit are rejected":
    var huge = encodePng(newImage(1, 1))
    huge.patchU32(16, 0xFFFF_FFFF'u32)
    expect PngError:
      discard decodePng(huge)
    var wide = encodePng(newImage(1, 1))
    wide.patchU32(16, 0x7FFF_FFFF'u32)
    wide.patchU32(20, 0x7FFF_FFFF'u32)
    expect PngError:
      discard decodePng(wide)
