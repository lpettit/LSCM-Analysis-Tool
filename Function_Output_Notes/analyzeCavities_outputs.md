# analyzeCavities outputs

`analyzeCavities` is Module 2. In its current testing-phase rework, it targets inclusive **inter-mound boiling cavities** rather than generic watershed basins.

The cavity objects are built from mound-defined Delaunay triangle neighborhoods, then merged when neighboring triangles support the same physical depression.

## Key outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `n_cavities` | Number of accepted inter-mound cavities that passed the depth threshold. | This is the current count of physically meaningful depressions attributed to the mound field. |
| `n_shallow` | Number of merged cavity candidates rejected for being too shallow or weak. | This helps show how many provisional depressions were not retained in the final cavity set. |
| `depth_um` | Depth from the accepted mouth level to the robust cavity floor. | This is the effective cavity depth used for the boiling-oriented geometry model. |
| `floor_z_um` | Robust floor height of each cavity. | This is the local cavity-bottom reference level, using a small floor patch rather than only one minimum pixel. |
| `mouth_z_um` | Accepted mouth or opening height of each cavity. | This is the top reference level used for the effective cavity opening. |
| `mouth_area_um2` | Area of the accepted mouth cross-section. | This is the current best estimate of the opening area for the surface-accessible cavity. |
| `mouth_equiv_radius_um` | Equivalent radius derived from `mouth_area_um2`. | This is the radius of a circle with the same area as the accepted mouth cross-section. |
| `mouth_equiv_diameter_um` | Equivalent diameter derived from `mouth_area_um2`. | This is the corresponding equivalent opening diameter. |
| `mouth_inscribed_radius_um` | Largest inscribed radius fully contained inside the accepted mouth mask. | This is a conservative opening-size descriptor that guarantees fit inside the measured opening. |
| `cone_half_angle_deg` | Effective cone half-angle from equivalent radius and depth. | This is a compact descriptor of how open or steep the cavity is under the current cone-like approximation. |
| `cone_fit_rmse_um` | Fit-error summary for the cone-like approximation. | This helps show whether the cavity geometry is close to the simple effective cone model or more irregular. |
| `persistence_um` | Local significance or persistence-style height span. | This measures how much vertical relief the candidate cavity has before it merges into surrounding terrain, helping suppress roughness-scale minima. |
| `independent_relief_um` | Relief of the surviving cavity minimum above its nearest swallowing saddle test. | This helps distinguish minima that survived consolidation from weak sub-minima that should be absorbed into a broader cavity. |
| `n_supporting_triangles` | Number of Delaunay triangles merged into the final cavity object. | This shows whether the cavity was localized to one triangle or spanned a broader inter-mound region. |
| `supporting_triangle_idx` | Triangle indices supporting each cavity. | This preserves which mound-neighborhood candidates contributed to the final cavity object. |
| `bounding_mound_idx` | Mound centroid indices supporting each cavity. | This identifies which mounds define the inter-mound cavity neighborhood. |
| `n_bounding_mounds` | Number of supporting mounds for each cavity. | This gives a compact count of the mound neighborhood around the cavity. |
| `cavity_support_type` | Support classification such as `single_triangle`, `merged_two_triangle`, or `merged_multi_triangle`. | This shows how much candidate merging was needed to define the final cavity. |
| `cavity_enclosure_type` | Enclosure classification such as `enclosed`, `semi_enclosed`, or `open_trough_like`. | This indicates whether the depression looks more like a pocketed cavity or a more open inter-mound trough. |
| `cavity_quality_flag` | Quality and caution flags for each cavity. | This summarizes issues such as reflection sensitivity, irregular mouths, open geometry, or poor cone fit. |
| `centroid_px` | Pixel coordinates of accepted cavity centroids. | These locate the final cavity objects on the surface. |
| `floor_px` | Pixel coordinates of the accepted floor location. | These locate the deepest accepted point used to anchor the cavity geometry. |
| `raw_minimum_px` | Pixel coordinates of the raw minimum associated with the accepted cavity record. | This preserves which local minimum survived the consolidation step. |
| `n_raw_minima` | Number of raw minima detected inside the merged support region. | This helps show how much local substructure existed before consolidation. |
| `n_surviving_minima_in_group` | Number of minima that remained after saddle-based consolidation in that merged support region. | This indicates whether one merged support region produced multiple distinct cavity minima. |
| `minimum_saddle_um` | Saddle height associated with the local minimum consolidation decision. | This is the reference height used to judge whether a local minimum had enough independent relief to survive. |
| `is_inpainted` | Whether the cavity support region includes reflection-corrected pixels. | This warns that part of the local geometry depended on artifact correction. |
| `cavity_label` | Label image of accepted cavity objects. | This stores the final cavity segmentation for plotting and review. |
| `triangle_support_label` | Label image of the triangle-candidate support map. | This stores which Delaunay triangle originally proposed each local neighborhood. |
| `cavity_smooth_sigma_px` | Gaussian smoothing sigma used for the cavity-analysis height map, in pixels. | This records how much lateral smoothing was applied before candidate and mouth detection. |
| `cavity_spacing_px` | Representative mound spacing used to scale cavity smoothing, in pixels. | This is the spacing reference used to choose the smoothing level. |
| `cavity_smooth_sigma_over_spacing` | Ratio of smoothing sigma to representative spacing. | This makes it easier to compare smoothing aggressiveness across surfaces with different mound spacing. |

