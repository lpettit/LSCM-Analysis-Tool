# Module 3: Mound Shape And Roughness

See also: [analyzeMoundShape_outputs.md](../Function_Output_Notes/analyzeMoundShape_outputs.md)

## 1. Module Purpose And Scientific Questions Answered
Module 3 is the main mound-centric morphology and height-interpretation module.

It is designed to answer questions such as:

- How tall are the mounds, and relative to what local base or valley definition?
- What mound footprint should be treated as the most physically representative body definition?
- How large, round, elongated, or irregular are the mound bodies?
- How much surface area and apparent volume-like shape complexity do the mound bodies have?
- How do whole-surface height slices evolve as the threshold plane moves through the surface?

Module 3 is also the module where scientific interpretation choices matter most, because different peak, base, valley, or footprint definitions can produce substantially different physical stories.

## 2. Inputs, Dependencies, And Upstream Assumptions
Primary entry point:

- `analyzeMoundShape.m`

Inputs:

- `m1` results from Module 1
- optional output directory

Dependencies:

- Module 1 centroids, calibration, height map, display image, and spacing summaries
- Image Processing Toolbox

Upstream assumptions:

- Module 1 centroids are the starting mound identities
- the calibrated height map is the physically meaningful vertical data source
- watershed partitioning is an acceptable way to define mound territories for body-shape and direct-height workflows

## 3. Recommended Reading Path
Because Module 3 is broad, the most useful first-pass reading order is:

1. preferred interpretation path
2. global reference and roughness context
3. direct mound-height workflow
4. footprint/body-shape workflow
5. whole-image height-slice workflow
6. figure guide

### Current preferred interpretation path
At the current finalized state:

- valley-dependent roughness uses Method B nearest-neighbor-circle logic
- direct mound height uses watershed-contained peak plus Method C watershed-boundary base
- footprint/body-shape geometry uses the watershed-restricted `Q50` half-max definition

The output-note page is the faster lookup layer for specific fields within that preferred path.

## 4. Calculation Workflow
### 4.1 Establish a whole-image vertical reference context
Module 3 begins by defining a global reference context for the surface and computing whole-image roughness-style reference quantities such as `Rp`, `Rv`, and `Rz`.

This gives the module a common vertical framing for:

- per-mound peak and valley quantities
- reference-plane-relative base positions
- whole-image slice plots

### 4.2 Build a watershed partition of the mound field
The module uses the Module 1 centroid field to seed a watershed-style decomposition of the surface into mound territories.

The watershed stage is foundational because it provides:

- mound-contained territories for peak search
- watershed-border geometry for Method C base logic
- spatial bounds for footprint/body-shape measurement
- source geometry for several diagnostics

The current workflow uses adaptive smoothing selection to improve watershed behavior across different mound densities and image conditions.

### 4.3 Define mound peaks
Within each watershed-defined mound region, the module identifies the watershed-contained raw-height peak.

This peak is important because it is currently the canonical summit used for the preferred direct mound-height path, and it also provides a comparison against the older centroid-window peak definition.

### 4.4 Define local valleys and bases
Module 3 separates two related but not identical concepts:

- a roughness-style local valley
- a direct-height local mound base

#### Method B valley logic
Method B uses a nearest-neighbor-circle construction around each mound to define a local valley environment.

This path is preferred for per-mound roughness-style `Rv` and `Rz` interpretation because it is designed around local mound-to-mound spacing rather than a watershed border.

#### Method C base logic
Method C uses the watershed boundary and a narrow inward band to define a local mound base.

This path is preferred for direct mound height because it is tied to the actual watershed-contained mound body rather than only a spacing-derived surrounding circle.

### 4.5 Build percentile-style base families
The module also stores percentile-based local base families derived from Method C samples.

Current interpretation labels:

- `Q10`: open-side base
- `Q50`: typical base
- `Q90`: crowded-side base

These are meant to preserve the physical idea that a mound can have a more open side and a more crowded side, rather than forcing a single universal base height to describe all directions equally well.

### 4.6 Compute direct mound heights
Direct mound height is calculated as peak above local base.

The preferred direct-height path is:

- watershed-contained peak
- minus Method C preferred base position

The percentile family extends that into:

- open-side height
- typical height
- crowded-side height

These direct-height outputs are separate from roughness-style `Rz` and should be interpreted as local mound-body height measures, not automatically as interchangeable roughness metrics.

