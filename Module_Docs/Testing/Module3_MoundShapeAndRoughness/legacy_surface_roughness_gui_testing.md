# Module 3 Testing: Legacy Surface Roughness GUI

Related finalized doc: [Module3_MoundShapeAndRoughness.md](../../Module3_MoundShapeAndRoughness.md)

Relevant history and planning:

- [SESSION_NOTES_2026-05-02.md](../../../SESSION_NOTES_2026-05-02.md)
- [LSCM_Project_Plans.md](../../../LSCM_Project_Plans.md)

## Promotion Status
`approved for finalization`

## Feature Under Test
A standalone legacy-style surface roughness ROI GUI, `legacySurfaceRoughnessGUI.m`, intended to mimic the manual VK-style measurement workflow closely enough to:

- verify the current surface-analysis pipeline against a legacy manual workflow
- compare newer Module 3 roughness interpretations against manually placed legacy ROIs

## Current Hypothesis Or Intended Behavior
The tool should provide a direct manual comparison path that is operationally familiar and scientifically tied to the current Module 3 reference framing.

Current intended behavior:

- load the surface directly from the selected `.vk4` file when launched standalone, or reuse an existing analysis struct when one is already available
- display the raw height surface with a rainbow-style `jet` colormap similar to the legacy screenshots
- let the user place up to 20 black-outlined measurement windows using:
  - `All areas`
  - `Rect.`
  - `Square`
  - `Area`
- measure each ROI against the whole-image global reference plane already used in `analyzeMoundShape`
- summarize ROI-level `Rp`, `Rv`, and `Rz` with mean and standard deviation
- save the finished ROI set and measurements when the user clicks `Done`

## Current Algorithm Or Workflow
1. launch `legacySurfaceRoughnessGUI(inputSource, outputDir)`
2. resolve the surface input in one of two ways:
   - preferred standalone path: pass the selected `.vk4` file path and load the calibrated height map directly with `readVK4`
   - compatibility path: pass an existing analysis struct and reuse its `Z`, `xy_um_per_px`, and `imagePath` fields
3. use the resolved raw height surface as the measurement surface and its lateral calibration for all physical-unit conversions
4. compute the whole-image global reference quantities from that height map:
   - `refPlane_um = mean(Z(:))`
   - `Rp_global = max(Z(:)) - refPlane_um`
   - `Rv_global = refPlane_um - min(Z(:))`
   - `Rz_global = Rp_global + Rv_global`
5. place ROIs manually:
   - `All areas` stores the full image as one exclusive measurement ROI
   - `Rect.` uses two clicks to define opposite corners, then stays armed so the next rectangle can be started immediately
   - `Square` uses two clicks but forces equal side lengths, then stays armed so the next square can be started immediately
   - `Area` opens a width/height popup in `um`, then uses one click to center a preview and a second click to place the first ROI
   - after each `Area` ROI is placed, `Area` mode stays armed but the next ROI is not primed automatically; the user clicks once on the surface to prime the next preview, then clicks again to place it
   - `Clear` removes all stored ROIs but keeps the currently selected placement mode armed so the user can resume placing windows immediately
6. for each ROI, compute:
   - `Rp_um = max(Z_roi) - refPlane_um`
   - `Rv_um = refPlane_um - min(Z_roi)`
   - `Rz_um = Rp_um + Rv_um`
7. automatically update the per-ROI table and the current summary after each completed ROI placement
8. on `Done`, save:
   - a `.mat` results struct with ROI geometry, global roughness context, and summary values
   - a `.csv` table of ROI-level measurements

## Temporary Assumptions And Open Decisions
- This tool is testing-only and is not yet part of the finalized Module 3 methodology.
- The GUI remains standalone rather than being run automatically from `runSOLFAnalysis.m`.
- The preferred standalone launch path is direct `.vk4` loading rather than dependence on Module 1 outputs.
- The measurement surface is the raw VK4-derived height map rather than a smoothed surface.
- ROI roughness is always referenced to the whole-image global reference plane, not a locally fitted plane.
- The display colormap is `jet` as a built-in approximation to the legacy VK look.
- The saved filenames use a `legacy_surface_roughness` suffix based on the source image name.

## Outputs And Figures Being Reviewed
### Provisional saved outputs
- `<imageName>_legacy_surface_roughness.mat`
  - full saved GUI result, including global roughness context, ROI geometry, per-ROI table, and summary values
- `<imageName>_legacy_surface_roughness.csv`
  - summary statistics (`n`, mean, and standard deviation for `Rp`, `Rv`, and `Rz`) followed by the ROI-level measurement table for spreadsheet or comparison workflows

### Provisional GUI outputs
- live ROI table:
  - ROI index
  - ROI type
  - ROI `Rp`, `Rv`, `Rz`
- live summary text:
  - global `Rp`, `Rv`, `Rz`
  - ROI count
  - mean and standard deviation of ROI `Rp`, `Rv`, `Rz`

## Promotion Criteria
Before promotion into the finalized Module 3 document, the following should be true:

- the manual placement workflow is stable and easy to use on representative datasets
- the saved ROI geometry and roughness outputs are sufficient for side-by-side comparison against current Module 3 methods
- the whole-image reference-plane interpretation is confirmed to be the correct legacy-comparison framing
- the visual behavior is close enough to the legacy VK workflow to support practical verification
- you explicitly approve finalization

## Unresolved Risks Or Competing Options
- The legacy software may have subtle ROI-placement or rendering behaviors that are not fully reproduced by a MATLAB approximation.
- A future comparison may show that a different display scaling or color mapping better matches the legacy operator experience.
- A future revision may need annotated-image export if spreadsheet-only comparison is not sufficient.
- If non-VK4 image launching becomes necessary later, the tool will need a second standalone calibration path rather than only direct VK4 loading.

## Review Notes
- Initial implementation goal is methodological comparison support, not finalized production workflow replacement.
- Promoted to finalized documentation status on 2026-05-11 after explicit approval.
- This testing document is retained as the historical record of the review and tuning phase.
