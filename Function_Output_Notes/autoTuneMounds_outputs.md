# autoTuneMounds outputs

`autoTuneMounds` searches for mound-detection parameters automatically using Bayesian optimization.

## Output

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `bestParams` | Table containing the best-performing detection parameters, mainly `gaussSigma`, `contrastMethod`, `clipLimit`, and `openRadius`. | This is not a physical surface measurement by itself; it is the tuned recipe the tool uses to turn the raw image into a mound map that should best match the underlying mound pattern. |

## Physical interpretation

This function does not describe the surface directly. Instead, it tries to find image-processing settings that make the detected mounds look most consistent with the expected self-organized mound population.
