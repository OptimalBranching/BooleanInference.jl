#import "@preview/touying:0.6.1": *
#import "@preview/touying-simpl-hkustgz:0.1.2": *
#import "@preview/cetz:0.4.0": canvas, draw, tree, vector, decorations
#import "@preview/cetz-plot:0.1.2": plot
#import "graph.typ": show-grid-graph, grid-graph-locations, show-graph, spring-layout, show-udg-graph, udg-graph, random-regular-graph
#import "images/mixmode.typ": mixmode, mixmode_tree, mixmode-bb
#import "@preview/pinit:0.2.2": *
#import "@preview/ctheorems:1.1.3": *
#import "diagbox.typ": *
#import "characters.typ": *

// Theorems configuration by ctheorems
#show: thmrules.with(qed-symbol: $square$)

#let theorem = thmbox("theorem", "Theorem", stroke: black).with(numbering: none)
#let corollary = thmplain(
  "corollary",
  "Corollary",
  base: "theorem",
  titlefmt: strong
)

#let definition = thmbox("definition", "Definition", inset: (x: 1.2em, top: 1em)).with(numbering: none)
#let example = thmplain("example", "Example").with(numbering: none)
#let proof = thmproof("proof", "Proof")
#let jinguo(txt) = [#txt]

#let globalvars = state("t", 0)
#let timecounter(minutes) = [
  #globalvars.update(t => t + minutes)
  #place(top + right, dx: 0%, dy: -5%, align(right, text(16pt, red)[#context globalvars.get()min]))
]
#let clip(image, top: 0pt, bottom: 0pt, left: 0pt, right: 0pt) = {
  box(clip: true, image, inset: (top: -top, right: -right, left: -left, bottom: -bottom))
}
#set cite(style: "apa")

#let ket(x) = $|#x angle.r$

#let tensor(location, name, label) = {
  import draw: *
  circle(location, radius: 13pt, name: name)
  content((), text(black, label))
}

#let labelnode(loc, label) = {
  import draw: *
  content(loc, [$#label$], align: center, fill:white, frame:"rect", padding:0.12, stroke: none, name: label)
}
#let codebox(txt, width: auto, size: 14pt) = {
  box(inset: 10pt, stroke: blue.lighten(70%), radius:4pt, fill: blue.transparentize(90%), text(size, txt), width: width)
}

#let myslide(left, right, gutter: 20pt) = {
  grid(columns: (1fr, 1fr), gutter: gutter, left, right)
}

#let strokered(loc, radius) = {
  import draw: *
  circle(loc, radius: radius, stroke: (paint: red, thickness: 2pt))
}
#let fillgray(loc, radius) = {
  import draw: *
  circle(loc, radius: radius, fill:gray)
}
#let fillblack(loc, radius) = {
  import draw: *
  circle(loc, radius: radius, fill:black)
}

#let demograph(colors, fontsize: 14pt) = {
  import draw: *
  circle((0, 0.5), radius:(4, 4), stroke: black, fill: green.lighten(50%))
  circle((-0.3, 1), radius:(3, 2.5), stroke: none, fill: white)
  let dx = 2.0
  let dy = 1.5
  for ((loc, name), color) in (((-dx, 0), "a"), ((-dx/2, 1.8*dy), "b"), ((dx/1.3, -dy/5), "c"), ((0, 0), "d"), ((-dx/2, dy), "e")).zip(colors) {
    circle(loc, radius:0.4, name: name, stroke: black, fill: color)
    content(loc, text(fontsize, name))
  }
  for (a, b) in (("a", "d"), ("a", "e"), ("b", "e"), ("c", "d"), ("d", "e")) {
    line(a, b)
  }
  line("a", (rel: (-1, -1), to: "a"))
  line("c", (rel: (1, -1), to: "c"))
  line("b", (rel: (0, 1), to: "b"))
  content((dx/2, 1), [$R$])
  content((0, -2.5), [$G$])
}

#let hd(name) = table.cell(text(10pt)[#name], fill: green.lighten(50%))
#let s(name) = table.cell(text(10pt)[#name])

#let decision(a, token, size: 1) = {
  import draw: *
  let color = if token < 0 {red} else {white}
  rect((a.at(0) - size / 2, a.at(1) - size / 2), (a.at(0) + size / 2, a.at(1) + size / 2), radius: 3pt, fill:color)
  if calc.abs(token) == 1 {
    content(a, text(14pt)[$1$])
  } else if calc.abs(token) == 2 {
    content(a, text(14pt)[$0$])
  } else if calc.abs(token) == 0 {
    content(a, text(14pt)[])
  }
}
#let decision_sequence(a, tokens, size: 1) = {
  import draw: *
  for (k, token) in tokens.enumerate() {
    decision((a.at(0) + k * size, a.at(1)), token, size: size)
  }
}

#let main-diagram() = {
  import draw: *
  content((0, -2), box(text(15pt)[Check some variables, get *feasible set*: $cal(S)$], stroke: black, inset: 10pt), name: "select")
  content((0, -4), box(text(15pt)[Generate *branching rules*: $cal(D)$], stroke: black, inset: 10pt), name: "rules")
  content((0, -6), box(text(15pt)[Try each branch], stroke: black, inset: 10pt), name: "branching")

  let ps_1 = (0, -7.5)
  let ps_2 = (0, -9.5)
  let ps_3 = (-3, -8.5)
  let ps_4 = (3, -8.5)

  line(ps_1, ps_3, ps_2, ps_4, close: true)

  content((0, -8.5), text(15pt)[More variables?], stroke: black, inset: 10pt)

  let point_1 = (6, -8.5)
  let point_2 = (6, -2)
  let point_start = (0, 0.0)
  let point_end = (0, -11.0)
  line("select", "rules", mark: (end: "straight"))
  line("rules", "branching", mark: (end: "straight"))
  line(ps_4, point_1, point_2, "select.east", mark: (end: "straight"))
  line(point_start, "select", mark: (end: "straight"))
  line("branching", ps_1, mark: (end: "straight"))
  line(ps_2, point_end, mark: (end: "straight"))
  content((4, -8), text(15pt)[Yes])
  content((-0.5, -10), text(15pt)[No])
}

#let norm(v) = calc.sqrt(v.map(x => calc.pow(x, 2)).sum())
#let distance(a, b) = norm(a.zip(b).map(x => x.at(0) - x.at(1)))

#show: hkustgz-theme.with(
  config-info(
    title: [B&B Tensor Network for Combinatorial Optimization],
    subtitle: [arXiv:2412.07685],
    author: [Jin-Guo Liu],
    date: datetime.today(),
    institution: [HKUST(GZ) - FUNH - Advanced Materials Thrust],
  ),
)

#title-slide()
#outline-slide()

= Tensor network for constraint satisfaction

== LLM needs a reasoner
#timecounter(1)

#v(10pt)

LLM fomulate problem + Reasoner solve it: @Pan2023

#figure(image("images/logiclm.png"))

*Reasoner*: Logic programming, Satisfiability Modulo Theories (SMT), constraint satisfaction problems (#highlight([CSP])), etc.
(Searching prohibitively large solution space!)

==
#figure(canvas({
  import draw: *
  content((-5, 0), [*LLM*])
  content((0, 0), [*Human*])
  content((5, 0), [*Reasoner*])
  content((-3, -1), text(12pt)[Reasoning])
  line((-2, -1), (-1, -1), mark: (end: "straight"))
  content((4.2, -1), text(12pt)[Knowledge & Intuition])
  line((2, -1), (1, -1), mark: (end: "straight"))
}))

*Examples*: "Fill a 9×9 Sudoku grid so each row, column, and 3×3 box contains 1-9."

