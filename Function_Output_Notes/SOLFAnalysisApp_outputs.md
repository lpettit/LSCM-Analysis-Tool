# SOLFAnalysisApp outputs

`SOLFAnalysisApp` is the MATLAB app wrapper around the single-file workflow.

## Public app state

| Property | What it represents | What it means physically or operationally |
| --- | --- | --- |
| `InputEditField` | Selected `.vk4` input path. | This identifies the surface being analyzed. |
| `OutputEditField` | Selected output folder. | This decides where the saved analysis products go. |
| `RunModule1CheckBox` | Whether Module 1 is enabled. | This controls whether spacing and mound-detection outputs are generated. |
| `RunModule2CheckBox` | Whether Module 2 is enabled. | This controls whether cavity geometry is analyzed. |
| `RunModule3CheckBox` | Whether Module 3 is enabled. | This controls whether mound height and shape metrics are analyzed. |
| `FillDeepPitsCheckBox` | Whether reflection pit correction is enabled. | This controls whether preprocessing treats dark reflective pits specially. |
| `FillThresholdField` | The `fillThreshold` value used when reflection correction is enabled. | This sets how aggressively the pipeline classifies dark pit regions before `autoTuneMounds`, `refineMounds`, and downstream analysis use that correction path. |
| `PickFillThresholdButton` | Launches the interactive `pickFillThreshold` helper. | This gives the user a visual way to choose the pit mask threshold instead of typing or relying on a fallback prompt at runtime. |
| `ShowAutoTunePlotsCheckBox` | Whether auto-tuning plots are shown. | This is an operational visibility setting rather than a scientific measurement. |
| `UseRefineMoundsCheckBox` | Whether to launch guided refinement after auto-tuning. | This enables extra user control if the automatic mound detection looks wrong. |
| `AutoTuneEvalsField` | Maximum optimization evaluations for `autoTuneMounds`. | This trades runtime against tuning thoroughness. |
| `DilateRadiusField` | Morphological dilation radius setting. | This affects how detected mound blobs are expanded during detection. |
| `MinObjectAreaField` | Minimum detected object area retained. | This controls how aggressively tiny features are treated as noise. |
| `MinDepthField` | Minimum cavity depth threshold for Module 2. | This sets the cutoff between meaningful cavities and shallow roughness. |
| `AnnulusInnerField` | Legacy Method A inner annulus factor for Module 3. | This affects only the legacy annulus-based valley estimate. |
| `AnnulusOuterField` | Legacy Method A outer annulus factor for Module 3. | This affects only the legacy annulus-based valley estimate. |
| `StatusTextArea` | Run-status text shown to the user. | This is operational feedback rather than a scientific output. |

## Physical interpretation

The app itself does not generate new metrics. Its role is to make the existing analysis workflow easier to run consistently without using the command window directly.
