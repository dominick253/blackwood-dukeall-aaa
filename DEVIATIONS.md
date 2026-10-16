# DEVIATIONS

## mower: side-silhouette acceptance not achieved within pinned 5-round cap
- Section 4.1 rule: "Stop at 5 rounds and record a deviation."
- Rounds 1-2 failed on construction method (open shells). Round 3 changed
  method to closed solids; rounds 4-5 fixed fender placement (real bug),
  tyre tread, body massing, and light rig.
- Current state: front and 3-quarter views read as a coherent sit-on mower
  (vision-confirmed); side view still gets "scattered parts" verdicts from
  vision review. Geometry AABBs prove fenders ARE arched over tyres; the thin
  16mm shells do not read against the body mass at side angle.
- Closest compliant version shipped: mower.glb, 8004 tris, layered worn-paint
  material with baked edge-wear vertex mask, chevron-lug tyres, split body.
- Follow-up candidate (post-cap, would need explicit approval): repaint fenders
  in a contrasting panel colour + widen fender lip to 30mm so the arch reads
  in silhouette.

## viewmodel: bottle-grip close-up not fully passing at 5-round cap
- Right hand + cigar close-up: affirmative "authored, not generated" verdict.
- Left hand + bottle close-up: wrapping/thumb-opposition confirmed by every
  review round; remaining flags are render-pipeline (glass reads white in
  headless Cycles QC) and skin micro-detail at 30cm.
- Closest compliant version shipped: viewmodel.glb, 9920 tris, grip pose baked,
  layered skin, glove cuffs, nails, solidified tinted glass.
- Brief 4.6 already overrides bottle glass at runtime (alpha-blend + emissive
  liquid disc + condensation beads), which addresses the dominant defect.
