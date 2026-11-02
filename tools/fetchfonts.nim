## Downloads the fonts the text tests, the text scene and the lettering
## example use into tests/fonts, and checks each against a pinned SHA-256
## sum. The fonts aren't committed: `nimble fonts` runs this, and so does
## every task that compiles something that embeds them. A file that is
## already there with the right sum isn't downloaded again.
##
## The fonts are Source Sans 3 Regular in its TrueType and its CFF form,
## from Adobe's repository at a release tag, under the SIL Open Font
## License. Downloading uses `curl`, which macOS, Windows 10 and later, and
## the CI runners all have.

import std/[os, osproc, strutils]

const
  release = "3.052R"
  base = "https://raw.githubusercontent.com/adobe-fonts/source-sans/" & release & "/"
  fonts = [
    (
      "SourceSans3-Regular.ttf", "TTF/SourceSans3-Regular.ttf",
      "4644c81b86ec9caaa76b634889968ed3c4f4f52f054855933acc7c2b21e53b0f",
    ),
    (
      "SourceSans3-Regular.otf", "OTF/SourceSans3-Regular.otf",
      "08df266400933d3178d081a45f94a08814c3e55b4b7dd2e0ff69cb1329f13ab6",
    ),
  ]
  fontDir = currentSourcePath().parentDir.parentDir / "tests" / "fonts"

# SHA-256 (FIPS 180-4). The standard library has none.

const roundConstants = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32,
  0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32, 0xd807aa98'u32, 0x12835b01'u32,
  0x243185be'u32, 0x550c7dc3'u32, 0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32,
  0xc19bf174'u32, 0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
  0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32, 0x983e5152'u32,
  0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32,
  0x06ca6351'u32, 0x14292967'u32, 0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32,
  0x53380d13'u32, 0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
  0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32,
  0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32, 0x19a4c116'u32, 0x1e376c08'u32,
  0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32,
  0x682e6ff3'u32, 0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32,
]

func rotr(x: uint32, n: int): uint32 =
  (x shr n) or (x shl (32 - n))

func sha256*(data: string): string =
  ## The digest as lowercase hex.
  var h = [
    0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32, 0x510e527f'u32,
    0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32,
  ]
  # Pad with a one bit, zeros, and the length in bits as 64 bits.
  var msg = data
  msg.add '\x80'
  while msg.len mod 64 != 56:
    msg.add '\0'
  let bits = uint64(data.len) * 8
  for i in countdown(7, 0):
    msg.add char((bits shr (i * 8)) and 0xff)
  var w: array[64, uint32]
  for chunk in countup(0, msg.len - 1, 64):
    for i in 0 ..< 16:
      let p = chunk + i * 4
      w[i] =
        uint32(msg[p]) shl 24 or uint32(msg[p + 1]) shl 16 or uint32(msg[p + 2]) shl 8 or
        uint32(msg[p + 3])
    for i in 16 ..< 64:
      let s0 = rotr(w[i - 15], 7) xor rotr(w[i - 15], 18) xor (w[i - 15] shr 3)
      let s1 = rotr(w[i - 2], 17) xor rotr(w[i - 2], 19) xor (w[i - 2] shr 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
    for i in 0 ..< 64:
      let s1 = rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)
      let choose = (e and f) xor ((not e) and g)
      let t1 = hh + s1 + choose + roundConstants[i] + w[i]
      let s0 = rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)
      let majority = (a and b) xor (a and c) xor (b and c)
      let t2 = s0 + majority
      hh = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    for i, v in [a, b, c, d, e, f, g, hh]:
      h[i] += v
  for v in h:
    result.add toHex(v, 8).toLowerAscii

proc main(): int =
  doAssert sha256("abc") ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  createDir(fontDir)
  for (name, path, sum) in fonts:
    let dest = fontDir / name
    if fileExists(dest) and sha256(readFile(dest)) == sum:
      continue
    let url = base & path
    echo "fetching ", url
    let partial = dest & ".part"
    let (output, code) = execCmdEx(
      "curl --fail --silent --show-error --location --retry 3 --output " &
        quoteShell(partial) & " " & quoteShell(url)
    )
    if code != 0:
      stderr.writeLine "could not download ", url, ": ", output.strip
      removeFile(partial)
      return 1
    let got = sha256(readFile(partial))
    if got != sum:
      stderr.writeLine "checksum mismatch for ", url, ": expected ", sum, ", got ", got
      removeFile(partial)
      return 1
    moveFile(partial, dest)
  0

when isMainModule:
  quit main()
