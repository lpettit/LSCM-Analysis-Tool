# SOLFAnalysisApp outputs

`SOLFAnalysisApp` is the MATLAB app wrapper around the single-file workflow.

## Public app state

| Property | What it represents | What it means physically or operationally |
| --- | --- | --- |
| `InputEditField` | Selected `.vk4` input path. | This identifies the surface being analyzed. |
| `OutputEditField` | Selected output folder. | This decides where the saved analysis products go. |
| `BestParamsEditField` | Optional selected `bestParams_<imageName>.mat` path. | This lets the app unlock downstream analysis modules after mound detection has already been completed. |
| `MoundDetectionButton` | Starts the Module 1 mound-detection GUI workflow. | This controls access to stable automatic tuning and guided mound-count refinement. |
| `CavityAnalysisButton` | Placeholder for Module 2 workflow access. | This remains disabled while cavity-analysis GUI behavior is still under testing. |
| `MoundSurfaceButton` | Starts the GUI Module 3 mound/surface analysis workflow. | This is enabled only after a VK4 and its matching `bestParams_<imageName>.mat` are selected. |
| `SpatialAnalysisButton` | Starts future Module 4 spatial-analysis workflow access. | This is enabled only after both a VK4 and valid detection parameters are selected. |
| `LegacyRoughnessButton` | Opens the embedded legacy roughness ROI workflow. | This is enabled for VK4-only workflows and displays the manual roughness tool in the main review area. |
| analysis-switch save prompt | Prompt shown when switching modules with unsaved analysis results. | The user can save, continue without saving, or cancel the module switch. |
| `FillDeepPitsCheckBox` | Whether reflection pit correction is enabled for mound detection. | This controls whether preprocessing treats dark reflective pits specially. |
| `FillThresholdField` | The `fillThreshold` value used when reflection correction is enabled. | This sets how aggressively the pipeline classifies dark pit regions before `autoTuneMounds`, `refineMounds`, and downstream analysis use that correction path. |
| `PickFillThresholdButton` | Launches the interactive `pickFillThreshold` helper. | This gives the user a visual way to choose the pit mask threshold instead of typing or relying on a fallback prompt at runtime. |
| `MaxEvalsField` | Maximum initial optimization evaluations for GUI mound detection. | This trades Tier 1 runtime against tuning thoroughness; it defaults to `60`. |
| `RunMoundDetectionButton` | Runs Tier 1 stable mound detection in the GUI workflow. | This begins the user-reviewed parameter selection process. |
| `MoundSpacingCheckBox` | Selects the Module 1 spacing context tab for the Module 3 GUI workflow. | This shows mound count, density, nearest-neighbor spacing, Delaunay overlay, and spacing distribution. |
| `RoughnessCheckBox` | Selects the roughness-family Module 3 tab. | This shows `Rp`, `Rv`, `Rz`, and roughness diagnostics. |
| `DirectHeightCheckBox` | Selects the direct-height Module 3 tab. | This shows mound height, base-position, lift-out, and method-comparison outputs. |
| `FootprintShapeCheckBox` | Selects the footprint-shape Module 3 tab. | This shows footprint size, compactness, and shape metrics. |
| `AxesOrientationCheckBox` | Selects the axes/orientation Module 3 tab. | This shows ellipse, Feret, aspect-ratio, and orientation metrics. |
| `SurfaceAreaVolumeCheckBox` | Selects the surface-area/volume Module 3 tab. | This shows mound surface area, peak-cap empty volume, and surface-area-to-volume metrics. |
| `WholeImageSlicesCheckBox` | Selects the whole-image height-slice Module 3 tab. | This shows whole-surface area, perimeter, cumulative surface area versus height, and a raw-surface threshold overlay at the peak-perimeter height. |
| `QADiagnosticsCheckBox` | Selects the Module 3 QA diagnostics tab. | This shows watershed and base-definition diagnostic outputs. |
| `RunMoundSurfaceButton` | Runs or extends the GUI Module 3 analysis session. | This computes missing cached context, reuses cached results when possible, and appends newly selected output-group tabs. |
| `MoundSurfaceSession` | Private session-only cache for Module 3 GUI work. | This avoids repeating mound-spacing and downstream watershed/shape work while the selected VK4, bestParams file, and output folder stay unchanged. |
| `SaveCurrentTabButton` | Saves the active Module 3 GUI review tab export. | This writes a tab image and summary CSV to the selected output folder. |
| `SaveAllTabsButton` | Saves every visible Module 3 GUI review tab export. | This writes all selected tab images and summary CSV files to the selected output folder. |
| `ReviewTabGroup` | In-app tab set containing mound-detection review attempts. | Each tab shows a centroid overlay and spacing histogram for one refinement result. |
| `DoneButton` | Save button for the current mound-detection result. | This saves `bestParams_<imageName>.mat` and review figures under `<imageName>_mound_analysis_exports/Mound_Detection/`. |
| `TooFewButton` | Applies "too few mounds" feedback. | This nudges the target count upward and reruns stable refinement. |
| `TooManyButton` | Applies "too many mounds" feedback. | This nudges the target count downward and reruns stable refinement. |
| `ManualCountField` | User-entered expected mound count. | This provides a direct Tier 3 count target. |
| `ManualCountButton` | Runs manual-count refinement. | This reruns stable refinement using the entered count as the target. |
| `StatusTextArea` | Run-status and optimization log text shown to the user. | This is operational feedback rather than a scientific output. |
| `LegacyAxes` | Embedded surface display for legacy roughness ROI placement. | This shows the selected VK4 height map for manual `All areas`, `Rect.`, `Square`, and `Area` ROI selection. |
| `LegacySummaryTextArea` | Live roughness summary for stored legacy ROIs. | This reports global reference context plus ROI count, `Rp`, `Rv`, `Rz`, and `SA_to_A_ratio` summary statistics. |
| `LegacyTable` | Live per-ROI roughness table. | This shows the current ROI-level `Rp`, `Rv`, `Rz`, and `SA_to_A_ratio` measurements before saving. |
| `LegacyStatusTextArea` | Embedded legacy roughness status messages. | This gives operational feedback for ROI placement and saving. |

