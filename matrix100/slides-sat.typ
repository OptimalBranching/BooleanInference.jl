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
  #place(dx: 100%, dy: -5%, align(right, text(16pt, red)[#context globalvars.get()min]))
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
    title: [Branching principle for constraint satisfaction problems],
    subtitle: [arXiv:2412.07685],
    author: [Jin-Guo Liu],
    date: datetime.today(),
    institution: [HKUST(GZ) - FUNH - Advanced Materials Thrust],
  ),
)

#title-slide()
#outline-slide()

= AI, reasoning and constraint satisfaction

== The Logic Reasoning Gap
#timecounter(2)

*Large language models (LLMs) struggle with logical reasoning* @Pan2023
- Hallucinations in multi-step reasoning
- Cannot strictly enforce hard constraints
- No guarantees on correctness

#align(center, [? Machines cannot deep reason])

#pause

#align(center, [No!])

#figure(canvas({
  import draw: *
  content((-5, 0), [*LLM*])
  content((0, 0), [*Human*])
  content((5, 0), [*SAT Solvers*])
  content((-3, -1), text(12pt)[Reasoning])
  line((-2, -1), (-1, -1), mark: (end: "straight"))
  content((3.2, -1), text(12pt)[Knowledge])
  line((2, -1), (1, -1), mark: (end: "straight"))
}))
  
== LLM + SAT
#timecounter(2)

*New Scheme*: LLM + SAT solvers @Pan2023:

1. *First-Order Logic* (FOL): Theorem provers (e.g., Prover9)
   - Most expressive, but undecidable
   
2. *Satisfiability Modulo Theories* (SMT): Z3, CVC5 @deMoura2008
   - Boolean logic + arithmetic/arrays/bit-vectors
   - Decidable for many theories
#box(stroke: (paint: black, dash: "dashed"), outset: 10pt, [
3. *Constraint Satisfaction Problems* (CSP): Kissat, X-SAT
   - Finite domains, highly efficient
   - Foundation for many applications
])

#place(dx: 70%, dy: -20%, [*$checkmark$ Our objective*
- Simple
- Fundational])

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

// == Comparing the Three Paradigms
// #timecounter(2)

// *Problem*: "Three people have different ages. Alice > Bob."

// #grid(columns: 3, gutter: 25pt, align(top)[
//   *FOL (Theorem Proving)*
  
//   #text(14pt)[```
//   ∀x,y (x≠y → Age(x)≠Age(y))
//   Age(Alice) > Age(Bob)
  
//   Query: ?
//   ```]
  
//   ✓ Most expressive\ 
//   ✗ Undecidable
// ], align(top)[
//   *SMT (Z3, CVC5)*
  
//   #text(14pt)[```smt
//   (declare-const a Int)
//   (declare-const b Int)
//   (declare-const c Int)
//   (assert (distinct a b c))
//   (assert (> a b))
//   (check-sat)
//   ```]
  
//   ✓ Boolean + theories\
//   ✓ Decidable
// ], align(top)[
//   *CSP (Our Focus)*
  
//   #text(14pt)[```
//   Alice, Bob, Carol ∈ {1,2,3}
  
//   AllDifferent(·,·,·)
//   Alice > Bob
  
//   → 12 solutions
//   ```]
  
//   ✓ Highly efficient\
//   ✓ Combinatorial opt.
// ])

// #align(center, box(stroke: black, inset: 8pt)[
//   *CSP is the foundation of many SMT solvers and combinatorial algorithms*
// ])

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

== Focus of this talk: Branching for CSP
#timecounter(2)

By the end of the talk, you will
- Understand constraint satisfaction problems (CSP)
- Understand the principle of branching
- How branching is combined with tensor network methods to solve hard problems

*Branching*$(checkmark)$: contributes most of the SOTA exact exponential solvers for computational hard problems @Fomin2013.

#align(center, box(stroke: black, inset: 8pt)[
Branching implements human wisdom for reasoning: *case by case*.
])

e.g. Solving a Sudoku: assume a cell is `1`. If this choice leads to a conflict, backtrack and try `2`.

