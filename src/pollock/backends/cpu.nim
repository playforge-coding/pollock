## The CPU backend: a software rasterizer in pure Nim. It renders into a
## premultiplied RGBA float buffer and runs on every target, which makes it
## the reference renderer for the conformance tests.
##
## Fills work by flattening the path in device space and accumulating exact
## signed area coverage per pixel, the technique font rasterizers like
## font-rs use. Strokes are expanded into an outline by `stroke.nim` and
## filled with the nonzero rule. Clips are coverage masks that multiply into
## later fills.

import std/math
import ../context

export context

type
  ClipMask = ref object
    coverage: seq[float32] ## One value per pixel, 0..1.

  CpuState = object
    transform: Affine
    clip: ClipMask ## nil when nothing is clipped.

  CpuContext* = object
    width*, height*: int
    tolerance*: float64 ## Flattening tolerance in device pixels.
    pixels: seq[float32] ## Premultiplied RGBA, four values per pixel.
    acc: seq[float32] ## Coverage accumulation, `width + 2` cells per row.
    state: CpuState
    stack: seq[CpuState]
    error: string

  ShaderKind = enum
    skSolid
    skLinear
    skRadial
    skImage

  Shader = object
    ## A paint resolved into device space: `inverse` maps a device pixel
    ## back to user space where the paint is defined.
    kind: ShaderKind
    color: Color ## premultiplied
    inverse: Affine
    stops: seq[GradientStop]
    extend: Extend
    start: Point
    direction: Vec2 ## `(stop - start) / |stop - start|^2` for linear gradients
    center: Point
    radius: float64
    image: ImageData
    dst: Rect
    interp: Interpolation

proc newCpuContext*(width, height: int): CpuContext =
  ## A transparent black target of the given size in pixels.
  CpuContext(
    width: width,
    height: height,
    tolerance: 0.1,
    pixels: newSeq[float32](width * height * 4),
    acc: newSeq[float32]((width + 2) * height),
    state: CpuState(transform: affineIdentity),
  )

# Shaders

func makeShader(paint: Paint, transform: Affine): Shader =
  result.inverse = transform.inverse
  case paint.kind
  of pkSolid:
    result.kind = skSolid
    result.color = paint.color.clamped.premultiplied
  of pkLinearGradient:
    let d = paint.stop - paint.start
    let len2 = d.lengthSquared
    if len2 <= 0:
      # No direction: paint the last stop, as SVG specifies.
      result.kind = skSolid
      result.color = colorAt(paint.linearStops, 1.0).clamped.premultiplied
    else:
      result.kind = skLinear
      result.stops = paint.linearStops
      result.extend = paint.linearExtend
      result.start = paint.start
      result.direction = d / len2
  of pkRadialGradient:
    if paint.radius <= 0:
      result.kind = skSolid
      result.color = colorAt(paint.radialStops, 1.0).clamped.premultiplied
    else:
      result.kind = skRadial
      result.stops = paint.radialStops
      result.extend = paint.radialExtend
      result.center = paint.center
      result.radius = paint.radius

func imageShader(
    image: ImageData, dst: Rect, interp: Interpolation, transform: Affine
): Shader =
  Shader(
    kind: skImage, inverse: transform.inverse, image: image, dst: dst, interp: interp
  )

func texel(img: ImageData, x, y: int): Color =
  img[min(max(x, 0), img.width - 1), min(max(y, 0), img.height - 1)].premultiplied

