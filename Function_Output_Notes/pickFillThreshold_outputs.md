# pickFillThreshold outputs

`pickFillThreshold` is an interactive helper used when deep reflective pits need correction.

## Output

| Output | What is measured | What it means physically |
| --- | --- | --- |
| `fillThreshold` | Intensity threshold in normalized units from 0 to 1 used to define pit regions. | This controls which dark regions are treated as deep pits during preprocessing, so it determines where the algorithm believes reflection-related artifacts live. |

## Physical interpretation

This is not a surface metric. It is a user-selected preprocessing control that decides how aggressively the pipeline separates mound surface from deep pit regions.