= Branching, a generic principle

== Constraint Satisfaction Problem (CSP)
#timecounter(2)

#definition("Constraint Satisfaction Problem")[
  Given:
  - *Variables*: $bold(x) = {x_1, x_2, dots, x_n}$ with finite domains $D_i$
  - *Constraints*: $C_1, C_2, dots, C_m$ (relations over subsets of variables)
  - *Objective*: Find assignment satisfying all constraints (or optimize some function)
]

== Examples of CSP
#grid(columns: 2, gutter: 30pt,
align(top)[
  *Example: Graph Coloring*
  
  #figure(canvas({
    import draw: *
    let nodes = ((0, (0,0)), (1, (1.5,0)), (2, (0.75,1.3)))
    for (i, pos) in nodes {
      circle(pos, radius: 0.3, name: str(i))
      content(pos, text(12pt)[$v_#i$])
    }
    line("0", "1")
    line("1", "2")
    line("2", "0")
  }))
  
  - *Variables*: $v_0, v_1, v_2$
  - *Domain*: Each $v_i in {R, G, B}$
  - *Constraints*: Adjacent vertices $!=$ same color
  - *Objective*: Find valid coloring
],
align(top)[
  *Example: Maximum Independent Set*
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
  
  - *Variables*: $x_i in {0, 1}$ (in set or not)
  - *Constraints*: $x_i + x_j <= 1$ if edge $(i,j)$
  - *Objective*: *Maximize* $sum_i x_i$
])

#align(center, box(stroke: black, inset: 10pt)[
  Naive search: $|D|^n$ possibilities. *Can we do better?*

  *Key insight*: Constraint $ arrow.r.double$ reduces search space
])

== My favorite example @Fomin2006
#slide[
#canvas(length: 0.71cm, {
  import draw: *
  let scircle(loc, radius, name) = {
    circle((loc.at(0)-0.1, loc.at(1)-0.1), radius: radius, fill:black)
    circle(loc, radius: radius, stroke:black, name: name, fill:white)
  }
  let s = 1.5
  let dy = 3.0
  let la = (-s, 0)
  let lb = (0, s)
  let lc = (0, 0)
  let ld = (s, 0)
  let le = (s, s)
  scircle((0, 0), (3, 2), "branch")
  for (l, n) in ((la, "a"), (lb, "b"), (lc, "c"), (ld, "d"), (le, "e")){
    circle((l.at(0), l.at(1)-s/2), radius:0.4, name: n, stroke: if n == "a" {red} else {black})
    content((l.at(0), l.at(1)-s/2), text(14pt)[$#n$])
  }
  for (a, b) in (("a", "b"), ("b", "c"), ("c", "d"), ("d", "e"), ("b", "d")){
    line(a, b)
  }
  scircle((-4, -dy), (2, 1.5), "brancha")
  for (l, n) in ((lc, "c"), (ld, "d"), (le, "e")){
    let loc = (l.at(0)-5, l.at(1)-s/2-dy)
    circle(loc, radius:0.4, name: n, stroke: if n == "c" {red} else {black})
    content(loc, text(14pt)[$#n$])
  }
  for (a, b) in (("c", "d"), ("d", "e"), ("c", "d")){
    line(a, b)
  }
  scircle((4, -dy), (1, 1), "branchb")
  circle((4, -dy), radius:0.4, name: "e", stroke: red)
  content((4, -dy), text(14pt)[$e$])
  scircle((-6, -2*dy), (1, 1), "branchaa")
  circle((-6, -2*dy), radius:0.4, name: "e", stroke: red)
  content((-6, -2*dy), text(14pt)[$e$])
  scircle((-2, -2*dy), (0.5, 0.5), "branchab")
  scircle((4, -2*dy), (0.5, 0.5), "branchba")
  scircle((-6, -3*dy), (0.5, 0.5), "branchaaa")
  line("branch", "brancha")
  line("branch", "branchb")
  line("brancha", "branchaa")
  line("brancha", "branchab")
  line("branchb", "branchba")
  line("branchaa", "branchaaa")
  content((-5, -dy/2+0.5), text(12pt)[$G \\ N[a]$])
  content((3.5, -dy/2), text(12pt)[$G \\ N[b]$])
  content((-6.8, -3*dy/2), text(12pt)[$G \\ N[c]$])
  content((-1.5, -3*dy/2-0.4), text(12pt)[$G \\ N[d]$])
  content((-4.8, -5*dy/2-0.4), text(12pt)[$G \\ N[e]$])
  content((5.2, -3*dy/2-0.4), text(12pt)[$G \\ N[e]$])
})
- Time complexity: $gamma^(|V|)$
- MIS size: $alpha(G) = 3$
][
#timecounter(3)
Step 1. Select a vertex, e.g. $a$
  - Case 1: $a$ is in the independent set, then create a branch $G \\ N[a]$
  - Case 2: $a$ is not in the independent set, then create a branch with $b$ selected, $G \\ N[b]$

#pause
#box(stroke: black, inset: 10pt, [Branching factor: $gamma approx 1.27$, from $gamma^(|V|) = gamma^(|V|-2) + gamma^(|V|-4)$])

#pause
Step 2. Solve two subproblems recursively
$
  alpha(G) = max(alpha(G \\ N[a]) + 1, alpha(G \\ N[b]) + 1)
$
]


== Why Branching? The Power of Divide-and-Conquer

#slide[
*Branching*: Recursively split problem into independent subproblems

#figure(canvas(length: 1cm, {
  import draw: *
  mixmode_tree()
}))
Key assumption: $T(rho) = O(gamma^rho)$, $rho$ is the *problem size measure* (e.g., \# variables)
][
#timecounter(2)
1. At each node, branch into $k$ subproblems with size reductions $Delta rho_1, dots, Delta rho_k$
2. Recurse, with time determined by: 
  $
  T(rho) = sum_(i=1)^k T(rho - Delta rho_i),
  $
  $
  1 = sum_(i=1)^k gamma^(-Delta rho_i)
  $
  Solve $gamma$: branching factor

*Objective*: reduce $gamma$, i.e. less branches, more problem size reduction.
]

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

