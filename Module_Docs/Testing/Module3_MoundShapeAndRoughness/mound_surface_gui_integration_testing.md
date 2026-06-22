# Module 3 Testing: Mound/Surface GUI Integration

Related finalized doc: [Module3_MoundShapeAndRoughness.md](../../Module3_MoundShapeAndRoughness.md)

## Promotion Status
`testing`

## Feature Under Test
The `Mound/Surface Analysis` button in `SOLFAnalysisApp`, using GUI-dedicated analysis cores:

- `analyzeMoundsGuiCore.m`
- `analyzeMoundShapeGuiCore.m`

The original command-line analysis functions remain unchanged while the GUI workflow is tested.

## Current Hypothesis Or Intended Behavior
The GUI should let a user run Module 3-style mound/surface analysis without being overwhelmed by every available output at once. The user selects output families in a compact two-column active settings panel below the left-column analysis buttons, runs the full GUI analysis once, and reviews selected output groups as tabs in the main app window.

## Current Algorithm Or Workflow
1. User selects a VK4 file and its matching `bestParams_<imageName>.mat`.
2. The MAT file must contain one table variable named `bestParams_<imageName>`.
3. The table must contain the optimizer fields plus the detection settings needed to rerun Module 1 directly:
   - `morphScale`
   - `contrastMethod`
   - `gaussSigma`
   - `openRadius`
   - `clipLimit`
   - `fillDeepPits`
   - `fillThreshold`
   - `dilateRadius`
   - `minObjectArea`
4. The GUI initializes a session-only Module 3 cache keyed by VK4 path, bestParams path, and output folder.
5. The GUI calls `analyzeMoundsGuiCore` only when Module 1 mound-spacing context is missing.
6. If only `Mound Spacing` is selected, the GUI stops after Module 1 context and does not enter the Module 3 shape core.
7. If any downstream mound/surface group is selected, the GUI computes the Module 3 watershed/shape context once and stores it for the current app session.
8. Later `Run Analysis` clicks reuse cached context and append newly requested tabs instead of clearing the review area.

## Output Groups Being Reviewed
- `Mound Spacing`
  - count, density, nearest-neighbor spacing, Delaunay overlay, and NN spacing histogram
- `Roughness`
  - Method B nearest-neighbor search-region overlay plus `Rp`, `Rv`, `Rz` distributions
- `Direct Height`
  - Method C base-band overlay plus direct mound height, base position, open/median/crowded height-family distributions, and the whole-image watershed-border Z-height distribution
- `Footprint Shape`
  - raw-surface shape/footprint overlays plus footprint area, equivalent diameter, perimeter, circularity, solidity, convexity, and extent
- `Axes And Orientation`
  - ellipse/Feret axes overlay plus ellipse axes, Feret axes, aspect ratios, orientation, and orientation agreement
- `Surface Area And Volume`
  - accepted watershed-region overlay plus mound surface area, peak-cap empty volume, and surface-area-to-volume scale
- `Whole-Image Slices`
  - whole-image area, perimeter, and cumulative surface area versus height
  - the perimeter plot marks the maximum-perimeter height using both reference-plane-relative and absolute height values
  - a raw-surface threshold overlay shows pixels at or above the maximum-perimeter height, with the threshold boundary highlighted
- `QA Diagnostics`
  - watershed seed overlay, watershed boundary overlay, base-band overlay, validity overlay, watershed score, and run-level validity diagnostics

## Surface Area Convention Under Test
The GUI Module 3 path uses the shared `vkSurfaceAreaMetrics` helper so that the GUI roughness and mound/surface paths use the VK-matched convention selected during legacy roughness testing:

- opposite-diagonal cell facets
- full finite-pixel projected area
- right/bottom edge extension