### 4.7 Define the footprint/body-shape plane
For body-shape geometry, the module currently prefers a watershed-restricted `Q50` half-max footprint.

This is a major interpretation choice. It means the mound body is not defined by the full watershed region alone and not by the previously reviewed `Q90` half-max alternative. Instead, the preferred body plane is the half-max plane built from the `Q50`-based base interpretation.

That choice was retained because it was judged the most physically representative compromise for footprint/body morphology.

### 4.8 Compute per-mound body-shape metrics
Within the preferred footprint/body definition, the module computes:

- footprint area
- equivalent diameter
- perimeter
- circularity
- solidity
- convexity
- extent
- ellipse axes and orientation
- Feret diameters and orientation
- surface area
- peak-cap empty volume
- several aspect-ratio variants

These describe the lateral geometry and overall body character of each mound rather than only its height.

### 4.9 Compute whole-image height-slice morphology
The module also includes a whole-surface workflow that thresholds the raw height map at a sequence of height levels and tracks how the above-threshold geometry evolves.

Current whole-image slice outputs include:

- cross-sectional area vs height
- perimeter vs height
- cumulative true 3D surface area vs height

These are intended to help interpret the surface as a full topographic population, not only as a collection of isolated mound objects.

## 5. Analysis Groups Within The Workflow
### Global reference and roughness context
This group defines the vertical framing of the module and supports roughness-style interpretation.

### Direct mound-height workflow
This group focuses on peak above local base, especially Method C and the percentile-based open/typical/crowded family.

### Footprint and body-shape workflow
This group focuses on what lateral mound body should be measured and how its size and shape should be described.

### Whole-surface morphology workflow
This group characterizes how the entire surface cross section evolves with height threshold.

### Diagnostic and provenance workflow
This group stores the geometry and figures needed to judge whether the preferred interpretation remains scientifically sensible.

## 6. Output Interpretation
For most downstream work, start with:

- `preferred_mound_height_um`
  - direct mound height from watershed peak to Method C base
- `height_open_um`, `height_typical_um`, `height_crowded_um`
  - directional-interpretation family for local base ambiguity
- `preferred_footprint_um2`
  - preferred mound footprint area
- `preferred_equiv_diam_um`
  - characteristic lateral size
- `preferred_circularity`, `preferred_solidity`, `preferred_convexity`
  - compactness and irregularity descriptors
- `preferred_surface_area_um2`
  - exposed body surface extent
- `whole_image_*`
  - whole-surface threshold-evolution descriptors

Interpretation cautions:

- roughness-style `Rz` and direct mound height are related but not identical concepts
- percentile-based heights are not competing errors; they are alternative local-base interpretations
- footprint/body metrics depend strongly on the chosen body-defining plane

## 7. Assumptions, Choices, And Why They Were Made
- Method B is preferred for roughness-style valley interpretation because it tracks a local spacing-informed valley environment.
- Method C is preferred for direct mound height because it is tied to the watershed-defined mound territory.
- The watershed-contained peak is favored over a simple centroid-window peak for mound-body interpretation.
- The preferred footprint/body-shape plane is the watershed-restricted `Q50` half-max definition because it was judged more physically representative than the reviewed alternatives.
- The percentile base family is preserved because one scalar base can hide real asymmetry between open and crowded mound sides.
- Whole-image slice morphology is retained because the surface can carry meaningful information that is not captured fully by per-mound summary metrics alone.

## 8. Diagnostics And Figure Guide
### `*_roughness_hist.png`
- Workflow stage: roughness-family summary
- Type: distribution/statistical figure
- Shows: roughness-related output distributions
- Use it for:
  - comparing the spread of peak/valley-style metrics
  - checking whether roughness families are tight or broad
- Watch for:
  - multi-modal structure that may indicate mixed mound populations or unstable valley definition

### `*_mound_height_hist.png`
- Workflow stage: direct-height summary
- Type: distribution/statistical figure
- Shows: direct mound-height distributions
- Use it for:
  - comparing mound-height interpretation families across surfaces
- Watch for:
  - strong skew or multiple populations

### `*_footprint_size_hist.png`, `*_footprint_shape_hist.png`, `*_elongation_axes_hist.png`, `*_aspect_ratio_hist.png`, `*_orientation_hist.png`, `*_surface_area_volume_hist.png`
- Workflow stage: body-shape interpretation
- Type: distribution/statistical figures
- Shows: size, shape, orientation, and surface-area-related distributions
- Use them for:
  - identifying dominant shape families
  - comparing surfaces by compactness, anisotropy, and exposed body scale
