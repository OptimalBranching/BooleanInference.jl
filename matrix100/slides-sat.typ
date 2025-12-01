#import "@preview/touying:0.6.1": *
#import "@preview/touying-simpl-hkustgz:0.1.2": *
#import "@preview/cetz:0.4.0": canvas, draw, tree
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

= Motivation: AI Needs Logical Reasoning

== LLM needs a reasoner
#timecounter(1)

#v(10pt)
*Large language models (LLMs) suffers from complex reasoning*#footnote([This statement is from year 2023, by @Pan2023.])
- Struggle with multi-step logical reasoning ("Hallucinations")
- Cannot strictly enforce hard constraints (e.g. rules of a game)

#align(center, [? Machines cannot deep reason])
#pause
#align(center, [No! We have expert tools.])

#figure(canvas({
  import draw: *
  content((-5, 0), [*LLM*])
  content((0, 0), [*Human*])
  content((5, 0), [*Reasoner*])
  content((-3, -1), text(12pt)[Reasoning])
  line((-2, -1), (-1, -1), mark: (end: "straight"))
  content((3.2, -1), text(12pt)[Knowledge])
  line((2, -1), (1, -1), mark: (end: "straight"))
}))

#v(-10pt)
*Reasoner*: Given a problem statement, disired *consequences*, and constraints, find a *cause*,
by exploring *exponentially large*, or even *infinitely many* solution space.

We can combine LLM + Reasoner! @Pan2023

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

== Reasoners
#timecounter(2)

*Problem*: "Fill a 9×9 Sudoku grid so each row, column, and 3×3 box contains 1-9."

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

#align(center, box(stroke: black, inset: 8pt)[
  *Constraint Satisfaction Problem (CSP)*:\ finite domains + constraints — foundation of SMT solvers
])

// == Exact solvers
// - Branching algorithms.
// - Dynamic programming.
// - Integer programming.
// - SAT solvers.

// === Physics-inspired (exact) algorithms
// - Grover search: quadratic speed up compared to bruteforce search.
// - Tensor networks (similar to dynamic programming).

// Dilema of physics-inspired algorithms:
// - None of the solvers above are close to the state-of-the-art exact solvers.

== This Talk
#timecounter(2)

*What you will learn:*
- Constraint satisfaction problem (CSP)?
- *Branching* matters, why is it so powerful, and what is the general principle?
- Combine branching with *tensor networks* for solving large scale CSPs

#align(center, box(stroke: black, inset: 8pt)[
Branching formalizes human reasoning: *case by case* analysis.
])

*Example*: Solving a Sudoku — assume a cell is `1`. If this leads to a conflict, backtrack and try `2`. This is branching!

Branching contributes to most state-of-the-art exact solvers for hard combinatorial problems @Fomin2013.

= The Branching Principle

// == What is a Constraint Satisfaction Problem (CSP)?
// #timecounter(2)

// #definition("Constraint Satisfaction Problem")[
//   Given:
//   - *Variables*: $bold(x) = {x_1, x_2, dots, x_n}$, each taking values from a finite set (e.g., $\{0, 1\}$, colors, etc.)
//   - *Constraints*: Rules that restrict which combinations of values are allowed
//   - *Goal*: Find an assignment that satisfies all constraints (or optimize an objective)
// ]

// Think of it as a *puzzle*: you have pieces (variables) and rules (constraints) — find a valid configuration.

== Two Examples (used in later sections)
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
  *Boolean Satisfiability (SAT)*
  
  #figure(canvas({
    import draw: *
    content((0, 0.8), text(14pt)[$(x_1 or x_2) and (not x_1 or x_3)$])
    content((0, 0), text(14pt)[$ and (not x_2 or not x_3)$])
  }))
  #v(10pt)
  
  - *Variables*: $x_i in \{0, 1\}$ (true or false)
  - *Constraint*: Clauses (OR of literals), generalized to gates later
  - *Goal*: Satisfy all clauses
])

#align(center, box(stroke: black, inset: 10pt)[
  Brute-force: $2^n$ configurations. Wait! Constraints prune the search space.
])

== 40 Years of Progress on MIS
#timecounter(1)

#let hd(name) = table.cell(text(10pt)[#name], fill: green.lighten(50%))
#let s(name) = table.cell(text(10pt)[#name])
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


