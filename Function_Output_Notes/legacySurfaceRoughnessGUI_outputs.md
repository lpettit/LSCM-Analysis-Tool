# legacySurfaceRoughnessGUI outputs

`legacySurfaceRoughnessGUI` is a standalone legacy-style roughness measurement tool. `SOLFAnalysisApp` also embeds an equivalent ROI workflow in its main review area when the user clicks `Legacy Roughness Measurement`.

It can be launched either from:

- a `.vk4` file path
- an existing analysis struct that already contains `Z`, `xy_um_per_px`, and `imagePath`

Its purpose is to reproduce a manual ROI-based roughness workflow for comparison against the newer Module 3 interpretation path.

The standalone function remains useful for compatibility and direct testing. The embedded app path uses the same measurement helper and saves the same `.mat` and `.csv` output pattern.

## Main behavior

The GUI:

- displays the raw height surface with a rainbow-style `jet` colormap
- lets the user place up to 20 black-outlined ROIs using:
  - `All areas`
  - `Rect.`
  - `Square`
  - `Area`
- computes `Rp`, `Rv`, and `Rz` inside each ROI relative to the whole-image reference plane
- computes the surface-area to projected-area ratio, `SA_to_A_ratio`, from a triangulated height-map surface
- shows live ROI-level and summary results
- saves a `.mat` file and a `.csv` file when the user clicks `Done`

## Saved return struct

The function returns a `results` struct and saves that same struct into:

- `<imageName>_legacy_surface_roughness.mat`

Top-level fields:

| Field | Meaning |
| --- | --- |
| `imagePath` | Source file path for the measured surface. |
| `xy_um_per_px` | Lateral calibration in micrometers per pixel. |
| `image_size_px` | Image size as `[width_px, height_px]`. |
| `image_size_um` | Physical image size as `[width_um, height_um]`. |
| `refPlane_um` | Whole-image mean height used as the global reference plane. |
| `Rp_global` | Global peak-above-reference value from the full image. |
| `Rv_global` | Global valley-below-reference value from the full image. |
| `Rz_global` | Global `Rp_global + Rv_global`. |
| `surface_area_global_um2` | Legacy-matched 3D surface area of the full height map, in square micrometers. |
| `projected_area_global_um2` | Full finite-pixel projected area used for the full-image surface-area ratio, in square micrometers. |
| `SA_to_A_ratio_global` | Full-image `surface_area_global_um2 / projected_area_global_um2`. |
| `roi_table` | Table of all stored ROI measurements and geometry. |
| `n_rois` | Number of stored ROIs included in the summary. |
| `mean_Rp_um`, `std_Rp_um` | Mean and standard deviation of ROI `Rp`. |
| `mean_Rv_um`, `std_Rv_um` | Mean and standard deviation of ROI `Rv`. |
| `mean_Rz_um`, `std_Rz_um` | Mean and standard deviation of ROI `Rz`. |
| `mean_SA_to_A_ratio`, `std_SA_to_A_ratio` | Mean and standard deviation of ROI surface-area to projected-area ratio. |
| `rois` | Stored raw ROI geometry structs used by the GUI. |
| `saved` | Logical flag indicating whether `Done` was used. |
| `saved_files` | Struct containing the saved `.mat` and `.csv` paths. |
| `gui_settings` | Saved GUI configuration such as colormap, ROI color, ROI limit, default area size, and completion timestamp. |

## ROI table fields

`roi_table` stores one row per measurement window.

| Field | Meaning |
| --- | --- |
| `ROI_Index` | Sequential ROI number in placement order. |
| `ROI_Type` | ROI type: `all_areas`, `rect`, `square`, or `area`. |
| `X_Min_px`, `X_Max_px`, `Y_Min_px`, `Y_Max_px` | Inclusive ROI bounds in pixel coordinates. |
| `Center_X_px`, `Center_Y_px` | ROI center in pixels. |
| `Width_px`, `Height_px` | ROI width and height in pixels. |
| `Center_X_um`, `Center_Y_um` | ROI center in micrometers. |
| `Width_um`, `Height_um` | ROI width and height in micrometers. |
| `Rp_um` | ROI peak-above-reference height. |
| `Rv_um` | ROI valley-below-reference depth. |
| `Rz_um` | ROI `Rp_um + Rv_um`. |
| `SurfaceArea_um2` | Legacy-matched 3D surface area of the ROI height map. |
| `ProjectedArea_um2` | Full finite-pixel projected area used for the ROI surface-area ratio. |
| `SA_to_A_ratio` | ROI `SurfaceArea_um2 / ProjectedArea_um2`. |

## CSV export layout

The saved CSV file:

- starts with a summary section
- includes:
  - `n_rois`
  - `mean_Rp_um`, `std_Rp_um`
  - `mean_Rv_um`, `std_Rv_um`
  - `mean_Rz_um`, `std_Rz_um`
  - `surface_area_global_um2`, `projected_area_global_um2`, `SA_to_A_ratio_global`
  - `mean_SA_to_A_ratio`, `std_SA_to_A_ratio`
- then appends the full `roi_table`

Saved file name:

- `<imageName>_legacy_surface_roughness.csv`

## Interpretation notes

- All ROI roughness values are referenced to the whole-image global reference plane, not a local plane fit.
- `All areas` should match the global `Rp`, `Rv`, and `Rz` values exactly.
- `SA_to_A_ratio` is dimensionless and uses the VK-matched convention selected during testing: opposite-diagonal cell facets, full finite-pixel projected area, and right/bottom edge extension.
- For a single ROI, the standard deviation fields are reported as `0`.
