# Module 2: Cavity Analysis

See also: [analyzeCavities_outputs.md](../Function_Output_Notes/analyzeCavities_outputs.md)

## 1. Module Purpose And Scientific Questions Answered
Module 2 characterizes the depressions between mound structures.

Scientifically, it addresses questions such as:

- How many cavities are physically meaningful rather than shallow roughness noise?
- How deep are the cavities?
- How wide are their mouths?
- How sharply do they narrow with depth?
- How many surrounding mounds define each cavity neighborhood?

This module is the depression-side complement to the mound-centric information in Module 3.

## 2. Inputs, Dependencies, And Upstream Assumptions
Primary entry point:

- `analyzeCavities.m`

Inputs:

- `m1` results from Module 1
- minimum cavity depth threshold
- optional reflection-correction settings
- optional output directory

Dependencies:

- Module 1 centroid, calibration, and display-image outputs
- Image Processing Toolbox

Upstream assumptions:

- Module 1 centroids are already trustworthy enough to define the mound scaffold around cavities
- `m1.Z` is the authoritative calibrated height map
- `m1.I_raw` is the operational display/intensity image used for threshold-based reflection handling

## 3. Recommended Reading Path
For a practical first pass, read:

1. smoothing and interior mask logic
2. optional reflection correction
3. cavity segmentation
4. depth and mouth-geometry measurement
5. bounding-mound interpretation
6. figure guide

## 4. Calculation Workflow
### 4.1 Start from Module 1 geometry and the calibrated height map
Module 2 imports:

- calibrated height map `Z`
- mound centroids
- lateral calibration
- mean mound spacing

That lets it measure cavities in the same physical coordinate system used by the mound analyses.

### 4.2 Smooth the height map before valley-floor analysis
The module smooths the height map before cavity segmentation so that small LSCM noise fluctuations do not create artificial valley minima.

This is a measurement-stability step. It is not intended to redefine the raw surface, only to stabilize depression segmentation and valley-floor localization.

### 4.3 Restrict analysis to the interior mound field
The module builds an analysis mask from the centroid geometry so that image-edge artifacts do not dominate cavity segmentation.

This matters because cavities near the image edge are often incomplete and can produce misleading mouth geometry or false watershed structure.

### 4.4 Optionally correct reflection artifacts
When enabled, reflection correction targets bright reflection islands inside dark pit regions.

The physical problem is that these bright islands can create false local maxima in depressions, which interferes with cavity seeding and depth interpretation.

The current strategy is intentionally conservative:

- identify pit regions from the stored display image
- identify the bright reflection subregion
- estimate a replacement height from the surrounding dark ring
- replace only the reflection pixels that sit above that ring-based fill value

This keeps the correction grounded in nearby measured pixels rather than an unconstrained fitted surface.

### 4.5 Segment cavity basins
After smoothing and any reflection handling, the module segments the depression network into candidate basins.

These basin candidates are then filtered by physical depth significance, so the final cavity set is meant to represent meaningful depressions rather than every minor local low point.

### 4.6 Measure cavity depth and mouth geometry
For each accepted cavity, the module measures:

- valley-floor height
- mouth-plane height
- cavity depth
- equivalent mouth radius
- mouth area
- cone half-angle

The current cavity depth path is intended to report depth using the physically meaningful calibrated height data rather than only the smoothed or display-space representation.

### 4.7 Count surrounding mound context
The module also records how many mound peaks bound each cavity.

This adds neighborhood context: a cavity enclosed by a more regular mound ring may have different physical implications than one embedded in a highly irregular local arrangement.

## 5. Analysis Groups Within The Workflow
### Reflection-handling group
This group exists to prevent optical artifacts from being mistaken for real cavity structure.

### Basin segmentation group
This group defines where one cavity begins and another ends.

### Depth and mouth-geometry group
This group produces the primary physical cavity metrics.

