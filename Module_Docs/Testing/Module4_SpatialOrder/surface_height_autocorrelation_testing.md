# Module 4 Testing: Surface-Height Autocorrelation

Related finalized doc: [Module4_SpatialOrder.md](../../Module4_SpatialOrder.md)

Relevant history and planning:

- [SESSION_NOTES_2026-05-02.md](../../../SESSION_NOTES_2026-05-02.md)
- [LSCM_Project_Plans.md](../../../LSCM_Project_Plans.md)

## Promotion Status
`testing`

## Feature Under Test
2D surface-height autocorrelation as a provisional Module 4 addition.

This testing addition is intended to evaluate whether a full-topography autocorrelation workflow adds useful spatial-order information beyond the existing centroid-based metrics such as `psi6`, pair distribution `g(r)`, neighbor-shell spacing, and Voronoi-derived local density.

The feature is not intended to replace the current centroid workflow. It is being tested as a complementary field-level descriptor that works directly from the calibrated height map.

## Current Hypothesis Or Intended Behavior
The current hypothesis is that a 2D autocorrelation map of the surface height field can strengthen spatial-order interpretation by answering a slightly different question than the existing Module 4 metrics.

Existing Module 4 outputs mainly describe how ordered the detected mound centers are as a planar point population. A height-map autocorrelation would instead describe how self-similar the full topography is as a function of lateral shift.

If useful, this should help clarify:

- whether the surface carries a dominant repeat spacing even when centroid detection is imperfect
- whether the topography is isotropic or directionally biased
- whether spatial order is only short-range or persists over larger separations
- whether the full height field tells the same spatial-order story as the centroid-only metrics

The intended behavior is to produce a review-stage radial and directional autocorrelation interpretation layer that can be compared directly against `g(r)`, neighbor-shell regularity, and `psi6`.

## Current Algorithm Or Workflow
Document the current testing logic in workflow order:

1. Start from the calibrated Module 1 height map `Z` rather than from the centroid graph alone.
2. Remove any broad vertical offset or planar trend that would artificially inflate long-range correlation.
3. Mean-center the working surface so the autocorrelation emphasizes fluctuating topographic structure rather than absolute height offset.
4. Compute the 2D normalized autocorrelation surface `ACF(dx,dy)` for lateral shifts across the field of view.
5. Extract a radial average `ACF(r)` so the review can compare decay behavior and repeated-spacing signatures in a compact 1D form.
6. Inspect the central peak width as a candidate correlation-length measure for how quickly local topographic similarity decays with separation.
7. Inspect off-center rings or local maxima as candidate indicators of characteristic mound-spacing or repeated texture scales.
8. Compare directional contour shape or directional line cuts to assess anisotropy and preferred alignment.
9. Compare the resulting signatures against current Module 4 outputs:
   - `first_peak_r_um` from `g(r)`
   - neighbor-shell distance summaries
   - `global_psi6_interior` and `mean_local_psi6_interior`
10. Treat all derived summary scalars as provisional until cross-surface behavior and interpretability are reviewed.

## Temporary Assumptions And Open Decisions
- The exact detrending method is still provisional.
- The preferred normalization is still open because different normalizations change the apparent strength of long-range structure.
- It is still under review whether the canonical interpretation should rely mainly on:
  - the full 2D map
  - the radial average `ACF(r)`
  - a small derived summary set
- Boundary handling is still provisional because finite image size can distort correlation at larger shifts.
- It is still undecided whether autocorrelation belongs scientifically in Module 4 as a spatial-order diagnostic or in Module 3 as a whole-surface morphology descriptor. For testing, it is being treated as a Module 4 addition because the primary question is order and repeat spacing.
- Cross-comparison is still needed to determine whether autocorrelation adds genuinely new interpretation rather than duplicating the practical role of `g(r)`.

## Outputs And Figures Being Reviewed
Provisional review-stage outputs may include:

- `acf2d`
  - normalized 2D autocorrelation map
  - intended to show directional structure, repeating offsets, and overall self-similarity geometry
- `acf_r`
  - radial-average autocorrelation curve
  - intended to show correlation decay and possible repeated-spacing peaks in a compact form
- `acf_correlation_length_um`
  - retained only as a diagnostic/internal summary during testing
  - not currently recommended as a comparison-facing output
- `acf_first_ring_radius_um`
  - retained only as a diagnostic/internal summary during testing
  - not currently recommended as a comparison-facing output
