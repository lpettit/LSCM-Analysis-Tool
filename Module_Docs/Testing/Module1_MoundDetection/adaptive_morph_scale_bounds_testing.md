# Module 1 Testing: Adaptive Morphology Scale Bounds

Related finalized doc: [Module1_MoundDetection.md](../../Module1_MoundDetection.md)

## Promotion Status
`testing`

## Feature Under Test
Adaptive `morphScale` bounds for the GUI mound-detection workflow in `refineMoundsStableGuiCore.m`.

## Current Hypothesis Or Intended Behavior
The detector should reduce user-count nudging bias by grounding the optimizer's scale range in the image being analyzed. `gaussSigma` and `openRadius` remain derived from `morphScale`, but the optimizer no longer always uses the same broad `[0.5, 3.0]` range.

## Current Algorithm Or Workflow
- Estimate mound spacing from the existing distance-transform targets:
  - `d_p90`
  - `d_p95`
  - `d_p99`
- Estimate seed spacing from the existing spacing-pruned regional-maxima seed diagnostic.
- Classify scale confidence:
  - high confidence: distance percentiles agree tightly and seed spacing agrees with `d_p95`
  - moderate confidence: estimates agree loosely
  - low confidence: estimates disagree or seed evidence is weak
- Select adaptive `morphScale` bounds:
  - high: `[0.75, 1.60]`
  - moderate: `[0.60, 2.20]`
  - low/fallback: `[0.50, 3.00]`
- Derive the searched physical parameter ranges from the selected bounds:
  - `gaussSigma = clamp(d_p95 * 0.08 * morphScale, 0.5, 15)`
  - `openRadius = clamp(round(d_p95 * 0.05 * morphScale), 1, 25)`
- Log confidence, spacing spread, seed spacing ratio, selected `morphScale` bounds, and derived `gaussSigma`/`openRadius` ranges in the app log.

## Temporary Assumptions And Open Decisions
- This first pass applies only to the GUI core, not the standalone `refineMoundsStable.m` path.
- The scale-locked relationship between `morphScale`, `gaussSigma`, and `openRadius` is preserved.
- Low-confidence images intentionally fall back to the previous broad bounds.
- The adaptive bounds should be judged by whether Tier 1 needs fewer corrective nudges on representative VK4 files.

## Outputs And Figures Being Reviewed
- In-app log lines for spacing confidence and adaptive bounds.
- Tier 1 centroid overlay and spacing histogram.
- Accepted `bestParams.mat`, with the same public fields as before.

## Promotion Criteria
- Adaptive bounds reduce unnecessary Tier 2/3 user nudges on representative images.
- Low-confidence fallback does not make difficult images worse than the previous broad search.
- Saved `bestParams` remain compatible with downstream modules.
- User explicitly approves promotion into finalized Module 1 documentation.

## Unresolved Risks Or Competing Options
- If the spacing estimates are biased by non-mound structures, high-confidence bounds may still be too narrow.
- Additional diagnostics such as autocorrelation or power-spectrum spacing may be needed if distance-transform and seed spacing disagree often.
- A future pass may apply the same adaptive bounds to standalone `refineMoundsStable.m` after GUI testing.

## Review Notes
- Early representative-surface testing suggests the adaptive bounds are mechanically working and are not preventing accurate detections.
- Several accurate or ultimately accepted workflows still required Tier 2 nudging, but the nudges usually bracketed the visually supported count quickly.
- A repeated pattern emerged: Tier 1 often selected the lower-count candidate with the best spacing regularity inside the broad count band, while a higher-count candidate closer to the image-derived target had only a slightly worse score.
- This pattern should not automatically be treated as a failure. In some surfaces the image-derived count target was clearly high, and the lower-count Tier 1 result was visually accurate.
- Current interpretation: the morphology search range is no longer the main limitation. Remaining friction is more about which candidate is shown first and how much context the reviewer gets.
- Avoid adding a stronger count penalty for now. The count target is sometimes unreliable, and over-weighting it would push the workflow toward visually wrong detections on surfaces where spacing regularity is the better signal.
- Candidate future improvements, deferred until more users test the workflow:
  - show both the best-spacing candidate and a nearest-count candidate when their scores are close
  - add a count-position-in-band diagnostic to the app log
  - auto-run a single higher-count probe when Tier 1 selects near the lower band edge
  - separate scale confidence from count-target confidence in the log
- Current decision: pause additional algorithm changes and gather feedback from other reviewers before implementing more selection or presentation changes.
