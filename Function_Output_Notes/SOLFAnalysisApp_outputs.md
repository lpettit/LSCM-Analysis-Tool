# SOLFAnalysisApp outputs

`SOLFAnalysisApp` is the MATLAB app wrapper around the single-file workflow.

## Public app state

| Property | What it represents | What it means physically or operationally |
| --- | --- | --- |
| `InputEditField` | Selected `.vk4` input path. | This identifies the surface being analyzed. |
| `OutputEditField` | Selected output folder. | This decides where the saved analysis products go. |
| `BestParamsEditField` | Optional selected `bestParams.mat` path. | This lets the app unlock downstream analysis modules after mound detection has already been completed. |
| `MoundDetectionButton` | Starts the Module 1 mound-detection GUI workflow. | This controls access to stable automatic tuning and guided mound-count refinement. |
| `CavityAnalysisButton` | Placeholder for Module 2 workflow access. | This remains disabled while cavity-analysis GUI behavior is still under testing. |
| `MoundSurfaceButton` | Starts future Module 3 mound/surface analysis workflow access. | This is enabled only after both a VK4 and valid `bestParams.mat` are selected. |
| `SpatialAnalysisButton` | Starts future Module 4 spatial-analysis workflow access. | This is enabled only after both a VK4 and valid `bestParams.mat` are selected. |
| `LegacyRoughnessButton` | Starts future legacy roughness workflow access. | This is enabled for VK4-only workflows but its full GUI path is deferred. |
| `FillDeepPitsCheckBox` | Whether reflection pit correction is enabled for mound detection. | This controls whether preprocessing treats dark reflective pits specially. |
| `FillThresholdField` | The `fillThreshold` value used when reflection correction is enabled. | This sets how aggressively the pipeline classifies dark pit regions before `autoTuneMounds`, `refineMounds`, and downstream analysis use that correction path. |
| `PickFillThresholdButton` | Launches the interactive `pickFillThreshold` helper. | This gives the user a visual way to choose the pit mask threshold instead of typing or relying on a fallback prompt at runtime. |
| `MaxEvalsField` | Maximum initial optimization evaluations for GUI mound detection. | This trades Tier 1 runtime against tuning thoroughness; it defaults to `60`. |
| `RunMoundDetectionButton` | Runs Tier 1 stable mound detection in the GUI workflow. | This begins the user-reviewed parameter selection process. |
| `ReviewTabGroup` | In-app tab set containing mound-detection review attempts. | Each tab shows a centroid overlay and spacing histogram for one refinement result. |
| `DoneButton` | Accepts the current mound-detection result. | This saves `bestParams.mat` to the selected output folder. |
| `TooFewButton` | Applies "too few mounds" feedback. | This nudges the target count upward and reruns stable refinement. |
| `TooManyButton` | Applies "too many mounds" feedback. | This nudges the target count downward and reruns stable refinement. |
| `ManualCountField` | User-entered expected mound count. | This provides a direct Tier 3 count target. |
| `ManualCountButton` | Runs manual-count refinement. | This reruns stable refinement using the entered count as the target. |
| `StatusTextArea` | Run-status and optimization log text shown to the user. | This is operational feedback rather than a scientific output. |

## Physical interpretation

The app itself does not generate new metrics. Its role is to make the existing analysis workflow easier to run consistently without using the command window directly.
