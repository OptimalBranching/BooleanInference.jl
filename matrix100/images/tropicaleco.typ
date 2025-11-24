#import "@preview/cetz:0.4.1": canvas, draw, tree
#set page(width: auto, height: auto, margin: 5pt)

#let boxed(it, width: 100pt, height: 18pt, fill: white) = box(stroke: black, inset: 5pt, fill: fill, width: width, height: height, align(center + horizon)[#it])

#figure(canvas({
  import draw: *
  content((0, 0), boxed[(Cu)TropicalGEMM])
  content((-2, 0.8), boxed[OMEinsum])
  content((-4, 0), boxed(text(7pt)[OMEinsumContractionOrders]))
  content((0, -0.8), boxed[TropicalNumbers])
  content((4, 1), boxed[OptimalBranching], name: "ob")
  content((1, 2.5), boxed(fill: yellow, [TensorBranching]), name: "tb")
  content((-4, 2.0), boxed(text(8pt)[GenericTensorNetworks]), name: "gtn")
  rect((-5.9, -1.3), (1.9, 1.3), stroke: (dash: "dashed"), name: "tropicaltn")
  content((rel: (0, -0.5), to: "tropicaltn.south"), [热带张量网络生态])
  line("tropicaltn", "tb", mark: (end: "straight"))
  line("ob", "tb", mark: (end: "straight"))
  line("tropicaltn", "gtn", mark: (end: "straight"))
}))