func sample(sh: Shader, x, y: float64): Color =
  ## The premultiplied color at a device position.
  case sh.kind
  of skSolid:
    sh.color
  of skLinear:
    let u = sh.inverse * point(x, y)
    let t = applyExtend(dot(u - sh.start, sh.direction), sh.extend)
    colorAt(sh.stops, t).clamped.premultiplied
  of skRadial:
    let u = sh.inverse * point(x, y)
    let t = applyExtend(distance(u, sh.center) / sh.radius, sh.extend)
    colorAt(sh.stops, t).clamped.premultiplied
  of skImage:
    let u = sh.inverse * point(x, y)
    let fx = (u.x - sh.dst.x0) / sh.dst.width * sh.image.width.float64
    let fy = (u.y - sh.dst.y0) / sh.dst.height * sh.image.height.float64
    case sh.interp
    of ipNearest:
      sh.image.texel(int(floor(fx)), int(floor(fy)))
    of ipBilinear:
      let gx = fx - 0.5
      let gy = fy - 0.5
      let x0 = int(floor(gx))
      let y0 = int(floor(gy))
      let tx = gx - x0.float64
      let ty = gy - y0.float64
      let top = lerp(sh.image.texel(x0, y0), sh.image.texel(x0 + 1, y0), tx)
      let bottom = lerp(sh.image.texel(x0, y0 + 1), sh.image.texel(x0 + 1, y0 + 1), tx)
      lerp(top, bottom, ty)

# Rasterization

proc accumulateLine(ctx: var CpuContext, a, b: Point) =
  # Adds the signed area contribution of one edge to the accumulation
  # buffer. Both x coordinates must already lie in `0 .. width`.
  if abs(a.y - b.y) < 1e-12:
    return
  var p0 = a
  var p1 = b
  var dir = 1.0
  if a.y > b.y:
    p0 = b
    p1 = a
    dir = -1.0
  let w = ctx.width.float64
  let stride = ctx.width + 2
  let dxdy = (p1.x - p0.x) / (p1.y - p0.y)
  var x = p0.x
  if p0.y < 0:
    x -= p0.y * dxdy
  let yStart = max(0, int(floor(p0.y)))
  let yEnd = min(ctx.height, int(ceil(p1.y)))
  for y in yStart ..< yEnd:
    let lineStart = y * stride
    let dy = min(float64(y + 1), p1.y) - max(float64(y), p0.y)
    let xnext = min(w, max(0.0, x + dxdy * dy))
    x = min(w, max(0.0, x))
    let d = dy * dir
    var x0 = x
    var x1 = xnext
    if x1 < x0:
      swap x0, x1
    let x0floor = floor(x0)
    let x0i = int(x0floor)
    let x1ceil = ceil(x1)
    let x1i = int(x1ceil)
    if x1i <= x0i + 1:
      let xmf = 0.5 * (x + xnext) - x0floor
      ctx.acc[lineStart + x0i] += float32(d - d * xmf)
      ctx.acc[lineStart + x0i + 1] += float32(d * xmf)
    else:
      let s = 1.0 / (x1 - x0)
      let x0f = x0 - x0floor
      let a0 = 0.5 * s * (1.0 - x0f) * (1.0 - x0f)
      let x1f = x1 - x1ceil + 1.0
      let am = 0.5 * s * x1f * x1f
      ctx.acc[lineStart + x0i] += float32(d * a0)
      if x1i == x0i + 2:
        ctx.acc[lineStart + x0i + 1] += float32(d * (1.0 - a0 - am))
      else:
        let a1 = s * (1.5 - x0f)
        ctx.acc[lineStart + x0i + 1] += float32(d * (a1 - a0))
        for xi in x0i + 2 ..< x1i - 1:
          ctx.acc[lineStart + xi] += float32(d * s)
        let a2 = a1 + float64(x1i - x0i - 3) * s
        ctx.acc[lineStart + x1i - 1] += float32(d * (1.0 - a2 - am))
      ctx.acc[lineStart + x1i] += float32(d * am)
    x = xnext