- Watch for:
  - unstable tails caused by marginal footprint validity
  - broad orientation scatter when a preferred directional alignment was expected

### `*_mound_shapes.png`
- Workflow stage: on-surface shape overview
- Type: on-surface/process visualization
- Shows: mound territories and preferred-valid mound context
- Use it for:
  - checking spatial coverage of valid mound-shape analysis
- Watch for:
  - many rejected mounds in one region
  - obvious mismatch between the visible surface and analyzed mound locations

### `*_footprint_spatial_ellipse_overlay.png`
- Workflow stage: footprint geometry interpretation
- Type: on-surface visualization
- Shows: preferred footprint boundaries with ellipse and Feret-related overlays
- Use it for:
  - understanding what the module is calling the measured mound body
  - checking whether orientation and axis metrics match visual intuition
- Watch for:
  - overlays extending outside the visually reasonable mound body
  - unstable geometry on highly irregular or tiny footprints

### `*_method_c_base_band_diag.png`
- Workflow stage: Method C base definition
- Type: diagnostic/process figure
- Shows: watershed border and inward base-band geometry
- Use it for:
  - checking whether the base samples are being taken from the intended local mound boundary zone
- Watch for:
  - obvious border artifacts
  - broken bands or spurs that suggest watershed cleanup issues

### `*_watershed_augmented_seed_diag.png`
- Workflow stage: watershed construction
- Type: diagnostic/process figure
- Shows: watershed seeding with added border-support seeds
- Use it for:
  - checking whether edge-aware seeding improved mound partition stability
- Watch for:
  - excessive added seeds
  - seed layouts that appear inconsistent with the visible mound field

### `*_mound_liftout_diag.png`
- Workflow stage: 3D mound interpretation
- Type: surface-visualization/diagnostic figure
- Shows: representative watershed-contained mound lift-outs with peak, centroid, and mass-centroid markers
- Use it for:
  - visually judging whether the chosen peak and base concepts match physical intuition
  - understanding 3D mound asymmetry
- Watch for:
  - border spurs
  - centroid or peak markers landing in visually implausible locations

### `*_valley_diag.png`, `*_valley_nn_diag.png`, `*_valley_method_compare.png`
- Workflow stage: valley/base comparison
- Type: diagnostic/comparison figure
- Shows: legacy and current valley/base workflows and their distribution-level comparisons
- Use them for:
  - checking whether Method B and Method C are behaving as intended
  - comparing old and new interpretations
- Watch for:
  - large unexplained shifts between methods
  - strong systematic offsets on visually ordinary mounds

### `*_whole_image_height_slices.png`
- Workflow stage: whole-surface morphology
- Type: summary/comparison figure
- Shows: cross-sectional area, perimeter, and cumulative surface area vs height on both `z_rel` and derived `0` to mean preferred `Rz` framings
- Use it for:
  - understanding how much of the surface survives as the threshold rises
  - identifying where perimeter complexity peaks
- Watch for:
  - low-threshold tails dominated by framing or edge context
  - over-interpretation of the alternate `0` to `Rz` axis as a replacement for `z_rel`

### `*_rz_diag.png`
- Workflow stage: roughness framing
- Type: diagnostic/distribution figure
- Shows: `Rp/Rv/Rz` distributions and a profile-style visual explanation
- Use it for:
  - connecting roughness summaries to the actual vertical geometry
- Watch for:
  - mismatches between roughness numbers and profile intuition

### `*_mound_shapes.xlsx`
- Workflow stage: export and detailed review
- Type: summary/supporting output
- Shows: per-mound metrics, whole-image slice tables, summary sheet, and diagnostics sheet
- Use it for:
  - detailed scientific review
  - later cross-module analysis

## 9. Known Limitations And Caution Points
- Module 3 is sensitive to interpretation choices, especially peak, base, valley, and footprint definitions.
- Watershed stability matters; poor partitioning can distort both direct-height and body-shape results.
- Some outputs are intentionally diagnostic or comparison-oriented and should not automatically be treated as the main public interpretation path.
- Whole-image slice curves are powerful but can be misread if the user forgets they describe the full surface, not individual mound bodies.

## 10. Change Log For Finalized Methodology
- 2026-05-08: Created the long-form finalized Module 3 scientific-methods document and aligned it with the current preferred interpretation path and output-note layer.