### Neighborhood-context group
This group connects each cavity to the surrounding mound arrangement rather than treating the cavity as an isolated pit.

## 6. Output Interpretation
The outputs to focus on first are:

- `n_cavities`
  - the count of cavities that pass the current physical depth threshold
- `depth_um`
  - how deep the depressions are
- `r_mouth_um` and `mouth_area_um2`
  - how wide the cavity openings are
- `beta_deg`
  - a compact description of cavity steepness/opening geometry
- `n_bounding_mounds`
  - the local topographic context around each cavity

Interpretation examples:

- deeper cavities with similar mouth sizes indicate stronger vertical relief
- larger mouth radius at similar depth indicates a broader, more open depression
- large variability in `n_bounding_mounds` suggests less regular local cavity enclosure

## 7. Assumptions, Choices, And Why They Were Made
- The module smooths before segmentation because raw valley noise can create unstable basin structure.
- Reflection correction is optional because not every surface or image needs it.
- The reflection fill value is based on nearby dark-ring pixels so the correction stays tied to measured local context.
- A minimum depth threshold is used so the public cavity set reflects meaningful depressions rather than trivial roughness.

## 8. Diagnostics And Figure Guide
### `*_reflection_diag.png`
- Workflow stage: artifact handling
- Type: diagnostic/process figure
- Shows: pit region, reflection region, dark-ring reference region, and replaced pixels
- Use it for:
  - checking whether the reflection mask is targeting the right bright islands
  - verifying that the replacement region tracks the surrounding dark pit structure
- Watch for:
  - correction spilling outside the true reflection
  - too little ring support
  - very large corrected regions that suggest threshold mismatch

### `*_watershed_diag.png`
- Workflow stage: basin segmentation
- Type: diagnostic/on-surface figure
- Shows: cavity watershed structure and candidate minima context
- Use it for:
  - checking whether cavity basins align with visible depressions
  - identifying over-segmentation or missed basins
- Watch for:
  - basin fragmentation in smooth depressions
  - merged neighboring cavities that should be separate

### `*_3D_cones.png`
- Workflow stage: cavity geometry interpretation
- Type: surface-visualization figure
- Shows: smoothed 3D surface with cavity-cone geometry overlays
- Use it for:
  - understanding how mouth size, depth, and cone angle relate visually
- Watch for:
  - visually unrealistic cone fits
  - apparent mismatch between cone apex and visible valley location

### `*_cavities.png`
- Workflow stage: final accepted cavity map
- Type: on-surface visualization
- Shows: cavity locations, equivalent mouth circles, and neighborhood context overlays
- Use it for:
  - understanding which depressions entered the final statistics
  - relating each cavity to the surrounding mound field
- Watch for:
  - accepted cavities that do not look physically meaningful
  - obvious missed deep depressions

### `*_cavity_hist.png`
- Workflow stage: cavity distribution summary
- Type: distribution/statistical figure
- Shows: distributions of depth, mouth radius, cone half-angle, and bounding-mound count
- Use it for:
  - comparing cavity populations across surfaces
  - spotting broad or multi-family cavity behavior
- Watch for:
  - strongly skewed or multi-modal distributions that may need explanation

### `*_cavities.xlsx`
- Workflow stage: export and detailed review
- Type: summary/supporting output
- Shows: per-cavity tables, shallow-basin table, and summary statistics
- Use it for:
  - checking exact numerical values behind figures
  - later cross-module comparisons

## 9. Known Limitations And Caution Points
- Cavity interpretation depends on the stability of Module 1 centroids and the basin segmentation path.
- Reflection correction is a pragmatic optical-artifact fix, not a physical reconstruction of missing data.
- The accepted cavity set depends on the current minimum-depth threshold.
- Cavity geometry near the edge of the analyzable mound field should be treated cautiously even with masking.

## 10. Change Log For Finalized Methodology
- 2026-05-08: Created the long-form finalized Module 2 scientific-methods document and aligned it with the current output-note layer.
