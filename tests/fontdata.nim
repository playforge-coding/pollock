## The fonts the text tests, the text scene and the lettering example use,
## embedded at compile time so they work under JavaScript too. They aren't
## committed: `nimble fonts` downloads them into tests/fonts (see
## tools/fetchfonts.nim), and every task that needs them does that first.
##
## Source Sans 3 Regular, by Adobe, under the SIL Open Font License, in its
## TrueType form (`glyf` outlines, composite glyphs) and its CFF form
## (subroutines, hint masks, flex).

import std/[os, staticos, strutils]

const
  # Under JavaScript `std/os` follows POSIX rules even on a Windows host, so
  # `parentDir` can't take a path with backslashes apart. Windows takes
  # forward slashes too.
  fontDir = currentSourcePath().replace('\\', '/').parentDir & "/fonts"
  trueTypePath = fontDir & "/SourceSans3-Regular.ttf"
  cffPath = fontDir & "/SourceSans3-Regular.otf"

# `staticFileExists` rather than `fileExists`, which the JavaScript target
# doesn't have.
when not staticFileExists(trueTypePath) or not staticFileExists(cffPath):
  {.
    error: "the test fonts aren't in tests/fonts; run `nimble fonts` to download them"
  .}

const
  trueTypeData* = staticRead(trueTypePath)
  cffData* = staticRead(cffPath)
