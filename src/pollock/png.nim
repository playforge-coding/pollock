## PNG reading and writing with no dependencies, so the CPU backend can save
## its output and the SVG backend can embed images on every target.
##
## Writing uses stored (uncompressed) deflate blocks: simple, fast and enough
## for test output. Reading handles any zlib stream, eight bits per channel,
## color types gray, RGB, palette, gray+alpha and RGBA, and no interlacing.

import ./image

type PngError* = object of CatchableError

const pngSignature = [0x89'u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

# Checksums

func makeCrcTable(): array[256, uint32] =
  for n in 0 .. 255:
    var c = uint32(n)
    for _ in 0 .. 7:
      if (c and 1) != 0:
        c = 0xEDB88320'u32 xor (c shr 1)
      else:
        c = c shr 1
    result[n] = c

const crcTable = makeCrcTable()

func crc32(data: openArray[uint8], start, stop: int): uint32 =
  var c = 0xFFFFFFFF'u32
  for i in start ..< stop:
    c = crcTable[int((c xor uint32(data[i])) and 0xFF)] xor (c shr 8)
  c xor 0xFFFFFFFF'u32

func adler32(data: openArray[uint8]): uint32 =
  var a = 1'u32
  var b = 0'u32
  for x in data:
    a = (a + uint32(x)) mod 65521
    b = (b + a) mod 65521
  (b shl 16) or a

# Writing

func addU32(s: var seq[uint8], v: uint32) =
  s.add uint8(v shr 24)
  s.add uint8((v shr 16) and 0xFF)
  s.add uint8((v shr 8) and 0xFF)
  s.add uint8(v and 0xFF)

func addChunk(s: var seq[uint8], kind: string, data: openArray[uint8]) =
  s.addU32 uint32(data.len)
  let start = s.len
  for ch in kind:
    s.add uint8(ch)
  s.add data
  s.addU32 crc32(s, start, s.len)

func zlibStored(raw: openArray[uint8]): seq[uint8] =
  result = @[0x78'u8, 0x01]
  var pos = 0
  while true:
    let n = min(65535, raw.len - pos)
    let final = pos + n >= raw.len
    result.add(if final: 1'u8 else: 0'u8)
    result.add uint8(n and 0xFF)
    result.add uint8(n shr 8)
    let nlen = (not n) and 0xFFFF
    result.add uint8(nlen and 0xFF)
    result.add uint8(nlen shr 8)
    for i in pos ..< pos + n:
      result.add raw[i]
    pos += n
    if final:
      break
  result.addU32 adler32(raw)

func encodePng*(img: ImageData): seq[uint8] =
  ## The PNG file contents for an image. Premultiplied images are written
  ## with straight alpha, since PNG has no premultiplied format.
  let src =
    if img.format == ifRgba8Premul:
      img.convert(ifRgba8)
    else:
      img
  let colorType =
    case src.format
    of ifGray8: 0'u8
    of ifRgb8: 2'u8
    of ifRgba8, ifRgba8Premul: 6'u8
  let stride = src.stride
  var raw = newSeqOfCap[uint8]((stride + 1) * src.height)
  for y in 0 ..< src.height:
    raw.add 0'u8 # filter: none
    for i in y * stride ..< (y + 1) * stride:
      raw.add src.data[i]

  result.add pngSignature
  var ihdr: seq[uint8]
  ihdr.addU32 uint32(src.width)
  ihdr.addU32 uint32(src.height)
  ihdr.add 8'u8 # bit depth
  ihdr.add colorType
  ihdr.add 0'u8 # compression
  ihdr.add 0'u8 # filter method
  ihdr.add 0'u8 # interlace
  result.addChunk("IHDR", ihdr)
  result.addChunk("IDAT", zlibStored(raw))
  result.addChunk("IEND", [])

# Inflate

type
  Huffman = object
    counts: array[16, int]
    symbols: seq[int]

  Inflater = object
    data: seq[uint8]
    pos: int
    bitBuf: uint32
    bitCnt: int
    output: seq[uint8]

const
  lengthBase = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
    115, 131, 163, 195, 227, 258,
  ]
  lengthExtra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,
    0,
  ]
  distBase = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
    1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  distExtra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
    12, 12, 13, 13,
  ]
  codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

