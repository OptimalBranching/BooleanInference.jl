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

// Theorems configuration
#show: thmrules.with(qed-symbol: $square$)

#let clip(image, top: 0pt, bottom: 0pt, left: 0pt, right: 0pt) = {
  box(clip: true, image, inset: (top: -top, right: -right, left: -left, bottom: -bottom))
}

#let theorem = thmbox("theorem", "Theorem", stroke: black).with(numbering: none)
#let definition = thmbox("definition", "Definition", inset: (x: 1.2em, top: 1em)).with(numbering: none)

#let globalvars = state("t", 0)
#let timecounter(minutes) = [
  #globalvars.update(t => t + minutes)
  #place(top + right, dx: 0%, dy: -5%, align(right, text(16pt, red)[#context globalvars.get()min]))
]

#set cite(style: "apa")

#let myslide(left, right, gutter: 20pt) = {
  grid(columns: (1fr, 1fr), gutter: gutter, left, right)
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

= The Challenge: AI Needs Better Reasoners

== Machine Reasoning
#timecounter(2)

#v(10pt)

*New paradigm*: LLM formulates problem + Reasoner solves it @Pan2023

#figure(image("images/logiclm.png"))

*Problem*: Constraint Satisfaction Problems (CSP) require searching prohibitively large solution spaces ($2^n$ configurations for $n$ variables)

*Examples*: Sudoku, logic puzzles, circuit verification, optimization problems

== Constraint Satisfaction: Two Key Examples
#timecounter(2)

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
  
  - *Variables*: $x_i in {0, 1}$ (selected or not)
  - *Constraint*: No two neighbors both selected
  - *Goal*: Maximize $sum x_i$
], align(top)[
  *Circuit Satisfiability (SAT)*
  
  #figure(canvas({
    import draw: *
    content((0, 0.8), text(14pt)[$(x_1 or x_2 = x_3) and\ (x_1 xor x_3 = x_4) and\ (x_5 = not x_4)$])
  }))
  #v(10pt)
  
  - *Variables*: $x_i in {0, 1}$ (true or false)
  - *Constraint*: Logic gates
  - *Goal*: Satisfy all constraints
])

#align(center, box(stroke: black, inset: 10pt)[
  Both are NP-complete @Karp1972 — brute-force requires checking $2^n$ configurations
])

== Our Approach: Tensor Networks Meet Branching
#timecounter(3)

#myslide([
  *Tensor Network Representation*:
  - Each *variable* $arrow.r$ bond (index)
  - Each *constraint* $arrow.r$ tensor
  - Contraction finds solutions
  
  #figure(canvas({
    import draw: *
    circle((0, 0), radius: 0.6, name: "v")
    content((0, 0), [$V_i$])
    
    let dx = 3.0
    content((dx, 0), [$E_(i j)$])
    circle((dx, 0), radius: 0.6, name: "e")
    line("v", (rel: (0, 1.5), to: "v"))
    line("e", (rel: (-1, 1.5), to: "e"))
    line("e", (rel: (1, 1.5), to: "e"))
    content((0, 1.8), [$x_i$])
    content((dx - 1, 1.8), [$x_i$])
    content((dx + 1, 1.8), [$x_j$])
  }))
], [
  *Challenge*: Memory bottleneck!
  
  For complex problems, memory cost is $2^"tree-width"$ — can be exponential
  
  *Our Innovation*: Smart "branching" strategy that cuts a large tensor network into multiple smaller ones

  Applicable to any contraction of *sparse tensor networks*.
])

#align(center, box(stroke: black, inset: 10pt, fill: yellow.lighten(80%))[
  *Key Insight*: Use the structure of constraints to divide the problem intelligently
])

= Key Innovation: Optimal Branching

== The Core Idea: Learning from Feasible Solutions
#timecounter(3)

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
  
  let show-graph-remove-edge(vertices, edges, removed, ready, color: blue, radius:0.2, st: 0.5pt) = {
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
  
  show-graph-remove-edge(ksg_loc.map(v=>(v.at(0)*gridsize, v.at(1)*gridsize)), edges, (), (19, 16, 18), radius:r, st: lw)
  content((0.0, 1), [$x_1$])
  content((1.5, 1.6), [$x_2$])
  content((2, 0), [$x_3$])
}))