#align(center, grid(columns: 3, gutter: 30pt, align: left, align(top)[
  *First order logic*
  
  #text(13pt)[```
  ∀i,j,k (Cell(i,j)=Cell(i,k) 
    → j=k)
  ∀i,j,k (Cell(i,j)=Cell(k,j) 
    → i=k)
  ...
  ```]
  
  ✓ Most expressive\ 
  ✗ Undecidable
], align(top)[
  *SMT (Z3, CVC5)*
  
  #text(13pt)[```smt
  (declare-const c11 Int)
  ...
  (assert (distinct row1))
  (assert (distinct col1))
  (check-sat)
  ```]
  
  ✓ Boolean + theories\
  ✓ Decidable
], align(top)[
  *CSP (Our Focus)*
  
  #text(13pt)[```
  Each cell ∈ {1..9}
  
  AllDifferent(each row)
  AllDifferent(each col)
  AllDifferent(each box)
  ```]
  
  ✓ Highly efficient\
  ✓ Combinatorial opt.
]))

#place(dx: 57%, dy: -47%, text(14pt, fill: red, align(center)[$arrow.l$\ foundation]))

== Constraint satisfaction problems: MIS and SAT
#timecounter(1)
#myslide(align(top)[
  *Maximum Independent Set (MIS)*
  #figure(canvas({
    import draw: *
    let nodes = ((0, (0,0)), (1, (1.5,0)), (2, (0.75,1.3)))
    for (i, pos) in nodes {
      circle(pos, radius: 0.3, name: str(i))
      content(pos, text(12pt)[$x_#i$])
    }
    line("0", "1")
    line("1", "2")
    line("2", "0")
  }))
  
  - *Variables*: $x_i in \{0, 1\}$ (selected or not)
  - *Constraint*: No two neighbors both selected
  - *Goal*: Maximize $sum x_i$
], align(top)[
  *Circuit Satisfiability*
  
  #figure(canvas({
    import draw: *
    content((0, 0.8), text(14pt)[$(x_1 or x_2 = x_3) and\ (x_1 xor x_3 = x_4) and\ (x_5 = not x_4)$])
  }))
  #v(10pt)
  
  - *Variables*: $x_i in \{0, 1\}$ (true or false)
  - *Constraint*: Logic gates
  - *Goal*: Satisfy all logical constraints
])

#align(center, box(stroke: black, inset: 10pt)[
  Both are NP-complete @Karp1972 — brute-force: $2^n$ configurations.
])

_Remark_: So far, none of the LLMs can beat state-of-the-art CSP solvers.

== Encoding CSP as Energy Minimization
#timecounter(2)
Map constraint satisfaction to finding the *ground state* of an energy function:

#myslide([
  *MIS Hamiltonian*:
  $ H_"MIS" = -sum_i x_i + lambda sum_((i,j) in E) x_i x_j $
  - First term: reward for selecting vertices
  - Second term: penalty for violated edges ($lambda arrow infinity$)
], [
  *SAT Hamiltonian*:
  $ H_"SAT" = lambda sum_"clause" (1 - "sat"("clause")) $
  - Each unsatisfied clause contributes energy $lambda$ ($arrow.r infinity$)
  - Solution: $H = 0$
])

#align(center, box(stroke: black, inset: 10pt, fill: yellow.lighten(80%))[
  *Hard constraints* $arrow.r$ *infinite energy penalty*\
  *Objective* $arrow.r$ *additive energy terms* to be minimized
])

== Mapping CSP to Tensor Networks @Liu2023
#timecounter(2)

#myslide([
  *Tensor network representation*: Diagrammatic representation of sum-product network, where
  - Each *variable* $x_i$ $arrow.r$ a *bond* (index)
  - Each *constraint* $arrow.r$ a *tensor*
  
  #figure(canvas({
    import draw: *
    // Simple tensor network for MIS
    circle((0, 0), radius: 0.6, name: "v")
    content((0, 0), [$V_i$])
    
    let dx = 3.0
    content((dx, 0), [$E_(i j)$])
    circle((dx, 0), radius: 0.6, name: "e")
    line("v", (rel: (0, 1.5), to: "v"))
    line("e", (rel: (-1, 1.5), to: "e"))
    line("e", (rel: (1, 1.5), to: "e"))
    content((0, 1.8), [$x_i$])
    content((dx  -1, 1.8), [$x_i$])
    content((dx + 1, 1.8), [$x_j$])
  }))
], [
  *MIS problem*:
  $ Z(beta) &= sum_(x_1, dots, x_n) e^(-beta H_"MIS"(x_1, dots, x_n)) \
  &= sum_(x_1, dots, x_n) product_i V_i (x_i) product_((i,j) in E) E_(i j)(x_i, x_j) $

  - Vertex: $V_i (x_i) = e^(beta x_i)$ (weight for selection)
  - Edge: $E_(i j)(x_i, x_j) = cases(0 "if" x_i = x_j = 1, 1 "otherwise")$
  
])

== From Partition Function to Optimization
#timecounter(1)
In the limit $beta arrow infinity$ (zero temperature):
$ F = - 1/beta ln Z(beta) arrow min_sigma H(sigma) $

Emergence of max-plus algebra @Liu2021:
#align(center, table(
  columns: (auto, auto, auto), inset: 5pt,
  table.header(table.cell(fill: green.lighten(50%))[], table.cell(fill: green.lighten(50%))[Partition function ($beta arrow.r infinity$)], table.cell(fill: green.lighten(50%))[Tropical ($max, +$)]),
  [Sum], [$e^(beta a) + e^(beta b) approx e^(beta max(a, b))$], [$max(a, b)$],
  [Product], [$e^(beta a) e^(beta b) = e^(beta (a + b))$], [$a + b$],
  [Zero], [$0$], [$-infinity$],
  [One], [$1$], [$0$],
))

_Remark_: Commutative semiring, tensor network contraction order optimization is still valid. However, no fast matrix factorization.

// Tensor network visualization functions (DRY principle)
#let tn-node-style = (radius: 0.3, fill: blue.lighten(70%), stroke: (thickness: 1.5pt))
#let tn-edge-style = (thickness: 1.5pt)

#let draw-chain-tn(n: 5, spacing: 1.5, label: [Chain $(O(D^2))$]) = {
  import draw: *
  let start_x = -(n - 1) * spacing / 2
  let radius = 0.35
  
  // Create named nodes
  for i in range(n) {
    let x = start_x + i * spacing
    circle((x, 0), radius: radius, name: "n" + str(i), ..tn-node-style)
  }
  
  // Connect nodes
  for i in range(n - 1) {
    line("n" + str(i), "n" + str(i + 1), stroke: tn-edge-style)
  }
  
  content((0, -1.5), text(12pt, weight: "bold")[#label])
}

#let draw-tree-tn(label: [Tree $(O(D^3))$]) = {
  import draw: *
  let node-data = (
    ("root", (0, 1.5), 0.35),
    ("l1-0", (-1.2, 0.6), 0.35),
    ("l1-1", (1.2, 0.6), 0.35),
    ("l2-0", (-1.8, -0.3), 0.3),
    ("l2-1", (-0.6, -0.3), 0.3),
    ("l2-2", (0.6, -0.3), 0.3),
    ("l2-3", (1.8, -0.3), 0.3),
  )
  let edges = (
    ("root", "l1-0"), ("root", "l1-1"),
    ("l1-0", "l2-0"), ("l1-0", "l2-1"),
    ("l1-1", "l2-2"), ("l1-1", "l2-3"),
  )
  
  // Create named nodes
  for (node-name, pos, radius) in node-data {
    circle(pos, radius: radius, name: node-name, ..tn-node-style)
  }
  
  // Connect nodes
  for (from, to) in edges {
    line(from, to, stroke: tn-edge-style)
  }
  
  content((0, -1.5), text(12pt, weight: "bold")[#label])
}

#let draw-grid-tn(size: 4, spacing: 0.9, label: [Grid $(O(D^(sqrt(n))))$]) = {
  import draw: *
  let offset = -(size - 1) * spacing / 2
  let radius = 0.28
  
  // Create named nodes
  for i in range(size) {
    for j in range(size) {
      let x = offset + i * spacing
      let y = offset + j * spacing
      circle((x, y), radius: radius, name: "g" + str(i) + "-" + str(j), ..tn-node-style)
    }
  }
  
  // Connect horizontal edges
  for i in range(size) {
    for j in range(size - 1) {
      line("g" + str(i) + "-" + str(j), "g" + str(i) + "-" + str(j + 1), stroke: tn-edge-style)
    }
  }
  
  // Connect vertical edges
  for i in range(size - 1) {
    for j in range(size) {
      line("g" + str(i) + "-" + str(j), "g" + str(i + 1) + "-" + str(j), stroke: tn-edge-style)
    }
  }
  
  content((0, offset - 1.2), text(12pt, weight: "bold")[#label])
}

#let draw-mera-tn(label: [MERA $(O(D^(log n)))$]) = {
  import draw: *
  let radius = 0.25
  let h-space = 0.7
  
  // MERA: Alternating layers of disentanglers (squares) and isometries (circles)
  // Physical layer (bottom): 8 sites
  let y0 = 0
  for i in range(8) {
    let x = (i - 3.5) * h-space
    circle((x, y0), radius: radius, name: "p" + str(i), ..tn-node-style)
  }
  
  // Layer 1: Disentanglers (act on pairs 0-1, 2-3, 4-5, 6-7)
  let y1 = 0.8
  for i in range(4) {
    let x = (i * 2 - 3) * h-space
    rect((x - 0.2, y1 - 0.2), (x + 0.2, y1 + 0.2), name: "d1-" + str(i), fill: green.lighten(70%), stroke: (thickness: 1.5pt))
  }
  
  // Connect physical to disentanglers
  for i in range(4) {
    line("p" + str(i * 2), "d1-" + str(i), stroke: tn-edge-style)
    line("p" + str(i * 2 + 1), "d1-" + str(i), stroke: tn-edge-style)
  }
  
  // Layer 2: Isometries (coarse-grain, but with OVERLAP - key difference from tree!)
  let y2 = 1.6
  for i in range(3) {
    let x = (i - 1) * h-space * 2
    circle((x, y2), radius: radius, name: "iso1-" + str(i), fill: orange.lighten(70%), stroke: (thickness: 1.5pt))
  }
  
  // Connect disentanglers to isometries (overlapping pattern!)
  line("d1-0", "iso1-0", stroke: tn-edge-style)
  line("d1-1", "iso1-0", stroke: tn-edge-style)  // Shared!
  line("d1-1", "iso1-1", stroke: tn-edge-style)  // Shared!
  line("d1-2", "iso1-1", stroke: tn-edge-style)  // Shared!
  line("d1-2", "iso1-2", stroke: tn-edge-style)  // Shared!
  line("d1-3", "iso1-2", stroke: tn-edge-style)
  
  // Layer 3: Another disentangler layer
  let y3 = 2.4
  rect((-0.2, y3 - 0.2), (0.2, y3 + 0.2), name: "d2-0", fill: green.lighten(70%), stroke: (thickness: 1.5pt))
  
  // Connect isometries to top disentangler
  line("iso1-0", "d2-0", stroke: tn-edge-style)
  line("iso1-1", "d2-0", stroke: tn-edge-style)
  line("iso1-2", "d2-0", stroke: tn-edge-style)
  
  content((0, y0 - 1.2), text(12pt, weight: "bold")[#label])
}

#let draw-regular-tn(n: 6, graph-radius: 1.3, label: [3-Regular $O(D^(n\/6))$]) = {
  import draw: *
  let radius = 0.3
  
  // Create named nodes in circular layout
  for i in range(n) {
    let angle = i * 360deg / n - 90deg
    let x = graph-radius * calc.cos(angle)
    let y = graph-radius * calc.sin(angle)
    circle((x, y), radius: radius, name: "r" + str(i), ..tn-node-style)
  }
  
  // Connect nodes to form 3-regular graph
  let edges = ((0, 1), (0, 2), (0, 5), (1, 2), (1, 3), (2, 4), (3, 4), (3, 5), (4, 5))
  for (i, j) in edges {
    line("r" + str(i), "r" + str(j), stroke: tn-edge-style)
  }
  
  content((0, -graph-radius - 1.2), text(12pt, weight: "bold")[#label])
}

== The difficulty of tensor network contraction

- *Time complexity*: the number of elementary operations
- *Space complexity*: the number of elements in the largest tensor

#align(center, [
  #grid(align: bottom, columns: 3, column-gutter: 30pt, row-gutter: 25pt,
    canvas(length: 0.8cm, { draw-chain-tn() }),
    canvas(length: 0.8cm, { draw-tree-tn() }),
    canvas(length: 0.8cm, { draw-mera-tn() }),
  )
  
  #v(15pt)
  
  #grid(columns: 2, column-gutter: 60pt,
    canvas(length: 0.8cm, { draw-grid-tn() }),
    canvas(length: 0.8cm, { draw-regular-tn() }),
  )
])

== Tensor Network Contraction Complexity
#timecounter(2)

=== Intuition
The tree tensor network is easier to contract. Why not map a tensor network to a tree by "gluing" the variables together?

*Time complexity*: $O(2^"tw")$ where $"tw"$ = *tree-width* of the network @Markov2008

#myslide([
  *Low tree-width* (geometric graphs):
  - Grid: $"tw" = O(sqrt(n))$
  - Tree: $"tw" = 1$
  
  $arrow.r$ Sub-exponential algorithms exist!
], [
  *High tree-width* (random/dense graphs):
  - 3-regular: $"tw" approx n\/6$
  - Complete graph: $"tw" = n - 1$
  
  $arrow.r$ Exponential, but sparse tensors help!
])

#align(center, box(stroke: black, inset: 10pt, fill: yellow.lighten(80%))[
  *Challenge*: What if $2^"tw"$ is too large for memory?
])

== Summary of part 1

- Constraint satisfaction problem (CSP) is a reasoner that LLM can not beat yet.
- CSP problems can be represented as tensor networks (optionally with max-plus algebra).
- In tensor network simulation, the *memory cost* is usually the bottleneck.


= Reduce the memory: From slicing to branching

== The Slicing Technique @Gray2021
#timecounter(2)
*Idea*: Fix some variables to reduce tree-width, then sum over all values.

$ Z = sum_(x_1, dots, x_n) T(x_1, dots, x_n) = sum_(bold(x)_"slice") underbrace(sum_(bold(x)_"rest") T(x_1, dots, x_n), "smaller tree-width") $

#let show-graph-remove-edge(vertices, edges, removed, ready, color: blue, radius:0.2, st: 0.5pt) = {
  import draw: *
  for (k, (i, j)) in vertices.enumerate() {
    circle((i, j), radius:radius, name: str(k), fill: color, stroke:none)
  }
  for (i, (k, l)) in edges.enumerate() {
    if i in removed {
      line(str(k), str(l), stroke: (paint: silver.lighten(50%), thickness: st))
    } else if i in ready{
      line(str(k), str(l), stroke: (paint: red, thickness: st))
    } else {
      line(str(k), str(l), stroke:st)
    }
  }
}

#align(center, canvas(length: 0.8cm, {
  import draw: *
  let lw = 2pt
  let ksg_loc = ((1.2, 2.3), (3.4, -0.4), (0.3, 2.3), (2.8, 2.0), (4.5, 1.1), (1.7, 0.5), (0.6, 0.1), (4.1, 2.6), (3.0, 0.8), (0.0, 1.1), (4.8, -0.3))
  let edges = ()
  for i in range(ksg_loc.len()) {
    for j in range(i + 1, ksg_loc.len()) {
      if distance(ksg_loc.at(i), ksg_loc.at(j)) <= 2.0 {
        edges.push((i, j))
      }
    }
  }
  let gridsize = 1.5
  let r = 0.3
  show-graph-remove-edge(ksg_loc.map(v=>(v.at(0)*gridsize, v.at(1)*gridsize)), edges, (), (2,10,12,14,16,18), radius:r, st: lw)
  content((3.5, -2), [Fix #text(red)[red] variables $arrow.r$ tree-width $arrow.b$])

  content((9.5, 2), text(24pt)[$= quad 2^6 times$])

  set-origin((12, 0))
  show-graph-remove-edge(ksg_loc.map(v=>(v.at(0)*gridsize, v.at(1)*gridsize)), edges, (2,10,12,14,16,18),(), radius:r, st: lw)
  }))

== Slicing Trade-off
#timecounter(1)

#myslide([
  *With $k$ sliced variables*:
  - Time: $O(2^k dot 2^("tw" - Delta"tw"))$
  - Space: $O(2^("tw" - Delta"tw"))$
], [
  #figure(canvas(length: 1.5cm, {
    import draw: *
    // Trade-off curve
    line((0, 0), (5, 0), mark: (end: "straight"))
    line((0, 0), (0, 3), mark: (end: "straight"))
    content((6, 0), [Time])
    content((0, 3.5), [Space])
    bezier((0.5, 2.5), (4.5, 0.3), (2, 1.5))
    circle((0.5, 2.5), radius: 0.1, fill: blue)
    circle((4.5, 0.3), radius: 0.1, fill: red)
    content((0.8, 2.8), text(14pt)[no slice])
    content((5.0, 0.6), text(14pt)[max slice])
  }))
*Problem*: The time complexity grows.

])


== Sparse Tensors in CSP
#timecounter(2)

Hard constraints create *sparse tensors* — most entries are $0$ (or $-infinity$ in tropical).

*Example*: Edge tensor for MIS
$ E(x_i, x_j) = mat(1, 1; 1, 0) quad arrow.r quad "only 3 of 4 entries are non-zero" $

If we have $n$-such tensors, the ratio of non-zero entries is $~(3\/4)^n$! With bounding, it can be much smaller.

*For Circuit SAT*: Each gate tensor has few satisfying assignments out of $2^k$ (where $k$ is the number of input/output wires).

#align(center, box(stroke: black, inset: 10pt)[
  *Sparsity* = ratio of zero entries, can be very close to 1!
])

== Path Integral Perspective
#timecounter(2)

Tensor contraction $approx$ summing over all "paths" (configurations):
$ Z = sum_"paths s.t. constraints" "weight"("path") $

*Sparse tensors*:
- *invalid* paths are those with zero weight, they either:
 - violate constraints, or
 - *bounded* by maximum criteria (local or global)

_Remark_: In *quantum circuit simulation*, a similar sparsity arises @Shao2024@Begusic2024, enabling efficient simulation of *Kicked Ising model (127 qubits)*, orders of magnitude faster than tensor network contraction.


== The Key Idea
#timecounter(2)

#align(center, canvas(length: 0.8cm, {
  import draw: *
  let lw = 2pt
  let ksg_loc = ((1.2, 2.3), (3.4, -0.4), (0.3, 2.3), (2.8, 2.0), (4.5, 1.1), (1.7, 0.5), (0.6, 0.1), (4.1, 2.6), (3.0, 0.8), (0.0, 1.1), (4.8, -0.3))
  let edges = ()
  for i in range(ksg_loc.len()) {
    for j in range(i + 1, ksg_loc.len()) {
      if distance(ksg_loc.at(i), ksg_loc.at(j)) <= 2.0 {
        edges.push((i, j))
      }
    }
  }
  let gridsize = 1.5
  let r = 0.3

  show-graph-remove-edge(ksg_loc.map(v=>(v.at(0)*gridsize, v.at(1)*gridsize)), edges, (), (19, 16,18), radius:r, st: lw)
  content((0.0, 1), [$x_1$])
  content((1.5, 1.6), [$x_2$])
  content((2, 0), [$x_3$])
}))

- Observe: only configs ${010, 101, 110}$ are feasible (correspond to *non-zero entries*)
- "Learn" a *true statement in disjunctive normal form (DNF)*:
 - $(not x_1 and x_2 and not x_3) or (x_1 and not x_2 and x_3) or (x_1 and x_2 and not x_3)$
 - $x_1 or not x_1$
 - $(x_2 and not x_3) or (x_1 and not x_2 and x_3)$ (best)
- Branching ($approx$ non-uniform slicing) rule to "cut" problems:
 - (assign $x_2$ to $1$ and $x_3$ to $0$) OR (assign $x_1$ to $1$ and $x_2$ to $0$ and $x_3$ to $1$)

== Time-Space Trade-off Improvement
#timecounter(1)

#myslide[
  #image("images/ksg_60x60_tc_s1.svg", width: 100%)
][
  *Slicing*:
  - Time grows as you slice more variables
  
  *BBTN (our method)*
  - Both time and space complexity *decrease* (in this case)!

#let namebox(src, name) = box(align(center, [#image(src, width:60pt, height:80pt)#v(-10pt)#name]))
#align(center,[
#namebox("images/yijiawang.png", text(16pt)[Yi-Jia Wang (ITP)])#h(20pt)
#namebox("images/xuanzhao.png", text(16pt)[Xuan-Zhao Gao (CCM)])
])
]

== Scaling to Large Problems
#timecounter(2)
#figure(image("images/time_complexity.svg", width: 70%))

1. *BBTN* scales to much larger instances than pure tensor network methods.
2. *BBTN* outperforms SOTA open source integer programming solvers (SCIP).

// == Beating SOTA on MIS
// #timecounter(2)

// #grid(columns: 2, gutter: 0pt,
// image("images/fig5.svg", width: 350pt), [
//   *Metric*: Number of branches (lower is better)
  
//   *Methods compared*:
//   - #text(red)[`ob`]: Our optimal branching
//   - #text(green)[`xiao2013`]: Best hand-crafted 3-MIS rules
//   - #text(blue)[`akiba2015`]: PACE competition winner
  
//   #v(10pt)
//   *Key findings*:
//   - #text(red)[`ob`] generates the fewest branches across all graph types
//   - On 3-regular graphs: $gamma = 1.0441$ (vs. 1.0487 for hand-crafted)
// ])

== Circuit SAT: Integer factoring as an example
#timecounter(1)

*Problem*: Given $m = p times q$, find the factors $p$ and $q$.

*Approach*: Model a multiplier circuit as a CSP — each gate is a constraint.

#place(bottom + right, align(center, [
  #image("images/xiweipan.png", width: 50pt, height: 70pt) #text(14pt, [#v(-15pt)Xi-Wei Pan])
  #image("images/zhongyi.jpg", width: 50pt, height: 70pt) #text(14pt, [#v(-15pt)Zhong-Yi Ni])
]))

#let multiplier-block(loc, size, sij, cij, pij, qij, pijp, qipj, sipjm, cimj) = {
  import draw: *
  rect((loc.at(0) - size/2, loc.at(1) - size/2), (loc.at(0) + size/2, loc.at(1) + size/2), stroke: black, fill: white)
  circle((loc.at(0) + size/2, loc.at(1) - size/2), name: sij, radius: 0)
  circle((loc.at(0) - size/2, loc.at(1) - size/4), name: cij, radius: 0)
  circle((loc.at(0) - size/2, loc.at(1) + size/4), name: qipj, radius: 0)
  circle((loc.at(0), loc.at(1) + size/2), name: pij, radius: 0)
  circle((loc.at(0) + size/2, loc.at(1) + size/4), name: qij, radius: 0)
  circle((loc.at(0), loc.at(1) - size/2), name: pijp, radius: 0)
  circle((loc.at(0) - size/2, loc.at(1) + size/2), name: sipjm, radius: 0)
  circle((loc.at(0) + size/2, loc.at(1) - size/4), name: cimj, radius: 0)
}

#let multiplier(m, n, size: 1) = {
  import draw: *
  for i in range(m){
    for j in range(n) {
      multiplier-block((-2 * i, -2 * j), size, "s" + str(i) + str(j), "c" + str(i) + str(j), "p" + str(i) + str(j), "q" + str(i) + str(j), "p" + str(i) + str(j+1) + "'", "q" + str(i+1) + str(j) + "'", "s" + str(i+1) + str(j - 1) + "'", "c" + str(i - 1) + str(j) + "'")
    }
  }
  for i in range(m){
    for j in range(n){
      if (i > 0) and (j < n - 1) {
        line("s" + str(i) + str(j), "s" + str(i) + str(j) + "'", mark: (end: "straight"))
      }
      if (i < m - 1){
        line("c" + str(i) + str(j), "c" + str(i) + str(j) + "'", mark: (end: "straight"))
      }
      if (j > 0){
        line("p" + str(i) + str(j), "p" + str(i) + str(j) + "'", mark: (start: "straight"))
      }
      if (i > 0){
        line("q" + str(i) + str(j), "q" + str(i) + str(j) + "'", mark: (start: "straight"))
      }
    }
  }
  for i in range(m){
    let a = "p" + str(i) + "0"
    let b = (rel: (0, 0.5), to: a)
    line(a, b, mark: (start: "straight"))
    content((rel: (0, 0.3), to: b), text(14pt)[$p_#i$])


    let a2 = "s" + str(i+1) + str(-1) + "'"
    let b2 = (rel: (-0.4, 0.4), to: a2)
    line(a2, b2, mark: (start: "straight"))
    content((rel: (-0.2, 0.2), to: b2), text(14pt)[$0$])

    let a3 = "s" + str(i) + str(n - 1)
    let b3 = (rel: (0.4, -0.4), to: a3)
    line(a3, b3, mark: (end: "straight"))
    content((rel: (0.2, -0.2), to: b3), text(14pt)[$m_#(i+m - 1)$])

  }
  for j in range(n){
    let a = "q0" + str(j)
    let b = (rel: (0.5, 0), to: a)
    line(a, b, mark: (start: "straight"))
    content((rel: (0.3, 0), to: b), text(14pt)[$q_#j$])

    let a2 = "q" + str(m) + str(j) + "'"
    let b2 = (rel: (-0.5, 0), to: a2)
    line(a2, b2, mark: (end: "straight"))


    let a3 = "c" + str(-1) + str(j) + "'"
    let b3 = (rel: (0.5, 0), to: a3)
    line(a3, b3, mark: (start: "straight"))
    content((rel: (0.3, 0), to: b3), text(14pt)[$0$])
  
    if (j < n - 1) {
      let a4 = "c" + str(m - 1) + str(j)
      let b4 = "s" + str(m) + str(j) + "'"
      bezier(a4, b4, (rel: (-1, 0), to: a4), (rel: (-0.5, -1), to: a4), mark: (end: "straight"))
    } else {
      let a4 = "c" + str(m - 1) + str(j)
      line(a4, (rel: (-0.5, 0), to: a4), mark: (end: "straight"))
      content((rel: (-0.8, 0), to: a4), text(14pt)[$m_#(j+m)$])
    }
    if (j < n - 1) {
      let a5 = "s0" + str(j)
      let b5 = (rel: (0.4, -0.4), to: a5)
      line(a5, b5, mark: (end: "straight"))
      content((rel: (0.2, -0.2), to: b5), text(14pt)[$m_#j$])
    }
  }
}

#grid(columns: 2, gutter: 40pt, canvas({
  import draw: *
  let i = 0
  let j = 0
  multiplier(4, 4, size: 1.0)
}),
[#canvas({
  import draw: *
  multiplier-block((0, 0), 1.0, "so", "co", "pi", "qi", "po", "qo", "si", "ci")
  line("si", (rel:(-0.5, 0.5), to:"si"), mark: (start: "straight"))
  content((rel:(-0.75, 0.75), to:"si"), text(14pt)[$s_i$])
  line("ci", (rel:(0.5, 0), to:"ci"), mark: (start: "straight"))
  content((rel:(0.75, 0), to:"ci"), text(14pt)[$c_i$])
  line("pi", (rel:(0, 0.5), to:"pi"), mark: (start: "straight"))
  content((rel:(0, 0.75), to:"pi"), text(14pt)[$p_i$])
  line("qi", (rel:(0.5, 0), to:"qi"), mark: (start: "straight"))
  content((rel:(0.75, 0), to:"qi"), text(14pt)[$q_i$])
  line("po", (rel:(0, -0.5), to:"po"), mark: (end: "straight"))
  content((rel:(0, -0.75), to:"po"), text(14pt)[$p_i$])
  line("qo", (rel:(-0.5, 0), to:"qo"), mark: (end: "straight"))
  content((rel:(-0.75, 0), to:"qo"), text(14pt)[$q_i$])
  line("so", (rel:(0.5, -0.5), to:"so"), mark: (end: "straight"))
  content((rel:(0.75, -0.75), to:"so"), text(14pt)[$s_o$])
  line("co", (rel:(-0.5, 0), to:"co"), mark: (end: "straight"))
  content((rel:(-0.75, 0), to:"co"), text(14pt)[$c_o$])
  content((5, 0), text(14pt)[Logical constraints:\ $2c_o + s_o = p_i q_i + c_i + s_i$])
})
]
)

== Circuit SAT: Reduced number of branches
#timecounter(1)
- Much less branching steps to 2-SAT subproblems!
- Directly applicable to all boolean satisfiability problems, i.e. Circuit SAT and $K$-SAT.
#myslide[
  #image("images/branch_comparison.png", width: 100%)
][
  #image("images/branch_comparison_3sat.png", width: 100%)
]




= General principle of branching
== Which DNF is the best?
#timecounter(1)
- $(not x_1 and x_2 and not x_3) or (x_1 and not x_2 and x_3) or (x_1 and x_2 and not x_3)$
- $x_1 or not x_1$
- $(x_2 and not x_3) or (x_1 and not x_2 and x_3)$

== The branching hierachy
#timecounter(1)
#align(center, grid(columns: 2, gutter: 40pt, box(width: 300pt, canvas({
  import draw: *
  scale(x:60%, y:60%)
  let DY = 3
  let size = 1
  for k in range(5){
    content((k * size, 0.2 + size), text(12pt, box([$#numbering("a", k+1)$], fill: none, inset: 2pt)))
  }
  content((2, 2.5), align(center, text(12pt)[feasible set: $(b, c, d) in {101, 100, 011}$]))
  content((-5.5, -1.5), align(center, text(12pt)[branch: $b = 1, c = 0$]))
  decision_sequence((0, 0), (0, -3, -3, -3, 0))
  decision_sequence((-4, -DY), (-3, 1, 2, -3, -3))
  decision_sequence((4, -DY), (-3, 2, 1, 1, -3))
  decision_sequence((-8, -2*DY), (1, 1, 2, 2, -3))
  decision_sequence((0, -2*DY), (1, 1, 2, 1, 2))
  decision_sequence((8, -2*DY), (1, 2, 1, 1, 1))
  decision_sequence((-8, -3*DY), (1, 1, 2, 2, 2))
  line((1.2, -0.8), (-1.2, -DY + 0.8), mark: (end: "straight"))
  line((2.8, -0.8), (5.2, -DY + 0.8), mark: (end: "straight"))
  line((6.8, -DY - 0.8), (9.2, -2 * DY + 0.8), mark: (end: "straight"))
  line((-2.8, -DY - 0.8), (-5.2, -2 * DY + 0.8), mark: (end: "straight"))
  line((-1.2, -DY - 0.8), (1.2, -2 * DY + 0.8), mark: (end: "straight"))
  line((-6, -2 * DY - 0.8), (-6, -3 * DY + 0.8), mark: (end: "straight"))
})),
[
#canvas(length: 25pt, {
  import draw: *
  main-diagram()
})
]
))

*Key idea*: Recursively generate more branches, until $rho = 0$.

== The branching factor $gamma$
#timecounter(2)

#myslide[
#figure(canvas(length: 1cm, {
  import draw: *
  mixmode_tree()
}))
Runtime: $T(rho) = O(gamma^rho)$, where $rho$ = *problem size* (e.g., number of unfixed variables)
][
1. Split into $k$ subproblems, each reducing size by $Delta rho_1, dots, Delta rho_k$. Total time satisfies the recurrence:
  $
  T(rho) = sum_(i=1)^k T(rho - Delta rho_i)
  $
3. Decide *branching factor* $gamma$:
  $
  gamma^rho = sum_(i=1)^k gamma^(rho -Delta rho_i) arrow.double.r
  1 = sum_(i=1)^k gamma^(-Delta rho_i)
  $

*Goal*: Minimize $gamma$ — fewer branches, larger size reductions!
]

// == It is difficult
// #timecounter(1)

// #align(center, box(stroke:black, inset:10pt, align(left, [
// We are generating "theories"!
// ])))
// In the following,
// - A formal definition of a branching "theory", the size of theories space is double exponential.
// - An algorithm to generate provably optimal branching rules.
// - For efficient contraction of sparse tensor networks.

// == Branching - an art of deviding and conquering
// #timecounter(2)
// Let $rho$ be a measure of problem size (e.g. number of variables)
// #figure(canvas(length: 0.8cm, {
//   mixmode_tree()
// }))

// #align(left, box(stroke: black, inset: 10pt)[Let $Delta rho_i$ be the size reduction in the $i$-th branch.
// Then the _branching factor_ is given by
// $
// gamma^rho = sum_i gamma^(rho - Delta rho_i) arrow.double.r 1 = sum_i gamma^(- Delta rho_i)
// $])

// == Measure

// Characterizes the hardness of the instance

// - The number of vertices in the sub-problem
// - Degree 3 measure: $sum_(v in V) max(0, d(v) - 2)$, because degree 2 graphs are easy!
// - More sofisticated measures, e.g. assigning different measurs for vertices with different degree.
// - The tree-width of a graph topology.

// It must be *positive*, *non-increasing* during branching, measure 0 problem is directly solvable.


== Key: Valid and good branching rule as DNF $cal(D)$
#timecounter(2)

- Valid: all elements in *feasible set* are true assignments of $cal(D)$, i.e. $cal(D)$ is true.
- Good: create less branches, eliminate more variables.

#grid(columns:2, gutter: 20pt, canvas({
    import draw: *
    circle((0, 0), radius: (4, 2))
    circle((1, 0), radius: 1, fill: silver, stroke: none)
    circle((1.4, 0), radius: (1.8, 1.2), fill: aqua.transparentize(80%))
    content((1, 0), text(14pt)[feasible])
    content((-1.5, 0), text(14pt)[Total])
    content((2.5, 0), text(14pt)[$cal(D)$])
}),
[
$ cal(D) = underbrace((b and not c) or overbrace(( not b and c and d), "size reduction (longer is better)"), "number of branches (less is better)") $

]
)

#align(left, box(stroke: black, inset: 10pt)[Objective $gamma$: Let $Delta rho(c_i)$ be the size reduction after applying the clause $c_i$.
Then the branching factor is given by $gamma^rho = sum_i gamma^(rho - Delta rho(c_i))$, i.e.
$
  1 = sum_i gamma^(- Delta rho(c_i))
$])

== Remark on the measure
#timecounter(2)
*Measure $rho$*: a measure of problem size that monotonically decreases during branching. $rho = 0$ means the problem is *directly solvable*.
#box(stroke: black, inset: 10pt)[
#myslide(align(top)[
=== MIS Problem
- Number of variables with degree $> 2$ (*intuition*: MIS on graph with maximum degree 2 is easy.) in optimal branching paper.
- The tree-width of the graph in BBTN #footnote([Tree-width was found with `OMEinsumContractionOrders.jl`, orders faster than CoTengra.])
], align(top)[
=== Circuit SAT Problem
Number of "hard" clauses/gates (those with $> 2$ variables). *Intuition*: 2-SAT (clauses with $<= 2$ variables) is easy (polynomial time).
])
]

_Remark_: When fixing a variable, constraint propagation triggers a cascade of simplifications, i.e. it enlarges $Delta rho$.

== Intuition: Finding Patterns in Feasible Solutions
#timecounter(2)

#let colred(x) = text(fill: red, $#x$)
*Example 1*: $"feasible"(a, b, c, d) = {101colred(0), 100colred(0), 010colred(0)}$

Notice: $d = 0$ in all solutions! $arrow.r$ No branching needed, just set $d = 0$.
$ gamma = 1 quad ("free reduction!")$

*Example 2*: $"feasible"(a, b, c, d, e) = {colred(1111)1, colred(0000)0, colred(1111)0, colred(0000)1}$

Pattern: first 4 bits are either all 1 or all 0. Branch on this!
$ gamma^n = 2 gamma^(n-4) arrow.r gamma approx 1.19$

*Example 3*: $"feasible"(a, b, c, d) = {1000, 0100, 0010, 0001}$

Exactly one variable is 1. Optimal: branch on whether $a = 1$ or not.

*Key insight*: The structure of feasible solutions reveals efficient branching strategies.


// == Visualizing the Search Space
// #figure(image("images/ob_new.svg", width: 400pt))

== The Challenge: Exponentially Many Strategies
#timecounter(1)
#align(center, box(stroke: black, inset: 10pt)[*Q*: How do we find the optimal branching rule?])

*The search space is astronomically large!*
The number of branching rule on $n$ variables is equal to the number of Disjunctive Normal Form (DNF):
$
"# of possible clauses" &= 3^n \
"# of DNF formulas" &= 2^(3^n)
$

#align(center, box(text(14pt)[
$n=3$: $2^(27) approx 10^8$ formulas\
$n=4$: $2^(81) approx 10^(24)$ formulas\
$n=5$: $2^(243) approx 10^(73)$ formulas\
...
], stroke: black, inset: 10pt))

*Our algorithm*: arXiv:2412.07685, enables optimal branching on $~20$ variables.

== 40 Years of Progress on MIS Branching
#timecounter(1)

#myslide(table(
  columns: (auto, auto, auto, auto),
  table.header(hd[Year], hd[Running times], hd[References], hd[Notes]),
  s[1977], s[$O^*(1.2600^n)$], s[@Tarjan1977], s[],
  s[1986], s[$O^*(1.2346^n)$], s[@Jian1986], s[],
  s[1986], s[$O^*(1.2109^n)$], s[@Robson1986], s[],
  s[1999], s[$O^*(1.0823^m)$], s[@Beigel1999], s[],
  s[2001], s[$O^*(1.1893^n)$], s[@Robson2001], s[],
  s[2003], s[$O^*(1.1254^n)$ for 3-MIS], s[@Chen2003], s[],
  s[2005], s[$O^*(1.1034^n)$ for 3-MIS], s[@Xiao2005], s[],
  s[2006], s[$O^*(1.2210^n)$], s[@Fomin2006], s[Measure and conquer,\ mirror rule],
  s[2006], s[$O^*(1.1225^n)$ for 3-MIS], s[@Fomin2006b], s[Same as TN],
  s[2006], s[$O^*(1.1120^n)$ for 3-MIS], s[@Furer2006], s[],
  s[2006], s[$O^*(1.1034^n)$ for 3-MIS], s[@Razgon2006], s[],
  s[2008], s[$O^*(1.0977^n)$ for 3-MIS], s[@Bourgeois2008], s[],
  s[2009], s[$O^*(1.0919^n)$ for 3-MIS], s[@Xiao2009], s[],
  s[2009], s[$O^*(1.2132^n)$], s[@Kneis2009], s[Satellite rule],
  s[2013], s[$O^*(1.0836^n)$ for 3-MIS], s[@Xiao2013], s[SOTA],
  s[2016], s[$O^*(1.2210^n)$], s[@Akiba2016], s[PACE winner],
  s[2017], s[$O^*(1.1996^n)$], s[@Xiao2017], s[SOTA],
),
[
#align(center, box([MIS is NP-complete — no polynomial-time algorithm exists (unless P=NP) @Karp1972.], stroke: black, inset: 10pt))

#let formin() = {
  import draw: *
  let s = 2
  let dy = 3.0
  let la = (-s, 0)
  let lb = (0, s)
  let lc = (0, 0)
  let ld = (s, 0)
  let le = (s, s)
 
  for (l, n, color) in ((la, "a", red), (lb, "b", black), (lc, "c", red), (ld, "d", black), (le, "e", red)){
    circle((l.at(0), l.at(1)-s/2), radius:0.4, name: n, stroke: color)
    content((l.at(0), l.at(1)-s/2), text(14pt)[$#n$])
  }
  for (a, b) in (("a", "b"), ("b", "c"), ("c", "d"), ("d", "e"), ("b", "d")){
    line(a, b)
  }
}
])

== Can We Beat Expert-Designed Rules?
#timecounter(1)

*The bottleneck case* from @Xiao2013 (state-of-the-art 3-MIS algorithm):

#grid(columns: 3,
  image("images/bottleneck.svg", width: 300pt),
  h(30pt),
  align(horizon, text(20pt, black)[
    - 21 variables in the local region
    - 71 feasible configurations
    - 15,782 candidate clauses
    
    *Our result*: 4 branches with size reductions $[10, 16, 26, 26]$
    *$ gamma = 1.0817 < 1.0836 $*
    (Solved in 1 second!)
  ]),
)

*Our automatic method beats 40 years of expert-designed rules!*


== Which DNF is the best?
#timecounter(1)
- $(not x_1 and x_2 and not x_3) or (x_1 and not x_2 and x_3) or (x_1 and x_2 and not x_3)$
  $ 1 = 3 gamma^(-3) arrow.r gamma = 3^(1\/3) approx 1.44 $
- $x_1 or not x_1$
  $ 1 = 2 gamma^(-1) arrow.r gamma = 2 $
- $(x_2 and not x_3) or (x_1 and not x_2 and x_3)$
  $ 1 = gamma^(-2) + gamma^(-3) arrow.r gamma approx 1.32 $

== Compare sparse TN and our branching method
#timecounter(1)

#figure(image("images/compare_nu_u.pdf"))

// == Not as easy as it seems
// #timecounter(1)

// $ "oracle"(a, b, e, f) = {1010, 1001, 0100} $
// #align(center, [#canvas({
//   import draw: *
//   let size = 1
//   for k in range(8){
//     content((k * size, size), text(14pt, box([$#numbering("a", k+1)$], fill: none, inset: 2pt)))
//   }
//   decision_sequence((0, 0), (-3, -3, 0, 0, -3, -3, 0, 0))
// })

// Task: find the best branching strategy $cal(D)$.

// ]
// )

// ==
// #timecounter(2)
// $ "oracle"(a, b, c, d) = {1010, 1001, 0100} $

// - A searching strategy can be represented as a boolean expression in disjunctive normal (DNF), i.e. a disjunction of conjunctive clauses.
// - #highlight([A searching strategy is *valid* if the none of the possible choices lead to good ending is missed.])

// === Examples of valid searching strategies
// #christina(size: 34pt) Christina (case by case): $((a and not b and c and not d) or (a and not b and not c and d) or (not a and b and not c and not d))$.\
// #murphy(size: 34pt) Murphy (minimalist): $a or not a$.\
// #ina(size: 34pt) Ina: $(a and not b) or (b and not a and not c and not d)$ is the optimal one.

// ==
// #timecounter(2)

// #definition("Valid branching rule")[
//     A branching rule $cal(D)$ is valid on $cal(S)_R$ if and only if for any set $S_(bold(s)_(partial R)) in cal(S)_R$, there exists a configuration $bold(s)_(V(R)) in S_(bold(s)_(partial R))$ that satisfies $cal(D)$, denoted as $S_(bold(s)_(partial R)) tack.r cal(D)$.
// ]

// #example([oracle: {1010, 1001, 0100}])[
// - Valid: $((a and not b and c and not d) or (a and not b and not c and d) or (not a and b and not c and not d))$.
// - Valid: $a or not a$.
// - Not valid: $((a and not b and c and not d) or (a and not b and not c and d))$.
// ]

// - Christina: $((a and not b and c and not d) or (a and not b and not c and d) or (not a and b and not c and not d))$.
//   $ gamma^n = 3 gamma^(n - 4) arrow.r gamma = 3^(1/4) approx 1.32 $
// - Murphy: $a or not a$.
//   $ gamma^n = 2 gamma^(n - 1) arrow.r gamma = 2 $
// - Ina: $(a and not b) or (b and not a and not c and not d)$ is the optimal one ($gamma approx 1.27$).

// == More examples
// #timecounter(2)

// #let colred(x) = text(fill: red, $#x$)
// - $"oracle"(a, b, c, d) = {101colred(0), 100colred(0), 010colred(0)}$

//   The optimal branching rule is $not d$, removing one variable for free!
//   $ gamma^n = gamma^(n-1) arrow.r gamma = 1$

// - $"oracle"(a, b, c, d, e) = {colred(1111)1, colred(0000)0, colred(1111)0, colred(0000)1}$

//   Optimal branching: $(a and b and c and d) or (not a and not b and not c and not d)$.
//   $ gamma^n = 2 gamma^(n-4) arrow.r gamma approx 1.19$

// - $"oracle"(a, b, c, d) = {1000, 0100, 0010, 0001}$

//   Optimal branching: $(a and not b and not c and not d) or (not a)$.
//   $ gamma^n = gamma^(n-1) + gamma^(n-4) arrow.r gamma approx 1.38$

// #box(stroke: black, inset: 10pt)[
//   *Less is more*\
//   - #highlight([Capture bit correlations rather than maximally reducing the search space.])\
// ]


// == The optimal branching algorithm
// #timecounter(1)

// 1. Denote the oracle $cal(S) = {bold(s)_1, bold(s)_2, dots, bold(s)_l}$
// 2. Generate candidate clauses $cal(C) = {c_1, c_2, dots, c_m}$ (Can be exponentially large)
// 3. Find the optimal branching rule $cal(D) = c_(k_1) or c_(k_2) or dots$ by bisecting over $gamma$, find the smallest one that make the cost to the following weighted minimum set covering problem $<=1$:
// $
// min_(x) sum_(i=1)^(|cal(C)|) gamma^(-Delta rho(c_i)) x_i,  "s.t." union.big_(i = 1, dots, |cal(D)|,\ x_i = 1) J_i = {1, 2, dots, |cal(S)|}
// $
// where $J_i$ is the indices of bitstrings that covered by the $i$-th clause.
// - _Remark_: Although this problem is NP-hard, it is efficiently solvable with integer programming in practise. It allows us to handle number of vertices $>20$.

// == Showcase: King's subgraph at 0.8 filling
// #timecounter(1)

// #grid(columns: 2, gutter: 20pt,
// [#canvas({
//   import draw: *
//   show-grid-graph(8, 8, filling: 0.8, unitdisk: 1.6)
// })
// ],
// [
//   - Independent set problem on King's subgraph is NP-hard @Pichler2018, also known as hard-core lattice gas @Nath2014, and is implementable on Rydberg atoms arrays @Ebadi2022.
//   - Previous (classical) record: $40 times 40$ for tensor network @Liu2023 and branching methods, estimated to be $70 times 70$ for integer programming (CPLEX) @Andrist2023
// ])
// = Application 1: BBTN for MIS
// == Branch-and-Bound Tensor Network (BBTN)
// #timecounter(2)

// #myslide[
// #figure(image("images/bbtn.svg", width: 360pt))
// ][
//   *Key idea*: Use branching to decompose a large network into smaller, tractable pieces.

//   *The right measure*: "Tree-width" of the tensor network (contraction complexity).

//   *Left*: Traditional *slicing* — branch on one variable at a time.

//   *Right*: BBTN — *non-uniform slicing* that more effectively reduces tree-width.
  
//   *Result*: Much less number of sub-networks.
// ]

== Open Source Implementation
#timecounter(1)

#align(center, grid(columns: 1, gutter: 10pt, image("images/ob-logo.svg", width: 300pt), 
[
#link("https://github.com/OptimalBranching/OptimalBranching.jl")[OptimalBranching/OptimalBranching.jl]
]))

#align(center, image("images/barcode.png", width: 150pt))

// == Optimal Branching for Circuit SAT
// #timecounter(2)

// #myslide[
// *Algorithm*:
// 1. Select a local region (nearby gates)
// 2. Enumerate feasible configurations (via tensor contraction), and apply unit propagation
// 3. Find optimal branching rule
// 4. Apply branch, propagate, and recurse
// ][
//   #box(stroke: black, inset: 10pt, fill: yellow.lighten(80%))[
//     *Key difference from MIS*: 
//     - Measure = number of hard clauses (involving $>2$ varaibles), since 2-SAT is easy.
//     - Exploits unit propagation to reduce the number of hard clauses.
//   ]
// ]

// == LLM + Solver: The Neuro-Symbolic Future
// #timecounter(2)

// *New Scheme*: LLM + SAT Solvers

// 1. *First-Order Logic* (FOL): Undecidable
   
// 2. *SMT* (Z3, CVC5): Decidable, software verification @deMoura2008
   
// #box(stroke: (paint: black, dash: "dashed"), outset: 10pt, [
// 3. *CSP* (Kissat, X-SAT): Simplest, foundation of SMT
// ])

// #place(dx: 70%, dy: -20%, [*$checkmark$ Our Focus*
// - Simple, but powerful
// - Connects to Tensor Networks
// ])

// == Why CSP Matters for AI + Science
// #timecounter(1)

// *Neuro-symbolic AI*:
// - SATNet @Wang2019: Differentiable SAT solver layer
// - NeuroSAT @Selsam2018: Learning to solve SAT with GNNs
// - AlphaGeometry @Trinh2024: LLMs + symbolic solvers

// *Scientific Applications*:
// - Protein structure prediction, molecular design
// - Circuit verification, control systems
// - Combinatorial optimization (spin systems, scheduling)

// == Reasoners
// #timecounter(2)

// *Problem*: "Fill a 9×9 Sudoku grid so each row, column, and 3×3 box contains 1-9."

// #align(center, grid(columns: 3, gutter: 30pt, align: left, align(top)[
//   *First order logic*
  
//   #text(13pt)[```
//   ∀i,j,k (Cell(i,j)=Cell(i,k) 
//     → j=k)
//   ∀i,j,k (Cell(i,j)=Cell(k,j) 
//     → i=k)
//   ...
//   ```]
  
