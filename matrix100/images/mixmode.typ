#import "@preview/cetz:0.4.0": canvas, draw, tree
#import "@preview/cetz-plot:0.1.2": plot
#import "../graph.typ": show-grid-graph, grid-graph-locations, show-graph, spring-layout, show-udg-graph, udg-graph, random-regular-graph
#set page(width: auto, height: auto, margin: 5pt)

#let mixmode() = {
  import draw: *
  let DY = 1.3
  let DY2 = 0.7
  let DY3 = 0.5
  let DX1 = 2.5
  let DX2 = 1.2
  let DX3 = 0.7
  let DX4 = 0.3
  let DX5 = 0.15
  let root = (0, DY)
  let left = (-DX1, 0)
  let right = (DX1, 0)
  let left_left = (-DX1 - DX2, -DY)
  let left_right = (-DX1 + DX2, -DY)
  let right_left = (DX1 - DX2, -DY)
  let right_mid = (DX1 + DX2/2, -DY)
  let right_right = (DX1 +  2 * DX2, -DY)

  let left_left_left = (-DX1 - DX2 - DX3, -2*DY)
  let left_left_right = (-DX1 - DX2 + DX3, -2*DY)
  let left_right_left = (-DX1 + DX2 - DX3, -2*DY)
  let left_right_right = (-DX1 + DX2 + DX3, -2*DY)
  let right_left_left = (DX1 - DX2 - DX3, -2*DY)
  let right_left_right = (DX1 - DX2 + DX3, -2*DY)
  let right_right_left = (DX1 + DX2 - DX3, -2*DY)
  let right_right_right = (DX1 + DX2 + DX3, -2*DY)

  // rect((-DX1 - DX2 - DX3 - DX4 - DX5 - 0.5, -2 * DY + 0.2), (DX1 + DX2 + DX3 + DX4 + DX5 + 0.5, -2*DY - DY2 - DY3 - 0.2), fill: blue.transparentize(50%), radius: 3pt, stroke: (dash: "dashed"))
  let ymid = -2*DY + 0.5

  for (a, b) in ((root, left), (root, right), (left, left_left), (left, left_right), (right, right_left), (right, right_right), (left_left, left_left_left), (left_left, left_left_right), (right, right_mid)){
    line(a, b)
    circle(a, radius:0.1, fill: red.lighten(30%))
  }

  set-origin((-5, -4))
  show-grid-graph(4, 4, filling:0.6, unitdisk: 1.5, gridsize: 0.4, radius: 0.1, seed: 1)
  set-origin((1.7, 0))
  show-grid-graph(4, 4, filling:0.6, unitdisk: 1.5, gridsize: 0.4, radius: 0.1, seed: 2)
  set-origin((1.7, 1.2))
  show-grid-graph(4, 4, filling:0.8, unitdisk: 1.5, gridsize: 0.4, radius: 0.1, seed: 3)
  set-origin((2.2, 0))
  show-grid-graph(4, 4, filling:0.8, unitdisk: 1.5, gridsize: 0.4, radius: 0.1, seed: 4)
  set-origin((2, 0))
  show-grid-graph(4, 4, filling:0.8, unitdisk: 1.5, gridsize: 0.4, radius: 0.1, seed: 5)
  set-origin((2, 0))
  show-grid-graph(4, 4, filling:0.8, unitdisk: 1.5, gridsize: 0.4, radius: 0.1, seed: 6)
}

#let mixmode_tree() = {
  import draw: *
  set-origin((4, 0.35))
  let DY = 1.3
  let DY2 = 0.7
  let DY3 = 0.5
  let DX1 = 2.5
  let DX2 = 1.2
  let DX3 = 0.7
  let DX4 = 0.3
  let DX5 = 0.15
  let root = (0, DY)
  let left = (-DX1, 0)
  let right = (DX1, 0)
  let left_left = (-DX1 - DX2, -DY)
  let left_right = (-DX1 + DX2, -DY)
  let right_left = (DX1 - DX2, -DY)
  let right_right = (DX1 + DX2, -DY)

  let left_left_left = (-DX1 - DX2 - DX3, -2*DY)
  let left_left_right = (-DX1 - DX2 + DX3, -2*DY)
  let left_right_left = (-DX1 + DX2 - DX3, -2*DY)
  let left_right_right = (-DX1 + DX2 + DX3, -2*DY)
  let right_left_left = (DX1 - DX2 - DX3, -2*DY)
  let right_left_right = (DX1 - DX2 + DX3, -2*DY)
  let right_right_left = (DX1 + DX2 - DX3, -2*DY)
  let right_right_right = (DX1 + DX2 + DX3, -2*DY)

  // rect((-DX1 - DX2 - DX3 - DX4 - DX5 - 0.5, -2 * DY + 0.2), (DX1 + DX2 + DX3 + DX4 + DX5 + 0.5, -2*DY - DY2 - DY3 - 0.2), fill: blue.transparentize(50%), radius: 3pt, stroke: (dash: "dashed"))
  let ymid = -2*DY + 0.5

  for (a, b) in ((root, left), (root, right), (left, left_left), (left, left_right), (right, right_left), (right, right_right), (left_left, left_left_left), (left_left, left_left_right), (left_right, left_right_left), (left_right, left_right_right), (right_left, right_left_left), (right_left, right_left_right), (right_right, right_right_left), (right_right, right_right_right)){
    line(a, b)
    circle(a, radius:0.1, fill: red.lighten(30%))
  }

  for (l, t) in ((left_left_left, [$W_1$]), (left_left_right, [$B_(12)$]), (left_right_left, [$W_2$]), (left_right_right, [$B_(23)$]), (right_left_left, [$W_3$]), (right_left_right, [$B_(34)$]), (right_right_left, [$W_4$]), (right_right_right, [$B_(41)$])){
    let a = (rel: (-DX4, -DY2), to: l)
    let b = (rel: (DX4, -DY2), to: l)
    line(l, a)
    line(l, b)
    line(a, (rel: (-DX5, -DY3), to: a))
    line(a, (rel: (DX5, -DY3), to: a))
    line(b, (rel: (-DX5, -DY3), to: b))
    line(b, (rel: (DX5, -DY3), to: b))
    circle(l, radius:0.1, fill: red.lighten(30%))
    circle(a, radius:0.1, fill: red.lighten(30%))
    circle(b, radius:0.1, fill: red.lighten(30%))
  }
  content((0.0, 1.7), text(16pt)[$t ~ gamma^(rho)$])
  content((4, 0.5), text(16pt)[$t_2 ~ gamma^(rho-Delta rho_2)$])
  content((-4, 0.5), text(16pt)[$t_1 ~ gamma^(rho-Delta rho_1)$])
}

