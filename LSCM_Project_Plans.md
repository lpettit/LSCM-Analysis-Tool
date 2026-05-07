# LSCM Project Plans and Ideas

## Purpose
- This file collects forward-looking plans, unresolved ideas, proposed next steps, and methodological questions for the LSCM Analysis Tool project.
- Historical session records should stay in the running session notes, while active planning and backlog items should accumulate here.

## Current Planning Themes
- Use `Q50`-based half-max as the preferred footprint/body-shape definition for footprint-derived shape metrics.
- Continue refining Module 3 so the preferred interpretation is physically representative and clearly reported.
- Keep the app/orchestration workflow growing without duplicating analysis logic.
- Preserve enough diagnostics to validate physical interpretation on difficult surfaces.

## Footprint and Shape-Definition Planning
- Decision made:
  - use the half-max plane built from `Q50` as the preferred footprint/body-shape definition for footprint area, circularity, Feret diameters, and related morphology
- Comparison outcome from footprint-plane review:
  - half-max from `Q90` was judged too high and should be discarded
  - the raw `Q90` plane footprint remains a useful comparison/context view, but not the main footprint definition
  - the `Q50` half-max footprint had the tightest distributions and the most physically reasonable plane placement
- Interpretation note:
  - the raw `Q90` plane footprint tends to be more right-skewed and wider because that plane is often lower
- Once the footprint measurement plane is determined, overlay all mound perimeters measured at that plane onto a single figure and estimate a representative footprint shape.
- Keep any non-`Q50` footprint definitions as comparison/diagnostic families rather than the main public footprint metric.

## Module 3 Methodology and Reporting
- Decide whether the direct mound-height family should become the main public mound-height reporting path, distinct from the roughness-oriented Method B `Rv/Rz` path.
- Decide whether the centroid-neighborhood `Rp` definition should eventually be replaced globally, since the current centroids come from smoothed mound minima / seed placement rather than the exact raw summit.
- Resolve the open methodological question of whether the watershed-contained peak should replace `Rp` only for mound height or everywhere in Module 3.
- Decide whether legacy Method A fields should remain for compatibility, be demoted to explicitly secondary outputs, or be removed from the main interpretation path long-term.
- Finish the remaining Method B-first cleanup in summary printing, figure titles, default interpretation, Excel summary columns, and any downstream consumers that still assume older defaults.
- Update any stale top-of-file documentation and comments that still present annulus logic as the main workflow.
- Re-check the low-`Rz` concern once Method B-first reporting and peak definitions are settled.

## Deferred Shape-Parameter Ideas
- Put a pin in additional shape parameters unless the current morphology set does not separate surfaces well enough.
- Ranking emphasis for future additions should prioritize scientific usefulness for comparing different surfaces.
- Important caveats for revisiting this later:
  - the LSCM resolution is not fine enough to resolve true nanoscale mound texturing, so mesoscale shape characterization matters more than fine texture metrics
  - the 3D mass centroid is not a preferred basis for new descriptors because of the dual-base and mound-cutoff ambiguity
- Ranked future candidates:
  - `surface_area / footprint_area`
    - strongest additional mesoscale descriptor for how much sloped exposed surface exists relative to plan-view size
  - volume-based compactness metrics
    - examples: `volume / footprint_area` or `volume / (footprint_area * height)`
    - useful for distinguishing broad-low mounds from compact-bulky mounds across surfaces
  - boundary radial variability
    - examples: standard deviation of boundary radius, coefficient of variation of radius, or `max_radius / min_radius`
    - helps distinguish smooth rounded mounds from lobed or irregular mounds in ways circularity alone may miss
  - orientation consistency with height
    - compare orientation at multiple contour levels to see whether mounds maintain shape direction with height or twist/distort upward
  - normalized anisotropy
    - recommended form: `(major - minor) / (major + minor)`
    - bounded and easier to compare across surfaces than raw axis lengths alone
  - peak offset from footprint center
    - potentially informative for asymmetry, but lower priority than the items above because it still depends on a footprint-center definition
  - profile-based flank steepness
    - potentially useful, but more method-sensitive and may depend strongly on profile selection
  - convex deficiency
    - example: `(convex_area - area) / convex_area`
    - mostly an alternate framing of solidity, so lower priority
  - eccentricity
    - recognized easily by readers, but mostly redundant with ellipse major/minor axes and ellipse aspect ratio
  - rectangularity / minimum-bounding-rectangle occupancy
    - likely less physically meaningful for natural mound morphologies than ellipse/Feret-based descriptors
  - mass-centroid offsets
    - lowest priority because of the dual-base and mound-cutoff issue
- Top 3 most worth revisiting first if more discrimination is needed:
  - `surface_area / footprint_area`
  - volume compactness metrics
  - boundary radial variability
- Important interpretation note for future volume work:
  - the current peak-cap empty volume is a valid geometric quantity
  - but a mound-material-like volume between the local base plane and the surface inside the watershed may become a more intuitive long-term morphology descriptor

## Watershed / Boundary Debugging
- Resolve the remaining Module 3 watershed-border spur issue still visible on mound 2 in the 3D lift-out diagnostic.
- Best next debugging step:
  - inspect mound 2's exact local watershed/border mask
  - likely replace the current border-cleaning approach with tracing a single closed perimeter for the mound region
- Check one of the dense-mound images again and compare the saved watershed diagnostics under the adaptive sigma-selection workflow.
- If useful later, expose the selected sigma and candidate-score table in a dedicated diagnostic figure or sheet for easier review across images.

## Module 2 and Validation Follow-Up
- Re-test whether `analyzeCavities.m` still reproduces the reflection-correction failure after the seed-order and `Z_raw` depth updates.
- Validate the `analyzeCavities.m` changes against real data beyond the current representative smoke test.
- Validate behavior with more VK4 files instead of only the current representative path.

## Autotuning and Reproducibility
- Revisit `autoTuneMounds` non-determinism, since near-tied CV minima can produce different accepted parameter sets and downstream counts.
- Candidate fixes or alternatives to evaluate:
  - force deterministic tie-breaking after optimization with a stable secondary rule
  - save and reuse an approved parameter set for a given file
  - restrict or seed the optimizer so repeated runs explore the same sequence of trial points
  - replace single-best selection with a small Pareto or top-k review path
  - reduce score degeneracy by adding secondary penalties

## App and Workflow Expansion
- Continue expanding the app workflow after the single-file launcher/orchestrator baseline.
- Implement batch analysis when the single-file workflow is stable enough.
- Keep `runSOLFAnalysis.m` and the app as orchestration layers rather than re-implementing module logic inside the UI path.

## Broader Project Backlog
- Build Module 4:
  - bond-angle distribution
  - pair distribution
  - `Q6`
- Build Module 5:
  - summary statistics
  - cross-module correlations
- Build the broader project plan in more detail before larger structural work continues.

## Practical Notes
- The original uploaded handoff still exists as `LSCM_Project_Handoff.docx`.
- `LSCM_Project_Handoff.md` remains the main plain-text project context file.
- This plans file should be the preferred home for future ideas, backlog items, and methodological decision candidates.