//   ✓ Most expressive\ 
//   ✗ Undecidable
// ], align(top)[
//   *SMT (Z3, CVC5)*
  
//   #text(13pt)[```smt
//   (declare-const c11 Int)
//   ...
//   (assert (distinct row1))
//   (assert (distinct col1))
//   (check-sat)
//   ```]
  
//   ✓ Boolean + theories\
//   ✓ Decidable
// ], align(top)[
//   *CSP (Our Focus)*
  
//   #text(13pt)[```
//   Each cell ∈ {1..9}
  
//   AllDifferent(each row)
//   AllDifferent(each col)
//   AllDifferent(each box)
//   ```]
  
//   ✓ Highly efficient\
//   ✓ Combinatorial opt.
// ]))

// #align(center, box(stroke: black, inset: 8pt)[
//   *Constraint Satisfaction Problem (CSP)*:\ finite domains + constraints — foundation of SMT solvers
// ])

== Summary
#timecounter(1)

*Key Takeaways*:
1. CSP $arrow.r$ Tensor networks with *tropical algebra* for ground state search
2. *Slicing* trades time for space, but *ignores sparsity structure*
3. *Optimal branching* = smart slicing that exploits *constraint correlations*
4. _Remark_: Can be generalized to other CSPs, to cut the solution space efficiently, reflecting human wisdom of *case by case analysis*.

