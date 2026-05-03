# analyzeMoundShape outputs

`analyzeMoundShape` is Module 3. It measures the height, footprint, and shape of each mound after Module 1 has already found mound centers.

This document focuses on the outputs other than the `Rp`, `Rv`, and `Rz` families, since those are already in a good spot and you asked to start with the rest first. I still list the roughness-family fields where needed for completeness.

## Big picture

The preferred interpretation in this function is:

- valley-dependent quantities come from the nearest-neighbor-radius circle ("Method B")
- footprint geometry comes from a centroid-seeded watershed partition intersected with a raw `Z_raw` half-max mask
- Voronoi-based footprint geometry is still available only as a comparison path

Physically, that means the preferred numbers are trying to describe each mound using the local space that mound actually occupies, rather than a more arbitrary annulus-based background estimate.

## Surface-level outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `n_mounds` | Number of mounds that passed the preferred Method B validity check. | This is the count of mounds that the shape module considers trustworthy enough to include in preferred reporting. |
| `n_valid_a` | Number of mounds valid under legacy Method A. | This is mainly a compatibility and diagnostic count, useful for comparing the old annulus-based approach to the newer preferred method. |
| `n_valid_nn` | Number of mounds valid under Method B nearest-neighbor-circle logic before footprint filtering. | This tells you how many mounds passed the preferred valley-definition step, even before the watershed footprint requirement is applied. |
| `n_total` | Total number of mound centroids received from Module 1. | This tells you how many candidate mounds existed before Module 3 filtered out questionable ones. |
| `preferred_method` | Text label describing the preferred measurement pathway. | This is provenance metadata so you know exactly which geometric definition was used for the preferred outputs. |
| `preferred_n_mounds` | Same preferred valid count reported explicitly in the preferred namespace. | This makes downstream reporting easier because preferred outputs stay grouped together. |
| `imageName` | Name of the analyzed image without extension. | This is traceability metadata for matching results to a file. |
| `imagePath` | Full source path of the analyzed file. | This preserves provenance and helps reproducibility. |
| `m1` | Full Module 1 results struct passed into Module 3. | This keeps the upstream mound-detection context attached to the Module 3 output. |

## Setup and reference geometry

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `annulus_inner` | Inner radius multiplier for the legacy annulus method. | This controls where the old Method A starts sampling the surrounding valley zone relative to mound spacing. |
| `annulus_outer` | Outer radius multiplier for the legacy annulus method. | This controls how far outward the old Method A looks when estimating a local valley reference. |
| `r_inner_px` | Inner annulus radius in pixels. | This is the actual image-scale realization of `annulus_inner`. |
| `r_outer_px` | Outer annulus radius in pixels. | This is the actual image-scale realization of `annulus_outer`. |
| `nn_radius_px` | Distance from each mound center to its nearest neighboring mound center, in pixels. | This is a local spacing scale, so it tells you how tightly packed each mound is and sets the preferred local neighborhood size for Method B. |
| `centroid_px` | Mound centroid locations in pixel coordinates. | These are the mound center positions used as anchors for all per-mound measurements. |
| `watershed_L` | Label image for the centroid-seeded watershed partition. | Physically, this partitions the surface using the actual smoothed topography, so mound territories follow saddles and valleys instead of simple nearest-center distance. |
| `refPlane_um` | Mean height of the raw surface, in micrometers. | This is a whole-surface reference plane; it represents the average surface level relative to the scan floor and is the baseline for several height metrics. |
| `Z_smooth` | Smoothed version of the height map used for some visualizations and comparisons. | This suppresses noise, but it is no longer the preferred basis for footprint geometry because smoothing can blur edge locations and flatten sharp features. |

## Peak and valley position outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `peak_z_um` | Peak height near each mound center in the raw height map. | This tells you how tall each mound top sits above the scan floor, independent of where you decide the local valley is. |
| `valley_z_um` | Legacy Method A valley height from the annulus region. | This is the old local valley estimate and is useful mostly for historical comparison. |
| `valley_z_nn_um` | Preferred Method B valley height from the nearest-neighbor-radius circle. | This is the preferred local valley reference because it is tied to the local mound spacing and usually better reflects the true trough surrounding that mound. |
| `preferred_peak_z_um` | Preferred alias of `peak_z_um`. | This keeps the preferred output family self-contained for downstream use. |
| `preferred_valley_z_um` | Preferred alias of `valley_z_nn_um`. | This marks the Method B valley as the default valley interpretation for reporting. |

## Height outputs other than Rp/Rv/Rz

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `mound_height_um` | Legacy Method A peak-to-valley mound height. | This is the old estimate of how far a mound rises above its local surroundings. |
| `mound_height_nn_um` | Preferred Method B peak-to-valley mound height. | This is the preferred mound elevation above the nearby trough, so it is usually the most direct geometric measure of how pronounced each mound is. |
| `preferred_mound_height_um` | Preferred alias of `mound_height_nn_um`. | This makes the preferred height easy to consume without checking legacy fields. |

