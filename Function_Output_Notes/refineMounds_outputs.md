# refineMounds outputs

`refineMounds` is the user-guided follow-up to `autoTuneMounds`. It lets you adjust the detection target if the automatic detection does not look right.

## Output

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `bestParams` | Refined detection-parameter table in the same format returned by `autoTuneMounds`. | This is the user-corrected parameter set used when visual judgment says the fully automatic mound detection did not capture the real mound population well enough. |

## Physical interpretation

This function is about human-in-the-loop trust rather than a new surface metric. It gives you a controlled way to steer mound detection when the optimization objective alone is not enough.