== Advanced Materials Thrust \u{2665} AI
#timecounter(1)
#grid(image("images/AMAT_Logo_Gold-Blue.png", width: 300pt), text(16pt)[Enabling innovation in *new materials*, *new energy*, *sustainable environment* and *biomedical devices*], columns: 2, gutter: 20pt)

#align(center, grid(columns: 2, gutter: 20pt,
image("images/2025-01-13-09-19-10.png", height: 150pt),
image("images/2025-01-13-09-26-32.png", height: 150pt)))

Great food, world-class facilities, and wonderful colleagues!

== Thank You!
#timecounter(1)
#box(stroke: white, inset: 20pt, width: 100%, fill: color.mix(blue.lighten(50%), yellow), [
#align(center, [*arXiv:2412.07685*])
Automated Discovery of Branching Rules with Optimal Complexity for the Maximum Independent Set Problem

_Xuanzhao Gao, Yijia Wang, Pan Zhang, Jinguo Liu_
])
#v(20pt)
#align(left, grid(
image("images/xuanzhao.png", width:50pt, height:60pt), [Xuanzhao Gao],
image("images/yijiawang.png", width:50pt, height:60pt), [Yijia Wang],
image("images/panzhang.png", width:50pt, height: 60pt), [Pan Zhang],
image("images/fengpan.png", width:50pt, height: 60pt), [Feng Pan],
image("images/zhongyi.jpg", width:50pt, height: 60pt), [Zhong-Yi Ni],
image("images/xiweipan.png", width:50pt, height: 60pt), [Xi-Wei Pan],
columns: 6, column-gutter: 20pt, row-gutter: 10pt))


== References
#bibliography("refs.bib", title: none)