proc accumulateEdge(ctx: var CpuContext, a, b: Point) =
  # Splits an edge where it crosses the left and right borders. The part
  # outside becomes a vertical edge on the border, which keeps its winding
  # effect on the pixels inside.
  let w = ctx.width.float64
  if a.x <= 0 and b.x <= 0:
    ctx.accumulateLine(point(0, a.y), point(0, b.y))
  elif a.x >= w and b.x >= w:
    ctx.accumulateLine(point(w, a.y), point(w, b.y))
  elif (a.x < 0) != (b.x < 0):
    let t = (0 - a.x) / (b.x - a.x)
    let m = point(0, a.y + (b.y - a.y) * t)
    ctx.accumulateEdge(a, m)
    ctx.accumulateEdge(m, b)
  elif (a.x > w) != (b.x > w):
    let t = (w - a.x) / (b.x - a.x)
    let m = point(w, a.y + (b.y - a.y) * t)
    ctx.accumulateEdge(a, m)
    ctx.accumulateEdge(m, b)
  else:
    ctx.accumulateLine(a, b)

func coverage(acc: float32, rule: FillRule): float32 =
  case rule
  of frNonZero:
    min(1.0'f32, abs(acc))
  of frEvenOdd:
    let w = abs(acc)
    let m = w - 2.0'f32 * floor(w * 0.5'f32)
    1.0'f32 - abs(1.0'f32 - m)

template forCoverage(
    ctx: var CpuContext,
    polylines: seq[Polyline],
    rule: FillRule,
    x, y: untyped,
    cov: untyped,
    body: untyped,
) =
  ## Runs `body` for every pixel the polylines cover, with `x`, `y` and the
  ## coverage `cov` (already multiplied by the clip) in scope.
  block:
    let bounds = boundingBox(polylines).intersect(
        rect(0, 0, ctx.width.float64, ctx.height.float64)
      )
    if not bounds.isEmpty:
      let rowStart = max(0, int(floor(bounds.y0)))
      let rowEnd = min(ctx.height, int(ceil(bounds.y1)))
      # Edges only write cells from `floor(x0)` to `ceil(x1) + 1`. Left of
      # that the running sum is zero, and right of the last pixel the shape
      # touches it is back to zero, since every polyline is closed. So only
      # those columns are cleared and scanned.
      let colStart = int(floor(bounds.x0))
      let accEnd = min(ctx.width + 2, int(ceil(bounds.x1)) + 2)
      let colEnd = min(ctx.width, int(ceil(bounds.x1)) + 1)
      let stride = ctx.width + 2
      for y in rowStart ..< rowEnd:
        for i in y * stride + colStart ..< y * stride + accEnd:
          ctx.acc[i] = 0
      for poly in polylines:
        let n = poly.points.len
        for i in 0 ..< n:
          ctx.accumulateEdge(poly.points[i], poly.points[(i + 1) mod n])
      let clip = ctx.state.clip
      for y in rowStart ..< rowEnd:
        var sum = 0.0'f32
        let lineStart = y * stride
        for x in colStart ..< colEnd:
          sum += ctx.acc[lineStart + x]
          var cov = coverage(sum, rule)
          if clip != nil:
            cov *= clip.coverage[y * ctx.width + x]
          if cov > 0.0005'f32:
            body

proc blend(ctx: var CpuContext, x, y: int, src: Color, cov: float32) =
  # Source-over with premultiplied colors.
  let i = (y * ctx.width + x) * 4
  let a = float32(src.a) * cov
  let inv = 1.0'f32 - a
  ctx.pixels[i] = float32(src.r) * cov + ctx.pixels[i] * inv
  ctx.pixels[i + 1] = float32(src.g) * cov + ctx.pixels[i + 1] * inv
  ctx.pixels[i + 2] = float32(src.b) * cov + ctx.pixels[i + 2] * inv
  ctx.pixels[i + 3] = a + ctx.pixels[i + 3] * inv

proc fillPolylines(
    ctx: var CpuContext, polylines: seq[Polyline], rule: FillRule, shader: Shader
) =
  if shader.kind == skSolid:
    let c = shader.color
    ctx.forCoverage(polylines, rule, x, y, cov):
      ctx.blend(x, y, c, cov)
  else:
    ctx.forCoverage(polylines, rule, x, y, cov):
      ctx.blend(x, y, shader.sample(x.float64 + 0.5, y.float64 + 0.5), cov)

