#import "default.typ": default
#import "@preview/cetz:0.2.2"
#import "utils.typ"
#import cetz.draw

#let default-anchor = (type: "coord", anchor: (0, 0))
#let max-int = 9223372036854775807

#let default-ctx = (
	// general
  last-anchor: default-anchor, // keep trace of the place to draw
  group-id: 0,                 // id of the current group
  link-id: 0,                  // id of the current link
	links: (),                   // list of links to draw
  hooks: (:),                  // list of hooks
	hooks-links: (),						 // list of links to hooks
  relative-angle: 0deg,        // current global relative angle
  angle: 0deg,                 // current global angle

	// branch
	first-branch: false,         // true if the next element is the first in a branch

	// cycle
	first-molecule: none,        // name of the first molecule in the cycle
  in-cycle: false,             // true if we are in a cycle
  cycle-faces: 0,              // number of faces in the current cycle
  faces-count: 0,              // number of faces already drawn
  cycle-step-angle: 0deg,      // angle between two faces in the cycle
	record-vertex: false,        // true if the cycle should keep track of its vertices
	vertex-anchors: (),          // list of the cycle vertices
)

#let set-last-anchor(ctx, anchor) = {
  if ctx.last-anchor.type == "link" {
    ctx.links.push(ctx.last-anchor)
  }
  (..ctx, last-anchor: anchor)
}

#let link-molecule-index(angle, end, count, vertical) = {
  if not end {
    if vertical and utils.angle-in-range-strict(angle, 0deg, 180deg) {
      0
    } else if utils.angle-in-range-strict(angle, 90deg, 270deg) {
      0
    } else {
      count
    }
  } else {
    if vertical and utils.angle-in-range-strict(angle, 0deg, 180deg) {
      count
    } else if utils.angle-in-range-strict(angle, 90deg, 270deg) {
      count
    } else {
      0
    }
  }
}

#let molecule-link-anchor(name, id, count) = {
  if count <= id {
    panic("The last molecule only has " + str(count) + " connections")
  }
  if id == -1 {
    id = count - 1
  }
  (name: name, anchor: (str(id), "center"))
}

#let link-molecule-anchor(name: none, id, count) = {
  if id >= count {
    panic("This molecule only has " + str(count) + " anchors")
  }
  if id == -1 {
    panic("The index of the molecule to link to must be defined")
  }
  if name == none {
    (name: str(id), anchor: "center")
  } else {
    (name: name, anchor: (str(id), "center"))
  }
}

#let angle-from-ctx(ctx, object, default) = {
  if "relative" in object {
    object.at("relative") + ctx.relative-angle
  } else if "absolute" in object {
    object.at("absolute")
  } else if "angle" in object {
    object.at("angle") * ctx.config.angle-increment
  } else {
    default
  }
}

#let cycle-angle(ctx) = {
  if ctx.in-cycle {
    if ctx.faces-count == 0 {
      ctx.relative-angle - ctx.cycle-step-angle - (180deg - ctx.cycle-step-angle) / 2
    } else {
      ctx.relative-angle - (180deg - ctx.cycle-step-angle) / 2
    }
  } else {
    ctx.angle
  }
}

/// Draw a triangle between two molecules
#let cram(from, to, ctx, args) = {
  import cetz.draw: *

  let (ctx, (from-x, from-y, _)) = cetz.coordinate.resolve(ctx, from)
  let (ctx, (to-x, to-y, _)) = cetz.coordinate.resolve(ctx, to)
  let base-length = utils.convert-length(
    ctx,
    args.at("base-length", default: .8em),
  )
  line(
    (from-x, from-y - base-length / 2),
    (from-x, from-y + base-length / 2),
    (to-x, to-y),
    close: true,
    stroke: args.at("stroke", default: none),
    fill: args.at("fill", default: black),
  )
}

