#import "@preview/touying:0.6.1": *
#import "@preview/touying-simpl-hkustgz:0.1.2": *
#import "@preview/cetz:0.4.0": canvas, draw, tree
#import "@preview/cetz-plot:0.1.2": plot

#set page(width: auto, height: auto, margin: 5pt)

#let variable(a, token, radius: 0.1, fontsize: 12pt) = {
  import draw: *
  let color = if token < 0 {red} else {white}
  circle((a.at(0), a.at(1)), radius: radius, fill:color)
  if calc.abs(token) == 1 {
    content(a, text(fontsize)[$1$])
  } else if calc.abs(token) == 2 {
    content(a, text(fontsize)[$0$])
  } else if calc.abs(token) == 0 {
    content(a, text(fontsize)[])
  }
}

#let tensor(a, token, radius: 0.1, fontsize: 12pt) = {
  import draw: *
  let color = if token < 0 {red} else {white}
  rect((a.at(0) - radius, a.at(1) - radius), (a.at(0) + radius, a.at(1) + radius), radius: 0pt, fill:color)
  if calc.abs(token) == 1 {
    content(a, text(fontsize)[$1$])
  } else if calc.abs(token) == 2 {
    content(a, text(fontsize)[$0$])
  } else if calc.abs(token) == 0 {
    content(a, text(fontsize)[])
  }
}

#let decision(a, token, size: 1, fontsize) = {
  import draw: *
  let color = if token < 0 {red} else {white}
  rect((a.at(0) - size / 2, a.at(1) - size / 2), (a.at(0) + size / 2, a.at(1) + size / 2), radius: 1pt, fill:color)
  if calc.abs(token) == 1 {
    content(a, text(fontsize)[$1$])
  } else if calc.abs(token) == 2 {
    content(a, text(fontsize)[$0$])
  } else if calc.abs(token) == 0 {
    content(a, text(fontsize)[])
  }
}
#let decision_sequence(a, tokens, size: 1, fontsize: 8pt) = {
  import draw: *
  for (k, token) in tokens.enumerate() {
    decision((a.at(0) + k * size, a.at(1)), token, size: size, fontsize)
  }
}

#let problem(region) ={
  import draw: *
  let a = (0.6, 0)
  let b = (0.6, -1)
  let and_abg1 = (1.2, -0.5)
  let g1 = (2, -0.5)
  let d = (2, -1.3)
  let or_g1dg3 = (2.7, -0.9)
  let g3 = (3.3, -0.9)
  let c = (0.6,-2)
  let xor_bcg2 = (1.2, -1.5)
  let g2 = (2, -2)
  let e = (2, -2.7)
  let nand_g2eg4 = (2.7, -2.4)
  let g4 = (3.3, -2.4)
  let out = (4.6, -1.6)
  let and_g3g4out = (3.9, -1.6)

  if region == 1 {
    rect((a.at(0) - 0.2, a.at(1) + 0.2), (g1.at(0) -0.1, g1.at(1) - 0.7), fill: teal.transparentize(50%), stroke: none)
    rect((g1.at(0) - 0.1, g1.at(1) + 0.2), (g3.at(0) + 0.1, g3.at(1) - 0.6), fill: teal.transparentize(50%), stroke: none)
  }

  line(a, and_abg1)
  line(b, and_abg1)
  line(g1, and_abg1)

  line(d, or_g1dg3)
  line(g1, or_g1dg3)
  line(g3, or_g1dg3)

  line(c, xor_bcg2)
  line(b, xor_bcg2)
  line(g2, xor_bcg2)

  line(e, nand_g2eg4)
  line(g2, nand_g2eg4)
  line(g4, nand_g2eg4)

  line(out, and_g3g4out)
  line(g3, and_g3g4out)
  line(g4, and_g3g4out)

  variable(a, -3)
  variable(b, -3)
  variable(g1, -3)
  tensor(and_abg1, 0)

  tensor(or_g1dg3, 0)
  variable(d, -3)
  variable(g3, -3)

  variable(c, 0)
  tensor(xor_bcg2, 0)
  variable(g2, 0)

  variable(e, 0)
  tensor(nand_g2eg4, 0)
  variable(g4, 0)

  variable(out, 0)
  tensor(and_g3g4out, 0)
} 


#canvas({
  import draw: *

  content((2.3,0.95), text(10pt)[(a) select a local region])
  content((7.2,0.7), text(10pt)[(b) contraction &\ configuration enumeration])
  content((12.5,0.95), text(10pt)[(c) Get & Apply optimal branching rule])


  group({
    scale(0.9)
    translate((0.4,0))
    problem(1)
  })

  content((2.6,-3.3), text(8pt)[Factor graph\ Circles: variables\ Rectangles: tensors (constraints)])

  line((4.8,-1.4), (5.3,-1.4),mark: (end: "straight"))

  let LUT = (6,-1.4)
  let var1 = (6, -0.7)
  let var2 = (5.5, -2.1)
  let var3 = (6.5, -2.1)
  let var4 = (6.7, -1.4)
  rect((var1.at(0)-0.7, var1.at(1)+0.2), (var4.at(0)+0.2, var3.at(1)-0.2), fill: teal.transparentize(50%), stroke: none)
  line(LUT, var1)
  line(LUT, var2)
  line(LUT, var3)
  line(LUT, var4)
  line(var1, (var1.at(0), var1.at(1)+0.5), stroke:(dash:"dashed"))
  line(var3, (var3.at(0)+0.4, var3.at(1)-0.4), stroke:(dash:"dashed"))
  tensor(LUT, 0, radius: 0.13)
  variable(var1, -3)
  variable(var2, -3)
  variable(var3, -3)
  variable(var4, -3)

  line((7,-1.4), (7.5,-1.4), mark: (end: "straight"))

  decision_sequence((7.8,-0), (2,2,2,2), size: 0.3)
  decision_sequence((7.8,-0.35), (2,2,2,1), size: 0.3)
  decision_sequence((7.8,-0.7), (2,2,1,2), size: 0.3)
  decision_sequence((7.8,-1.05), (2,2,1,1), size: 0.3)
  decision_sequence((7.8,-1.4), (1,2,2,2), size: 0.3)
  decision_sequence((7.8,-1.75), (1,2,2,1), size: 0.3)
  decision_sequence((7.8,-2.1), (1,2,1,2), size: 0.3)
  decision_sequence((7.8,-2.45), (1,1,1,1), size: 0.3)

  content((8.2,-3.1), text(size:8pt)[Feasible\ Configurations])
 
  line((9,-1.4), (9.5,-1.4), mark: (end: "straight"))

  rect((9.7,0), (11,-2.5), fill: gray.transparentize(50%), stroke: (dash: "dashed", paint: black))
  content((9.75,-0.9), (11,-2.5), text(size: 8pt)[Optimal Branching])

  line((11.2,-0.7), (11.7,-0.4), mark: (end: "straight"))
  line((11.2,-1.7), (11.7,-2), mark: (end: "straight"))

  decision_sequence((12,-0.4), (-3,2,2,-3), size: 0.3)
  content((12.4,-0.05), text(8pt)[Branch Case 1])
  decision_sequence((12,-2), (-3,-3,1,-3), size: 0.3)
  content((12.4,-1.63), text(8pt)[Branch Case 2])

  line((13.2,-0.4), (13.7,-0.4), mark: (end: "straight"))
  line((13.2,-2), (13.7,-2), mark: (end: "straight"))

  content((14.6,-0.4), text(8pt)[Propagate &\ sub-problem])
  content((14.6,-2), text(8pt)[Propagate &\ sub-problem])
})