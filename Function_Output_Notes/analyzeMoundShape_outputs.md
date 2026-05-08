# analyzeMoundShape outputs

`analyzeMoundShape` is Module 3. It takes the Module 1 `m1` struct and returns per-mound height, base, footprint, shape, orientation, and diagnostic outputs.

This note reflects the current code output fields, with emphasis on the preferred interpretation path.

## Preferred interpretation

The current preferred path is:

- valley-dependent roughness uses Method B nearest-neighbor-circle logic
- direct mound height uses the watershed-contained peak plus the Method C watershed-boundary base
- footprint/body-shape geometry uses the watershed-restricted `Q50` half-max definition

So in most downstream work, the fields starting with `preferred_...` are the main ones to use first.

## Top-level counts and provenance

| Field | Meaning |
| --- | --- |
| `n_mounds` | Count of mounds passing the preferred Method B validity path. |
| `n_valid_nn` | Number of mounds valid under Method B nearest-neighbor-circle logic. |
| `n_valid_c` | Number of mounds valid for the Method C base-position / direct-height path. |
| `n_total` | Total number of Module 1 centroid candidates passed into Module 3. |
| `preferred_n_mounds` | Preferred valid mound count repeated in the preferred namespace. |
| `preferred_method` | Current preferred footprint/body-shape definition label. |
| `imageName` | Input image/file stem. |
| `imagePath` | Source file path. |
| `m1` | Full Module 1 results struct carried through for provenance. |

## Global roughness/reference outputs

| Field | Meaning |
| --- | --- |
| `refPlane_um` | Whole-image mean `Z_raw` reference plane. |
| `Rp_global` | Global peak-above-reference height. |
| `Rv_global` | Global valley-below-reference depth. |
| `Rz_global` | Global `Rp + Rv`. |
| `Z_smooth` | Smoothed height map used in watershed selection/diagnostics. |

## Whole-image height-slice morphology outputs

These are whole-surface curves derived from thresholding the raw height map with `Z_raw >= z`.
For the perimeter curve, image-frame border segments are excluded so the scan boundary does not contribute artificial perimeter.

| Field | Meaning |
| --- | --- |
| `whole_image_slice_z_um` | Absolute height levels used for the whole-image slice curves. |
| `whole_image_slice_z_rel_um` | Same height levels expressed relative to the global reference plane, `z - refPlane_um`. |
| `whole_image_slice_z_from_rv_um` | Same height levels re-expressed on a `0` to mean preferred `Rz` axis, where `0` is the mean preferred circle-method valley side and the upper bound is the mean preferred circle-method `Rz`. |
| `whole_image_cross_section_area_um2` | Projected cross-sectional area of all above-threshold islands at each height level. |
| `whole_image_perimeter_um` | Full summed perimeter of all above-threshold islands at each height level, excluding artificial image-border segments. |
| `whole_image_cumulative_surface_area_um2` | Bottom-up cumulative true 3D surface area up to each height cutoff. |
| `whole_image_cumulative_surface_area_fraction` | Normalized cumulative surface-area curve, scaled to `1` at the full-surface total. |
| `whole_image_mean_preferred_rv_um` | Mean preferred circle-method `Rv` used to shift `z_rel` into the `0` to `Rz` plotting axis. |
| `whole_image_mean_preferred_rz_um` | Mean preferred circle-method `Rz` used as the span of the `0` to `Rz` plotting row. |
| `whole_image_rz_span_um` | Alias of the mean preferred circle-method `Rz` used for the `0` to `Rz` plotting row. |
| `whole_image_peak_perimeter_um` | Maximum value of the whole-image perimeter curve. |
| `whole_image_z_at_peak_perimeter_um` | Absolute height where the perimeter curve reaches its maximum. |
| `whole_image_z_rel_at_peak_perimeter_um` | Reference-plane-relative height where the perimeter curve reaches its maximum. |
| `whole_image_z_from_rv_at_peak_perimeter_um` | Peak-perimeter location on the `0` to mean preferred `Rz` plotting axis. |
| `whole_image_cross_section_area_at_peak_perimeter_um2` | Cross-sectional area at the peak-perimeter height. |
| `whole_image_z_at_half_area_um` | Absolute height where cross-sectional area first drops to half of its low-threshold value. |
| `whole_image_z_rel_at_half_area_um` | Reference-plane-relative height where cross-sectional area first drops to half of its low-threshold value. |
| `whole_image_z_from_rv_at_half_area_um` | Half-area location on the `0` to mean preferred `Rz` plotting axis. |