## Physical interpretation

The app itself does not define new scientific metrics. Its role is to make the existing analysis workflows easier to run consistently without using the command window directly. The embedded legacy roughness view uses the same ROI measurement interpretation documented for `legacySurfaceRoughnessGUI`.

## Saved app-side files

The updated mound-detection GUI saves one image-specific MAT file per analyzed VK4:

- folder: `<imageName>_mound_analysis_exports/Mound_Detection/`
- file: `bestParams_<imageName>.mat`
- variable: `bestParams_<imageName>`
- table columns: `morphScale`, `contrastMethod`, `gaussSigma`, `openRadius`, `clipLimit`, `fillDeepPits`, `fillThreshold`, `dilateRadius`, and `minObjectArea`

The embedded legacy roughness workflow saves its ROI outputs under:

- folder: `<imageName>_mound_analysis_exports/Legacy_Roughness/`
- files: `<imageName>_legacy_surface_roughness.mat` and `<imageName>_legacy_surface_roughness.csv`

The Module 3 GUI exports additional tab review products under `<imageName>_mound_analysis_exports/` in the selected output folder only when the user clicks `Save Current Tab` or `Save All`. Summary CSV files are written in that root export folder. Plot PNGs are written into readable output-category subfolders such as `Mound_Spacing/`, `Roughness/`, and `Surface_Area_And_Volume/`. Each output-category subfolder also receives a `*_raw_data.csv` file containing the numeric values needed to recreate that category's distributions in another program. Re-saving overwrites files with the same names.

For export readability, histogram and line-style plots are re-rendered into temporary offscreen MATLAB figures with default MATLAB fonts and larger paper/presentation text. Image-overlay plots are exported from the in-app axes with temporary export-only text scaling. Repeated `Save All` calls skip plot PNGs already exported during the current app session unless `Save Current Tab` is used to force a refresh of the active tab.

Current overlay marker convention: mound-detection centroids use red `+` markers, and Rp locations use yellow filled dots.

During testing, GUI Module 3 shape MAT outputs may also include lightweight provenance fields such as `selectedGroups`, `computedStages`, and `cacheVersion`. These describe the GUI session/request context and do not change the scientific metric definitions.