func devicePolylines(ctx: CpuContext, path: BezPath): seq[Polyline] =
  ctx.state.transform.transform(path).flatten(ctx.tolerance)

# The contract

proc clear*(ctx: var CpuContext, color: Color) =
  let c = color.clamped.premultiplied
  for i in 0 ..< ctx.width * ctx.height:
    ctx.pixels[i * 4] = float32(c.r)
    ctx.pixels[i * 4 + 1] = float32(c.g)
    ctx.pixels[i * 4 + 2] = float32(c.b)
    ctx.pixels[i * 4 + 3] = float32(c.a)

proc fillPath*(ctx: var CpuContext, path: BezPath, paint: Paint, rule: FillRule) =
  if path.isEmpty:
    return
  ctx.fillPolylines(
    ctx.devicePolylines(path), rule, makeShader(paint, ctx.state.transform)
  )

proc strokePath*(ctx: var CpuContext, path: BezPath, paint: Paint, style: StrokeStyle) =
  if path.isEmpty or style.width <= 0:
    return
  # The stroke is expanded in user space so a non-uniform transform
  # stretches it like the native renderers do. The flattening tolerance is
  # converted to user units by the largest stretch, so it holds along the
  # most stretched axis too.
  let scale = max(ctx.state.transform.maxScale, 1e-12)
  let outline = strokeOutline(path, style, ctx.tolerance / scale)
  ctx.fillPolylines(
    ctx.devicePolylines(outline), frNonZero, makeShader(paint, ctx.state.transform)
  )

proc clipPath*(ctx: var CpuContext, path: BezPath, rule: FillRule) =
  var mask = ClipMask(coverage: newSeq[float32](ctx.width * ctx.height))
  # Bound first: `forCoverage` is a template and would flatten twice.
  let polylines = ctx.devicePolylines(path)
  ctx.forCoverage(polylines, rule, x, y, cov):
    mask.coverage[y * ctx.width + x] = cov
  ctx.state.clip = mask

proc save*(ctx: var CpuContext) =
  ctx.stack.add ctx.state

proc restore*(ctx: var CpuContext) =
  if ctx.stack.len > 0:
    ctx.state = ctx.stack.pop()

proc transform*(ctx: var CpuContext, affine: Affine) =
  ctx.state.transform = ctx.state.transform * affine

proc currentTransform*(ctx: CpuContext): Affine =
  ctx.state.transform

proc drawImage*(
    ctx: var CpuContext, image: ImageData, dst: Rect, interp: Interpolation
) =
  if image.isEmpty or dst.isEmpty:
    return
  ctx.fillPolylines(
    ctx.devicePolylines(dst.toPath),
    frNonZero,
    imageShader(image, dst, interp, ctx.state.transform),
  )

proc finish*(ctx: var CpuContext): RenderResult =
  if ctx.error.len > 0:
    result = failure(ctx.error)
    ctx.error = ""
  else:
    result = success()

# Reading back

func pixel*(ctx: CpuContext, x, y: int): Color =
  ## The straight-alpha color of one pixel.
  let i = (y * ctx.width + x) * 4
  Color(
    r: ctx.pixels[i].float64,
    g: ctx.pixels[i + 1].float64,
    b: ctx.pixels[i + 2].float64,
    a: ctx.pixels[i + 3].float64,
  ).unpremultiplied

func toImage*(ctx: CpuContext, format = ifRgba8): ImageData =
  ## The rendered picture.
  result = newImage(ctx.width, ctx.height, format)
  for y in 0 ..< ctx.height:
    for x in 0 ..< ctx.width:
      result[x, y] = ctx.pixel(x, y).clamped

static:
  doAssert CpuContext is RenderContext
