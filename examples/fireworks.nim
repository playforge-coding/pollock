## Fireworks over a city. Rockets go up on their own; clicking sends one to
## the pointer, and holding the button down lights a sparkler there.
##
## Shows: a particle simulation drawn fresh every frame, translucent strokes
## with round caps for the spark trails, radial gradients for the flashes,
## and a skyline built once as a single path.

import std/[math, random]
import ./scene

type
  Spark = object
    pos, vel: Vec2
    trail: array[4, Vec2] ## Earlier positions, newest first.
    life, maxLife, hue, width, drag: float64
    twinkle: bool

  Rocket = object
    pos, vel: Vec2
    trail: array[6, Vec2]
    fuse, hue: float64
    shape: int

  Flash = object
    pos: Point
    age, hue: float64

  Fireworks* = object
    rng: Rand
    time, nextLaunch: float64
    rockets: seq[Rocket]
    sparks: seq[Spark]
    flashes: seq[Flash]
    skyline: BezPath
    windows: seq[Rect]

const
  gravity = 90.0
  ground = sceneHeight - 6
  maxSparks = 1500

func newFireworks*(): Fireworks =
  result = Fireworks(rng: initRand(2024), nextLaunch: 0.3)
  # A row of buildings, as one path along the bottom of the scene.
  var x = 0.0
  result.skyline.moveTo point(0, sceneHeight)
  while x < sceneWidth:
    let w = 22 + result.rng.rand(40.0)
    let h = 30 + result.rng.rand(90.0)
    let top = sceneHeight - h
    result.skyline.lineTo point(x, top)
    if result.rng.rand(1.0) < 0.25:
      # A spire.
      result.skyline.lineTo point(x + w / 2 - 2, top)
      result.skyline.lineTo point(x + w / 2, top - 18 - result.rng.rand(20.0))
      result.skyline.lineTo point(x + w / 2 + 2, top)
    result.skyline.lineTo point(x + w, top)
    var wy = top + 8
    while wy < sceneHeight - 10:
      var wx = x + 5
      while wx < x + w - 8:
        if result.rng.rand(1.0) < 0.35:
          result.windows.add rectXywh(wx, wy, 4, 5)
        wx += 8
      wy += 10
    x += w
  result.skyline.lineTo point(sceneWidth, sceneHeight)
  result.skyline.closePath()

proc launch(s: var Fireworks, target: Point) =
  ## Sends a rocket from the ground to burst at `target`.
  let start = vec2(target.x + s.rng.rand(-80.0 .. 80.0), ground)
  let rise = max(ground - target.y, 40.0)
  # Fired straight up at this speed, gravity stops it at the target height.
  let vy = sqrt(2 * gravity * rise)
  let fuse = vy / gravity
  let vx = (target.x - start.x) / fuse
  var r = Rocket(
    pos: start,
    vel: vec2(vx, -vy),
    fuse: fuse,
    hue: s.rng.rand(1.0),
    shape: s.rng.rand(2),
  )
  for p in r.trail.mitems:
    p = start
  s.rockets.add r

proc burst(s: var Fireworks, r: Rocket) =
  s.flashes.add Flash(pos: r.pos.toPoint, hue: r.hue)
  let count = 90 + s.rng.rand(60)
  for i in 0 ..< count:
    let angle = s.rng.rand(2 * PI)
    # 0 is a full sphere, 1 a ring (every spark at the same speed), 2 a
    # golden willow that hangs and fades slowly.
    let speed =
      case r.shape
      of 0:
        sqrt(s.rng.rand(1.0)) * 120
      of 1:
        110.0 + s.rng.rand(8.0)
      else:
        s.rng.rand(30.0 .. 90.0)
    var spark = Spark(
      pos: r.pos,
      vel: r.vel * 0.2 + vec2(cos(angle), sin(angle)) * speed,
      hue:
        if r.shape == 2:
          0.11
        else:
          r.hue + s.rng.rand(-0.04 .. 0.04),
      width: 1.2 + s.rng.rand(1.2),
      drag: if r.shape == 2: 1.6 else: 1.1,
      twinkle: s.rng.rand(1.0) < 0.3,
    )
    spark.maxLife =
      if r.shape == 2:
        2.4 + s.rng.rand(1.0)
      else:
        1.1 + s.rng.rand(0.8)
    spark.life = spark.maxLife
    for p in spark.trail.mitems:
      p = r.pos
    if s.sparks.len < maxSparks:
      s.sparks.add spark

