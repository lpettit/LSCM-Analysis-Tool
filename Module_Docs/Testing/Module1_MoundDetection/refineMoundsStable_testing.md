# refineMoundsStable Testing

See also: [Module1_MoundDetection.md](../../Module1_MoundDetection.md)

## Feature Under Test
`refineMoundsStable.m` is an experimental comparison copy of `refineMounds.m` for manual refinement after `autoTuneMoundsStable.m`.

It keeps the tiered user workflow from `refineMounds`, but uses the stable scale-locked tuning logic.

## Current Hypothesis Or Intended Behavior
Manual count nudges should refine the stable detector without reintroducing independent `gaussSigma` and `openRadius` drift.

The function should let the user correct imperfect automatic mound counts while keeping the same scale-locked morphology assumptions used by `autoTuneMoundsStable`.

## Current Algorithm Or Workflow
- Load the image using the same VK4/image path logic as `refineMounds`.
- Estimate the same distance-transform count targets, seed-count diagnostic, p95 spacing anchor `d_est0`, and broad plausible count band used by `autoTuneMoundsStable`.
- Convert `initParams` into scale-locked form if needed.
- Optimize only:
  - `morphScale`
  - `contrastMethod`
- Derive:
  - `gaussSigma = clamp(d_est0 * 0.08 * morphScale, 0.5, 15)`
  - `openRadius = clamp(round(d_est0 * 0.05 * morphScale), 1, 25)`
- Use raw normalized image values for `fillThreshold` when deep-pit filling is enabled.
- Preserve the original refinement tiers:
  - directional too-few / too-many nudges
  - manual expected-count entry
- Make the `n_mid_init` input optional. When it is omitted, use the internally computed geometric target from the same setup as `autoTuneMoundsStable`.

## Temporary Assumptions And Open Decisions
- `morphScale` defaults to `1` if older `initParams` do not include it.
- If older `initParams` include `gaussSigma`, the initial `morphScale` is estimated from that sigma and the current image spacing.
- Tier 2 uses the same broad count-band guardrail as `autoTuneMoundsStable`, with count penalty zero inside the band.
- Tier 3 still uses the stronger count penalty weight `2.0`.
- Contrast near-tie preference is `adapthisteq`, then `histeq`, then `none`.

## Outputs And Figures Being Reviewed
- Interactive overlay figure with detected centroids.
- Interactive nearest-neighbor spacing histogram.
- Refined `bestParams` table containing:
  - `morphScale`
  - `contrastMethod`
  - derived `gaussSigma`
  - derived `openRadius`
  - `clipLimit`

## Promotion Criteria
- The function launches and displays the same refinement workflow as `refineMounds`.
- Manual count feedback changes the stable detector in a predictable direction.
- Returned `bestParams` remain compatible with `analyzeMounds`.
- The workflow improves difficult images without returning to unstable independent sigma/open-radius tuning.

## Unresolved Risks Or Competing Options
- Because this workflow is interactive, full testing requires visual review on representative VK4 files.
- If count correction alone is insufficient, the next candidate is threshold-robust scoring or an alternate detector.
- Follow-up: `analyzeMounds` should be reviewed for alignment with the same raw-image pit-threshold behavior.

## Promotion Status
approved for finalization

Finalization note: promoted to the finalized Module 1 methodology on 2026-05-15. This testing document remains as the historical tuning record.
