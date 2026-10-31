# The sdl3 package loads libSDL3 at run time by its bare name, which macOS
# doesn't look for in Homebrew's prefix. When pkg-config knows SDL3, link it
# at build time instead (its flags carry an rpath). Without pkg-config (on
# Windows, usually) the program loads SDL3.dll from beside the executable or
# the PATH. (`nim check` doesn't run external commands, so it sees an empty
# result and skips this.)
let (libs, code) = gorgeEx("pkg-config --libs sdl3")
if code == 0 and libs.len > 0:
  switch("dynlibOverride", "SDL3")
  switch("passL", libs)