*Example*: Only 3 feasible configurations for highlighted variables: ${010, 101, 110}$

- "Learn" a *true statement in disjunctive normal form (DNF)*:
 - $(not x_1 and x_2 and not x_3) or (x_1 and not x_2 and x_3) or (x_1 and x_2 and not x_3)$
 - $x_1 or not x_1$
 - $(x_2 and not x_3) or (x_1 and not x_2 and x_3)$ (best)
- Branching ($approx$ non-uniform slicing) rule to "cut" problems:
 - (assign $x_2$ to $1$ and $x_3$ to $0$) OR (assign $x_1$ to $1$ and $x_2$ to $0$ and $x_3$ to $1$)

== Time-Space Trade-off: A Major Improvement
#timecounter(2)

#myslide[
  #image("images/ksg_60x60_tc_s1.svg", width: 100%)
][
  *Traditional slicing*:
  - Time grows exponentially as you reduce memory
  
  *Our BBTN method*:
  - Both time AND space decrease simultaneously!
  - Exploits problem structure

#let namebox(src, name) = box(align(center, [#image(src, width:60pt, height:80pt)#v(-10pt)#name]))
#align(center,[
#namebox("images/yijiawang.png", text(16pt)[Yi-Jia Wang])#h(20pt)
#namebox("images/xuanzhao.png", text(16pt)[Xuan-Zhao Gao])
])
]

= Results: Breaking Records

== Scaling to Large Problems
#timecounter(2)
#figure(image("images/time_complexity.svg", width: 70%))

*Key achievements*:
1. BBTN scales to instances 100x larger than pure tensor network methods
2. Outperforms state-of-the-art open source solvers (SCIP)

== Circuit SAT & Integer Factoring
#timecounter(2)

#place(bottom + right, align(center, [
  #image("images/xiweipan.png", width: 50pt, height: 70pt) #text(14pt, [#v(-15pt)Xi-Wei Pan])
  #image("images/zhongyi.jpg", width: 50pt, height: 70pt) #text(14pt, [#v(-15pt)Zhong-Yi Ni])
]))

#myslide(gutter: -50pt)[
  #image("images/branch_comparison.png", width: 80%)
][
  #image("images/branch_comparison_3sat.png", width: 80%)
]

*Result*: Dramatically fewer branches to reach solvable subproblems!

== Beating 40 Years of Expert-Designed Rules
#timecounter(2)

*The bottleneck case* from state-of-the-art algorithm @Xiao2013:

#grid(columns: 3,
  image("images/bottleneck.svg", width: 300pt),
  h(30pt),
  align(horizon, text(20pt, black)[
    - 21 variables in local region
    - 71 feasible configurations
    - 15,782 candidate rules tested
    
    *Our automated result*:
    *$ gamma = 1.0817 < 1.0836 $*
    
    *Better than best human-designed rule!*
    
    (Computed in 1 second)
  ]),
)

== Talk is cheap, show me the code!
#timecounter(1)

#myslide([
#align(center, grid(columns: 1, gutter: 10pt, image("images/ob-logo.svg", width: 300pt), 
[
#link("https://github.com/OptimalBranching/OptimalBranching.jl")[OptimalBranching/OptimalBranching.jl]
]))

#align(center, image("images/barcode.png", width: 150pt))
], [
Julia language based ecosystem

- OMEinsumContractionOrders (faster than CoTengra by several orders) & OMEinsum
- TropicalGEMM & CuTropicalGEMM (world's fastest tropical matrix multplication)
- ProblemReductions, GenericTensorNetworks & TensorInference

My Github handle: *GiggleLiu*
])

== Summary: Key Takeaways
#timecounter(2)

- *Problem*: Constraint satisfaction $->$ tensor network $->$ Memory explodes!

- *Innovation*: Cut a large tensor network to multiple smaller ones by exploiting constraint correlations (or sparsity in tensor networks)

- *Results*: 
    - Compared with integer programming, it has advantage in both MIS problem and Circuit SAT problem
    - Compared with expert-designed branching rules, it is optimal
    - Compared with slicing, it has advantage in time-space trade-off

- *Impact*: Enables better reasoners for LLMs, scientific applications, and industrial optimization

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


#image("images/sycamore.pdf", width: 60%)