## Mouth-comparison outputs

These testing-phase fields expose the two mouth-definition methods currently being compared:

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `mouth_z_highest_valid_um` | Mouth height from the highest admissible contour. | This is the largest contour level that still passed the local cavity-validity checks. |
| `mouth_area_highest_valid_um2` | Mouth area from the highest admissible contour. | This is the opening area under the Method A mouth definition. |
| `depth_highest_valid_um` | Depth using the highest admissible contour. | This is the corresponding cavity depth under Method A. |
| `cone_half_angle_highest_valid_deg` | Cone half-angle using the highest admissible contour. | This is the Method A cone-like opening descriptor. |
| `mouth_z_plateau_top_um` | Mouth height from the top of the stability plateau. | This is the current Method B mouth definition, based on the highest stable admissible contour band. |
| `mouth_area_plateau_top_um2` | Mouth area from the plateau-top contour. | This is the opening area under Method B. |
| `depth_plateau_top_um` | Depth using the plateau-top contour. | This is the corresponding cavity depth under Method B. |
| `cone_half_angle_plateau_top_deg` | Cone half-angle using the plateau-top contour. | This is the Method B cone-like opening descriptor. |
| `contour_level_history_um` | Swept contour levels tested for this cavity. | This stores the contour-height history used in the mouth comparison logic. |
| `contour_area_history_px` | Component area at each swept contour level. | This helps evaluate how the local cavity region grew as the contour level rose. |
| `contour_candidate_flag` | Whether each swept level qualified as a mouth candidate level. | This indicates where the contour first began satisfying the local boundary-contact rule. |
| `contour_admissible_flag` | Whether each swept level passed the full admissibility checks. | This shows which contour levels remained isolated and cavity-like enough to be retained. |
| `method_compare_n_different` | Number of accepted cavities where the two mouth methods produced different results. | This is the direct count of real method disagreements on that surface. |
| `method_compare_fraction_different` | Fraction of accepted cavities where the two mouth methods differed. | This helps show whether the plateau method is meaningfully distinct or mostly collapsing to the highest admissible contour. |
| `method_compare_different_idx` | Indices of accepted cavities where the two methods differed. | This lets you jump directly to the differing cavity records for review. |
| `method_compare_abs_mouth_delta_um` | Per-cavity absolute difference in mouth height between the two methods. | This quantifies the mouth-height disagreement cavity by cavity. |
| `method_compare_abs_depth_delta_um` | Per-cavity absolute difference in depth between the two methods. | This quantifies the depth disagreement cavity by cavity. |
| `method_compare_max_abs_mouth_delta_um` | Maximum absolute mouth-height difference on the surface. | This is a compact worst-case summary of method divergence. |
| `method_compare_median_abs_mouth_delta_um` | Median absolute mouth-height difference on the surface. | This is a compact typical-case summary of method divergence. |
| `method_compare_max_abs_depth_delta_um` | Maximum absolute depth difference on the surface. | This is the worst-case depth disagreement between the two mouth methods. |
| `method_compare_median_abs_depth_delta_um` | Median absolute depth difference on the surface. | This is the typical depth disagreement between the two mouth methods. |

## Compatibility aliases

These fields are still returned for downstream compatibility:

| Field | Current meaning |
| --- | --- |
| `r_mouth_um` | Alias of `mouth_equiv_radius_um`. |
| `beta_deg` | Alias of `cone_half_angle_deg`. |
| `valley_z_um` | Alias of `floor_z_um`. |
| `basin_label` | Alias of `cavity_label`. |

## Physical interpretation

This testing-phase rework is meant to describe **surface-accessible inter-mound boiling cavities**. It is more inclusive than a conservative closed-pocket-only approach, so some accepted features may be semi-open or trough-like and should be interpreted together with:

- `cavity_enclosure_type`
- `cavity_support_type`
- `persistence_um`
- `cavity_quality_flag`

This method does **not** infer hidden undercut or re-entrant geometry below the visible LSCM surface. It reports an effective cavity geometry based on the measured topography.

## Current contour-construction note

In the current testing-phase workflow:

- candidate minima and contour levels are still selected from a lightly smoothed height map
- the final accepted mouth mask is then rebuilt on raw `Z` within the local cavity support region before area, equivalent radius, inscribed radius, and plotted mouth boundary are finalized

So the smooth map still stabilizes cavity topology, but the reported final mouth geometry is no longer taken directly from the smoothed contour mask alone.
