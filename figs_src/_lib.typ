// =============================================================
//  figs_src/_lib.typ  --  shared helpers for paper figures
//  Files starting with "_" are includes only: the Makefile skips
//  them, so they never produce a standalone PDF.
//  Import with:   #import "_lib.typ": *
// =============================================================

// ---- Canonical widths (A4 two-column article) ---------------
#let single-column = 85mm
#let double-column = 170mm

// ---- Page scaffold ------------------------------------------
// Fixed-size, zero-margin, opaque white canvas so the PDF bounding
// box equals the panel box. LaTeX then includes it 1:1.
#let paper-figure(
  width: single-column,
  height: auto,
  margin: 0pt,
  font: auto,
  size: 8pt,
  body,
) = {
  set page(width: width, height: height, margin: margin, fill: white)
  if font != auto {
    set text(font: font, size: size)
  } else {
    set text(size: size)
  }
  set par(leading: 0.62em, justify: false)
  body
}

// ---- Panel label + content ----------------------------------
//   #panel[(a) Schematic cross-section][ #image(...) ]
#let panel(label, size: 8pt, gap: 1.2mm, body) = {
  block(width: 100%, {
    text(weight: "bold", size: size)[#label]
    v(gap)
    body
  })
}

// ---- In-figure annotation -----------------------------------
// Absolute placement relative to the enclosing block.
//   #annot(dx: 42%, dy: 30%)[ScAlN 30%]
#let annot(dx: 0pt, dy: 0pt, align: left + top, size: 7pt, body) = {
  place(align, dx: dx, dy: dy, text(size: size, body))
}

// ---- Simple scale bar ---------------------------------------
//   #scalebar(10mm, "10 mm")
#let scalebar(len, label, thickness: 0.7pt) = {
  block(width: len, height: 1.6em, {
    place(bottom, line(length: len, stroke: thickness))
    place(center + top, text(size: 6.5pt, label))
  })
}

// ---- Multi-panel grid ---------------------------------------
//   #panels(columns: 2, gutter: 3mm)[(a)...][(b)...]
#let panels(columns: 1, gutter: 3mm, ..bodies) = {
  grid(columns: (1fr,) * columns, gutter: gutter, ..bodies.pos())
}
