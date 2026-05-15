# autoTuneMoundsStable outputs

`autoTuneMoundsStable` searches for repeatable mound-detection parameters using scale-locked morphology and deterministic candidate selection.

## Output

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `bestParams` | Table containing the selected detection recipe: `morphScale`, `contrastMethod`, derived `gaussSigma`, derived `openRadius`, and `clipLimit`. | This is not a surface measurement by itself. It is the repeatable image-processing recipe used to convert the image into a mound-centroid map for Module 1. |

## Parameter fields

| Field | Meaning |
| --- | --- |
| `morphScale` | Shared scale multiplier used to derive both smoothing and opening size from the image-estimated mound spacing. |
| `contrastMethod` | Contrast transform used before morphology. Stable near-tie preference is `adapthisteq`, then `histeq`, then `none`. |
| `gaussSigma` | Gaussian smoothing sigma derived from `morphScale` and the estimated mound spacing. |
| `openRadius` | Morphological opening radius derived from `morphScale` and the estimated mound spacing. |
| `clipLimit` | Contrast-limited adaptive histogram equalization clip limit when applicable. |

## Physical interpretation

The stable tuner is designed to reduce run-to-run drift in the detection recipe. It treats mound count as a broad plausibility guardrail and mainly favors regular centroid spacing, then applies deterministic tie-breaking when several candidates score nearly the same.
