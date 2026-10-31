## pollock: an abstract 2D graphics API.
##
## `import pollock` brings in the drawing API, PNG support and the default
## backend for the platform. Until the native backends exist that is the CPU
## backend everywhere. Choose another with `-d:pollockBackend=<module>`,
## where the module can come from any package, for example
## `-d:pollockBackend=pollock/backends/svg`.

import std/[macros, strutils]
import ./pollock/[draw, png]

export draw, png

const pollockBackend {.strdefine.} = "pollock/backends/cpu"

macro importBackend(path: static string): untyped =
  let name = path.rsplit('/', 1)[^1]
  result = newStmtList(
    newNimNode(nnkImportStmt).add(newLit(path)),
    newNimNode(nnkExportStmt).add(ident(name)),
  )

importBackend(pollockBackend)