// == Branching in Action: MIS Example @Fomin2006
// #slide[
// #canvas(length: 0.71cm, {
//   import draw: *
//   let scircle(loc, radius, name) = {
//     circle((loc.at(0)-0.1, loc.at(1)-0.1), radius: radius, fill:black)
//     circle(loc, radius: radius, stroke:black, name: name, fill:white)
//   }
//   let s = 1.5
//   let dy = 3.0
//   let la = (-s, 0)
//   let lb = (0, s)
//   let lc = (0, 0)
//   let ld = (s, 0)
//   let le = (s, s)
//   scircle((0, 0), (3, 2), "branch")
//   for (l, n) in ((la, "a"), (lb, "b"), (lc, "c"), (ld, "d"), (le, "e")){
//     circle((l.at(0), l.at(1)-s/2), radius:0.4, name: n, stroke: if n == "a" {red} else {black})
//     content((l.at(0), l.at(1)-s/2), text(14pt)[$#n$])
//   }
//   for (a, b) in (("a", "b"), ("b", "c"), ("c", "d"), ("d", "e"), ("b", "d")){
//     line(a, b)
//   }
//   scircle((-4, -dy), (2, 1.5), "brancha")
//   for (l, n) in ((lc, "c"), (ld, "d"), (le, "e")){
//     let loc = (l.at(0)-5, l.at(1)-s/2-dy)
//     circle(loc, radius:0.4, name: n, stroke: if n == "c" {red} else {black})
//     content(loc, text(14pt)[$#n$])
//   }
//   for (a, b) in (("c", "d"), ("d", "e"), ("c", "d")){
//     line(a, b)
//   }
//   scircle((4, -dy), (1, 1), "branchb")
//   circle((4, -dy), radius:0.4, name: "e", stroke: red)
//   content((4, -dy), text(14pt)[$e$])
//   scircle((-6, -2*dy), (1, 1), "branchaa")
//   circle((-6, -2*dy), radius:0.4, name: "e", stroke: red)
//   content((-6, -2*dy), text(14pt)[$e$])
//   scircle((-2, -2*dy), (0.5, 0.5), "branchab")
//   scircle((4, -2*dy), (0.5, 0.5), "branchba")
//   scircle((-6, -3*dy), (0.5, 0.5), "branchaaa")
//   line("branch", "brancha")
//   line("branch", "branchb")
//   line("brancha", "branchaa")
//   line("brancha", "branchab")
//   line("branchb", "branchba")
//   line("branchaa", "branchaaa")
//   content((-5, -dy/2+0.5), text(12pt)[$G \\ N[a]$])
//   content((3.5, -dy/2), text(12pt)[$G \\ N[b]$])
//   content((-6.8, -3*dy/2), text(12pt)[$G \\ N[c]$])
//   content((-1.5, -3*dy/2-0.4), text(12pt)[$G \\ N[d]$])
//   content((-4.8, -5*dy/2-0.4), text(12pt)[$G \\ N[e]$])
//   content((5.2, -3*dy/2-0.4), text(12pt)[$G \\ N[e]$])
// })
// - Time complexity: $gamma^(|V|)$
// - MIS size: $alpha(G) = 3$
// ][
// #timecounter(3)
// *Step 1.* Pick a vertex (e.g., $a$) and consider two cases:
//   - *Case 1*: $a$ is in the MIS $arrow.r$ remove $a$ and its neighbors
//   - *Case 2*: $a$ is not in the MIS $arrow.r$ some neighbor (e.g., $b$) must be

// #pause
// #box(stroke: black, inset: 10pt, [*Branching factor*: $gamma approx 1.27$, from $gamma^n = gamma^(n-2) + gamma^(n-4)$])

// #pause
// *Step 2.* Solve subproblems recursively:
// $
//   alpha(G) = max(alpha(G \\ N[a]) + 1, alpha(G \\ N[b]) + 1)
// $
// Each branch reduces the problem size — that's the power of branching!
// ]

// ==
// #grid(columns: 2, gutter: 20pt,
// align(top)[
//   *Example: Simple branching*
  
//   Pick variable $x$, branch on $x=0$ and $x=1$:
//   - Removes 1 variable per branch
//   - $gamma^n = 2 gamma^(n-1)$
//   - Solving: $gamma = 2$
  
// ], align(top)[
//   *Better branching*:
  
//   Branch cleverly to remove more variables:
//   - Branch 1: remove 3 variables
//   - Branch 2: remove 5 variables
//   - $gamma^n = gamma^(n-3) + gamma^(n-5)$
//   - Solving: $gamma approx 1.32$
// ])
  
//   *Goal*: Find branching rules that minimize $gamma$!
// #align(center, box(stroke: black, inset: 10pt)[
//   *Key*: A good *branching rule* utilizes problem structure to achieve a small branching factor $gamma$.
// ])

== Traditional Approach: Hand-Crafted Rules
#timecounter(1)

#align(center, grid(columns: 3, gutter: 20pt,
align(top, [1. Design rules by hand]), align(top, [2. Match graph patterns]), align(top, [3. Apply corresponding rule]),
align(left + top, box(stroke: black, inset: 10pt, width: 200pt, [
- Dominance rule
- Mirror rule
- Satellite rule
- ...
])),
align(center+top, text(11pt)[#canvas(length: 0.5cm, demograph((white, white, white, white, white), fontsize: 12pt))]),
align(left+top, box(stroke: black, inset: 10pt, width: 320pt, [
  - If `degree(v) == 1`, add `v` to the set
  - If `has_mirror`, use mirror rule
  - If `has_satellite`, use satellite rule
  - ...
]))
))

*Limitations:*
- Rules are *problem-specific* — years of expert effort to design
- Rules do not know *subgraph structure*, and are not optimal (all precooked)

== General principle that applicable to all boolean CSP?
#timecounter(1)

*Chain of thought*

Check a subset of variables $->$ Local constraints $->$ Limited local feasible solutions $->$ Optimal branching rule

- Q: Does a *local subset of variables* include all information required for branching?
- A: Yes. So far, every branching rule on MIS only check $N_2(v)$ - the second nearest neighbor.

