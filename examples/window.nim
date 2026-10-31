## Runs the example scenes live in a native window. pollock itself never
## opens windows; this program gets one from SDL3 (through the official
## `sdl3` package), draws each frame with a pollock backend into pixels and
## hands them to SDL as a texture.
##
##   nimble window                        # or
##   nim r -d:release examples/window.nim [scene]
##
## Frames are drawn at the window's size in points and scaled up to the
## screen's pixels: the CPU backend is the reference renderer, written to be
## exact rather than fast, and a high-density screen has four times the
## pixels. H switches to drawing every pixel.
##
## Keys: 1 to 5 or the arrow keys switch scenes, space pauses, R restarts
## the scene, H toggles full pixel density, S saves the frame as PNG and SVG
## into `out/`, Escape quits. Built with `-d:pollockCairo` (`nimble window`
## does that when pkg-config finds Cairo), B switches between the CPU and
## Cairo backends.

import std/[math, monotimes, os, strformat, strutils, times]
import pollock/[png, backends/cpu, backends/svg]
import sdl3 except Point, Rect
import ./scenes

when defined(pollockCairo):
  import pollock/backends/cairo

type
  Backend = enum
    beCpu = "CPU"
    beCairo = "Cairo"

  App = object
    window: Window
    renderer: Renderer
    texture: Texture
    textureSize: (int, int)
    scene: Scene
    input: Input
    paused, fullDensity, quit: bool
    backend: Backend
    cpu: CpuContext
    when defined(pollockCairo):
      cairo: CairoContext
      cairoSize: (int, int)
    frames: int ## Frames since the statistics were last measured.
    frameTime: float64 ## Seconds spent drawing those frames.
    statsClock: MonoTime ## When the statistics were last measured.
    stats: string ## The last measured frame time and rate.
    titleStale: bool ## The scene, backend or size changed since the title did.

const
  letterbox = rgb8(24, 24, 28)
  outDir = "out"

proc fail(what: string) =
  quit &"{what}: {getError()}"

func viewTransform(width, height: int): Affine =
  ## Maps the scene into a target of `width` by `height` pixels: as large as
  ## it fits, centered.
  let s = min(width.float64 / sceneWidth, height.float64 / sceneHeight)
  translate(
    (width.float64 - sceneWidth * s) / 2, (height.float64 - sceneHeight * s) / 2
  ) * scale(s)

proc drawFrame[C: RenderContext](
    ctx: var C, scene: Scene, view: Affine, width, height: int
) =
  ## Draws the scene through `view` and covers whatever it drew outside its
  ## bounds with the letterbox bars. Clipping to the bounds instead would
  ## give the same picture, but the CPU backend would build a mask the size
  ## of the target every frame.
  ctx.withTransform(view):
    scene.render(ctx)
  let inside = view.transform(sceneBounds)
  let (w, h) = (width.float64, height.float64)
  for bar in [
    rect(0, 0, w, inside.y0),
    rect(0, inside.y1, w, h),
    rect(0, 0, inside.x0, h),
    rect(inside.x1, 0, w, h),
  ]:
    if bar.width > 0 and bar.height > 0:
      ctx.fill(bar, letterbox)

proc pixelSize(app: App): (int, int) =
  ## The size to draw at.
  var w, h: cint
  let ok =
    if app.fullDensity:
      getWindowSizeInPixels(app.window, w, h)
    else:
      getWindowSize(app.window, w, h)
  if not ok:
    fail "Couldn't read the window size"
  (max(w.int, 1), max(h.int, 1))

proc toScene(app: App, x, y: cfloat): Point =
  ## Window coordinates (points, not pixels) to scene coordinates.
  var w, h: cint
  discard getWindowSize(app.window, w, h)
  viewTransform(w.int, h.int).inverse * point(x.float64, y.float64)

proc updateTitle(app: var App) =
  ## Measures the frame time and rate twice a second, and rewrites the title
  ## when they change or when a key changed what it describes.
  let elapsed = (getMonoTime() - app.statsClock).inMicroseconds.float64 / 1e6
  if elapsed >= 0.5:
    let fps = round(app.frames.float64 / elapsed).int
    let ms = 1000 * app.frameTime / max(app.frames, 1).float64
    app.stats = &"{ms:.1f} ms a frame, {fps} fps"
    app.frames = 0
    app.frameTime = 0
    app.statsClock = getMonoTime()
    app.titleStale = true
  if not app.titleStale:
    return
  let (w, h) = app.pixelSize
  let paused = if app.paused: " (paused)" else: ""
  let title =
    &"pollock: {app.scene.kind.title}{paused} | {app.scene.kind.hint} | " &
    &"{app.backend} {w}x{h}, {app.stats}"
  discard setWindowTitle(app.window, cstring(title))
  app.titleStale = false

proc present(app: var App, img: ImageData) =
  if app.textureSize != (img.width, img.height):
    if app.texture != nil:
      destroyTexture(app.texture)
    app.texture = createTexture(
      app.renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STREAMING, img.width.cint,
      img.height.cint,
    )
    if app.texture == nil:
      fail "Couldn't create a texture"
    app.textureSize = (img.width, img.height)
  if not updateTexture(app.texture, nil, img.data[0].addr, cint(img.stride)):
    fail "Couldn't upload the frame"
  discard renderClear(app.renderer)
  discard renderTexture(app.renderer, app.texture, nil, nil)
  discard renderPresent(app.renderer)

