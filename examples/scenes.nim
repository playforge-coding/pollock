## Every example scene behind one type, so a host can switch between them
## at run time.

import ./[scene, orrery, fireworks, beziers, gears, flowfield]

export scene

type
  SceneKind* = enum
    skOrrery
    skFireworks
    skBeziers
    skGears
    skFlowField

  Scene* = object
    case kind*: SceneKind
    of skOrrery: orrery: Orrery
    of skFireworks: fireworks: Fireworks
    of skBeziers: beziers: Beziers
    of skGears: gears: Gears
    of skFlowField: flowField: FlowField

func name*(kind: SceneKind): string =
  ## A short lowercase name, for the command line and file names.
  case kind
  of skOrrery: "orrery"
  of skFireworks: "fireworks"
  of skBeziers: "beziers"
  of skGears: "gears"
  of skFlowField: "flowfield"

func title*(kind: SceneKind): string =
  case kind
  of skOrrery: "Orrery"
  of skFireworks: "Fireworks"
  of skBeziers: "Bezier curves"
  of skGears: "Gears"
  of skFlowField: "Flow field"

func hint*(kind: SceneKind): string =
  ## What the pointer does, for a host to show.
  case kind
  of skOrrery: "move up and down to tilt, left and right to change speed"
  of skFireworks: "click to launch a rocket, hold for a sparkler"
  of skBeziers: "drag the control points"
  of skGears: "drag a gear to turn the train, let go to fling it"
  of skFlowField: "move to stir, hold the button to drain"

func newScene*(kind: SceneKind): Scene =
  case kind
  of skOrrery:
    Scene(kind: skOrrery, orrery: newOrrery())
  of skFireworks:
    Scene(kind: skFireworks, fireworks: newFireworks())
  of skBeziers:
    Scene(kind: skBeziers, beziers: newBeziers())
  of skGears:
    Scene(kind: skGears, gears: newGears())
  of skFlowField:
    Scene(kind: skFlowField, flowField: newFlowField())

proc update*(s: var Scene, dt: float64, input: Input) =
  case s.kind
  of skOrrery:
    s.orrery.update(dt, input)
  of skFireworks:
    s.fireworks.update(dt, input)
  of skBeziers:
    s.beziers.update(dt, input)
  of skGears:
    s.gears.update(dt, input)
  of skFlowField:
    s.flowField.update(dt, input)

proc render*[C: RenderContext](s: Scene, ctx: var C) =
  case s.kind
  of skOrrery:
    s.orrery.render(ctx)
  of skFireworks:
    s.fireworks.render(ctx)
  of skBeziers:
    s.beziers.render(ctx)
  of skGears:
    s.gears.render(ctx)
  of skFlowField:
    s.flowField.render(ctx)
