## Pixel images: the input to `drawImage` and the output of the CPU backend.

import ./color

type
  ImageFormat* = enum
    ifGray8 ## One byte per pixel.
    ifRgb8 ## Three bytes per pixel.
    ifRgba8 ## Four bytes per pixel, straight alpha.
    ifRgba8Premul ## Four bytes per pixel, alpha multiplied into the channels.

  ImageData* = object
    width*, height*: int
    format*: ImageFormat
    data*: seq[uint8] ## Rows top to bottom, no padding.

func bytesPerPixel*(format: ImageFormat): int =
  case format
  of ifGray8: 1
  of ifRgb8: 3
  of ifRgba8, ifRgba8Premul: 4

func newImage*(width, height: int, format = ifRgba8): ImageData =
  ImageData(
    width: width,
    height: height,
    format: format,
    data: newSeq[uint8](width * height * format.bytesPerPixel),
  )

func image*(width, height: int, format: ImageFormat, data: sink seq[uint8]): ImageData =
  ## Wraps existing pixel data. Raises `ValueError` when the length doesn't
  ## match the dimensions.
  if data.len != width * height * format.bytesPerPixel:
    raise newException(
      ValueError, "image data has the wrong length for its size and format"
    )
  ImageData(width: width, height: height, format: format, data: data)

func isEmpty*(img: ImageData): bool =
  img.width <= 0 or img.height <= 0

func stride*(img: ImageData): int =
  img.width * img.format.bytesPerPixel

func `[]`*(img: ImageData, x, y: int): Color =
  ## The pixel at `(x, y)` as a straight-alpha color.
  let i = (y * img.width + x) * img.format.bytesPerPixel
  case img.format
  of ifGray8:
    let v = img.data[i].float64 / 255
    Color(r: v, g: v, b: v, a: 1.0)
  of ifRgb8:
    rgb8(img.data[i], img.data[i + 1], img.data[i + 2])
  of ifRgba8:
    rgba8(img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3])
  of ifRgba8Premul:
    rgba8(img.data[i], img.data[i + 1], img.data[i + 2], img.data[i + 3]).unpremultiplied

func `[]=`*(img: var ImageData, x, y: int, c: Color) =
  let i = (y * img.width + x) * img.format.bytesPerPixel
  case img.format
  of ifGray8:
    img.data[i] = toRgba8(gray(0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)).r
  of ifRgb8:
    let p = c.toRgba8
    img.data[i] = p.r
    img.data[i + 1] = p.g
    img.data[i + 2] = p.b
  of ifRgba8:
    let p = c.toRgba8
    img.data[i] = p.r
    img.data[i + 1] = p.g
    img.data[i + 2] = p.b
    img.data[i + 3] = p.a
  of ifRgba8Premul:
    let p = c.premultiplied.toRgba8
    img.data[i] = p.r
    img.data[i + 1] = p.g
    img.data[i + 2] = p.b
    img.data[i + 3] = p.a

func convert*(img: ImageData, format: ImageFormat): ImageData =
  ## The same picture in another format.
  if img.format == format:
    return img
  result = newImage(img.width, img.height, format)
  for y in 0 ..< img.height:
    for x in 0 ..< img.width:
      result[x, y] = img[x, y]
