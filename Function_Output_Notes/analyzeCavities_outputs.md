# analyzeCavities outputs

`analyzeCavities` is Module 2. It characterizes the depressions or basins between surrounding mounds.

## Key outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `n_cavities` | Number of cavities that passed the depth threshold. | This is the count of depressions considered physically meaningful rather than shallow roughness noise. |
| `n_shallow` | Number of candidate basins rejected for being too shallow. | This helps show how much of the valley network was filtered out as insignificant. |
| `depth_um` | Depth of each cavity in micrometers. | This tells you how deep the troughs between mound structures are. |
| `r_mouth_um` | Equivalent mouth radius of each cavity. | This approximates how wide the cavity opening is at the top. |
| `beta_deg` | Cone half-angle in degrees. | This is a compact slope-like descriptor of how sharply the cavity narrows with depth. |
| `n_bounding_mounds` | Number of mound peaks surrounding each cavity. | This reflects the local topographic neighborhood and can indicate whether a cavity is embedded in a regular cell-like arrangement or an irregular one. |
| `mouth_area_um2` | Cross-sectional mouth area of the cavity in square micrometers. | This is the opening area available at the top of the depression. |
| `valley_z_um` | Valley-floor height of each cavity. | This tells you where the bottom of the cavity sits relative to the scan floor. |
| `mouth_z_um` | Mean height of the surrounding mouth boundary. | This approximates the top reference plane of the cavity opening. |
| `centroid_px` | Pixel coordinates of cavity centers. | These locate the basins on the surface. |
| `basin_label` | Label image assigning pixels to cavities. | This stores the segmented cavity regions for downstream plotting or inspection. |

## Physical interpretation

Module 2 is the depression-side complement to Module 3. It helps describe how the valleys between mounds may contribute to fluid trapping, nucleation-site behavior, and transport pathways on the processed surface.
