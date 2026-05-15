# refineMoundsStable outputs

`refineMoundsStable` is the user-guided follow-up to `autoTuneMoundsStable`. It keeps the stable scale-locked parameter logic while letting visual review correct automatic mound detection.

## Output

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `bestParams` | Refined detection-parameter table containing `morphScale`, `contrastMethod`, derived `gaussSigma`, derived `openRadius`, and `clipLimit`. | This is the user-corrected stable parameter set used when the fully automatic result does not capture the visually supported mound population well enough. |

## Diagnostic figures

| Diagnostic | What it shows | How to use it |
| --- | --- | --- |
| centroid overlay | Detected mound centers over the image during refinement. | Check whether manual count feedback improves actual centroid placement, not just total count. |
| nearest-neighbor histogram | Local spacing distribution for the current candidate. | Check whether a count correction creates a plausible spacing distribution. |

## Physical interpretation

This function is about controlled human-in-the-loop correction. It does not create a new physical metric; it selects a more trustworthy mound-detection recipe for `analyzeMounds`.