proc renderFrame(app: var App): ImageData =
  let (w, h) = app.pixelSize
  let view = viewTransform(w, h)
  case app.backend
  of beCpu:
    if app.cpu.width != w or app.cpu.height != h:
      app.cpu = newCpuContext(w, h)
    app.cpu.drawFrame(app.scene, view, w, h)
    let res = app.cpu.finish()
    if not res.ok:
      quit "The CPU backend failed: " & res.message
    app.cpu.toImage()
  of beCairo:
    when defined(pollockCairo):
      if app.cairoSize != (w, h):
        app.cairo = newCairoContext(w, h)
        app.cairoSize = (w, h)
      app.cairo.drawFrame(app.scene, view, w, h)
      let res = app.cairo.finish()
      if not res.ok:
        quit "The Cairo backend failed: " & res.message
      app.cairo.toImage()
    else:
      raiseAssert "built without Cairo"

proc save(app: App) =
  ## Writes the current frame at twice the scene's size as a PNG, and as an
  ## SVG from the same drawing calls.
  createDir(outDir)
  let name = outDir / app.scene.kind.name
  var cpu = newCpuContext(2 * sceneWidth.int, 2 * sceneHeight.int)
  cpu.drawFrame(app.scene, scale(2), cpu.width, cpu.height)
  doAssert cpu.finish().ok
  writePng(cpu.toImage(), name & ".png")
  var svg = newSvgContext(sceneWidth, sceneHeight)
  svg.drawFrame(app.scene, affineIdentity, sceneWidth.int, sceneHeight.int)
  doAssert svg.finish().ok
  writeFile(name & ".svg", svg.toSvg())
  echo &"saved {name}.png and {name}.svg"

proc switchTo(app: var App, kind: SceneKind) =
  app.scene = newScene(kind)

proc handleKey(app: var App, key: Keycode) =
  # Most keys change something the title shows: the scene, the pause, the
  # backend or the size drawn at.
  app.titleStale = true
  case key
  of SDLK_ESCAPE:
    app.quit = true
  of SDLK_SPACE:
    app.paused = not app.paused
  of SDLK_R:
    app.switchTo(app.scene.kind)
  of SDLK_H:
    app.fullDensity = not app.fullDensity
  of SDLK_S:
    app.save()
  of SDLK_B:
    when defined(pollockCairo):
      app.backend = if app.backend == beCpu: beCairo else: beCpu
  of SDLK_RIGHT:
    app.switchTo(SceneKind((app.scene.kind.ord + 1) mod (SceneKind.high.ord + 1)))
  of SDLK_LEFT:
    app.switchTo(
      SceneKind((app.scene.kind.ord + SceneKind.high.ord) mod (SceneKind.high.ord + 1))
    )
  elif key >= SDLK_1 and key <= SDLK_9:
    let i = int(key - SDLK_1)
    if i <= SceneKind.high.ord:
      app.switchTo(SceneKind(i))
  else:
    discard

proc handleEvents(app: var App) =
  app.input.pressed = false
  var event: Event
  while pollEvent(event):
    case event.type
    of EVENT_QUIT:
      app.quit = true
    of EVENT_KEY_DOWN:
      if not event.key.repeat:
        app.handleKey(event.key.key)
    of EVENT_MOUSE_MOTION:
      app.input.pos = app.toScene(event.motion.x, event.motion.y)
      app.input.inside = true
    of EVENT_MOUSE_BUTTON_DOWN:
      # A click can arrive with no motion before it, such as the one that
      # focuses the window.
      app.input.pos = app.toScene(event.button.x, event.button.y)
      app.input.inside = true
      app.input.down = true
      app.input.pressed = true
    of EVENT_MOUSE_BUTTON_UP:
      app.input.down = false
    of EVENT_WINDOW_MOUSE_LEAVE:
      app.input.inside = false
    else:
      discard
  # Letterboxing leaves room around the scene; the pointer is only inside
  # when it is over the scene itself.
  if app.input.inside and not sceneBounds.contains(app.input.pos):
    app.input.inside = false

proc main() =
  var app = App(
    scene: newScene(SceneKind.low),
    statsClock: getMonoTime(),
    stats: "measuring",
    titleStale: true,
  )
  if paramCount() >= 1:
    var found = false
    for kind in SceneKind:
      if kind.name == paramStr(1):
        app.scene = newScene(kind)
        found = true
    if not found:
      var names: seq[string]
      for kind in SceneKind:
        names.add kind.name
      quit &"There is no scene {paramStr(1)}. Pick one of: {names.join(\", \")}"

  if not init(INIT_VIDEO):
    fail "Couldn't initialize SDL"
  app.window = createWindow(
    "pollock",
    cint(sceneWidth * 1.5),
    cint(sceneHeight * 1.5),
    WINDOW_RESIZABLE or WINDOW_HIGH_PIXEL_DENSITY,
  )
  if app.window == nil:
    fail "Couldn't open a window"
  app.renderer = createRenderer(app.window, nil)
  if app.renderer == nil:
    fail "Couldn't create a renderer"
  discard setRenderVSync(app.renderer, 1)
  discard setWindowMinimumSize(app.window, 320, 200)

  var last = getMonoTime()
  while not app.quit:
    app.handleEvents()
    let now = getMonoTime()
    # A long stall (a dragged window, a breakpoint) shouldn't make the
    # simulations jump.
    let dt = min((now - last).inMicroseconds.float64 / 1e6, 0.05)
    last = now
    if not app.paused:
      app.scene.update(dt, app.input)
    let start = getMonoTime()
    let img = app.renderFrame()
    app.frameTime += (getMonoTime() - start).inMicroseconds.float64 / 1e6
    app.present(img)
    inc app.frames
    app.updateTitle()

  if app.texture != nil:
    destroyTexture(app.texture)
  destroyRenderer(app.renderer)
  destroyWindow(app.window)
  sdl3.quit()

main()