/// Draw a dashed triangle between two molecules
#let dashed-cram(from, to, length, ctx, args) = {
  import cetz.draw: *
  let (ctx, (from-x, from-y, _)) = cetz.coordinate.resolve(ctx, from)
  let (ctx, (to-x, to-y, _)) = cetz.coordinate.resolve(ctx, to)
  let base-length = utils.convert-length(
    ctx,
    args.at("base-length", default: .8em),
  )
  hide({
    line(name: "top", (from-x, from-y - base-length / 2), (to-x, to-y - 0.05))
    line(
      name: "bottom",
      (from-x, from-y + base-length / 2),
      (to-x, to-y + 0.05),
    )
  })
  let stroke = args.at("stroke", default: black + .05em)
  let dash-gap = utils.convert-length(ctx, args.at("dash-gap", default: .3em))
  let dash-width = stroke.thickness
  let converted-dash-width = utils.convert-length(ctx, dash-width)
  let length = utils.convert-length(ctx, length)

  let dash-count = int(calc.ceil(length / (dash-gap + converted-dash-width)))
  let incr = 100% / dash-count

  let percentage = 0%
  while percentage <= 100% {
    line(
      (name: "top", anchor: percentage),
      (name: "bottom", anchor: percentage),
      stroke: stroke,
    )
    percentage += incr
  }
}

#let draw-molecule-text(mol) = {
  for (id, eq) in mol.atoms.enumerate() {
    let name = str(id)
    // draw atoms of the group one after the other from left to right
    draw.content(
      name: name,
      anchor: if mol.vertical {
        "north"
      } else {
        "west"
      },
      (
        if id == 0 {
          (0, 0)
        } else if mol.vertical {
          (to: str(id - 1) + ".south", rel: (0, -.2em))
        } else {
          str(id - 1) + ".east"
        }
      ),
      {
        show math.equation: math.upright
        eq
      },
    )
    id += 1
  }
}

#let draw-molecule(mol, ctx) = {
  let name = mol.name
  if name != none {
    if name in ctx.hooks {
      panic("Molecule with name " + name + " already exists")
    }
    ctx.hooks.insert(name, mol)
  } else {
    name = "molecule" + str(ctx.group-id)
  }
  let (anchor, side, coord) = if ctx.last-anchor.type == "coord" {
    ("east", true, ctx.last-anchor.anchor)
  } else if ctx.last-anchor.type == "link" {
    if ctx.last-anchor.to == none {
      ctx.last-anchor.to = link-molecule-index(
        ctx.last-anchor.angle,
        true,
        mol.count - 1,
        mol.vertical,
      )
    }
    let anchor = link-molecule-anchor(ctx.last-anchor.to, mol.count)
    ctx.last-anchor.to-name = name
    (anchor, false, ctx.last-anchor.name + "-end-anchor")
  } else {
    panic("A molecule must be linked to a coord or a link")
  }
  ctx = set-last-anchor(
    ctx,
    (type: "molecule", name: name, count: mol.at("count"), vertical: mol.vertical),
  )
  ctx.group-id += 1
  (
    ctx,
    {
      draw.group(
        anchor: if side {
          anchor
        } else {
          "from" + str(ctx.group-id)
        },
        name: name,
        {
          draw.set-origin(coord)
          draw.anchor("default", (0, 0))
          draw-molecule-text(mol)
          if not side {
            draw.anchor("from" + str(ctx.group-id), anchor)
          }
        },
      )
    },
  )
}

#let angle-override(angle, ctx) = {
  if ctx.in-cycle {
    ("offset": "left")
  } else {
    (:)
  }
}

#let draw-last-cycle-link(link, ctx) = {
  let from-name = none
  let from-pos = none
  if ctx.last-anchor.type == "molecule" {
    from-name = ctx.last-anchor.name
    from-pos = (name: from-name, anchor: "center")
    if from-name not in ctx.hooks {
      ctx.hooks.insert(from-name, ctx.last-anchor)
    }
  } else if ctx.last-anchor.type == "link" {
    from-pos = ctx.last-anchor.name + "-end-anchor"
  } else {
    panic("A cycle link must be linked to a molecule or a link")
  }
  ctx.links.push((
    type: "link",
    name: link.at("name", default: "link" + str(ctx.link-id)),
    from-pos: from-pos,
    from-name: from-name,
    to-name: ctx.first-molecule,
    from: link.at("from", default: none),
    to: link.at("to", default: none),
    override: (offset: "left"),
    draw: link.draw,
  ))
  ctx.link-id += 1
  (ctx, ())
}

