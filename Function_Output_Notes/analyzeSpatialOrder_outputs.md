# analyzeSpatialOrder outputs

`analyzeSpatialOrder` is Module 4. It takes the Module 1 `m1` struct and returns centroid-based spatial-order, spacing, Voronoi, and neighbor-shell metrics.

The current implementation is built around:

- planar sixfold bond-orientational order via `psi6`
- pair distribution / approximate `g(r)`
- Voronoi-cell area and local-density metrics
- first/second/third-neighbor spacing metrics
- interpretation-oriented local order tiers and comparison labels

## Top-level provenance

| Field | Meaning |
| --- | --- |
| `n_mounds` | Number of Module 1 centroids analyzed. |
| `imageName` | Input image/file stem. |
| `imagePath` | Source file path. |
| `m1` | Full Module 1 results struct carried through for provenance. |
| `neighbor_definition` | Current neighbor graph definition; currently `trimmed_delaunay`. |
| `order_metric` | Current orientational-order metric label; currently `psi6`. |

## Local and global orientational-order outputs

| Field | Meaning |
| --- | --- |
| `coordination_number` | Delaunay neighbor count for each mound. |
| `local_psi6` | Per-mound magnitude of planar sixfold local order. |
| `psi6_phase` | Per-mound local `psi6` phase in radians. |
| `psi6_phase_deg` | Same phase in degrees. |
| `psi6_complex` | Full complex local `psi6` value per mound. |
| `global_psi6` | Whole-field global sixfold order magnitude using all valid mounds. |
| `global_psi6_interior` | Same global metric restricted to non-boundary mounds. |
| `mean_local_psi6`, `std_local_psi6` | Whole-field mean and standard deviation of local `psi6`. |
| `median_local_psi6`, `p25_local_psi6` | Robust whole-field summaries of local `psi6`. |
| `mean_local_psi6_interior` | Interior-only mean local `psi6`. |

## Boundary and interpretation-tier outputs

These fields are interpretation helpers. The underlying `psi6` metric is physical; the category thresholds are heuristic bins used for reporting.

| Field | Meaning |
| --- | --- |
| `boundary_margin_px` | Margin used to mark mounds as boundary-affected. |
| `boundary_flag` | Boolean flag for mounds near the bounding box edge of the centroid field. |
| `interior_flag` | Boolean flag for non-boundary mounds. |
| `local_order_class` | Heuristic local order label: `boundary`, `low`, `moderate`, or `high`. |
| `local_order_score` | Numeric score for local order; currently the local `psi6` value for interior mounds. |
| `psi6_moderate_threshold` | Threshold separating low from moderate local order. |
| `psi6_high_threshold` | Threshold separating moderate from high local order. |
| `low_psi6_threshold` | Current "low" local `psi6` threshold; same as the moderate threshold boundary. |
| `non_sixfold_flag` | True when coordination number is not `6`. |
| `interior_non_sixfold_flag` | Same non-6 flag but restricted to interior mounds. |
| `low_psi6_flag`, `moderate_psi6_flag`, `high_psi6_flag` | Tiered `psi6` category flags. |
| `soft_coordination_flag` | Interior flag for more strongly non-hexatic coordination (`<5` or `>7`). |
| `disorder_flag` | Softened interior-focused disorder flag. |
| `legacy_hard_disorder_flag` | Older stricter disorder flag retained for comparison. |
| `order_level_note` | Text note documenting the current heuristic tier definitions. |

## Voronoi outputs

These use a border-aware Voronoi workflow:

- border-inclusive helper centroids are added to confine the outer ring
- final Voronoi polygons are clipped to the image rectangle
- all clipped cells are currently kept in the outputs

| Field | Meaning |
| --- | --- |
| `voronoi_valid_flag` | True when a clipped finite Voronoi polygon was successfully assigned to that mound. |
| `voronoi_clipped_flag` | True when the mound's Voronoi polygon was altered by image-border clipping. |
| `voronoi_augmented_flag` | True when the Voronoi solution used the border-inclusive augmented centroid set. |
| `voronoi_area_um2` | Clipped Voronoi cell area for each mound, in square micrometers. |
| `local_density_um2_inv` | Local density estimate from inverse Voronoi area. |
| `voronoi_added_seed_count` | Number of helper centroids added for the border-aware Voronoi construction. |
| `voronoi_polygons_px` | Clipped Voronoi polygons stored as MATLAB `polyshape` objects in pixel coordinates. |
| `voronoi_area_mean_um2`, `voronoi_area_std_um2` | Whole-field mean and standard deviation of Voronoi area. |
| `local_density_mean_um2_inv`, `local_density_std_um2_inv` | Whole-field summaries of inverse Voronoi density. |