## Footprint size outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `footprint_um2` | Area of the raw half-max footprint mask for each mound, in square micrometers. | This estimates how much surface area the mound occupies at half of its local peak-to-valley height, which is a practical way to describe mound width without being overly sensitive to tiny edge noise. |
| `equiv_diam_um` | Diameter of a circle with the same area as the footprint. | This converts an irregular footprint into one intuitive width number, making mound size easier to compare across surfaces. |
| `preferred_footprint_um2` | Preferred alias of `footprint_um2`. | This flags the raw half-max area as the default footprint area for reporting. |
| `preferred_equiv_diam_um` | Preferred alias of `equiv_diam_um`. | This flags the raw half-max equivalent diameter as the default width metric. |

## Watershed comparison footprint outputs

These fields are now the preferred footprint family. They use the same half-max height threshold as before, but they restrict the footprint using a centroid-seeded watershed partition. Physically, they are trying to let the topography define where one mound hands off to the next.

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `watershed_valid_flag` | Boolean flag indicating a watershed-based half-max footprint could be extracted for that mound. | This tells you whether the watershed comparison path produced a usable mound body for that feature. |
| `watershed_footprint_um2` | Watershed-restricted half-max footprint area in square micrometers. | This is the mound area you get when the lateral territory is defined by topographic basins rather than nearest-centroid distance. |
| `watershed_equiv_diam_um` | Equivalent diameter from the watershed-based footprint area. | This is the watershed-based version of mound width. |
| `watershed_aspect_ratio` | Height-to-diameter ratio using the watershed-based equivalent diameter. | This shows how slender or squat the mound looks when width is measured from the watershed footprint. |
| `watershed_perimeter_um` | Watershed-based footprint perimeter. | This tells you how long the mound boundary is when topography-following partitioning is used. |
| `watershed_circularity` | Circularity of the watershed-based footprint. | This shows how close the watershed-defined footprint is to a compact circular mound. |
| `watershed_solidity` | Solidity of the watershed-based footprint. | This captures how concave or indented the watershed-defined footprint is. |
| `watershed_convexity` | Convexity of the watershed-based footprint boundary. | This measures how smooth versus irregular the watershed-defined mound edge is. |
| `watershed_convex_area_ratio` | Convex-area comparison for the watershed-based footprint. | This is another indicator of how much the watershed-defined footprint departs from a simple convex shape. |
| `watershed_extent` | Bounding-box fill fraction for the watershed-based footprint. | This reflects how efficiently the watershed-defined footprint fills its enclosing box. |
| `watershed_major_axis_um` | Major-axis length of the watershed-based footprint. | This is the long in-plane dimension of the watershed-defined mound body. |
| `watershed_minor_axis_um` | Minor-axis length of the watershed-based footprint. | This is the short in-plane dimension of the watershed-defined mound body. |
| `watershed_feret_max_um` | Maximum Feret diameter for the watershed-based footprint. | This is the largest caliper width under watershed partitioning. |
| `watershed_feret_min_um` | Minimum Feret diameter for the watershed-based footprint. | This is the smallest caliper width under watershed partitioning. |
| `watershed_feret_aspect_ratio` | Ratio of watershed-based maximum to minimum Feret diameter. | This is a watershed-based anisotropy measure. |
| `watershed_feret_orientation_deg` | Feret-based in-plane orientation for the watershed-defined footprint. | This indicates the dominant elongation direction of the watershed-defined mound footprint. |
| `watershed_L` | Label image of the centroid-reassigned watershed partition. | This stores the topography-guided mound territories used for the watershed comparison metrics. |

## Shape anisotropy and axis outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `aspect_ratio` | Ratio of major to minor footprint dimensions from the region properties. | This tells you how elongated the mound footprint is; values near 1 mean more circular mounds, while larger values mean more stretched or directional footprints. |
| `major_axis_um` | Major-axis length of the fitted footprint ellipse. | This is the longest principal dimension of the mound footprint based on an ellipse-like approximation. |
| `minor_axis_um` | Minor-axis length of the fitted footprint ellipse. | This is the shorter principal dimension of the mound footprint and helps quantify how narrow or compressed the mound is in the orthogonal direction. |
| `preferred_major_axis_um` | Preferred alias of `major_axis_um`. | This marks the major axis as part of the preferred geometry family. |
| `preferred_minor_axis_um` | Preferred alias of `minor_axis_um`. | This marks the minor axis as part of the preferred geometry family. |