== Traditional branching: Rule-based
#timecounter(1)

#align(center, grid(columns: 3, gutter: 20pt,
align(top, [1. Design a rule table]), align(top, [2. Pattern matching]), align(top, [3. Pattern $arrow.r$ which rule]),
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

- _Remark_: Each rule is associated with a branching factor $gamma$. The overall complexity is upper bounded by the maximum branching factor in the rule table.
- _Remark_: The table of rules is *problem-specific*.

== Branching - a problem agnostic, generic principle
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
// 1. Get an *oracle* over a subset of _variables_, representing the decisions that may leads to the best solution.
// 2. Make _decisions_ over some _variables_, go to step 1 if any _variable_ left.
// 3. An _ending_ is observed, *time travel* to a previous scene and change some decisions until no more potential good endings to be explored.
#canvas(length: 25pt, {
  import draw: *
  main-diagram()
})
]
))



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

== Exercises
#timecounter(2)

#let colred(x) = text(fill: red, $#x$)
- $"oracle"(a, b, c, d) = {101colred(0), 100colred(0), 010colred(0)}$

  Optimal branching: $not d$, removing one variable for free!

  $ gamma^n = gamma^(n-1) arrow.r gamma = 1$

- $"oracle"(a, b, c, d, e) = {colred(1111)1, colred(0000)0, colred(1111)0, colred(0000)1}$

  Optimal branching: $(a and b and c and d) or (not a and not b and not c and not d)$.

  $ gamma^n = 2 gamma^(n-4) arrow.r gamma approx 1.19$

- $"oracle"(a, b, c, d) = {1000, 0100, 0010, 0001}$

  Optimal branching: $(not a) or (a and not b and not c and not d)$.


==
#figure(image("images/ob_new.svg", width: 400pt))

== Bruteforce is infeasible
#timecounter(1)
#align(center, box(stroke: black, inset: 10pt)[Q: How to find the "best" (smallest $gamma$) strategy from the bit strings?])

The number of $n$-variable DNF formulas:

