# pickReflectionThreshold outputs

`pickReflectionThreshold` is an interactive helper used during cavity preprocessing when reflective pixels inside pits need to be identified.

## Output

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `reflThreshold` | Intensity threshold in normalized units from 0 to 1 used to classify bright reflection pixels inside pit regions. | This controls which pit pixels are treated as reflection artifacts rather than real topography, which strongly affects cavity-floor correction. |

## Physical interpretation

This is also a preprocessing control, not a direct physical measurement. It matters because good cavity geometry depends on not mistaking optical reflections for actual raised or flat surface features.
