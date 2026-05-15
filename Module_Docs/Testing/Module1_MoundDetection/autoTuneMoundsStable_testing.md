# autoTuneMoundsStable Testing

See also: [Module1_MoundDetection.md](../../Module1_MoundDetection.md)

## Feature Under Test
`autoTuneMoundsStable.m` is an experimental comparison copy of `autoTuneMounds.m`.

It keeps the current mound-detection morphology workflow, but adds repeatability controls, raw-image pit thresholding, and scale-locked morphology around Bayesian optimization and final parameter selection.

## Current Hypothesis Or Intended Behavior
Repeated runs on the same image, with the same inputs and optimizer seed, should select the same final mound-detection parameters.

The expected-count estimate should remain a broad guardrail, not the dominant criterion. The selected result should still be driven mainly by spacing regularity while avoiding implausible mound counts.

The scale-locked morphology hypothesis is that `gaussSigma` and `openRadius` should not vary independently because both suppress small-scale structure. Tying them to one shared mound-scale multiplier should reduce the low-sigma/high-opening versus high-sigma/low-opening tradeoff.

## Current Algorithm Or Workflow
- Load the input image using the same VK4/image path logic as `autoTuneMounds`.
- Estimate the plausible mound-count target and hard guardrail using the same distance-transform workflow.
- Print a diagnostic-only seed-count estimate based on local peak prominence; this does not affect scoring yet.
- Build a broad plausible count band from distance-transform and seed-count diagnostics, then penalize only detections outside that band.
- Run a Bayesian optimization search over:
  - `morphScale`
  - `contrastMethod`
- Derive `gaussSigma` and `openRadius` from the image-estimated mound spacing:
  - `gaussSigma = clamp(d_est0 * 0.08 * morphScale, 0.5, 15)`
  - `openRadius = clamp(round(d_est0 * 0.05 * morphScale), 1, 25)`
- Use a fixed MATLAB RNG seed around `bayesopt` so the optimizer explores the same sequence of trial points for repeated runs.
- When deep-pit filling is enabled, apply `fillThreshold` to the raw normalized display image rather than the candidate-specific Gaussian-blurred image.
- Re-score evaluated candidates from the optimization trace.
- Build a near-tie set from candidates within a small tolerance of the best trace score.
- Select the final parameter set deterministically using:
  1. combined objective score
  2. count distance from the geometric-mean target
  3. spacing CV
  4. `morphScale` closest to the baseline value of `1`
  5. fixed contrast-method preference order, favoring `adapthisteq` first because it usually better accentuates smaller or recessed mounds
  6. lower `morphScale`
  7. lower derived `gaussSigma`
  8. lower derived `openRadius`
  9. original trace order

## Temporary Assumptions And Open Decisions
- The current morphology operations are intentionally preserved for the first comparison version.
- `gaussSigma` and `openRadius` are derived from one optimized `morphScale` rather than optimized independently.
- Baseline scale fractions are inherited from the original image-derived seed logic: `0.08` for Gaussian sigma and `0.05` for opening radius.
- The count penalty weight remains `0.5`, but the penalty is now zero inside the broad plausible count band rather than minimized at a single exact target.
- The default optimizer seed is `1`.
- The near-tie contrast preference is `adapthisteq`, then `histeq`, then `none`.
- The `fillThreshold` value is assumed to be chosen from the raw/display image and is therefore applied to that same image during stable tuning.
- The near-tie tolerance is currently defined inside the function and may need tuning after repeated-image comparisons.
- The stable selector currently returns one automatic best parameter set rather than requiring top-candidate review.
- The preliminary seed count is diagnostic-only until visual review shows it tracks true mound count better than the distance-transform estimate.

## Outputs And Figures Being Reviewed
- Console diagnostics comparing raw `bestPoint(results)` against the stable selected candidate.
- Seed-count diagnostics: seed smoothing scale, local-background radius, automatic `h_seed`, raw seed count, spacing-filtered seed count, `h_seed` sensitivity counts, minimum-spacing sensitivity counts, and candidate count-target rules.
- Selected `morphScale` and the derived `gaussSigma`/`openRadius`.
- Final `bestParams` table.
- The existing auto-tune result figure when `showPlots` is true.
- Downstream `analyzeMounds` centroid overlay and spacing histogram when the selected parameters are used.

## Promotion Criteria
- Repeated `autoTuneMoundsStable` runs on the same input return identical selected parameters.
- The selected parameters produce visually acceptable mound centroids.
- Mound count and spacing CV are comparable to or better than the original `autoTuneMounds` result on representative images.
- The deterministic tie-breaking does not visibly prefer over-merged or over-split detections just because they are slightly simpler morphologically.
- The function remains compatible with `analyzeMounds`.

## Unresolved Risks Or Competing Options
- If the score landscape has many shallow minima, deterministic selection may be repeatable without being the scientifically best detection.
- If the seed-count diagnostic agrees with visual review, a future test can blend it with the distance-transform count or use it to form a count band.
- Initial VK4 sweep showed the original `h_seed` floor of `0.01` was too permissive, so the diagnostic floor is currently `0.04`.
- Candidate target diagnostics currently include the geometric mean, conservative p99 count, p95/p99 weighted count, seed/geometric ratio, a proposed over-seeding rule target, and the broad count band used for scoring.
- A future version may need robustness scoring under small crops, shifts, or intensity perturbations.
- Follow-up: `analyzeMounds` should be reviewed for alignment with the stable raw-image fill-threshold behavior so final analysis and stable tuning use the same pit mask logic.
- A future version may test a scale-aware peak detector or watershed-style detector if the current morphology pipeline remains too degenerate.
- Saved approved parameter sets by file hash may still be useful for locked reanalysis workflows.

## Promotion Status
approved for finalization

Finalization note: promoted to the finalized Module 1 methodology on 2026-05-15. This testing document remains as the historical tuning record.