#let draw-link(link, ctx) = {
  let link-angle = 0deg
  if ctx.in-cycle {
    if ctx.faces-count == ctx.cycle-faces - 1 and ctx.first-molecule != none {
      return draw-last-cycle-link(link, ctx)
    }
    if ctx.faces-count == 0 {
      link-angle = ctx.relative-angle
    } else {
      link-angle = ctx.relative-angle + ctx.cycle-step-angle
    }
  } else {
    link-angle = angle-from-ctx(ctx, link, ctx.angle)
  }
  link-angle = utils.angle-correction(link-angle)
  ctx.relative-angle = link-angle
  let override = angle-override(link-angle, ctx)

  let to-connection = link.at("to", default: none)
  let from-connection = none
  let from-name = none

  let from-pos = if ctx.last-anchor.type == "coord" {
    ctx.last-anchor.anchor
  } else if ctx.last-anchor.type == "molecule" {
    from-connection = link-molecule-index(
      link-angle,
      false,
      ctx.last-anchor.count - 1,
      ctx.last-anchor.vertical,
    )
    from-connection = link.at("from", default: from-connection)
    from-name = ctx.last-anchor.name
    molecule-link-anchor(
      ctx.last-anchor.name,
      from-connection,
      ctx.last-anchor.count,
    )
  } else if ctx.last-anchor.type == "link" {
    ctx.last-anchor.name + "-end-anchor"
  } else {
    panic("Unknown anchor type " + ctx.last-anchor.type)
  }
  let length = link.at("atom-sep", default: ctx.config.atom-sep)
  let link-name = link.at("name", default: "link" + str(ctx.link-id))
  if ctx.record-vertex {
    if ctx.faces-count == 0 {
      ctx.vertex-anchors.push(from-pos)
    }
    if ctx.faces-count < ctx.cycle-faces - 1 {
      ctx.vertex-anchors.push(link-name + "-end-anchor")
    }
  }
  ctx = set-last-anchor(
    ctx,
    (
      type: "link",
      name: link-name,
      override: override,
      from-pos: from-pos,
      from-name: from-name,
      from: from-connection,
      to-name: none,
      to: to-connection,
      angle: link-angle,
      draw: link.draw,
    ),
  )
  ctx.link-id += 1
  (
    ctx,
    {
      let anchor = (to: from-pos, rel: (angle: link-angle, radius: length))
      if ctx.config.debug {
        draw.line(from-pos, anchor, stroke: blue + .1em)
      }
      draw.group(
        name: link-name + "-end-anchor",
        {
          draw.anchor("default", anchor)
        },
      )
    },
  )
}

/// Insert missing vertices in the cycle
#let missing-vertices(ctx, vertex, cetz-ctx) = {
  let atom-sep = utils.convert-length(cetz-ctx, ctx.config.atom-sep)
  for i in range(ctx.cycle-faces - vertex.len()) {
    let (x, y, _) = vertex.last()
    vertex.push((
      x + atom-sep * calc.cos(ctx.relative-angle + ctx.cycle-step-angle * (i + 1)),
      y + atom-sep * calc.sin(ctx.relative-angle + ctx.cycle-step-angle * (i + 1)),
      0,
    ))
  }
  vertex
}

#let cycle-center-radius(ctx, cetz-ctx, vertex) = {
  let min-radius = max-int
  let center = (0, 0)
  let faces = ctx.cycle-faces
  let odd = calc.rem(faces, 2) == 1
  for (i, v) in vertex.enumerate() {
    if (ctx.config.debug) {
      draw.circle(v, radius: .1em, fill: blue, stroke: blue)
    }
    let (x, y, _) = v
    center = (center.at(0) + x, center.at(1) + y)
    if odd {
      let opposite1 = calc.rem-euclid(i + calc.div-euclid(faces, 2), faces)
      let opposite2 = calc.rem-euclid(i + calc.div-euclid(faces, 2) + 1, faces)
      let (ox1, oy1, _) = vertex.at(opposite1)
      let (ox2, oy2, _) = vertex.at(opposite2)
      let radius = utils.distance-between(cetz-ctx, (x, y), ((ox1 + ox2) / 2, (oy1 + oy2) / 2)) / 2
      if radius < min-radius {
        min-radius = radius
      }
    } else {
      let opposite = calc.rem-euclid(i + calc.div-euclid(faces, 2), faces)
      let (ox, oy, _) = vertex.at(opposite)
      let radius = utils.distance-between(cetz-ctx, (x, y), (ox, oy)) / 2
      if radius < min-radius {
        min-radius = radius
      }
    }
  }
  ((center.at(0) / vertex.len(), center.at(1) / vertex.len()), min-radius)
}

