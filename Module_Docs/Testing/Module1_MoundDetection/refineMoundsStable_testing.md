# refineMoundsStable Testing

See also: [Module1_MoundDetection.md](../../Module1_MoundDetection.md)

## Feature Under Test
`refineMoundsStable.m` is an experimental comparison copy of `refineMounds.m` for stable automatic tuning plus manual refinement.

It keeps the tiered user workflow from `refineMounds`, but uses the stable scale-locked tuning logic.

## Current Hypothesis Or Intended Behavior
Manual count nudges should refine the stable detector without reintroducing independent `gaussSigma` and `openRadius` drift.

The function should run as the main interactive mound-tuning entry point. When no initial parameter table is supplied, it should first run the stable automatic tuning logic internally, show the initial centroid and spacing review figure, and then let the user correct imperfect automatic mound counts while keeping the same scale-locked morphology assumptions used by `autoTuneMoundsStable`.

## Current Algorithm Or Workflow
- Load the image using the same VK4/image path logic as `refineMounds`.
- Estimate the same distance-transform count targets, seed-count diagnostic, p95 spacing anchor `d_est0`, and broad plausible count band used by `autoTuneMoundsStable`.
- If `initParams` are omitted, run an internal stable auto-tune pass before the review prompt:
  - use 60 Bayesian evaluations
  - allow a numeric sixth argument to override the internal auto-tune evaluation count
  - use the image-derived `morphScale = 1`, `contrastMethod = histeq` seed when its score is acceptable
  - suppress optimizer plot windows
  - select stable near-tie parameters using the same scale-locked candidate-selection logic
- If `initParams` are supplied, convert them into scale-locked form if needed and skip the internal auto-tune pass.
- Optimize only:
  - `morphScale` over the provisional widened range `[0.5, 3.0]`
  - `contrastMethod`
- Derive:
  - `gaussSigma = clamp(d_est0 * 0.08 * morphScale, 0.5, 15)`
  - `openRadius = clamp(round(d_est0 * 0.05 * morphScale), 1, 25)`
- Use raw normalized image values for `fillThreshold` when deep-pit filling is enabled.
- Preserve the original refinement tiers:
  - automatic initial detection review
  - directional too-few / too-many nudges using `countWeight = 1.25` and a target band of +/-10%
  - manual expected-count entry using `countWeight = 2.0` and direct linear count penalty
- Make the `n_mid_init` input optional. When it is omitted, use the internally computed geometric target from the same setup as `autoTuneMoundsStable`.
- Save the accepted final parameter table as `bestParams.mat` beside the input image.

## Temporary Assumptions And Open Decisions
- `morphScale` defaults to `1` if older `initParams` do not include it.
- If older `initParams` include `gaussSigma`, the initial `morphScale` is estimated from that sigma and the current image spacing.
- The widened `morphScale` range is being tested to see whether Tier 3 can reach lower manual count targets on images where the previous upper bound saturated near `morphScale = 2`.
- Absolute caps still apply to derived parameters: `gaussSigma <= 15` and `openRadius <= 25`.
- Standalone calls are now preferred for interactive use; calls with `initParams` remain supported for backward compatibility.
- The internal auto-tune pass uses 60 evaluations, matching the default stable tuner.
- A call like `refineMoundsStable(imagePath, fillDeepPits, fillThreshold, dilateRadius, minObjectArea, 30)` means standalone mode with 30 initial evaluations, not legacy `initParams`.
- `bestParams.mat` may overwrite an existing file in the input image folder.
- Tier 1 keeps the broad plausible-count guardrail with count weight `0.5`.
- Tier 2 uses a middle-strength count weight of `1.25` with the current target band.
- Tier 3 still uses the stronger count penalty weight `2.0` with linear direct target penalty.
- Contrast near-tie preference is `adapthisteq`, then `histeq`, then `none`.

## Outputs And Figures Being Reviewed
- Interactive overlay figure with detected centroids.
- Interactive nearest-neighbor spacing histogram.
- `bestParams.mat` saved beside the input image after the user accepts the Tier 2 or Tier 3 result.
- Refined `bestParams` table containing:
  - `morphScale`
  - `contrastMethod`
  - derived `gaussSigma`
  - derived `openRadius`
  - `clipLimit`

## Promotion Criteria
- The function launches and displays the same refinement workflow as `refineMounds`.
- A five-argument standalone call performs internal stable tuning before prompting for visual review.
- A six-argument standalone call with numeric argument 6 uses that number as the internal auto-tune evaluation count.
- A legacy call with `initParams` skips internal auto-tuning and starts from the supplied parameter table.
- Manual count feedback changes the stable detector in a predictable direction.
- Returned `bestParams` remain compatible with `analyzeMounds`.
- Accepting from either Tier 2 or Tier 3 writes `bestParams.mat` beside the input image.
- The workflow improves difficult images without returning to unstable independent sigma/open-radius tuning.

## Unresolved Risks Or Competing Options
- Because this workflow is interactive, full testing requires visual review on representative VK4 files.
- If count correction alone is insufficient, the next candidate is threshold-robust scoring or an alternate detector.
- Follow-up: `analyzeMounds` should be reviewed for alignment with the same raw-image pit-threshold behavior.

## Promotion Status
testing

This standalone-entry behavior is under review and should not be moved into finalized Module 1 documentation until explicitly approved.