#let mixmode-bb() = {
  import draw: *
  set-origin((4, 0.35))
  let DY = 1.3
  let DY2 = 0.7
  let DY3 = 0.5
  let DX1 = 2.5
  let DX2 = 1.2
  let DX3 = 0.7
  let DX4 = 0.3
  let DX5 = 0.15
  let root = (0, DY)
  let left = (-DX1, 0)
  let right = (DX1, 0)
  let left_left = (-DX1 - DX2, -DY)
  let left_right = (-DX1 + DX2, -DY)
  let right_left = (DX1 - DX2, -DY)
  let right_right = (DX1 + DX2, -DY)

  let left_left_left = (-DX1 - DX2 - DX3, -2*DY)
  let left_left_right = (-DX1 - DX2 + DX3, -2*DY)
  let left_right_left = (-DX1 + DX2 - DX3, -2*DY)
  let left_right_right = (-DX1 + DX2 + DX3, -2*DY)
  let right_left_left = (DX1 - DX2 - DX3, -2*DY)
  let right_left_right = (DX1 - DX2 + DX3, -2*DY)
  let right_right_left = (DX1 + DX2 - DX3, -2*DY)
  let right_right_right = (DX1 + DX2 + DX3, -2*DY)

  // rect((-DX1 - DX2 - DX3 - DX4 - DX5 - 0.5, -2 * DY + 0.2), (DX1 + DX2 + DX3 + DX4 + DX5 + 0.5, -2*DY - DY2 - DY3 - 0.2), fill: blue.transparentize(50%), radius: 3pt, stroke: (dash: "dashed"))
  let ymid = -2*DY + 0.5
  line((-DX1 - DX2 - DX3 - 0.5, ymid), (DX1 + DX2 + DX3 + 4.5, ymid), stroke: (dash: "dashed"))

  for (a, b) in ((root, left), (root, right), (left, left_left), (left, left_right), (right, right_left), (right, right_right), (left_left, left_left_left), (left_left, left_left_right), (left_right, left_right_left), (left_right, left_right_right), (right_left, right_left_left), (right_left, right_left_right), (right_right, right_right_left), (right_right, right_right_right)){
    line(a, b)
    circle(a, radius:0.1, fill: red.lighten(30%))
  }

  for (l, t) in ((left_left_left, [$W_1$]), (left_left_right, [$B_(12)$]), (left_right_left, [$W_2$]), (left_right_right, [$B_(23)$]), (right_left_left, [$W_3$]), (right_left_right, [$B_(34)$]), (right_right_left, [$W_4$]), (right_right_right, [$B_(41)$])){
    let a = (rel: (-DX4, -DY2), to: l)
    let b = (rel: (DX4, -DY2), to: l)
    line(l, a)
    line(l, b)
    line(a, (rel: (-DX5, -DY3), to: a))
    line(a, (rel: (DX5, -DY3), to: a))
    line(b, (rel: (-DX5, -DY3), to: b))
    line(b, (rel: (DX5, -DY3), to: b))
    circle(l, radius:0.1, fill: blue.lighten(30%))
    circle(a, radius:0.1, fill: blue.lighten(30%))
    circle(b, radius:0.1, fill: blue.lighten(30%))
  }
  content((6.8, -1.2), text(16pt)[`ob`])
  content((7.5, -3), text(16pt)[`xiao2013`])

}

#figure(canvas(length: 1.0cm, {
  mixmode()
}))
