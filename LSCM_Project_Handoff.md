# LSCM Project Handoff

## Current Status
- MATLAB prototype for LSCM microstructured boiling-surface analysis.
- 8 `.m` files are present in the repo.
- Current implemented modules:
  - Module 1: mound detection, spacing, density, Delaunay analysis
  - Module 2: cavity geometry analysis
  - Module 3: per-mound shape and roughness analysis
- Planned but not built:
  - Module 4: bond-angle distribution, pair distribution, Q6
  - Module 5: summary statistics and cross-module correlations
- Active handoff issues from the uploaded `.docx`:
  - `analyzeCavities.m`: reflection correction reportedly corrects `0` reflections in the current failing case
  - `analyzeMoundShape.m`: reported low `Rz` / peak-handling issue under investigation
- User clarifications after upload:
  - For the current VK4 workflow, the reference plane calculation in `analyzeMoundShape.m` has already been verified as correct.
  - Intended cavity depth should use `Z_raw`.
  - Method B should replace Method A as the preferred valley-definition path.
  - For direct mound-height interpretation, the user now wants peak-above-local-base reporting framed as:
    - open-side height
    - typical height
    - crowded-side height
  - For Module 3 footprint/body-shape geometry, the preferred footprint definition should use the `Q50`-based half-max plane.
  - The `Q90`-based half-max footprint was reviewed and rejected as too high.
  - The raw `Q90`-plane footprint can remain as a comparison/context view, but not as the main footprint measurement.

## Files Present
- `readVK4.m`
- `autoTuneMounds.m`
- `refineMounds.m`
- `pickFillThreshold.m`
- `pickReflectionThreshold.m`
- `analyzeMounds.m`
- `analyzeCavities.m`
- `analyzeMoundShape.m`
 - `runSOLFAnalysis.m`
 - `SOLFAnalysisApp.m`
 - `launchSOLFAnalysisApp.m`

## Prototype Shape
- `readVK4.m`
  - Reads Keyence `.vk4` files into calibrated height map `Z`
  - Returns `xy_um_per_px`, `total_height_um`, `imgH`, `imgW`
  - Depends on external `vk4mat` functions on MATLAB path
- `autoTuneMounds.m`
  - Bayesian parameter tuning for mound detection
  - Accepts `.vk4` or standard image input
  - Produces `bestParams` for downstream use
- `refineMounds.m`
  - Interactive refinement after `autoTuneMounds`
  - Reuses detection pipeline with user-guided count adjustment
- `pickFillThreshold.m`
  - Interactive GUI to choose pit-fill threshold
- `pickReflectionThreshold.m`
  - Interactive GUI to choose reflection threshold inside pit regions
- `analyzeMounds.m`
  - Main Module 1 entry point
  - Produces `m1` struct used by downstream modules
  - Stores `Z`, `I_raw`, centroids, triangulation, spacing stats, calibration
- `analyzeCavities.m`
  - Module 2
  - Consumes `m1`
  - Uses `Z_smooth` for cavity segmentation and `Z_raw` for reported cavity depth measurements
- `analyzeMoundShape.m`
  - Module 3
  - Consumes `m1`
  - Computes global `Rp/Rv/Rz`, preferred per-mound roughness, watershed-restricted mound geometry, 3D lift-out diagnostics, mass centroids, and percentile-based direct mound-height variants
  - Contains both Method A and Method B valley logic; Method B is the intended preferred path
- `runSOLFAnalysis.m`
  - Single-file orchestration entry point for selected modules
  - Calls threshold pickers as needed and then runs the existing analysis functions
- `SOLFAnalysisApp.m`
  - First MATLAB single-file app/UI wrapper built on `matlab.apps.AppBase` and `uifigure`
- `launchSOLFAnalysisApp.m`
  - Convenience launcher for the app

## Current Flow
```matlab
fillThreshold = pickFillThreshold('Left-50x.vk4');
reflThreshold = pickReflectionThreshold('Left-50x.vk4', fillThreshold);
bestParams    = autoTuneMounds('Left-50x.vk4', true, fillThreshold, 3, 20);
% n_mid printed by autoTuneMounds if refinement is needed
bestParams    = refineMounds('Left-50x.vk4', true, fillThreshold, 3, 20, bestParams, n_mid);
m1            = analyzeMounds('Left-50x.vk4', bestParams, true, fillThreshold, 3, 20);
cavResults    = analyzeCavities(m1, 2.0, true, fillThreshold, reflThreshold);
moundResults  = analyzeMoundShape(m1);
```

## Important Dependencies
- `readVK4.m` requires external `vk4mat` functions:
  - `vk4_readVk4Binary`
  - `vk4_computeVk4Offsets`
- Toolboxes inferred from code:
  - Image Processing Toolbox
  - Statistics and Machine Learning Toolbox
- Canonical test input from prior context:
  - `Left-50x.vk4`

## Important Data Assumptions
- `m1.Z` is the ground-truth calibrated height map in micrometers.
- `m1.I_raw` is the `uint8` display/intensity image used for threshold-based operations.
- `.vk4` is the preferred input path because BMP-based height maps lose precision.
- Detection logic is intentionally duplicated across multiple files for portability according to the uploaded handoff.

## Notes From Uploaded Handoff
- Prior-context constants for `Left-50x.vk4`:
  - `xy_um_per_px = 0.141740`
  - `total_height_um = 80.58`
  - `z_pm_per_count = 100`
- The handoff says Module 3 currently prefers a nearest-neighbor-circle valley method over the earlier annulus method. User confirmation says Method B should replace Method A, but the current code still carries both paths and still exposes annulus parameters publicly.
- The handoff also warns not to change watershed direction, VK4 zeroing convention, or `countBoundaryLoops` behavior casually.

## Immediate Next Steps
- Resolve the remaining Module 3 watershed-border spur issue still visible on mound 2 in the 3D lift-out diagnostic.
- Decide whether the current percentile-based direct mound-height family should continue using `Q10/Q50/Q90` or whether a different local-base definition is more physically representative after further visual review.
- Decide whether the direct mound-height family should become the main public mound-height reporting path, distinct from the roughness-oriented Method B `Rv/Rz` path.
- Re-test whether `analyzeCavities.m` still reproduces the reflection-correction failure after the seed-order and `Z_raw` depth updates.
- Continue expanding the app workflow after the single-file launcher/orchestrator baseline.

## Missing External Inputs
- `Left-50x.vk4`
- Optional companion `Left-50x.bmp`
- `vk4mat` MATLAB library on path