#let draw-cycle-center-arc(ctx, name, arc) = {
  let faces = ctx.cycle-faces
  let vertex = ctx.vertex-anchors
  draw.get-ctx(cetz-ctx => {
    let (cetz-ctx, ..vertex) = cetz.coordinate.resolve(cetz-ctx, ..vertex)
    if vertex.len() < faces {
      vertex = missing-vertices(ctx, cetz-ctx)
    }
    let (center, min-radius) = cycle-center-radius(ctx, cetz-ctx, vertex)
    if name != none {
      draw.group(
        name: name,
        {
          draw.anchor("default", center)
        },
      )
    }
    if arc != none {
      if min-radius == max-int {
        panic("The cycle has no opposite vertices")
      }
      if ctx.cycle-faces > 4 {
        min-radius *= arc.at("radius", default: 0.7)
      } else {
        min-radius *= arc.at("radius", default: 0.5)
      }
      let start = arc.at("start", default: 0deg)
      let end = arc.at("end", default: 360deg)
      let delta = arc.at("delta", default: end - start)
      center = (
        center.at(0) + min-radius * calc.cos(start),
        center.at(1) + min-radius * calc.sin(start),
      )
      draw.arc(
        center,
        ..arc,
        radius: min-radius,
        start: start,
        delta: delta,
      )
    }
  })

}

#let draw-hooks-links(links, name, ctx, from-mol) = {
  for (to-name, (link,)) in links {
    if to-name not in ctx.hooks {
      panic("Molecule " + to-name + " does not exist")
    }
    let to-hook = ctx.hooks.at(to-name)
    if to-hook.type == "molecule" {
      ctx.links.push((
        type: "link",
        name: link.at("name", default: "link" + str(ctx.link-id)),
        from-pos: if from-mol {
          (name: name, anchor: "center")
        } else {
          name + "-end-anchor"
        },
        from-name: if from-mol {
          name
        },
        to-name: to-name,
        from: none,
        to: none,
        override: angle-override(ctx.angle, ctx),
        draw: link.draw,
      ))
    } else if to-hook.type == "hook" {
      ctx.links.push((
        type: if from-mol {
          "mol-hook-link"
        } else {
          "link-hook-link"
        },
        name: link.at("name", default: "link" + str(ctx.link-id)),
        from-pos: if from-mol {
          (name: name, anchor: "center")
        } else {
          name + "-end-anchor"
        },
        from-name: if from-mol {
          name
        },
        to-name: to-name,
        to-hook: to-hook.hook,
        override: angle-override(ctx.angle, ctx),
        draw: link.draw,
      ))
    } else {
      panic("Unknown hook type " + ctx.hook.at(to-name).type)
    }
    ctx.link-id += 1
  }
  ctx
}

#let update-parent-context(parent-ctx, ctx) = {
  (
    ..parent-ctx,
    hooks: parent-ctx.hooks + ctx.hooks,
    hooks-links: parent-ctx.hooks-links + ctx.hooks-links,
    links: parent-ctx.links + ctx.links,
    group-id: ctx.group-id,
    link-id: ctx.link-id,
  )
}

