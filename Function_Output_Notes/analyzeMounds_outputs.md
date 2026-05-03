# analyzeMounds outputs

`analyzeMounds` is Module 1. It detects mound centers and summarizes how those centers are spaced across the surface.

## Key outputs

| Field | What is measured | What it means physically |
| --- | --- | --- |
| `centroids` | Pixel coordinates of detected mound centers. | These are the anchor points for nearly every downstream analysis, so they define where the tool believes each mound lives. |
| `n_mounds` | Total number of detected mounds after filtering and border cleanup. | This is the basic mound count for the analyzed field of view. |
| `density_mm2` | Mound number density in mounds per square millimeter. | This tells you how densely the self-organized features pack the surface. |
| `nn_dist_px` | Nearest-neighbor spacings in pixels from the trimmed Delaunay graph. | This captures local mound spacing before unit conversion. |
| `nn_dist_um` | Nearest-neighbor spacings in micrometers. | This is the physically meaningful mound-to-mound spacing distribution. |
| `nn_mean_px` | Mean nearest-neighbor spacing in pixels. | This is the characteristic mound spacing on the image grid. |
| `nn_mean_um` | Mean nearest-neighbor spacing in micrometers. | This is a first-order characteristic wavelength of the self-organized mound pattern. |
| `nn_std_px` | Standard deviation of nearest-neighbor spacing in pixels. | This tells you how much the spacing fluctuates from mound to mound. |
| `nn_std_um` | Standard deviation of nearest-neighbor spacing in micrometers. | This is the physical spread of the mound spacing distribution. |
| `nn_cv` | Coefficient of variation of nearest-neighbor spacing. | This is a normalized disorder metric; lower values mean more uniform spacing and higher values mean a less regular pattern. |
| `dt` | Delaunay triangulation object for the mound centers. | This stores the neighborhood graph used to define spacing and local connectivity. |
| `trimmed_edges` | Delaunay edges kept after trimming long boundary edges. | These are the mound-to-mound connections considered trustworthy for spacing statistics. |
| `Z` | Calibrated height map in micrometers. | This is the surface topography used downstream for cavity and mound-shape analysis. |
| `I_raw` | Uint8 display image associated with the same surface. | This is the intensity-style image used by several helper and plotting routines. |
| `xy_um_per_px` | Lateral calibration in micrometers per pixel. | This converts all in-plane pixel distances into physical units. |
| `total_height_um` | Full vertical scan range in micrometers. | This gives the total available topography range for the measurement. |
| `imageName` | Input file name without extension. | This helps label outputs and maintain provenance. |
| `imagePath` | Full path to the original input file. | This preserves traceability to the raw data source. |

## Physical interpretation

Module 1 mostly answers: how many mounds are there, where are they, and how regularly are they spaced. For SOLF surfaces, those outputs are the foundation for asking whether the pattern is dense, uniform, and locally ordered.
