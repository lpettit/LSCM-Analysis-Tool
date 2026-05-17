# Module 2 Testing: Inclusive Inter-Mound Cavity Rework

Related finalized doc: [Module2_CavityAnalysis.md](../../Module2_CavityAnalysis.md)

Relevant history and planning:

- [LSCM_Project_Plans.md](../../../LSCM_Project_Plans.md)

## Promotion Status
`testing`

## Feature Under Test
Inclusive inter-mound cavity detection and measurement for boiling-oriented cavity geometry.

This rework replaces the old assumption that final cavity identity should come directly from global watershed basins seeded by all local minima. The new target object is a physically meaningful depression created by the mound field, even when that depression spans multiple neighboring Delaunay triangles.

## Current Hypothesis Or Intended Behavior
The working hypothesis is that cavity identity should come from mound-defined inter-mound neighborhoods first, then be refined by topography.

The intended behavior is:

- Delaunay triangles from mound centroids define candidate inter-mound neighborhoods
- each candidate neighborhood should contain at most one dominant provisional depression
- neighboring triangle candidates can merge if they clearly support the same physical pit
- shallow roughness minima inside a broader depression should not become separate cavities
- final cavity geometry should come from the accepted merged cavity object, not from raw triangle boundaries

## Current Algorithm Or Workflow
1. Build candidate inter-mound neighborhoods from a border-aware Delaunay triangulation.
2. Search each triangle neighborhood for a dominant depression floor on a lightly smoothed surface, with smoothing scaled to representative mound spacing rather than using a fixed pixel sigma.
3. Score each triangle candidate by a local significance / persistence-style height span between the floor and the first escape saddle or rim proxy.
4. Reject triangle candidates with insufficient significance.
5. Merge adjacent triangle candidates when they share the same depression signal.
6. Within each merged support region, detect raw minima and consolidate weak minima using local saddle relief so roughness-scale sub-minima can be swallowed before mouth selection.
7. Build a contour-height history for each surviving minimum and compare two mouth-definition paths:
   - highest admissible contour
   - stability-plateau top contour with stricter multi-level stability checks on area, equivalent radius, aspect ratio, contact fraction, and solidity
8. Select contour levels on the smoothed topology, then rebuild the final accepted mouth mask on raw `Z` within the local support region before reporting geometry.
9. Measure:
   - robust floor height
   - mouth height from both comparison methods
   - true mouth area
   - equivalent mouth radius / diameter
   - inscribed mouth radius
   - effective cone half-angle
10. Classify each cavity by support type, enclosure type, and quality flags.

## Temporary Assumptions And Open Decisions
- Default mode is inclusive rather than conservative.
- Broad pits spanning multiple triangles should merge unless a meaningful saddle separates them.
- Triangle candidates are only proposal regions and are not final cavity boundaries.
- Border handling now follows the Module 3 augmented-seed logic so added edge seeds can produce more realistic triangles near the image boundary.
- Height-map smoothing is now spacing-scaled; the current default target is approximately `0.08 * representative_spacing_px`.
- Candidate significance is a secondary filter for roughness suppression, not the primary definition of cavity identity.
- Semi-open depressions can remain in the accepted cavity set, but should be flagged distinctly from better-enclosed pockets.
- Mouth detection is still under review and may need refinement if contour stability is poor on representative surfaces.
- Candidate topology is still found on the smoothed surface, but the selected final contour is now rebuilt on raw `Z` before cavity geometry is reported.

## Outputs And Figures Being Reviewed
Primary provisional outputs under review:

- cavity significance / persistence-like height span
- independent relief of consolidated minima
- raw-minima count and surviving-minima count per merged support region
- number of supporting triangles per final cavity
- supporting triangle index list
- highest-admissible mouth metrics
- plateau-top mouth metrics
- equivalent mouth radius / diameter from true area
- inscribed mouth radius as a separate conservative metric
- cavity enclosure and support-type classification
- quality flags for reflection sensitivity and weak mouth / cone fits

Diagnostic figures under review:

- triangle candidate overlay
- merged-cavity support overlay
- mouth contour overlay on accepted cavities
- highest-valid-only mouth overlay
- plateau-top-only mouth overlay
- method-difference-only overlay for cavities where the two mouth definitions diverge
- significance / merge diagnostic views

## Promotion Criteria
Before promotion to the finalized Module 2 methodology, the following should be true:

- cavity counts are stable across representative surfaces
- broad shared pits are not split into duplicate cavities
- triangles without real depressions drop out cleanly
- corrugated cavity floors do not create multiple false cavity records
- mouth area, equivalent diameter, and inscribed radius semantics are internally consistent
- the two mouth-definition methods diverge only where there is a defensible contour-stability reason, not because of plotting ambiguity
- accepted cavity geometries look physically defensible for boiling-oriented inter-mound cavities
- explicit user approval is given for finalization

## Unresolved Risks Or Competing Options
- Open trough handling may still be too inclusive or not inclusive enough.
- Merge thresholds may need tuning relative to mound spacing.
- Rim / mouth contour detection may become unstable on very irregular cavities.
- Reflection correction could still influence candidate floor placement in difficult pits.
- The final cavity geometry remains an effective surface-accessible model; undercut or re-entrant hidden geometry cannot be recovered from LSCM topography alone.
- The stricter plateau criteria may still collapse to the highest-admissible contour on many surfaces if contour growth remains smooth to the top admissible level.

## Review Notes
- This document is the provisional home for the inter-mound cavity rework.
- Do not move this content into the finalized Module 2 doc until the rework is reviewed and explicitly approved for finalization.
- Current isolated change under review: border-aware triangulation using Module 3-style border-inclusive seed detection before Delaunay construction.
- Current isolated change under review: spacing-scaled cavity smoothing using representative mound spacing instead of a fixed Gaussian sigma.
- Current isolated change under review: stricter plateau-top mouth selection plus a difference-only comparison overlay and saved method-divergence summary metrics.
- Current isolated change under review: raw-`Z` refinement of the final selected mouth contour after contour-level selection on the smoothed topology.