== Our approach: online branching rule generation
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

*Key idea*: Generate optimal branching rules *on-the-fly* from the problem structure.

== The Math Behind Branching
#timecounter(2)

#myslide[
*Branching* = Divide-and-conquer with a twist

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


// == Key: Valid and good branching rule
// #timecounter(2)

// - Valid: all elements in *feasible set* are true assignments of $cal(D)$ (exploring all possibilities).
// - Good: create less branches, eliminate more variables.

// #grid(columns:2, gutter: 20pt, canvas({
//     import draw: *
//     circle((0, 0), radius: (4, 2))
//     circle((1, 0), radius: 1, fill: silver, stroke: none)
//     circle((1.4, 0), radius: (1.8, 1.2), fill: aqua.transparentize(80%))
//     content((1, 0), text(14pt)[oracle])
//     content((-1.5, 0), text(14pt)[Total])
//     content((2.5, 0), text(14pt)[$cal(D)$])
// }),
// [
// $ cal(D) = underbrace((b and not c) or overbrace(( not b and c and d), "size reduction (longer is better)"), "number of branches (less is better)") $

// ]
// )

// #align(left, box(stroke: black, inset: 10pt)[Objective $gamma$: Let $Delta rho(c_i)$ be the size reduction after applying the clause $c_i$.
// Then the branching factor is given by $gamma^rho = sum_i gamma^(rho - Delta rho(c_i))$, i.e.
// $
//   1 = sum_i gamma^(- Delta rho(c_i))
// $])

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

*Our solution*: arXiv:2412.07685

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


// == Methods for solving MIS
// #timecounter(1)

// *Tensor network (or dynamic programming)* has time complexity $O(2^"tw"(G))$. Suited for:
// - Graphs with small tree width, e.g.
//   - Tree graph, $"tw"(G) = 1$ 
//   - Geometric graphs such as the grid graph, $"tw"(G) = O(sqrt(n))$

// *Branching* has time complexity $gamma^n$, where $gamma$ is the branching factor. Suited for:
// - Graphs with high degree, e.g.
//   - Fully connected graph, complexity is $O(n)$.

// *Hard for both:*
// - 3-regular graph, high dimensional, but sparse enough.
//   - Tree width is $approx n/6$, rendering a tensor network algorithm with complexity $O(1.1225^n)$.
//   - The best branching algorithm is $O(1.0836^n)$ @Xiao2013.

// == Difference with traditional branching? @Fomin2006
// #slide[
// #canvas(length: 0.71cm, {
//   import draw: *
//   let scircle(loc, radius, name) = {
//     circle((loc.at(0)-0.1, loc.at(1)-0.1), radius: radius, fill:black)
//     circle(loc, radius: radius, stroke:black, name: name, fill:white)
//   }
//   let s = 1.5
//   let dy = 3.0
//   let la = (-s, 0)
//   let lb = (0, s)
//   let lc = (0, 0)
//   let ld = (s, 0)
//   let le = (s, s)
//   scircle((0, 0), (3, 2), "branch")
//   for (l, n) in ((la, "a"), (lb, "b"), (lc, "c"), (ld, "d"), (le, "e")){
//     circle((l.at(0), l.at(1)-s/2), radius:0.4, name: n, stroke: if n == "a" {red} else {black})
//     content((l.at(0), l.at(1)-s/2), text(14pt)[$#n$])
//   }
//   for (a, b) in (("a", "b"), ("b", "c"), ("c", "d"), ("d", "e"), ("b", "d")){
//     line(a, b)
//   }
//   scircle((-4, -dy), (2, 1.5), "brancha")
//   for (l, n) in ((lc, "c"), (ld, "d"), (le, "e")){
//     let loc = (l.at(0)-5, l.at(1)-s/2-dy)
//     circle(loc, radius:0.4, name: n, stroke: if n == "c" {red} else {black})
//     content(loc, text(14pt)[$#n$])
//   }
//   for (a, b) in (("c", "d"), ("d", "e"), ("c", "d")){
//     line(a, b)
//   }
//   scircle((4, -dy), (1, 1), "branchb")
//   circle((4, -dy), radius:0.4, name: "e", stroke: red)
//   content((4, -dy), text(14pt)[$e$])
//   scircle((-6, -2*dy), (1, 1), "branchaa")
//   circle((-6, -2*dy), radius:0.4, name: "e", stroke: red)
//   content((-6, -2*dy), text(14pt)[$e$])
//   scircle((-2, -2*dy), (0.5, 0.5), "branchab")
//   scircle((4, -2*dy), (0.5, 0.5), "branchba")
//   scircle((-6, -3*dy), (0.5, 0.5), "branchaaa")
//   line("branch", "brancha")
//   line("branch", "branchb")
//   line("brancha", "branchaa")
//   line("brancha", "branchab")
//   line("branchb", "branchba")
//   line("branchaa", "branchaaa")
//   content((-5, -dy/2+0.5), text(12pt)[$G \\ N[a]$])
//   content((3.5, -dy/2), text(12pt)[$G \\ N[b]$])
//   content((-6.8, -3*dy/2), text(12pt)[$G \\ N[c]$])
//   content((-1.5, -3*dy/2-0.4), text(12pt)[$G \\ N[d]$])
//   content((-4.8, -5*dy/2-0.4), text(12pt)[$G \\ N[e]$])
//   content((5.2, -3*dy/2-0.4), text(12pt)[$G \\ N[e]$])
// })
// - Time complexity: $gamma^(|V|)$
// - MIS size: $alpha(G) = 3$
// ][
// #timecounter(1)
// Step 1. Select a vertex, e.g. $a$
//   - Case 1: $a$ is in the independent set, then create a branch $G \\ N[a]$
//   - Case 2: $a$ is not in the independent set, then create a branch with $b$ selected, $G \\ N[b]$