proc sparkle(s: var Fireworks, at: Point, dt: float64) =
  ## A sparkler at the pointer: short, fast, golden sparks in every
  ## direction.
  let count = int(260 * dt) + 1
  for _ in 0 ..< count:
    let angle = s.rng.rand(2 * PI)
    let speed = s.rng.rand(20.0 .. 140.0)
    var spark = Spark(
      pos: at.toVec,
      vel: vec2(cos(angle), sin(angle)) * speed,
      hue: 0.1 + s.rng.rand(0.05),
      width: 1.0,
      drag: 4,
      twinkle: true,
    )
    spark.maxLife = 0.25 + s.rng.rand(0.35)
    spark.life = spark.maxLife
    for p in spark.trail.mitems:
      p = spark.pos
    if s.sparks.len < maxSparks:
      s.sparks.add spark

proc update*(s: var Fireworks, dt: float64, input: Input) =
  s.time += dt
  if s.time >= s.nextLaunch:
    s.launch(point(s.rng.rand(80.0 .. sceneWidth - 80), s.rng.rand(50.0 .. 180.0)))
    s.nextLaunch = s.time + s.rng.rand(0.5 .. 1.4)
  if input.inside and input.pressed:
    s.launch(input.pos)
  if input.inside and input.down:
    s.sparkle(input.pos, dt)

  var i = 0
  while i < s.rockets.len:
    var r = s.rockets[i]
    for k in countdown(r.trail.high, 1):
      r.trail[k] = r.trail[k - 1]
    r.trail[0] = r.pos
    r.vel.y += gravity * dt
    r.pos = r.pos + r.vel * dt
    r.fuse -= dt
    if r.fuse <= 0:
      s.burst(r)
      s.rockets.del i
    else:
      s.rockets[i] = r
      inc i

  i = 0
  while i < s.sparks.len:
    var p = s.sparks[i]
    for k in countdown(p.trail.high, 1):
      p.trail[k] = p.trail[k - 1]
    p.trail[0] = p.pos
    p.vel = p.vel * exp(-p.drag * dt)
    p.vel.y += gravity * 0.6 * dt
    p.pos = p.pos + p.vel * dt
    p.life -= dt
    if p.life <= 0 or p.pos.y > ground:
      s.sparks.del i
    else:
      s.sparks[i] = p
      inc i

  i = 0
  while i < s.flashes.len:
    s.flashes[i].age += dt
    if s.flashes[i].age > 0.5:
      s.flashes.del i
    else:
      inc i

proc render*[C: RenderContext](s: Fireworks, ctx: var C) =
  ctx.fill(
    sceneBounds,
    linearGradient(point(0, 0), point(0, sceneHeight), rgb8(6, 8, 26), rgb8(48, 30, 70)),
  )
  for f in s.flashes:
    let k = 1 - f.age / 0.5
    ctx.fill(
      circle(f.pos, 140),
      radialGradient(
        f.pos, 140, hsl(f.hue, 0.8, 0.7, 0.35 * k * k), hsl(f.hue, 0.8, 0.5, 0)
      ),
    )

  let trailStyle = strokeStyle(width = 2, cap = lcRound, join = ljRound)
  for r in s.rockets:
    var path = newPath()
    path.moveTo r.pos.toPoint
    for p in r.trail:
      path.lineTo p.toPoint
    ctx.stroke(
      path,
      linearGradient(
        r.pos.toPoint, r.trail[^1].toPoint, rgb8(255, 230, 180), rgba8(255, 150, 60, 0)
      ),
      trailStyle,
    )

  for p in s.sparks:
    let k = p.life / p.maxLife
    var alpha = min(1.0, k * 1.6)
    if p.twinkle and sin(p.life * 60 + p.hue * 100) < -0.3:
      alpha *= 0.25
    var path = newPath()
    path.moveTo p.pos.toPoint
    for q in p.trail[0 .. 2]:
      path.lineTo q.toPoint
    var style = trailStyle
    style.width = p.width * (0.5 + 0.5 * k)
    # Hot sparks start pale and take on their color as they cool.
    ctx.stroke(path, hsl(p.hue, 0.9, 0.55 + 0.4 * k * k, alpha), style)

  ctx.fill(s.skyline, rgb8(10, 10, 22))
  for i, w in s.windows:
    let flicker = 0.5 + 0.5 * sin(s.time * 0.7 + i.float64 * 12.9898)
    ctx.fill(w, rgb8(255, 200, 110).withAlpha(0.25 + 0.5 * flicker))
