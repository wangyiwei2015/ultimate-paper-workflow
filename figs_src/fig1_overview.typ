// =============================================================
//  fig1_overview.typ  --  single-panel example
//  Build:  make figs   ->   figs_output/fig1_overview.pdf
//  Include in LaTeX:  \includegraphics{figs_output/fig1_overview}
// -------------------------------------------------------------
//  Rule of this pipeline:
//    MATLAB  = data only (bare SVG, no text)
//    Typst   = composition (panels, (a)/(b) labels, annotations,
//              scale bars, arrows) -- all in one shared typeface
//    LaTeX   = only \includegraphics + caption
// =============================================================

#import "_lib.typ": *

#show: doc => paper-figure(width: single-column, doc)

#panel[(a) Device overview][
  #image("../matlab/svg_out/fig1_overview.svg", width: 100%)

  // In-figure annotation, positioned relative to this block
  // #annot(dx: 55%, dy: 20%)[30% Sc-AlN]
]

// -------------------------------------------------------------
//  Two-panel variant (copy this pattern for multi-panel figures):
//
//  #show: doc => paper-figure(width: double-column, doc)
//  #panels(columns: 2, gutter: 4mm)[
//    #panel[(a) Cross-section][ #image("../matlab/svg_out/fig1_overview.svg", width: 100%) ]
//  ][
//    #panel[(b) Frequency response][ #image("../matlab/svg_out/fig2_response.svg", width: 100%) ]
//  ]
// -------------------------------------------------------------