// #pause
// #box(stroke: black, inset: 10pt, [Branching factor: $gamma approx 1.27$, from $gamma^(|V|) = gamma^(|V|-2) + gamma^(|V|-4)$])

// #pause
// Step 2. Solve two subproblems recursively
// $
//   alpha(G) = max(alpha(G \\ N[a]) + 1, alpha(G \\ N[b]) + 1)
// $
// ]

== On-the-Fly Rule Generation
#timecounter(1)
#align(center, grid(columns: 3, gutter: 25pt,
align(center, [1. Select a local region]),
align(center, [2. Enumerate feasible configs]),
align(center, [3. Compute optimal rule]),
align(center+top, text(11pt)[#canvas(length: 0.5cm, demograph((white, white, white, white, white), fontsize: 12pt))]),
align(left+top, text(16pt)[
- 00001 (or 00010)
- 00101
- 01010
- 11100
]),
align(center + top, text(80pt)[\u{1F4CF}])
))

*Why is this better?*
- No manual rule design — fully automatic
- Exploits local structure — adapts to each subproblem
- Provably optimal — minimizes $gamma$ for the given region

// == Branching on the fly algorithm
// #timecounter(1)
// #align(center, grid(columns: 2, gutter: 40pt, box(width: 300pt, align(left)[
// #canvas({
//   import draw: *
//   scale(x:60%, y:60%)
//   let DY = 3
//   let size = 1
//   for k in range(5){
//     content((k * size, 0.2 + size), text(12pt, box([$#numbering("a", k+1)$], fill: none, inset: 2pt)))
//   }
//   content((2, 2.5), align(center, text(12pt)[oracle: $(b, c, d) in {101, 100, 011}$]))
//   decision_sequence((0, 0), (0, -3, -3, -3, 0))
// })
// - _Oracle_ is a set of bit strings representing feasible solutions over some variables.
// ]),
// canvas(length: 25pt, {
//   import draw: *
//   main-diagram()
//   content((0, -2), box(text(15pt)[Check some variables, get oracle: $cal(S)$], stroke: (thickness: 2pt, paint: yellow), inset: 10pt), name: "orange", fill: white)
// })
// ))

// == Branching rule: a Disjunctive Normal Form (DNF) formula
// #timecounter(1)
// #align(center, grid(columns: 2, gutter: 40pt, box(width: 300pt, align(left)[
// #canvas({
//   import draw: *
//   scale(x:60%, y:60%)
//   let DY = 3
//   let size = 1
//   for k in range(5){
//     content((k * size, 0.2 + size), text(12pt, box([$#numbering("a", k+1)$], fill: none, inset: 2pt)))
//   }
//   content((2, 2.5), align(center, text(12pt)[oracle: $(b, c, d) in {101, 100, 011}$]))
//   content((-5.5, -1.5), align(center, text(12pt)[branch: $b = 1, c = 0$]))
//   decision_sequence((0, 0), (0, -3, -3, -3, 0))
//   decision_sequence((-4, -DY), (-3, 1, 2, -3, -3))
//   decision_sequence((4, -DY), (-3, 2, 1, 1, -3))
//   line((1.2, -0.8), (-1.2, -DY + 0.8), mark: (end: "straight"))
//   line((2.8, -0.8), (5.2, -DY + 0.8), mark: (end: "straight"))
// })

// - DNF: a disjunction of clauses.
// - clause (branch): a conjunction of literals.
// $ cal(D) = (#pin(1)b#pin(2) and not c) or ( #pin(3)not b#pin(4) and c and d) $
//   #pinit-highlight(1, 2)
//   #pinit-point-from(1, pin-dy: 65pt, offset-dy: 80pt, body-dy: -50pt, body-dx: -75pt, offset-dx: -10pt)[positive literal $arrow.r$ 1]
//   #pinit-highlight(3, 4)
//   #pinit-point-from(3, pin-dy: 65pt, offset-dy: 80pt, body-dy: -50pt, body-dx: -15pt, offset-dx: 10pt)[negative literal $arrow.r$ 0]
// ]),
// canvas(length: 25pt, {
//   import draw: *
//   main-diagram()
//   content((0, -4), box(text(15pt)[Generate branching rules: $cal(D)$], stroke: (thickness: 2pt, paint: yellow), inset: 10pt), name: "orange", fill: white)
// })
// ))

// = The time traveler problem