## Peak, valley, and base outputs

| Field | Meaning |
| --- | --- |
| `peak_z_um` | Raw peak height near each mound centroid. |
| `centroid_peak_z_um` | Raw local peak from the centroid neighborhood window. |
| `centroid_peak_Rp_um` | `Rp` from the centroid-neighborhood peak. |
| `watershed_peak_z_um` | Highest raw-height pixel inside each mound watershed region. |
| `watershed_peak_rowcol_px` | Pixel row/column of the watershed peak. |
| `watershed_peak_Rp_um` | `Rp` recomputed from the watershed peak. |
| `Rp_minus_watershed_peak_Rp_um` | Difference between centroid-neighborhood and watershed-peak `Rp`. |
| `valley_z_nn_um` | Preferred Method B local valley height. |
| `valley_z_c_um` | Method C watershed-boundary base height. |
| `mound_base_z_um` | Preferred alias of the Method C base height. |
| `mound_base_position_um` | Preferred base position relative to the global reference plane. |
| `mound_base_valid_flag` | Validity flag for the preferred mound-base definition. |
| `method_c_band_width_px` | Width of the Method C base band; currently `2` pixels. |
| `method_c_watershed_border_mask` | Full-image mask of the watershed-border pixels used by Method C. |
| `method_c_base_band_label_img` | Labeled image of Method C base-band membership. |
| `method_c_base_samples_um` | Stored raw Method C base-band samples by mound. |
| `method_c_base_samples_percentile_um` | Stored percentile summaries of Method C base-band samples. |
| `method_c_clean_boundary_mask` | Cleaned local boundary mask used in Method C processing. |
| `method_b_skip_reason`, `method_c_skip_reason` | Per-mound text reasons for why the Method B or Method C path was rejected. |
| `method_b_circle_mask` | Local stored nearest-neighbor-radius circle masks used by Method B. |
| `method_b_crop_boxes` | Bounding boxes for the Method B local windows. |
| `method_c_base_band_mask` | Local stored Method C base-band masks by mound. |
| `method_c_boundary_band_boxes` | Bounding boxes for the Method C watershed-boundary windows. |
| `footprint_mask_q50_halfmax` | Local stored preferred `Q50` half-max footprint masks by mound. |

## Direct height outputs

| Field | Meaning |
| --- | --- |
| `mound_height_um` | Preferred direct mound height using watershed peak + Method C base position. |
| `mound_height_c_um` | Explicit Method C form of direct mound height. |
| `mound_height_nn_um` | Method B peak-to-valley span based on the nearest-neighbor-radius circle. |
| `preferred_mound_height_um` | Preferred alias of `mound_height_um`. |
| `preferred_mound_base_z_um` | Preferred alias of `mound_base_z_um`. |
| `preferred_mound_base_position_um` | Preferred alias of `mound_base_position_um`. |
| `method_c_mound_height_um` | Explicit Method C mound-height alias. |
| `method_c_base_z_um` | Explicit Method C base-height alias. |
| `method_c_base_position_um` | Explicit Method C base-position alias. |

## Percentile/base-family direct height outputs

These are the "open / typical / crowded" direct-height interpretations built from percentile-style local base positions.

| Field | Meaning |
| --- | --- |
| `base_q10_z_um`, `base_q50_z_um`, `base_q90_z_um` | Absolute base heights for the open-side / typical / crowded-side interpretations. |
| `base_q10_position_um`, `base_q50_position_um`, `base_q90_position_um` | Reference-plane-relative base positions for those same interpretations. |
| `height_open_um` | Peak above the open-side base. |
| `height_typical_um` | Peak above the typical base. |
| `height_crowded_um` | Peak above the crowded-side base. |
| `height_open_valid_flag`, `height_typical_valid_flag`, `height_crowded_valid_flag` | Validity flags for these direct-height families. |
| `height_open_mean_um`, `height_open_std_um` | Surface-wide summary of `height_open_um`. |
| `height_typical_mean_um`, `height_typical_std_um` | Surface-wide summary of `height_typical_um`. |
| `height_crowded_mean_um`, `height_crowded_std_um` | Surface-wide summary of `height_crowded_um`. |

## Roughness-family outputs