## Boundary and compactness outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `perimeter_um` | Length of the raw half-max footprint boundary, in micrometers. | This tells you how much boundary is needed to enclose the mound footprint; rougher or more irregular footprints tend to have longer perimeters for the same area. |
| `circularity` | Compactness metric based on area and perimeter, with 1 meaning a perfect circle. | This tells you how close the mound footprint is to a round, compact shape; lower values suggest elongation, lobing, or edge irregularity. |
| `extent` | Fraction of the footprint bounding box occupied by the footprint. | This indicates how efficiently the footprint fills its own bounding box; low values often point to elongated or highly irregular shapes. |
| `preferred_perimeter_um` | Preferred alias of `perimeter_um`. | This keeps the preferred footprint boundary length easy to export and summarize. |
| `preferred_circularity` | Preferred alias of `circularity`. | This keeps the preferred compactness metric grouped with the other preferred shape outputs. |
| `preferred_extent` | Preferred alias of `extent`. | This keeps the preferred box-filling measure grouped with the other preferred shape outputs. |

## Convexity and footprint integrity outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `solidity` | Ratio of footprint area to convex-hull area. | This tells you how much the footprint contains indentations or concavities; values near 1 mean a filled-in, convex footprint, while lower values suggest notches or irregular edges. |
| `convexity` | Ratio comparing the convex-hull perimeter to the actual perimeter. | This captures how jagged or indented the footprint boundary is; values near 1 mean a smoother convex outline, while lower values mean a more irregular edge. |
| `convex_area_ratio` | Ratio involving the convex-hull area relative to the footprint area. | This is another way to express how far the footprint departs from a simple convex shape, which can reflect merging, lobing, or asymmetry. |
| `preferred_solidity` | Preferred alias of `solidity`. | This keeps the preferred concavity measure grouped with the rest of the preferred morphology outputs. |
| `preferred_convexity` | Preferred alias of `convexity`. | This keeps the preferred boundary-irregularity measure grouped with the preferred morphology outputs. |
| `preferred_convex_area_ratio` | Preferred alias of `convex_area_ratio`. | This keeps the preferred convex-hull area comparison easy to summarize across mounds. |

## Feret diameter outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `feret_max_um` | Maximum caliper diameter of the footprint, in micrometers. | This is the largest tip-to-tip width the mound footprint presents when viewed from any in-plane direction. |
| `feret_min_um` | Minimum caliper diameter of the footprint, in micrometers. | This is the smallest in-plane width of the footprint and complements `feret_max_um` for anisotropy. |
| `feret_aspect_ratio` | Ratio of maximum to minimum Feret diameter. | This is a direction-independent elongation measure; values near 1 are more isotropic, while larger values indicate a stretched footprint. |
| `feret_orientation_deg` | In-plane orientation angle associated with the Feret measurement basis. | This tells you the dominant direction of footprint elongation, which may become useful when comparing mound alignment to laser scan direction or process anisotropy. |
| `preferred_feret_max_um` | Preferred alias of `feret_max_um`. | This keeps the preferred largest-width metric grouped with the rest of the preferred footprint outputs. |
| `preferred_feret_min_um` | Preferred alias of `feret_min_um`. | This keeps the preferred smallest-width metric grouped with the rest of the preferred footprint outputs. |
| `preferred_feret_aspect_ratio` | Preferred alias of `feret_aspect_ratio`. | This keeps the preferred Feret-based anisotropy measure easy to summarize surface-wide. |
| `preferred_feret_orientation_deg` | Preferred alias of `feret_orientation_deg`. | This keeps the preferred directional elongation angle available for future orientation/order analyses. |

## Validity and filtering outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `valid_flag` | Boolean flag indicating the mound passed legacy Method A checks. | This marks whether the old annulus-based measurement for that mound looked physically usable. |
| `valid_flag_nn` | Boolean flag indicating the mound passed Method B checks. | This marks whether the preferred nearest-neighbor-circle valley and half-max footprint could be measured reliably. |
| `preferred_valid_flag` | Preferred alias of `valid_flag_nn`. | This is the mask you should normally use when calculating averages or comparing per-mound preferred metrics. |

## Roughness-family fields listed for completeness

These are intentionally not expanded here in detail because you asked to skip `Rp`, `Rv`, and `Rz` explanations first:

- `Rp_per_mound`
- `Rv_per_mound`
- `Rz_a_per_mound`
- `Rv_nn_per_mound`
- `Rz_b_per_mound`
- `Rz_per_mound`
- `preferred_Rp_per_mound`
- `preferred_Rv_per_mound`
- `preferred_Rz_per_mound`
- `Rp_global`
- `Rv_global`
- `Rz_global`

## Suggested default interpretation order

If you want a short "what should I look at first?" reading order for Module 3:

1. `preferred_mound_height_um`
2. `preferred_footprint_um2`
3. `preferred_equiv_diam_um`
4. `preferred_circularity`
5. `preferred_solidity`
6. `preferred_feret_aspect_ratio`
7. `preferred_feret_orientation_deg`

That sequence moves from "how tall is the mound" to "how wide is it" to "how round or elongated is it."