$
&"# of clauses" &=& 3^n \
&"# of combinations of clauses (DNF)" &=& 2^(3^n)\
$

#align(left, box(text(14pt)[
$2^(3^3) = 134217728$\
$2^(3^4) = 2417851639229258349412352$\
$2^(3^5) = 14134776518227074636666380005943348126619871175004951664972849610340958208$\
$2^(3^6)= 2824013958708217496949108842204627863351353911851577524683401930862693830361198499905873920995\
229996970897865498283996578123296865878390947626553088486946106430796091482716120572632072492703527\
723757359478834530365734912\
dots.v$
], stroke: black, inset: 10pt))

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

== History: the branching algorithms for MIS

#let hd(name) = table.cell(text(10pt)[#name], fill: green.lighten(50%))
#let s(name) = table.cell(text(10pt)[#name])
#slide(table(
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
#timecounter(1)

- Independent set: is a set of vertices in a graph, no two of which are adjacent.
- MIS: the maximum independent set

#align(center, box([Finding MIS is NP-complete - unlikely to be solved in time polynomial to the input size @Karp1972.], stroke: black, inset: 10pt))

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


#grid([
#pad(canvas({
  import draw: *
  formin()
  content((0.5, -2), [$G = (V, E)$])
}), x:20pt)
],
[
  - 0 for not in the set
  - 1 for in the set
],
columns: 2, gutter: 30pt
)
])

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
== A bottleneck case in an expert designed 3-MIS branching
#timecounter(1)

A bottle neck case has been reported in @Xiao2013, with $gamma = 1.0836$.

#grid(columns: 3,
  image("images/bottleneck.svg", width: 300pt),
  h(30pt),
  align(horizon, text(20pt, black)[
    - 21 variables.
    - 71 items in oracle, 15782 candidate clauses. 
    // - The optimal branching rule can be solved in few seconds.
    - Result: 4 branches, size of the problem reduced by branches: $[10, 16, 26, 26]$, with 
    *$ gamma = 1.0817 < 1.0836 $* (solved in 1s)
  ]),
)


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

== We can generate branching rules by need!
#timecounter(1)
#align(center, grid(columns: 3, gutter: 25pt,
align(center, [1. Check a sub-graph]),
align(center, [2. Obtain an oracle]),
align(center, [3. Generate a rule (optimally)]),
align(center+top, text(11pt)[#canvas(length: 0.5cm, demograph((white, white, white, white, white), fontsize: 12pt))]),
align(left+top, text(16pt)[
- 00001 (or 00010)
- 00101
- 01010
- 11100
]),
align(center + top, text(80pt)[\u{1F4CF}])
))

=== Advantages
- No need to manually design rules
- No need to pick rules.
- Fully utlize the information of the sub-graph

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

== On-the-fly branching - No rule is better than any rule
#timecounter(3)

#grid(columns: 2, gutter: 0pt,
image("images/fig5.svg", width: 350pt), [
  - Metric: number of branches
  - Methods:
    - `A + B`: branching rule + reduction rule
    - #text(red)[`ob`]: optimal branching (this work)
    - #text(green)[`xiao2013`]: SOTA 3-MIS
    - #text(blue)[`akiba2015`]: PACE winner
  #v(20pt)
  - Same reduction rules $arrow.r$ #text(red)[`ob`] has the minimum number of branches in all cases.
  - 3-MIS $arrow.r$ #text(red)[`ob`] has the smallest average complexity $O(1.0455^n)$.
  
// #align(bottom, [Remark: The LP relaxation renders close-to-optimal branching rules.
// However, it is not needed. The computational cost if MILP is much lower than expected: e.g. problems with $10^4$ variables can be solved in few seconds.
// ])
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


= Application 1: B&B tensor networks for MIS

== Tensor network for combinatorial optimization
- Tensor networks with *tropical algebra* can be used for solving CSP @Liu2021@Liu2023
- Due to hard constraints and bounding, *sparsity* emerged in the tensor network contraction: only a small subset of configurations are needed to be considered.
- The sparsity helps a lot! but still *not surpass* branching. 😞
- New understanding: direct use of sparsity is not the most efficient.

== Branching and Bound Tensor Network (BBTN)

#slide[
#figure(image("images/bbtn.svg", width: 380pt))
][
  - *Key*: Use branching and bound to cut the originally intractable large scale problem into multiple smaller nets.
  - *Trick*: Use the right *measure*! Use the tree-width of a tensor network, which measures the contraction complexity.

  (Left) *Slicing*, which "branch" on one variable at a time.

  (Right) BBTN can be viewed as *non-uniform* version of *slicing*, which more effectively reduce the tree-width.
]