| Field | Meaning |
| --- | --- |
| `Rp_per_mound` | Per-mound `Rp` using the centroid-neighborhood peak definition. |
| `Rv_nn_per_mound` | Preferred Method B `Rv`. |
| `Rz_b_per_mound` | Preferred Method B `Rz`. |
| `Rv_c_per_mound` | Method C base-position magnitude. |
| `Rz_c_per_mound` | Method C direct-height span. |
| `Rz_per_mound` | Current preferred per-mound `Rz` alias. |
| `preferred_peak_z_um` | Preferred alias of `peak_z_um`. |
| `preferred_valley_z_um` | Preferred alias of `valley_z_nn_um`. |
| `preferred_Rp_per_mound` | Preferred alias of `Rp_per_mound`. |
| `preferred_Rv_per_mound` | Preferred alias of `Rv_nn_per_mound`. |
| `preferred_Rz_per_mound` | Preferred alias of `Rz_b_per_mound`. |
| `method_c_Rv_per_mound` | Explicit Method C base-position magnitude. |
| `method_c_Rz_per_mound` | Explicit Method C direct-height span. |

## Preferred footprint/body-shape outputs

These are the main per-mound shape outputs to use first. In the current code, the top-level footprint fields and the preferred footprint fields both point to the watershed-restricted `Q50` half-max geometry.

| Field | Meaning |
| --- | --- |
| `footprint_um2` | Preferred watershed-restricted `Q50` half-max footprint area. |
| `equiv_diam_um` | Equivalent-diameter width from the preferred footprint area. |
| `aspect_ratio` | Preferred aspect-ratio field for the main footprint/body-shape path. |
| `perimeter_um` | Preferred footprint perimeter. |
| `circularity` | Preferred footprint circularity. |
| `solidity` | Preferred footprint solidity. |
| `convexity` | Preferred footprint convexity. |
| `convex_area_ratio` | Preferred convex-area comparison metric. |
| `extent` | Preferred bounding-box fill fraction. |
| `major_axis_um`, `minor_axis_um` | Preferred ellipse major/minor axes. |
| `feret_max_um`, `feret_min_um` | Preferred maximum/minimum Feret diameters. |
| `feret_aspect_ratio` | Preferred Feret anisotropy. |
| `feret_orientation_deg` | Preferred Feret orientation angle. |
| `ellipse_orientation_deg` | Preferred ellipse orientation angle. |
| `ellipse_axis_ratio` | Preferred ellipse major/minor ratio. |
| `orientation_deg` | Current preferred orientation field; same direction as Feret max. |
| `orientation_method` | Current preferred orientation method label. |
| `orientation_agreement_deg` | Agreement between Feret and ellipse orientations. |
| `orientation_reliable_flag` | Reliability flag for the orientation estimate. |
| `surface_area_um2` | Preferred mound surface area on the watershed-restricted body. |
| `peak_cap_empty_volume_um3` | Preferred peak-cap empty-volume metric. |
| `surface_area_to_volume_inv_um` | Preferred surface-area-to-volume inverse scale. |

## Watershed and explicit Q50 half-max aliases

These fields repeat the same preferred footprint/body-shape family under more explicit namespaces.

| Field group | Meaning |
| --- | --- |
| `watershed_*` | Watershed-restricted footprint/body-shape fields. |
| `*_q50_halfmax*` | Explicit `Q50` half-max aliases of the same preferred watershed-restricted footprint/body-shape fields. |
| `valid_flag_q50_halfmax` | Validity flag for the preferred `Q50` half-max footprint path. |
| `watershed_valid_flag` | Validity flag for the watershed footprint path. |

Examples include:

- `watershed_footprint_um2`, `watershed_equiv_diam_um`
- `watershed_perimeter_um`, `watershed_circularity`, `watershed_solidity`
- `watershed_major_axis_um`, `watershed_minor_axis_um`
- `watershed_feret_max_um`, `watershed_feret_min_um`, `watershed_feret_aspect_ratio`
- `watershed_feret_orientation_deg`, `watershed_ellipse_orientation_deg`
- `watershed_surface_area_um2`, `watershed_peak_cap_empty_volume_um3`
- `footprint_q50_halfmax_um2`, `equiv_diam_q50_halfmax_um`, etc.

## Preferred aliases for geometry

The preferred namespace repeats the main geometry fields for easier downstream export:

