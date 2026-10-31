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