== Time complexity v.s. space complexity
#slide[
    #image("images/ksg_60x60_tc_s1.svg", width: 100%)][
#timecounter(1)
  - Dynamic slicing: time complexity grows with slice size.
  - TNBB (OB based method): both time and space complexity reduces.
]


== Performance comparison
#timecounter(2)
#figure(image("images/time_complexity.svg", width: 70%))

#let namebox(src, name) = box(align(center, [#image(src, width:60pt, height:80pt)#v(-10pt)#name]))
#align(center,[
#namebox("images/yijiawang.png", "Yijia Wang (IOTP)")#h(20pt)
#namebox("images/xuanzhao.png", "Xuanzhao Gao (HKUST)")
])

// ==
// #figure(image("images/tc_different_target.svg", width: 50%))

// ==
// #figure(image("images/compare_nu_u.svg", width: 50%))

= Application 2: Circuit SAT problems

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

== Circuit SAT problems
#timecounter(1)

#place(bottom + right, align(center, [
  #image("images/zhongyi.jpg", width: 50pt, height: 70pt) #text(14pt, [Zhong-Yi Ni])
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
  multiplier(5, 5, size: 1.0)
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
  content((5, 0), text(14pt)[$2c_o + s_o = p_i q_i + c_i + s_i$])

  let gate(loc, label, size: 1, name:none) = {
    rect((loc.at(0) - size/2, loc.at(1) - size/2), (loc.at(0) + size/2, loc.at(1) + size/2), stroke: black, fill: white, name: name)
    content(loc, text(14pt)[$label$])
  }
  set-origin((-1.5, -3))
  line((4.5, 0), (-1, 0))  // q
  line((3, 1), (3, -4.5))  // p
  let si = (-1, 1)
  let ci = (4.5, -2.5)
  gate((0.5, -0.5), [$and$], size: 0.5, name: "a1")
  gate((2.5, -0.5), [$and$], size: 0.5, name: "a2")
  gate((2.0, -2.5), [$and$], size: 0.5, name: "a3")
  gate((0.5, -2.5), [$or$], size: 0.5, name: "o1")
  gate((1.5, -1.5), [$xor$], size: 0.5, name: "x1")
  gate((3.5, -3.5), [$xor$], size: 0.5, name: "x2")
  line("a2", (2.5, 0))
  line("x1", (1.5, -0.5))
  line("a2", (3, -0.5))
  line("a2", "a1")
  line("a1", "o1")
  line("a3", "o1")
  line("o1", (rel: (-1.5, 0), to: "o1"))
  line(si, "a1")
  line(ci, "a3")
  line((3.5, -2.5), "x2")
  let turn = (1.5, -3.5)
  line("x1",(rel: (0.5, -2.5), to: si), (rel: (0.5, -0.5), to: si))
  line("x1", turn, "x2")
  line("x2", (rel: (1, -1), to: "x2"))
  line("a3", (2.0, -0.5))
  rect((-0.75, -4), (4, 0.75), stroke: (dash: "dashed"))

  let gate_with_leg(loc, label, size: 1, name:none) = {
    gate(loc, label, size: size, name: name)
    line(name, (rel: (0.5, 0), to: name))
    line(name, (rel: (-0.5, 0), to: name))
    line(name, (rel: (0, 0.5), to: name))
  }
  gate_with_leg((6, 0), [$xor$], size: 0.5, name: "x3")
  content((8, 0), text(14pt)[$= mat(mat(0, 1; 1, 0); mat(1, 0; 0, 1))$])

  gate_with_leg((6, -2), [$or$], size: 0.5, name: "o3")
  content((8, -2), text(14pt)[$= mat(mat(1, 0; 0, 0); mat(0, 1; 1, 1))$])

  gate_with_leg((6, -4), [$and$], size: 0.5, name: "a4")
  content((8, -4), text(14pt)[$= mat(mat(1, 1; 1, 0); mat(0, 0; 0, 1))$])
})
]
)