- `preferred_footprint_um2`
- `preferred_equiv_diam_um`
- `preferred_aspect_ratio`
- `preferred_perimeter_um`
- `preferred_circularity`
- `preferred_solidity`
- `preferred_convexity`
- `preferred_convex_area_ratio`
- `preferred_extent`
- `preferred_major_axis_um`
- `preferred_minor_axis_um`
- `preferred_feret_max_um`
- `preferred_feret_min_um`
- `preferred_feret_aspect_ratio`
- `preferred_feret_orientation_deg`
- `preferred_ellipse_orientation_deg`
- `preferred_ellipse_axis_ratio`
- `preferred_orientation_deg`
- `preferred_orientation_method`
- `preferred_orientation_agreement_deg`
- `preferred_orientation_reliable_flag`
- `preferred_surface_area_um2`
- `preferred_peak_cap_empty_volume_um3`
- `preferred_surface_area_to_volume_inv_um`

There are also several preferred height-to-width aspect-ratio variants:

- `preferred_aspect_ratio_equiv_diameter`
- `preferred_aspect_ratio_ellipse_major`
- `preferred_aspect_ratio_ellipse_minor`
- `preferred_aspect_ratio_geometric_mean_width`
- `preferred_aspect_ratio_feret_max`
- `preferred_aspect_ratio_feret_min`

## Mass-centroid and lift-out outputs

| Field | Meaning |
| --- | --- |
| `mass_centroid_x_px`, `mass_centroid_y_px`, `mass_centroid_z_um` | 3D mass-centroid location inside each mound body. |
| `mass_centroid_x_um`, `mass_centroid_y_um` | Lateral mass-centroid coordinates in micrometers. |
| `mass_centroid_valid_flag` | Validity flag for the mass-centroid path. |
| `centroid_axis_base_z_um`, `centroid_axis_top_z_um` | Base/top values used along the centroid axis in lift-out style diagnostics. |
| `liftout_mound_indices` | Mound indices selected for the 3D lift-out diagnostics. |

## Watershed-selection and diagnostic geometry outputs

| Field | Meaning |
| --- | --- |
| `watershed_L` | Final centroid-reassigned watershed label image. |
| `watershed_seed_centroids_px` | Seed centroids used in the watershed partition. |
| `added_edge_seed_centroids_px` | Additional edge seeds added to stabilize the watershed near image borders. |
| `augmented_watershed_seed_ok` | Whether edge-inclusive reseeding succeeded without falling back. |
| `augmented_watershed_seed_reason` | Fallback reason or status message from the augmented-seed builder. |
| `watershed_smooth_sigma_px` | Chosen smoothing sigma for watershed partitioning. |
| `watershed_spacing_px` | Representative mound spacing used to scale the watershed heuristic. |
| `watershed_sigma_candidates_px` | Candidate sigmas evaluated. |
| `watershed_selection_score` | Best scalar score from the watershed-smoothing selection heuristic. |
| `watershed_sigma_scores` | Scores for the candidate sigmas. |
| `watershed_sigma_metrics` | Detailed metrics used to score the candidates. |
| `watershed_region_boxes` | Bounding boxes for each watershed region. |

## Main validity flags

| Field | Meaning |
| --- | --- |
| `valid_flag_nn` | Method B validity mask. |
| `valid_flag_c` | Method C validity mask. |
| `watershed_valid_flag` | Watershed footprint validity mask. |
| `preferred_valid_flag` | Main mask to use for preferred per-mound reporting. |

## Workbook visibility notes

The Excel workbook now exposes the most useful lightweight diagnostics directly:

- `PerMound` includes `Valid_Preferred`, `SkipReason_B`, and `SkipReason_C`
- `WholeImageSlices` stores the new whole-image height-slice curves using absolute `z`, reference-plane-relative `z_rel`, and the derived `0` to mean preferred `Rz` axis
- `Summary` includes watershed-selection provenance such as smoothing sigma, spacing, added-seed count, and augmented-seed status
- `Summary` also includes whole-image slice descriptors such as peak-perimeter height, half-area height, and cumulative-surface-area fractions
- `Diagnostics` is a compact run-level sheet for quick QA / provenance review

The heavier mask-style diagnostics remain in the MATLAB struct only:

- `method_b_circle_mask`
- `method_c_base_band_mask`
- `footprint_mask_q50_halfmax`
- `method_c_clean_boundary_mask`

## Suggested default reading order

If you want a practical first-pass reading order for Module 3, start with:

1. `preferred_mound_height_um`
2. `preferred_mound_base_position_um`
3. `preferred_footprint_um2`
4. `preferred_equiv_diam_um`
5. `preferred_circularity`
6. `preferred_solidity`
7. `preferred_feret_aspect_ratio`
8. `height_open_um`, `height_typical_um`, `height_crowded_um`

That moves from "how tall and where is the base?" into "how wide is it?" and then into "how round, compact, or elongated is it?".