// == Branchmark on random graphs
// The resulting methods are denoted as *ob* and *ob+xiao* and the average branching factor is shown in the table.
// #align(center, table(
//     columns: (auto, auto, auto, auto, auto, auto),
//     table.header(hd[], hd[*ob*], hd[*ob+\ xiao*], hd[xiao2013], hd[akiba2015], hd[akiba2015+\ xiao&packing]),
//     s[3RR], s[1.0457], s[*1.0441*], s[*1.0487*], s[-], s[-],
//     s[ER], s[1.0011], s[1.0002], s[-], s[1.0044], s[1.0001],
//     s[KSG], s[1.0116], s[1.0022], s[-], s[1.0313], s[1.0019],
//     s[Grid], s[1.0012], s[1.0009], s[-], s[1.0294], s[1.0007],
// ))

// #align(center, grid(columns: 2, gutter: 20pt,
//   grid(rows: 5,
//   align(center,
//   ),
//   v(10pt),
//   text(15pt)[The resulting methods are denoted as *ob* and *ob+xiao* and the average branching factor is shown in the table.],
//   v(10pt),
//   align(center, table(
//     columns: (auto, auto, auto, auto, auto, auto),
//     table.header(hd[], hd[*ob*], hd[*ob+\ xiao*], hd[xiao2013], hd[akiba2015], hd[akiba2015+\ xiao&packing]),
//     s[3RR], s[1.0457], s[*1.0441*], s[*1.0487*], s[-], s[-],
//     s[ER], s[1.0011], s[1.0002], s[-], s[1.0044], s[1.0001],
//     s[KSG], s[1.0116], s[1.0022], s[-], s[1.0313], s[1.0019],
//     s[Grid], s[1.0012], s[1.0009], s[-], s[1.0294], s[1.0007],
//   ))),
//   figure(image("images/fig5.svg", width: 380pt), caption : [#text(15pt)[Average number of branches generated by different branching algorithms on 1000 random graphs.]])
// ))

== Benchmark: Fewer Branches $approx$ Faster Solving
#timecounter(3)

#grid(columns: 2, gutter: 0pt,
image("images/fig5.svg", width: 350pt), [
  *Metric*: Number of branches (lower is better)
  
  *Methods compared*:
  - #text(red)[`ob`]: Our optimal branching
  - #text(green)[`xiao2013`]: Best hand-crafted 3-MIS rules
  - #text(blue)[`akiba2015`]: PACE competition winner
  
  #v(10pt)
  *Key findings*:
  - #text(red)[`ob`] generates the fewest branches across all graph types, given the same reduction rule
  - On 3-regular graphs: $gamma = 1.0441$ (vs. 1.0487 for hand-crafted)
])

// == The branching overhead matters? Branching hierachy
// #timecounter(1)
// The overhead of branching on-the-fly is $8times$ the case with a pre-defined branching rule.
// #grid(gutter: 30pt, columns: 2, [#image("images/mix_runtime.svg", width: 300pt)], [
//   #figure(canvas(length: 1cm,
//     {
//       import draw: *
//       mixmode-bb()
//     }
//   ))
// ])
// #figure(box(stroke: black, inset: 10pt)[
//   Branching overhead can be mitigated by increasing the sub-problem size!
// ])


= Application 1: Maximal Independent Set (MIS)

== Tensor Networks for Combinatorial Optimization
#timecounter(2)
*Background for TN experts*:
- Tensor networks with *tropical algebra* can solve CSP @Liu2021@Liu2023
- Hard constraints create *sparsity* — many tensor elements are zero
- #v(-7pt)Sparse tensor network contraction helps, but *still slower than branching* 😞

*New insight*: Don't just exploit sparsity — use branching to *decompose* the network!

#let namebox(src, name) = box(align(center, [#image(src, width:60pt, height:80pt)#v(-10pt)#name]))
#align(center,[
#namebox("images/yijiawang.png", text(16pt)[Yijia Wang (IOTP)])#h(20pt)
#namebox("images/xuanzhao.png", text(16pt)[Xuanzhao Gao (HKUST)])
])



== Branch-and-Bound Tensor Network (BBTN)
#timecounter(2)

#myslide[
#figure(image("images/bbtn.svg", width: 360pt))
][
  *Key idea*: Use branching to decompose a large network into smaller, tractable pieces.

  *The right measure*: "Tree-width" of the tensor network (contraction complexity).

  *Left*: Traditional *slicing* — branch on one variable at a time.

  *Right*: BBTN — *non-uniform slicing* that more effectively reduces tree-width.
  
  *Result*: Much less number of sub-networks.
]

== Time vs. Space Complexity
#timecounter(1)

#myslide[
  #image("images/ksg_60x60_tc_s1.svg", width: 100%)
][
  *Dynamic slicing*: Time grows as you slice more variables.
  
  *BBTN (our method)*: Both time and space complexity *decrease* with more branching!
  
  *Why?* Optimal branching finds the most effective decomposition.
]


== Scaling to Large Problems
#timecounter(2)
#figure(image("images/time_complexity.svg", width: 70%))

1. BBTN scales to much larger instances than pure tensor network methods.
2. BBTN outperform SOTA open source integer programming solvers.

// ==
// #figure(image("images/tc_different_target.svg", width: 50%))

// ==
// #figure(image("images/compare_nu_u.svg", width: 50%))