## Neighbor-shell spacing outputs

These are full centroid-to-centroid neighbor-shell metrics computed from sorted pair distances, not just the Delaunay graph.

| Field | Meaning |
| --- | --- |
| `nn1_um` | First-neighbor distance for each mound. |
| `nn2_um` | Second-neighbor distance for each mound. |
| `nn3_um` | Third-neighbor distance for each mound. |
| `neighbor_distance_matrix_um` | Sorted full pair-distance matrix, in micrometers. |
| `nn1_mean_um`, `nn1_std_um`, `nn1_cv` | Whole-field first-neighbor summaries. |
| `nn2_mean_um`, `nn2_std_um`, `nn2_cv` | Whole-field second-neighbor summaries. |
| `nn3_mean_um`, `nn3_std_um`, `nn3_cv` | Whole-field third-neighbor summaries. |
| `edge_length_px`, `edge_length_um` | Trimmed-Delaunay bond lengths. |

## Bond-angle outputs

| Field | Meaning |
| --- | --- |
| `edge_angle_deg` | Delaunay bond orientation angles modulo `180` degrees. |
| `bond_angle_bins_deg` | Bond-angle histogram bin centers. |
| `bond_angle_counts` | Bond-angle histogram counts. |
| `bond_angle_bin_edges_deg` | Bond-angle histogram bin edges. |

## Pair-distribution outputs

These are the radial-order outputs.

| Field | Meaning |
| --- | --- |
| `pair_r_um` | Radial bin centers for approximate `g(r)`. |
| `pair_counts` | Raw unique-pair counts in each radial bin. |
| `pair_g_r` | Approximate 2D pair distribution function. |
| `pair_bin_edges_um` | Pair-distribution bin edges. |
| `pair_bin_width_um` | Pair-distribution bin width. |
| `pair_density_per_um2` | Whole-field point density used in the approximate `g(r)` normalization. |
| `first_peak_r_um` | Location of the first `g(r)` peak. |
| `first_peak_g_r` | Height of the first `g(r)` peak. |
| `radial_order_score` | Current simple radial-order strength score; `first_peak_g_r - 1`. |
| `pair_distribution_note` | Text note documenting the current practical `g(r)` normalization. |

## Comparison/label outputs

These are the compact comparison-ready outputs used to summarize a surface at a glance.

| Field | Meaning |
| --- | --- |
| `radial_order_label` | Heuristic radial-order label (`weak`, `moderate`, `strong`). |
| `orientational_order_label` | Heuristic orientational-order label (`weak`, `moderate`, `strong`). |
| `comparison_summary_line` | One-line comparison-ready text summary of radial order, orientational order, and local-tier fractions. |

## Geometry and centroid context

| Field | Meaning |
| --- | --- |
| `centroid_px` | Module 1 mound centroid coordinates used for all Module 4 calculations. |

## Saved output paths and figure handle

| Field | Meaning |
| --- | --- |
| `psi6_map_path` | Saved local `psi6` map. |
| `defect_map_path` | Saved order-tier / coordination diagnostic panel. |
| `voronoi_density_path` | Saved Voronoi/local-density diagnostic panel. |
| `voronoi_cells_path` | Saved Voronoi-cell overlay colored by cell area. |
| `voronoi_area_hist_path` | Saved Voronoi area histogram. |
| `neighbor_shells_path` | Saved neighbor-shell diagnostic panel. |
| `pair_plot_path` | Saved pair-distribution plot. |
| `bond_plot_path` | Saved bond-angle diagnostic plot. |
| `xlsx_path` | Saved Excel workbook path. |
| `tabbed_figure_handle` | Live handle to the tabbed diagnostics figure in the MATLAB session. This handle is kept in memory but not saved into the `.mat` file. |

## Workbook sheets written by analyzeSpatialOrder

The current Excel output contains:

- `PerMound`
- `PairDistribution`
- `BondAngles`
- `Voronoi`
- `NeighborShells`
- `Comparison`
- `Summary`

## Suggested default reading order

If you want a practical first-pass reading order for Module 4:

1. `comparison_summary_line`
2. `radial_order_label`
3. `orientational_order_label`
4. `first_peak_r_um`, `first_peak_g_r`, `radial_order_score`
5. `global_psi6_interior`, `mean_local_psi6_interior`
6. `nn1_cv`, `nn2_cv`, `nn3_cv`
7. `voronoi_area_mean_um2`, `local_density_mean_um2_inv`
8. `local_order_class`, `boundary_flag`, `voronoi_clipped_flag`

That moves from "how should I describe this surface quickly?" into "what spacing and order metrics support that description?" and finally into "which mounds/cells are driving the behavior?".