#let draw-molecules-and-link(ctx, body) = {
  let drawing = ()
  let cetz-drawing = ()
  (
    {
      for element in body {
        if ctx.in-cycle and ctx.faces-count >= ctx.cycle-faces {
          continue
        }
        if type(element) == function {
          cetz-drawing.push(element)
        } else if "type" not in element {
          panic("Element " + str(element) + " has no type")
        } else if element.type == "molecule" {
          if ctx.first-branch {
            panic("A molecule can not be the first element in a cycle")
          }
          (ctx, drawing) = draw-molecule(element, ctx)
          drawing
          if element.links.len() != 0 {
            ctx.hooks.insert(ctx.last-anchor.name, element)
            ctx.hooks-links.push((element.links, ctx.last-anchor.name, true))
          }
        } else if element.type == "link" {
          ctx.first-branch = false
          (ctx, drawing) = draw-link(element, ctx)
          ctx.faces-count += 1
          drawing
          if element.links.len() != 0 {
            ctx.hooks-links.push((element.links, ctx.last-anchor.name, false))
          }
        } else if element.type == "branch" {
          let angle = angle-from-ctx(ctx, element.args, cycle-angle(ctx))
          let (drawing, branch-ctx, cetz-rec) = draw-molecules-and-link(
            (
              ..ctx,
              in-cycle: false,
              first-branch: true,
              cycle-step-angle: 0,
              angle: angle,
            ),
            element.draw,
          )
          ctx = update-parent-context(ctx, branch-ctx)
          cetz-drawing += cetz-rec
          drawing
        } else if element.type == "cycle" {
          let cycle-step-angle = 360deg / element.faces
          let angle = angle-from-ctx(ctx, element.args, none)
          if angle == none {
            if ctx.in-cycle {
              angle = ctx.relative-angle - (180deg - cycle-step-angle)
              if ctx.faces-count != 0 {
                angle += ctx.cycle-step-angle
              }
            } else if ctx.relative-angle == 0deg and ctx.angle == 0deg and not element.args.at(
              "align",
              default: false,
            ) {
              angle = cycle-step-angle - 90deg
            } else {
              angle = ctx.relative-angle - (180deg - cycle-step-angle) / 2
            }
          }
          let first-molecule = none
          if ctx.last-anchor.type == "molecule" {
            first-molecule = ctx.last-anchor.name
            if first-molecule not in ctx.hooks {
              ctx.hooks.insert(first-molecule, ctx.last-anchor)
            }
          }
          let name = none
          let record-vertex = false
          if "name" in element.args {
            name = element.args.at("name")
            record-vertex = true
          } else if "arc" in element.args {
            record-vertex = true
          }
          let (drawing, cycle-ctx, cetz-rec) = draw-molecules-and-link(
            (
              ..ctx,
              in-cycle: true,
              cycle-faces: element.faces,
              faces-count: 0,
              first-branch: true,
              cycle-step-angle: cycle-step-angle,
              relative-angle: angle,
              first-molecule: first-molecule,
              angle: angle,
              record-vertex: record-vertex,
              vertex-anchors: (),
            ),
            element.draw,
          )
          ctx = update-parent-context(ctx, cycle-ctx)
          cetz-drawing += cetz-rec
          drawing
          if record-vertex {
            draw-cycle-center-arc(cycle-ctx, name, element.args.at("arc", default: none))
          }
        } else if element.type == "hook" {
          if element.name in ctx.hooks {
            panic("Hook " + element.name + " already exists")
          }
          if ctx.last-anchor.type == "link" {
            ctx.hooks.insert(element.name, (type: "hook", hook: ctx.last-anchor.name + "-end-anchor"))
          } else if ctx.last-anchor.type == "coord" {
            ctx.hooks.insert(element.name, (type: "hook", hook: ctx.last-anchor.anchor))
          } else {
            panic("A hook must placed after a link or at the beginning of the skeleton")
          }
        } else {
          panic("Unknown element type " + element.type)
        }
      }
      if ctx.last-anchor.type == "link" {
        ctx.links.push(ctx.last-anchor)
      }
    },
    ctx,
    cetz-drawing,
  )
}

#let anchor-north-east(cetz-ctx, (x, y, _), delta, molecule, id) = {
  let (cetz-ctx, (_, b, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "north")),
  )
  let (cetz-ctx, (a, _, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "east")),
  )
  let a = (a - x) + delta
  let b = (b - y) + delta
  (a, b)
}