== The 2-SAT Reduction Strategy
#timecounter(2)

*Observation*: After branching and unit propagation, many clauses become:
- Unit clauses (directly fixed by propagation)
- Binary clauses (2-SAT, solvable in linear time!)
- Larger clauses (still need branching)

#definition("Measure: Number of Non-2-SAT Clauses")[
  Define the measure $rho$ as the number of clauses with $>=3$ literals:
  $ rho(F) = |{c in F : |c| >= 3}| $
  
  A problem with $rho = 0$ is a 2-SAT problem, solvable in $O(n)$ time.
]

*Goal*: Design branching rules that maximize the reduction of $rho$, not just the number of variables.

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

#slide[
*Algorithm*:
1. Select a region of variables (e.g., variables in nearby gates)
2. Contract tensor network to get oracle $cal(S)$
3. Find optimal branching rule minimizing $gamma$:
   $ 1 = sum_(i) gamma^(-Delta rho(c_i)) $
   where $Delta rho(c_i)$ is the reduction in non-2-SAT clauses after branch $c_i$
4. Apply best branch, propagate, recurse
][
#timecounter(2)
  #box(stroke: black, inset: 10pt, fill: yellow.lighten(80%))[
    *Key difference from MIS*: Measure is clause-based, not variable-based.
    This exploits the cascading effect of unit propagation.
  ]
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

== Talk is cheap, show me the code
#timecounter(1)

#align(center, grid(columns: 1, gutter: 10pt, image("images/ob-logo.svg", width: 300pt), 
[Source code available on GitHub:
#link("https://github.com/OptimalBranching/OptimalBranching.jl")[OptimalBranching/OptimalBranching.jl].
]))

#align(center, grid(columns:2, gutter:20pt,image("images/barcode.png", width: 180pt)))

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

== Advanced materials thrust \u{2665} AI
#timecounter(1)
//#place(box(width: 200%, height: 200%, stroke: none, fill: white.transparentize(0%)), dx: -100pt, dy: -250pt)
#grid(image("images/AMAT_Logo_Gold-Blue.png", width: 300pt), text(16pt)[Enablers for technological innovation in *new materials*, *new energy*, *sustainable environment* and *biomedical devices*], columns: 2, gutter: 20pt)

#align(center, grid(columns: 2, gutter: 20pt,
image("images/2025-01-13-09-19-10.png", height: 150pt),
image("images/2025-01-13-09-26-32.png", height: 150pt)))

Yummy food, world class gym, swimming pool and nice colleagues!

== Thank you!
#timecounter(1)
#box(stroke: white, inset: 20pt, width: 100%, fill: color.mix(blue.lighten(50%), yellow), [
#align(center, [*arXiv.2412.07685* - Optimal classical structured search])
Automated Discovery of Branching Rules with Optimal Complexity for the Maximum Independent Set Problem, _Xuanzhao Gao, Yijia Wang, Pan Zhang and Jinguo Liu_
])
#v(20pt)
#align(left, grid(
image("images/xuanzhao.png", width:50pt, height:60pt), [Xuanzhao Gao],
image("images/yijiawang.png", width:50pt, height:60pt), [Yijia Wang],
image("images/panzhang.png", width:50pt, height: 60pt), [Pan Zhang],
image("images/fengpan.png", width:50pt, height: 60pt), [Feng Pan],
image("images/zhongyi.jpg", width:50pt, height: 60pt), [Zhong-Yi Ni],
image("images/zhongyi.jpg", width:50pt, height: 60pt), [Xi-Wei Pan],
columns: 6, column-gutter: 20pt, row-gutter: 10pt))

TODO: update avatar (xiwei)

== References
#bibliography("refs.bib", title: none)