## Session Cache Behavior Under Test
- Cache lifetime is session-only. It is cleared when the selected VK4, output folder, or bestParams file changes.
- Mound spacing is an independent cached stage and can be reviewed by itself.
- The current first incremental pass caches the Module 3 watershed/shape core as one heavy downstream stage. This prevents repeated watershed optimization when additional groups are added later, but the internal per-mound Module 3 calculations still need a deeper stage split before each downstream checkbox can compute only its own per-mound quantities.
- Review tabs are append-only within a session. Unchecking a group does not delete an already rendered tab.

## Temporary Assumptions And Open Decisions
- Full per-checkbox computation skipping inside `analyzeMoundShapeGuiCore` remains under development; this first pass isolates Mound Spacing and prevents repeated heavy downstream recomputation.
- Group-level checkboxes are the main workflow. Advanced per-metric controls are reserved for a later pass and are not shown in the current compact settings panel.
- `Mound Spacing` is shown above `Roughness` because it is upstream context for interpreting all mound/surface outputs.
- Old `bestParams.mat` files with generic or redundant variables do not unlock the Module 3 GUI workflow.
- The GUI-core analysis functions skip automatic standalone PNG figure generation by default; figures are rendered in the app and exported only through GUI save buttons.
- The centerline profile from the standalone `*_rz_diag.png` figure is intentionally removed from the GUI path.

## Outputs And Figures Being Reviewed
- In-app review tabs for selected output groups, with nested interactive plot tabs on the left and summary metrics on the right.
- The right-side review column contains the selected tab summary, a reserved scrollable analysis-information box, and the command/status window at the bottom.
- `Save Current Tab` GUI exports.
- `Save All` GUI exports.
- Normal GUI-core `MAT` and `XLSX` outputs.

## Export Folder Structure Under Test
- Module 3 GUI exports are written under `<imageName>_mound_analysis_exports/` inside the selected output folder.
- Each output category writes plot PNGs into its own readable subfolder, for example `Mound_Spacing/`, `Roughness/`, and `Surface_Area_And_Volume/`.
- Summary CSV files stay in the root `<imageName>_mound_analysis_exports/` folder so category summaries are easy to scan together.
- Each output-category subfolder also writes a `*_raw_data.csv` file containing the numeric vectors used for that category's distributions and line plots, padded with `NaN` where columns have different lengths.
- Re-saving the same tab or all tabs overwrites matching existing export files.
- Histogram and line-style exports are re-rendered in temporary offscreen MATLAB figures with default MATLAB fonts and larger text intended for papers and presentations.
- Image-overlay exports keep the in-app rendering but temporarily scale text for slide-style readability.
- Image overlays use a shared marker convention during testing: mound-detection centroids are red `+` markers, and Rp locations are yellow filled dots.
- Image-overlay legends are placed below the image with horizontal orientation so side legends do not shrink the image region on smaller monitors.
- `Save All` skips plot PNGs already exported during the current app session; `Save Current Tab` forces a refresh of the active tab.
- Switching to another analysis module after generating unsaved results prompts the user to save, continue without saving, or cancel the switch.
- The GUI label `Median Height` uses the existing `height_typical_um` compatibility field, which is calculated from the Q50/median base height.

## Promotion Criteria
- Reviewers can run Module 3 from VK4 plus the matching `bestParams_<imageName>.mat` without using separate command-window steps.
- The group ordering and default checked groups feel understandable.
- `Mound Spacing` provides enough context to verify count, spacing, density, and triangulation before interpreting shape metrics.
- GUI tab exports save to the selected output folder and match the active tab or visible tabs.
- Surface-area values remain consistent with the legacy VK-matched convention.
- User explicitly approves promotion into finalized Module 3 documentation.

## Unresolved Risks Or Competing Options
- The GUI core copies may drift from the original functions if both are edited independently for too long.
- Per-mound VK-style surface-area density is an approximation of the shared whole-patch convention and should be checked against representative surfaces.
- Future optimization may split the GUI cores into smaller renderable analysis stages instead of copying the full command-line functions.
- The next refactor target is splitting the current per-mound Module 3 loop into method-specific stages: watershed context, Method B roughness, Method C base/height, Q50 footprint geometry, surface area/volume, whole-image slices, and QA summaries.