#let anchor-north-west(cetz-ctx, (x, y, _), delta, molecule, id) = {
  let (cetz-ctx, (_, b, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "north")),
  )
  let (cetz-ctx, (a, _, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "west")),
  )
  let a = (x - a) + delta
  let b = (b - y) + delta
  (a, b)
}

#let anchor-south-west(cetz-ctx, (x, y, _), delta, molecule, id) = {
  let (cetz-ctx, (_, b, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "south")),
  )
  let (cetz-ctx, (a, _, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "west")),
  )
  let a = (x - a) + delta
  let b = (y - b) + delta
  (a, b)
}

#let anchor-south-east(cetz-ctx, (x, y, _), delta, molecule, id) = {
  let (cetz-ctx, (_, b, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "south")),
  )
  let (cetz-ctx, (a, _, _)) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "east")),
  )
  let a = (a - x) + delta
  let b = (y - b) + delta
  (a, b)
}

#let molecule-anchor(ctx, cetz-ctx, angle, molecule, id) = {
  let delta = utils.convert-length(cetz-ctx, ctx.config.delta)
  let (cetz-ctx, center) = cetz.coordinate.resolve(
    cetz-ctx,
    (name: molecule, anchor: (id, "center")),
  )

  let (a, b) = if utils.angle-in-range(angle, 0deg, 90deg) {
    anchor-north-east(cetz-ctx, center, delta, molecule, id)
  } else if utils.angle-in-range(angle, 90deg, 180deg) {
    anchor-north-west(cetz-ctx, center, delta, molecule, id)
  } else if utils.angle-in-range(angle, 180deg, 270deg) {
    anchor-south-west(cetz-ctx, center, delta, molecule, id)
  } else {
    anchor-south-east(cetz-ctx, center, delta, molecule, id)
  }

  // https://www.petercollingridge.co.uk/tutorials/computational-geometry/finding-angle-around-ellipse/
  let angle = if utils.angle-in-range-inclusive(angle, 0deg, 90deg) or utils.angle-in-range-strict(
    angle,
    270deg,
    360deg,
  ) {
    calc.atan(calc.tan(angle) * a / b)
  } else {
    calc.atan(calc.tan(angle) * a / b) - 180deg
  }


  if a == 0 or b == 0 {
    panic("Ellipse " + ellipse + " has no width or height")
  }
  (center.at(0) + a * calc.cos(angle), center.at(1) + b * calc.sin(angle))
}

#let calculate-mol-mol-link-anchors(ctx, cetz-ctx, link) = {
  let to-pos = (name: link.to-name, anchor: "center")
  if link.to == none or link.from == none {
    let angle = utils.angle-between(cetz-ctx, link.from-pos, to-pos)
    link.angle = angle
    if link.from == none {
      link.from = link-molecule-index(
        angle,
        false,
        ctx.hooks.at(link.from-name).count - 1,
        ctx.hooks.at(link.from-name).vertical,
      )
    }
    if link.to == none {
      link.to = link-molecule-index(
        angle,
        true,
        ctx.hooks.at(link.to-name).count - 1,
        ctx.hooks.at(link.to-name).vertical,
      )
    }
  }
  let start = molecule-anchor(ctx, cetz-ctx, link.angle, link.from-name, str(link.from))
  let end = molecule-anchor(ctx, cetz-ctx, link.angle + 180deg, link.to-name, str(link.to))
  ((start, end), utils.angle-between(cetz-ctx, start, end))
}

#let calculate-link-mol-anchors(ctx, cetz-ctx, link) = {
  if link.to == none {
    let angle = utils.angle-correction(
      utils.angle-between(
        cetz-ctx,
        link.from-pos,
        (name: link.to-name, anchor: "center"),
      ),
    )
    link.to = link-molecule-index(
      angle,
      true,
      ctx.hooks.at(link.to-name).count - 1,
      ctx.hooks.at(link.to-name).vertical,
    )
    link.angle = angle
  } else if "angle" not in link {
    link.angle = utils.angle-correction(
      utils.angle-between(
        cetz-ctx,
        link.from-pos,
        (name: link.to-name, anchor: (str(link.to), "center")),
      ),
    )
  }
  let end-anchor = molecule-anchor(
    ctx,
    cetz-ctx,
    link.angle + 180deg,
    link.to-name,
    str(link.to),
  )
  (
    (
      link.from-pos,
      end-anchor,
    ),
    utils.angle-between(cetz-ctx, link.from-pos, end-anchor),
  )
}