func bits(r: var Inflater, n: int): uint32 =
  while r.bitCnt < n:
    if r.pos >= r.data.len:
      raise newException(PngError, "truncated deflate stream")
    r.bitBuf = r.bitBuf or (uint32(r.data[r.pos]) shl r.bitCnt)
    inc r.pos
    r.bitCnt += 8
  result = r.bitBuf and ((1'u32 shl n) - 1)
  r.bitBuf = r.bitBuf shr n
  r.bitCnt -= n

func buildHuffman(lengths: openArray[int]): Huffman =
  for l in lengths:
    inc result.counts[l]
  result.counts[0] = 0
  var offsets: array[16, int]
  for i in 1 .. 14:
    offsets[i + 1] = offsets[i] + result.counts[i]
  result.symbols = newSeq[int](lengths.len)
  for sym, l in lengths:
    if l != 0:
      result.symbols[offsets[l]] = sym
      inc offsets[l]

func decodeSymbol(r: var Inflater, h: Huffman): int =
  var code = 0
  var first = 0
  var index = 0
  for len in 1 .. 15:
    code = code or int(r.bits(1))
    let count = h.counts[len]
    if code - count < first:
      return h.symbols[index + (code - first)]
    index += count
    first += count
    first = first shl 1
    code = code shl 1
  raise newException(PngError, "bad Huffman code")

func inflateCodes(r: var Inflater, lit, dist: Huffman) =
  while true:
    var sym = r.decodeSymbol(lit)
    if sym < 256:
      r.output.add uint8(sym)
    elif sym == 256:
      return
    else:
      sym -= 257
      if sym >= lengthBase.len:
        raise newException(PngError, "bad length code")
      let length = lengthBase[sym] + int(r.bits(lengthExtra[sym]))
      let dsym = r.decodeSymbol(dist)
      if dsym >= distBase.len:
        raise newException(PngError, "bad distance code")
      let d = distBase[dsym] + int(r.bits(distExtra[dsym]))
      if d > r.output.len:
        raise newException(PngError, "distance too far back")
      let start = r.output.len - d
      for i in 0 ..< length:
        r.output.add r.output[start + i]

func inflateStored(r: var Inflater) =
  r.bitBuf = 0
  r.bitCnt = 0
  if r.pos + 4 > r.data.len:
    raise newException(PngError, "truncated stored block")
  let len = int(r.data[r.pos]) or (int(r.data[r.pos + 1]) shl 8)
  let nlen = int(r.data[r.pos + 2]) or (int(r.data[r.pos + 3]) shl 8)
  r.pos += 4
  if len != ((not nlen) and 0xFFFF):
    raise newException(PngError, "stored block length mismatch")
  if r.pos + len > r.data.len:
    raise newException(PngError, "truncated stored block")
  for i in 0 ..< len:
    r.output.add r.data[r.pos + i]
  r.pos += len

func inflateFixed(r: var Inflater) =
  var lengths = newSeq[int](288)
  for i in 0 .. 143:
    lengths[i] = 8
  for i in 144 .. 255:
    lengths[i] = 9
  for i in 256 .. 279:
    lengths[i] = 7
  for i in 280 .. 287:
    lengths[i] = 8
  var distLengths = newSeq[int](30)
  for i in 0 ..< 30:
    distLengths[i] = 5
  r.inflateCodes(buildHuffman(lengths), buildHuffman(distLengths))

func inflateDynamic(r: var Inflater) =
  let nlen = int(r.bits(5)) + 257
  let ndist = int(r.bits(5)) + 1
  let ncode = int(r.bits(4)) + 4
  if nlen > 286 or ndist > 30:
    raise newException(PngError, "bad code counts")
  var lengths = newSeq[int](19)
  for i in 0 ..< ncode:
    lengths[codeLengthOrder[i]] = int(r.bits(3))
  let lenCode = buildHuffman(lengths)
  var all = newSeq[int](nlen + ndist)
  var index = 0
  while index < all.len:
    let sym = r.decodeSymbol(lenCode)
    if sym < 16:
      all[index] = sym
      inc index
    else:
      var len = 0
      var rep = 0
      if sym == 16:
        if index == 0:
          raise newException(PngError, "repeat with no previous length")
        len = all[index - 1]
        rep = 3 + int(r.bits(2))
      elif sym == 17:
        rep = 3 + int(r.bits(3))
      else:
        rep = 11 + int(r.bits(7))
      if index + rep > all.len:
        raise newException(PngError, "too many code lengths")
      for _ in 0 ..< rep:
        all[index] = len
        inc index
  r.inflateCodes(buildHuffman(all[0 ..< nlen]), buildHuffman(all[nlen ..^ 1]))

func inflate*(data: sink seq[uint8]): seq[uint8] =
  ## Decompresses a zlib stream.
  if data.len < 2 or (data[0] and 0x0F) != 8:
    raise newException(PngError, "not a zlib stream")
  var r = Inflater(data: data, pos: 2)
  while true:
    let final = r.bits(1)
    # Bound to a name first: the JS backend evaluates a `case` selector once
    # per branch, which would read the bits several times.
    let blockType = r.bits(2)
    case blockType
    of 0:
      r.inflateStored()
    of 1:
      r.inflateFixed()
    of 2:
      r.inflateDynamic()
    else:
      raise newException(PngError, "bad block type")
    if final == 1:
      break
  r.output

# Reading

func readU32(data: openArray[uint8], pos: int): uint32 =
  (uint32(data[pos]) shl 24) or (uint32(data[pos + 1]) shl 16) or
    (uint32(data[pos + 2]) shl 8) or uint32(data[pos + 3])

func paeth(a, b, c: uint8): uint8 =
  let p = int(a) + int(b) - int(c)
  let pa = abs(p - int(a))
  let pb = abs(p - int(b))
  let pc = abs(p - int(c))
  if pa <= pb and pa <= pc:
    a
  elif pb <= pc:
    b
  else:
    c

func unfilter(raw: openArray[uint8], width, height, bpp: int): seq[uint8] =
  let stride = width * bpp
  if raw.len < (stride + 1) * height:
    raise newException(PngError, "truncated image data")
  result = newSeq[uint8](stride * height)
  var pos = 0
  for y in 0 ..< height:
    let filter = raw[pos]
    inc pos
    let row = y * stride
    let prev = (y - 1) * stride
    for i in 0 ..< stride:
      let x = raw[pos + i]
      let a =
        if i >= bpp:
          result[row + i - bpp]
        else:
          0'u8
      let b =
        if y > 0:
          result[prev + i]
        else:
          0'u8
      let c =
        if y > 0 and i >= bpp:
          result[prev + i - bpp]
        else:
          0'u8
      result[row + i] =
        case filter
        of 0:
          x
        of 1:
          x + a
        of 2:
          x + b
        of 3:
          x + uint8((int(a) + int(b)) div 2)
        of 4:
          x + paeth(a, b, c)
        else:
          raise newException(PngError, "bad filter type")
    pos += stride

func decodePng*(data: openArray[uint8]): ImageData =
  ## Decodes a PNG file. Gray and RGB images keep their format; palette and
  ## gray+alpha images come back as RGBA.
  if data.len < 8:
    raise newException(PngError, "not a PNG file")
  for i in 0 .. 7:
    if data[i] != pngSignature[i]:
      raise newException(PngError, "not a PNG file")
  var pos = 8
  var width, height, bitDepth, colorType, interlace: int
  var idat: seq[uint8]
  var palette: seq[uint8]
  var trns: seq[uint8]
  var sawHeader = false
  while pos + 8 <= data.len:
    let len = int(readU32(data, pos))
    var kind = ""
    for i in pos + 4 ..< pos + 8:
      kind.add char(data[i])
    let start = pos + 8
    if start + len + 4 > data.len:
      raise newException(PngError, "truncated chunk " & kind)
    case kind
    of "IHDR":
      width = int(readU32(data, start))
      height = int(readU32(data, start + 4))
      bitDepth = int(data[start + 8])
      colorType = int(data[start + 9])
      interlace = int(data[start + 12])
      sawHeader = true
    of "PLTE":
      palette = data[start ..< start + len]
    of "tRNS":
      trns = data[start ..< start + len]
    of "IDAT":
      idat.add data[start ..< start + len]
    of "IEND":
      break
    else:
      discard
    pos = start + len + 4
  if not sawHeader:
    raise newException(PngError, "missing IHDR")
  if bitDepth != 8:
    raise newException(PngError, "only 8-bit PNGs are supported")
  if interlace != 0:
    raise newException(PngError, "interlaced PNGs are not supported")
  let channels =
    case colorType
    of 0:
      1
    of 2:
      3
    of 3:
      1
    of 4:
      2
    of 6:
      4
    else:
      raise newException(PngError, "bad color type")
  let pixels = unfilter(inflate(idat), width, height, channels)
  case colorType
  of 0:
    result = image(width, height, ifGray8, pixels)
  of 2:
    result = image(width, height, ifRgb8, pixels)
  of 6:
    result = image(width, height, ifRgba8, pixels)
  of 3:
    result = newImage(width, height, ifRgba8)
    for i in 0 ..< width * height:
      let idx = int(pixels[i])
      if idx * 3 + 2 >= palette.len:
        raise newException(PngError, "palette index out of range")
      result.data[i * 4] = palette[idx * 3]
      result.data[i * 4 + 1] = palette[idx * 3 + 1]
      result.data[i * 4 + 2] = palette[idx * 3 + 2]
      result.data[i * 4 + 3] =
        if idx < trns.len:
          trns[idx]
        else:
          255'u8
  else:
    result = newImage(width, height, ifRgba8)
    for i in 0 ..< width * height:
      result.data[i * 4] = pixels[i * 2]
      result.data[i * 4 + 1] = pixels[i * 2]
      result.data[i * 4 + 2] = pixels[i * 2]
      result.data[i * 4 + 3] = pixels[i * 2 + 1]

when not defined(js):
  import std/syncio

  proc writePng*(img: ImageData, path: string) =
    ## Saves an image as a PNG file.
    let bytes = encodePng(img)
    var s = newString(bytes.len)
    for i, b in bytes:
      s[i] = char(b)
    writeFile(path, s)

  proc readPng*(path: string): ImageData =
    ## Loads a PNG file.
    let s = readFile(path)
    var bytes = newSeq[uint8](s.len)
    for i, ch in s:
      bytes[i] = uint8(ch)
    decodePng(bytes)
