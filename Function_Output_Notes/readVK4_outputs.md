# readVK4 outputs

`readVK4` reads a Keyence `.vk4` file and converts it into a calibrated height map plus scale information.

## Outputs

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `Z` | Calibrated height map in micrometers, zeroed to the scan floor. | This is the measured surface topography itself and is the most fundamental physical input to the rest of the pipeline. |
| `xy_um_per_px` | Lateral calibration in micrometers per pixel. | This converts in-plane pixel distances into real physical distances on the surface. |
| `total_height_um` | Full measured vertical range in micrometers. | This tells you the total z-span captured by the scan. |
| `imgH` | Image height in pixels. | This is the number of rows in the measurement grid. |
| `imgW` | Image width in pixels. | This is the number of columns in the measurement grid. |

## Physical interpretation

This function is the bridge from vendor file format to research-ready topography. Its main value is preserving full height precision so later metrics are based on the real surface instead of an 8-bit surrogate image.
