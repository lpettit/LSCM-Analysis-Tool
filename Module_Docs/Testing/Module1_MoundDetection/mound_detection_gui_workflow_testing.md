# Mound Detection GUI Workflow Testing

Related finalized doc: [Module1_MoundDetection.md](../../Module1_MoundDetection.md)

## Feature Under Test
`SOLFAnalysisApp` is being reshaped into a fuller-screen, low-window-count GUI for running mound detection and reviewing `refineMoundsStable`-style refinement inside the app.

## Current Hypothesis Or Intended Behavior
The mound-detection workflow should feel like a single software surface instead of a sequence of command-window prompts and separate review figures.

The first testing build keeps file browsing and the existing `pickFillThreshold` helper window, but moves the main stable refinement review loop into the app with tabs, inline controls, and an app log.

## Current Algorithm Or Workflow
- The app launches maximized with a persistent left column for:
  - raw `.vk4` input
  - output folder
  - optional `bestParams.mat`
  - module-selection buttons
- The output folder defaults to the folder containing the selected VK4 file unless the user has manually chosen an output folder.
- Module buttons remain disabled until inputs support them:
  - VK4 only enables `Mound Detection` and `Legacy Roughness Measurement`
  - VK4 plus valid `bestParams.mat` enables downstream implemented analysis buttons
  - `Cavity Analysis` remains disabled during current testing
- Clicking `Mound Detection` opens a skinny settings column for reflection correction and fill-threshold selection.
- Clicking `Run Mound Detection` starts a GUI-specific stable refinement core:
  - Tier 1 automatic tuning runs synchronously
  - each review result is added as a new tab
  - detected centroids and nearest-neighbor spacing are drawn inside the app
  - `Done`, `Too Few Mounds`, `Too Many Mounds`, and `Manual Count` buttons drive the next step
- Accepting the result saves `bestParams.mat` to the selected output folder.

## Temporary Assumptions And Open Decisions
- The existing `pickFillThreshold` helper window remains acceptable for the first GUI pass.
- `refineMoundsStable.m` remains intact; `refineMoundsStableGuiCore.m` is the GUI-specific copy/core under test.
- Tier optimization runs synchronously while conflicting controls are disabled.
- The valid `.mat` contract is strict: the file must contain a table named `bestParams` with the required stable detection fields.
- Legacy roughness is present as a button but its full workflow is not implemented in this first GUI pass.

## Outputs And Figures Being Reviewed
- In-app centroid overlay tab per Tier 1, Tier 2 nudge, or Tier 3 manual-count result.
- In-app nearest-neighbor spacing histogram per review tab.
- In-app log/status area.
- `bestParams.mat` saved to the selected output folder after acceptance.

## Promotion Criteria
- The app launches maximized and remains usable on a typical workstation display.
- File-selection state reliably enables and disables the correct module buttons.
- Tier 1, Tier 2 feedback, Tier 3 manual count, and acceptance can be completed without command-window input.
- The in-app visual review matches the information previously shown by `refineMoundsStable` figures.
- Saved `bestParams.mat` remains compatible with `analyzeMounds` and downstream modules.
- You explicitly approve moving the workflow out of testing documentation.

## Unresolved Risks Or Competing Options
- The GUI core duplicates logic from `refineMoundsStable`, so future detection-method changes need to keep both paths aligned unless the core is later consolidated.
- Long Bayesian optimization runs still block the GUI thread during this first pass.
- The threshold picker still opens a helper figure; embedding that interaction remains a future polish option.

## Promotion Status
testing