= Application 2: Circuit SAT

// == DPLL Algorithm

// *Davis-Putnam-Logemann-Loveland (DPLL)* algorithm is a complete, backtracking-based search algorithm for deciding the satisfiability of propositional logic formulae in CNF.

// *Key ideas*:
// - *Unit propagation*: If a clause is a unit clause (only one literal), assign the variable to satisfy that clause.
// - *Pure literal elimination*: If a variable appears with only one polarity, assign it to satisfy all clauses containing it.
// - *Branching*: Choose a variable and recursively try both assignments (true and false).
// - *Backtracking*: If a branch leads to a conflict, backtrack and try the other assignment.

// *Time complexity*: $O(2^n)$ in the worst case, but often much better in practice due to pruning.

// ==
// *Example with branching*: Consider $F = (x_1 or x_2) and (not x_1 or x_3) and (not x_2 or not x_3) and (not x_3 or x_1)$

// #text(size: 16pt)[
// 1. *Initial*: $F = (x_1 or x_2) and (not x_1 or x_3) and (not x_2 or not x_3) and (not x_3 or x_1)$ (no unit clauses)
// 2. *Branch*: Choose $x_1$, try $x_1 = 1$ first
// 3. $F arrow.r cancel((x_1 or x_2)) and (cancel(not x_1) or x_3) and (not x_2 or not x_3) and (cancel(not x_3) or cancel(x_1))$\
//    $F arrow.r (x_3) and (not x_2 or not x_3)$
// 4. *Unit propagation*: $x_3 = 1$\
//    $F arrow.r cancel((x_3)) and (not x_2 or cancel(not x_3)) arrow.r (not x_2)$
// 5. *Unit propagation*: $x_2 = 0$\
//    $F arrow.r cancel((not x_2)) arrow.r emptyset$ #text(fill: green)[✓ *SAT*]
// 6. *Result*: Assignment found: $x_1 = 1, x_2 = 0, x_3 = 1$
// ]

// *Branching tree* shows search space reduction: Without branching, need to check $2^3 = 8$ assignments. DPLL finds solution by exploring only one branch with unit propagation.

// ==
// *Example with backtracking*: Consider $F = (x_1 or x_2) and (not x_1 or not x_2) and (not x_1 or x_2)$

// #text(size: 16pt)[
// *Left branch* ($x_1 = 1$):
// - $F arrow.r cancel((x_1 or x_2)) and (cancel(not x_1) or not x_2) and (cancel(not x_1) or x_2) arrow.r (not x_2) and (x_2)$
// - Get empty clause #text(fill: red)[✗ *UNSAT*] → *Backtrack!*

// *Right branch* ($x_1 = 0$):
// - $F arrow.r (cancel(x_1) or x_2) and cancel((not x_1 or not x_2)) and cancel((not x_1 or x_2)) arrow.r (x_2)$
// - Unit propagation: $x_2 = 1$ → $emptyset$ #text(fill: green)[✓ *SAT*]
// - *Result*: $x_1 = 0, x_2 = 1$
// ]

// This demonstrates how DPLL *branches* on variables and *backtracks* when conflicts arise, achieving $gamma^n$ complexity with $gamma < 2$ through pruning.

// == Combining Online Branching with Unit Propagation
// #timecounter(2)

// #slide[
// *Key Insight*: Unit propagation is extremely efficient, but traditional branching (choosing single variables) may not exploit the constraint structure optimally.

// *Our Approach*:
// 1. Select a subset of variables to form a region
// 2. Compute the oracle (tensor network contraction over the region)
// 3. Generate optimal branching rules from the oracle
// 4. Apply unit propagation after each branch
// ][
//   #align(center, canvas({
//     import draw: *
//     rect((-3, -0.5), (3, 0.5), fill: blue.lighten(80%), stroke: black)
//     content((0, 0), [1. Select region])
    
//     rect((-3, -2), (3, -1), fill: green.lighten(80%), stroke: black)
//     content((0, -1.5), [2. Compute oracle (TN)])
    
//     rect((-3, -3.5), (3, -2.5), fill: yellow.lighten(80%), stroke: black)
//     content((0, -3), [3. Optimal branching])
    
//     rect((-3, -5), (3, -4), fill: red.lighten(80%), stroke: black)
//     content((0, -4.5), [4. Unit propagation])
    
//     line((0, 0.5), (0, -1), mark: (end: "straight"))
//     line((0, -2), (0, -2.5), mark: (end: "straight"))
//     line((0, -3.5), (0, -4), mark: (end: "straight"))
//     line((0, -5), (5, -5), (5, 0.5), mark: (end: "straight"))
//   }))
// ]

== Example of Circuit SAT: Integer factoring
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