#let calculate-mol-link-anchors(ctx, cetz-ctx, link) = {
  (
    (
      molecule-anchor(ctx, cetz-ctx, link.angle, link.from-name, str(link.from)),
      link.name + "-end-anchor",
    ),
    link.angle,
  )
}

#let calculate-mol-hook-link-anchors(ctx, cetz-ctx, link) = {
  let hook = ctx.hooks.at(link.to-name)
  let angle = utils.angle-correction(
    utils.angle-between(cetz-ctx, link.from-pos, hook.hook),
  )
  let from = link-molecule-index(
    angle,
    false,
    ctx.hooks.at(link.from-name).count - 1,
    ctx.hooks.at(link.from-name).vertical,
  )
  let start-anchor = molecule-anchor(ctx, cetz-ctx, angle, link.from-name, str(from))
  (
    (
      start-anchor,
      hook.hook,
    ),
    utils.angle-between(cetz-ctx, start-anchor, hook.hook),
  )
}

#let calculate-link-hook-link-anchors(ctx, cetz-ctx, link) = {
  let hook = ctx.hooks.at(link.to-name)
  (
    (
      link.from-pos,
      hook.hook,
    ),
    utils.angle-between(cetz-ctx, link.from-pos, hook.hook),
  )
}

#let calculate-link-link-anchors(link) = {
  ((link.from-pos, link.name + "-end-anchor"), link.angle)
}

#let calculate-link-anchors(ctx, cetz-ctx, link) = {
  if link.type == "mol-hook-link" {
    calculate-mol-hook-link-anchors(ctx, cetz-ctx, link)
  } else if link.type == "link-hook-link" {
    calculate-link-hook-link-anchors(ctx, cetz-ctx, link)
  } else if link.to-name != none and link.from-name != none {
    calculate-mol-mol-link-anchors(ctx, cetz-ctx, link)
  } else if link.to-name != none {
    calculate-link-mol-anchors(ctx, cetz-ctx, link)
  } else if link.from-name != none {
    calculate-mol-link-anchors(ctx, cetz-ctx, link)
  } else {
    calculate-link-link-anchors(link)
  }
}

#let draw-link-decoration(ctx) = {
  import cetz.draw: *
  (
    get-ctx(cetz-ctx => {
      for link in ctx.links {
        let ((from, to), angle) = calculate-link-anchors(ctx, cetz-ctx, link)
        if ctx.config.debug {
          circle(from, radius: .1em, fill: red, stroke: red)
          circle(to, radius: .1em, fill: red, stroke: red)
        }
        let length = utils.distance-between(cetz-ctx, from, to)
        hide(line(from, to, name: link.name))
        group({
          set-origin(from)
          rotate(angle)
          (link.draw)(length, cetz-ctx, override: link.override)
        })
      }
    }),
    ctx,
  )
}

#let draw-skeleton(config: default, body) = {
  let ctx = default-ctx
  ctx.angle = config.base-angle
  ctx.config = config
  let (draw, ctx, cetz-drawing) = draw-molecules-and-link(ctx, body)
  for (links, name, from-mol) in ctx.hooks-links {
    ctx = draw-hooks-links(links, name, ctx, from-mol)
  }
  let (links, _) = draw-link-decoration(ctx)
  {
    draw
    links
    cetz-drawing
  }
}

/// setup a molecule skeleton drawer
#let skeletize(debug: false, background: none, config: (:), body) = {
  for (key, value) in default {
    if key not in config {
      config.insert(key, value)
    }
  }
  if "debug" not in config {
    config.insert("debug", debug)
  }
  cetz.canvas(
    debug: debug,
    background: background,
    draw-skeleton(config: config, body),
  )
}