- `acf_anisotropy_ratio`
  - current preferred comparison-facing ACF output
  - intended to summarize whether the surface texture is isotropic or directionally stretched and to compare against Module 3 footprint elongation
- `acf_dominant_orientation_deg`
  - current preferred comparison-facing ACF output
  - intended to support interpretation of process-direction alignment and to compare against Module 3 shape/orientation behavior

Provisional figure families under review:

- `*_acf2d.png`
  - 2D autocorrelation heat map with lateral axes in micrometers
  - intended to reveal central-peak shape, ring structure, and anisotropy
- `*_acf_radial.png`
  - radial-average `ACF(r)` curve
  - intended to reveal decay length and repeated-spacing peaks
- `*_acf_directional_cuts.png`
  - directional line cuts through the 2D autocorrelation map
  - intended to help decide whether any preferred orientation is real or visually misleading
- `*_acf_vs_gr.png`
  - comparison figure between `ACF(r)` and the existing radial-order `g(r)` interpretation
  - intended to determine whether the two methods agree, disagree, or provide different information

## Promotion Criteria
Before promotion into the finalized Module 4 document, the following should be true:

- the autocorrelation workflow gives a scientifically clear answer that is distinct from but complementary to existing Module 4 metrics
- the preferred preprocessing and normalization choices are justified and stable across representative surfaces
- the interpretation of correlation length, ring radius, and anisotropy is consistent enough to be useful in cross-surface comparison
- the 2D and radial figures are readable and not routinely misleading because of boundary artifacts or background trends
- comparison against `g(r)`, neighbor-shell metrics, and `psi6` shows when autocorrelation adds value and when it is redundant
- the proposed public outputs are limited to fields that are physically interpretable and not overly heuristic
- if kept at all, comparison-facing ACF outputs should currently be limited to anisotropy and dominant orientation rather than ring-radius or correlation-length summaries
- explicit user approval is given for finalization

Promotion still requires explicit user approval even if the testing evidence looks strong.

## Unresolved Risks Or Competing Options
- The autocorrelation may be dominated by broad topographic waviness rather than mound-to-mound ordering unless preprocessing is chosen carefully.
- ACF-derived spacing peaks may look precise while actually mixing multiple physical causes such as mound spacing, valley spacing, or scan-scale trends.
- The method may be less directly interpretable than centroid-based metrics because it does not isolate individual mound identities.
- Apparent anisotropy may come from scan artifacts, cropping, or detrending choices rather than real process-direction structure.
- The radial-average ACF may hide meaningful directional information that the full 2D map preserves.
- The full 2D map may be richer scientifically but harder to summarize consistently for routine reporting.
- A competing option is to retain autocorrelation only as a diagnostic figure family and avoid promoting scalar outputs unless they prove robust.
- Another competing option is to test related spectral approaches such as 2D power spectral density if autocorrelation proves too redundant or too sensitive to preprocessing.

## Review Notes
- Initial rationale for testing:
  - Module 4 already has strong centroid-based order descriptors, but none of them operate directly on the full calibrated height field.
  - This addition is being tested to see whether full-topography self-similarity adds useful evidence for repeat spacing, anisotropy, or order persistence.
- Current expected use:
  - supplementary order diagnostic
  - cross-check against `g(r)` and `psi6`
  - possible screening tool when centroid detection quality is uncertain
- Current non-goal:
  - replacing the existing centroid-based Module 4 interpretation stack
- Current outcome from initial testing:
  - the ACF ring-radius output has not yet shown enough robustness or interpretive clarity to justify treating it as a new primary spacing metric
  - comparison against `g(r)` and neighbor-shell spacing suggests the ACF ring is not cleanly measuring the same physical spacing family
  - stronger smoothing changed the ring-radius interpretation substantially, which reinforces that it is currently too filter-sensitive for confident spacing use
- Current useful signal retained:
  - the unsmoothed ACF anisotropy value near `1.5` matched the mean footprint ellipse aspect ratio from Module 3 `analyzeMoundShape`
  - this suggests the ACF may still have value as a field-level confirmation of elongation already measured more directly in Module 3
- Current recommendation:
  - keep ACF in testing
  - treat ring-radius behavior as diagnostic/provisional rather than comparison-ready
  - keep only anisotropy and dominant orientation as comparison-facing ACF outputs because those can be cross-checked directly against Module 3 footprint elongation/orientation behavior
  - remove the smoothing-comparison workflow unless later testing creates a strong reason to revisit it