//   let gate(loc, label, size: 1, name:none) = {
//     rect((loc.at(0) - size/2, loc.at(1) - size/2), (loc.at(0) + size/2, loc.at(1) + size/2), stroke: black, fill: white, name: name)
//     content(loc, text(14pt)[$label$])
//   }
//   set-origin((-1.5, -3))
//   line((4.5, 0), (-1, 0))  // q
//   line((3, 1), (3, -4.5))  // p
//   let si = (-1, 1)
//   let ci = (4.5, -2.5)
//   gate((0.5, -0.5), [$and$], size: 0.5, name: "a1")
//   gate((2.5, -0.5), [$and$], size: 0.5, name: "a2")
//   gate((2.0, -2.5), [$and$], size: 0.5, name: "a3")
//   gate((0.5, -2.5), [$or$], size: 0.5, name: "o1")
//   gate((1.5, -1.5), [$xor$], size: 0.5, name: "x1")
//   gate((3.5, -3.5), [$xor$], size: 0.5, name: "x2")
//   line("a2", (2.5, 0))
//   line("x1", (1.5, -0.5))
//   line("a2", (3, -0.5))
//   line("a2", "a1")
//   line("a1", "o1")
//   line("a3", "o1")
//   line("o1", (rel: (-1.5, 0), to: "o1"))
//   line(si, "a1")
//   line(ci, "a3")
//   line((3.5, -2.5), "x2")
//   let turn = (1.5, -3.5)
//   line("x1",(rel: (0.5, -2.5), to: si), (rel: (0.5, -0.5), to: si))
//   line("x1", turn, "x2")
//   line("x2", (rel: (1, -1), to: "x2"))
//   line("a3", (2.0, -0.5))
//   rect((-0.75, -4), (4, 0.75), stroke: (dash: "dashed"))

//   let gate_with_leg(loc, label, size: 1, name:none) = {
//     gate(loc, label, size: size, name: name)
//     line(name, (rel: (0.5, 0), to: name))
//     line(name, (rel: (-0.5, 0), to: name))
//     line(name, (rel: (0, 0.5), to: name))
//   }
//   gate_with_leg((6, 0), [$xor$], size: 0.5, name: "x3")
//   content((8, 0), text(14pt)[$= mat(mat(0, 1; 1, 0); mat(1, 0; 0, 1))$])

//   gate_with_leg((6, -2), [$or$], size: 0.5, name: "o3")
//   content((8, -2), text(14pt)[$= mat(mat(1, 0; 0, 0); mat(0, 1; 1, 1))$])

//   gate_with_leg((6, -4), [$and$], size: 0.5, name: "a4")
//   content((8, -4), text(14pt)[$= mat(mat(1, 1; 1, 0); mat(0, 0; 0, 1))$])
})
]
)

// == Smart Measure: Reducing to 2-SAT
// #timecounter(2)

// *Key observation*: After branching, many clauses simplify:
// - *Unit clauses* — directly propagate
// - *Binary clauses* — 2-SAT, solvable in linear time!
// - *Larger clauses* — still need branching

// #definition("Measure: Number of Hard Clauses")[
//   $ rho(F) = |{c in F : |c| >= 3}| $
  
//   When $rho = 0$, the problem reduces to 2-SAT — solvable in $O(n)$ time!
// ]

// *Goal*: Branch to maximize reduction of $rho$, not just the number of variables.

// This exploits the *cascading effect* of constraint propagation.

// == Why This Measure?
// #timecounter(1)

// #grid(columns: 2, gutter: 30pt,
// [
// *Traditional measure*: Number of unfixed variables
// - Assigns one variable $arrow.r$ reduces measure by 1
// - May not exploit constraint structure

// *Our measure*: Number of non-2-SAT clauses
// - Good branching can reduce many clauses simultaneously
// - Better captures problem hardness
// - Exploits clause structure through unit propagation
// ],
// canvas({
//   import draw: *
//   // Example showing clause reduction
//   content((0, 0), align(left)[
//     *Before*: $F = (a or b or c) and (not a or d or e)$\
//     $rho = 2$
//   ])
  
//   content((0, -1.5), align(left)[
//     *Branch*: $a = 1$
//   ])
  
//   content((0, -3), align(left)[
//     *After propagation*: $F = (d or e)$\
//     $rho = 0$ (2-SAT!) \ 
//     Reduction: $Delta rho = 2$
//   ])
// }))

== Optimal Branching for Circuit SAT
#timecounter(2)

#myslide[
*Algorithm*:
1. Select a local region (nearby gates)
2. Enumerate feasible configurations (via tensor contraction), and apply unit propagation
3. Find optimal branching rule
4. Apply branch, propagate, and recurse
][
  #box(stroke: black, inset: 10pt, fill: yellow.lighten(80%))[
    *Key difference from MIS*: 
    - Measure = number of hard clauses (involving $>2$ varaibles), since 2-SAT is easy.
    - Exploits unit propagation to reduce the number of hard clauses.
  ]
]

== Benchmark: Number of branches
#timecounter(1)
- Much less branching steps to 2-SAT subproblems!
- Directly applicable to all boolean satisfiability problems, i.e. Circuit SAT and $K$-SAT.
#myslide[
  #image("images/branch_comparison.png", width: 100%)
][
  #image("images/branch_comparison_3sat.png", width: 100%)
]


// == Example: Circuit SAT Instance
// #timecounter(2)

// Consider a small circuit with variables $x_1, x_2, x_3, x_4$ and clauses:
// $ F = &(x_1 or x_2 or x_3) and (not x_1 or x_3 or x_4) \ 
//     &and (not x_2 or not x_3 or x_4) and (not x_3 or not x_4) $

// - Initial: $rho = 4$ (all clauses have 3+ literals)
// - Traditional: branch on single variable, $Delta rho <= 2$
// - Our approach: compute oracle on ${x_1, x_2, x_3}$, find branching rule that reduces $rho$ maximally

// #box(stroke: black, inset: 10pt)[
// *Result*: Optimal branching may assign multiple variables simultaneously, achieving $Delta rho = 4$ in one branch!
// ]

== Open Source Implementation
#timecounter(1)

#align(center, grid(columns: 1, gutter: 10pt, image("images/ob-logo.svg", width: 300pt), 
[
#link("https://github.com/OptimalBranching/OptimalBranching.jl")[OptimalBranching/OptimalBranching.jl]
]))

#align(center, image("images/barcode.png", width: 150pt))

// == Example: Circuit SAT Instance
// #timecounter(2)

// Consider a small circuit with variables $x_1, x_2, x_3, x_4$ and clauses:
// $ F = &(x_1 or x_2 or x_3) and (not x_1 or x_3 or x_4) \ 
//     &and (not x_2 or not x_3 or x_4) and (not x_3 or not x_4) $

// - Initial: $rho = 4$ (all clauses have 3+ literals)
// - Traditional: branch on single variable, $Delta rho <= 2$
// - Our approach: compute oracle on ${x_1, x_2, x_3}$, find branching rule that reduces $rho$ maximally

// #box(stroke: black, inset: 10pt)[
// *Result*: Optimal branching may assign multiple variables simultaneously, achieving $Delta rho = 4$ in one branch!
// ]

// == Take home message
// #timecounter(2)
// #align(left, text(16pt)[
// - Developed a classical algorithm (*Optimal Branching*) to solve *finite domain constraint satisfaction problem*, e.g. maximum independent set problem.
// - The key contribution: a provable optimal way to devide a problem into subproblems (optimal branching rule).
// - To quantum scientists, it is a better way to slice a *sparse* tensor networks (tensors having a lot of zeros).
// ])

// #align(center, canvas({
//   import draw: *
//   let points = ((0, 0), (0, 1), (1, 0), (1, 1), (0, -1), (-2, 1), (-1, 0), (-1, 1))
//   let edges = (("0", "1"), ("0", "2"), ("0", "4"), ("1", "2"), ("1", "3"), ("2", "3"), ("1", "7"), ("1", "6"), ("7", "5"), ("2", "4"), ("4", "6"), ("5", "6"), ("6", "7"))
//   for (k, loc) in points.enumerate() {
//     circle(loc, radius: 0.2, name: str(k), fill: black)
//   }
//   for (k, (a, b)) in edges.enumerate() {
//     line(a, b, name: "e"+str(k), stroke: (if k == 4 {(paint: red, thickness: 2pt)} else {black}))
//   }
//   content((rel: (0, 0.5), to: "e4.mid"), text(14pt)[$i$])
  
//   set-origin((7.5, 0))
//   line((-5.5, 0), (-4.5, 0), mark: (end: "straight"))
//   content((-5, 0.4), text(14pt)[slicing])
//   content((-3, 0), [$ sum_i $])
//   for (k, loc) in points.enumerate() {
//     circle(loc, radius: 0.2, name: str(k), fill: black)
//   }
//   for (k, (a, b)) in edges.enumerate() {
//     line(a, b, name: "e"+str(k), stroke: (if k == 4 {(dash: "dashed")} else {black}))
//   }
//   content((rel: (0, 0.5), to: "e4.mid"), text(14pt)[$i$])

//   set-origin((0, -3))
//   line((-5.5, 0), (-4.5, 0), mark: (end: "straight"))
//   content((-5, 0.4), text(14pt)[Optimal Branching])
//   content((-5, -0.4), text(14pt)[By utilizing sparsity in tensors])
//   content((3, -1.6), text(14pt)[Sub-tensor-networks with different topologies])
//   for (k, loc) in points.enumerate() {
//     circle(loc, radius: 0.2, name: str(k), fill: black)
//   }
//   for (k, (a, b)) in edges.enumerate() {
//     line(a, b, name: "e"+str(k), stroke: (if (k == 4 or k == 3) {(dash: "dashed")} else {black}))
//   }
//   set-origin((5, 0))
//   content((-2.5, 0), [$+$])
//   for (k, loc) in points.enumerate() {
//     circle(loc, radius: 0.2, name: str(k), fill: black)
//   }
//   for (k, (a, b)) in edges.enumerate() {
//     line(a, b, name: "e"+str(k), stroke: (if (k == 4 or k == 0 or k == 1 or k == 2) {(dash: "dashed")} else {black}))
//   }
//   content((2.5, 0), [$+ quad dots$])
// }))

== Summary
#timecounter(1)

*Key Takeaways*:
1. LLMs need a reasoner to take care of hard constraints.
2. *Branching*, reflect human wisdom of case by case analysis, has an (locally) optimal strategy, in terms of \# of branches.
4. *Applications*: Maximum independent set, Circuit SAT and more.

#align(center, box(stroke: black, inset: 15pt, fill: yellow.lighten(80%))[
  *Case by case* - there is a better way. 
])

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