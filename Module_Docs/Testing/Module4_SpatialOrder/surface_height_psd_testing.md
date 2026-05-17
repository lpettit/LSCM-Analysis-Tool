# Module 4 Testing: Surface-Height Power Spectral Density

Related finalized doc: [Module4_SpatialOrder.md](../../Module4_SpatialOrder.md)

Related testing docs:

- [surface_height_autocorrelation_testing.md](./surface_height_autocorrelation_testing.md)

Relevant history and planning:

- [SESSION_NOTES_2026-05-02.md](../../../SESSION_NOTES_2026-05-02.md)
- [LSCM_Project_Plans.md](../../../LSCM_Project_Plans.md)

## Promotion Status
`needs review`

## Feature Under Test
2D surface-height power spectral density as a provisional Module 4 addition.

This testing addition was intended to evaluate whether PSD could add a useful whole-field spectral view of:

- repeat spacing / periodicity
- dominant spatial-frequency content
- anisotropy or preferred directional structure

The feature was never intended to replace the current centroid-based Module 4 workflow. It was evaluated as a complementary field-level diagnostic that works directly from the calibrated height map.

## Current Hypothesis Or Intended Behavior
The working hypothesis was that PSD could answer a related but distinct question from the existing centroid-based order metrics.

Existing Module 4 outputs mainly describe how ordered the detected mound centers are as a planar point population. A PSD workflow instead describes how the full topography distributes variance across spatial frequencies.

The intended interpretation was:

- low-frequency-heavy PSD suggests more gradual larger-scale unevenness
- high-frequency-heavy PSD suggests finer minute structure
- a distinct nonzero PSD peak may indicate repeat spacing or periodic texture
- a directionally elongated 2D PSD may indicate process-direction anisotropy or preferred alignment

## Current Algorithm Or Workflow
The tested workflow was:

1. Start from the calibrated Module 1 height map `Z` rather than from the centroid graph alone.
2. Remove broad planar trend so low-frequency PSD energy is not dominated by scan tilt or background slope.
3. Mean-center the detrended surface so the spectrum reflects topographic fluctuation rather than absolute height offset.
4. Compute the 2D FFT-based PSD of the prepared height field.
5. Shift the spectrum so zero frequency is centered for directional review.
6. Compute a radial average so the review can inspect PSD vs spatial frequency in compact 1D form.
7. Identify the strongest nonzero radial PSD peak as a provisional dominant-frequency candidate.
8. Convert that candidate frequency to wavelength only as a provisional comparison aid.
9. Inspect the full 2D PSD map for ring-like, spot-like, elongated, or artifact-dominated spectral structure.
10. Compare the PSD signatures against current Module 4 outputs:
    - `first_peak_r_um` from `g(r)`
    - neighbor-shell distance summaries
    - `global_psi6_interior` and `mean_local_psi6_interior`
11. Cross-check any directional PSD interpretation against:
    - Module 3 footprint elongation/orientation behavior
    - retained ACF anisotropy/orientation outputs
12. Treat all derived summary scalars as provisional until cross-surface behavior and interpretability are reviewed.

## Temporary Assumptions And Open Decisions
- The tested preprocessing used planar detrending plus mean-centering.
- The preferred testing figures were both:
  - the full 2D PSD map
  - the radial PSD curve
- The tested workflow did not treat the dominant PSD peak as automatically equivalent to mound spacing.
- Directional PSD summaries remained provisional because they required agreement with existing orientation evidence before they could be interpreted confidently.
- Boundary and windowing sensitivity remained an important concern because finite image size and crop geometry can influence spectral concentration.
- The PSD code path is no longer being retained in `analyzeSpatialOrder.m`; this document remains as the historical testing record for why the idea was not kept.

## Outputs And Figures Being Reviewed
Provisional review-stage outputs that were considered during testing included:

- `psd2d`
  - 2D surface-height power spectral density
  - intended to show where spectral energy is concentrated across spatial frequencies and directions
- `psd_fx_um_inv`, `psd_fy_um_inv`
  - frequency axes for the 2D PSD map
- `psd_radial_freq_um_inv`
  - radial spatial-frequency axis for the 1D PSD curve
- `psd_radial_power`
  - radial PSD values
  - intended to show whether the surface is low-frequency-heavy, high-frequency-heavy, or peaked at an intermediate frequency
- `psd_peak_frequency_um_inv`
  - dominant nonzero radial PSD peak frequency
  - treated only as a provisional candidate summary during testing
- `psd_peak_wavelength_um`
  - wavelength corresponding to the provisional dominant PSD peak
  - treated only as a provisional comparison aid during testing
- `psd_anisotropy_ratio`
  - provisional directional elongation summary from the 2D PSD
- `psd_dominant_orientation_deg`
  - provisional preferred orientation from the 2D PSD

Provisional figure families reviewed during testing:

- `*_surface_psd_2d.png`
  - 2D PSD map with spatial-frequency axes in `um^-1`
  - intended to reveal ring structure, spectral elongation, directional bias, or artifact-dominated concentration
- `*_surface_psd_radial.png`
  - radial PSD curve plotted against spatial frequency
  - intended to reveal low-frequency-heavy, high-frequency-heavy, or peaked intermediate-frequency behavior

## Promotion Criteria
Before promotion into the finalized Module 4 document, the following would have needed to be true:

- the PSD workflow gives a scientifically clear answer that is distinct from but complementary to existing Module 4 metrics
- the preprocessing choices are justified and stable across representative surfaces
- the radial PSD curve is readable and useful for comparison
- the 2D PSD map adds directional insight that is not already captured more clearly elsewhere
- the provisional dominant PSD peak is not overly sensitive to preprocessing or crop details
- any proposed scalar outputs are physically interpretable and do not overstate what the spectrum uniquely identifies
- explicit user approval is given for finalization

That promotion threshold was not met.

## Unresolved Risks Or Competing Options
- A PSD peak may look precise while mixing multiple physical causes such as mound spacing, mound width, broad waviness, or scan-direction artifacts.
- Low-frequency PSD loading may be dominated by residual background structure if detrending is not sufficient.
- The radial PSD may hide meaningful directional information preserved in the full 2D spectrum.
- The full 2D PSD may be scientifically richer but harder to summarize consistently for routine reporting.
- Apparent anisotropy may reflect cropping, windowing, or preprocessing rather than real process-direction structure.
- A competing option was to retain PSD only as a diagnostic figure family and avoid promoting scalar outputs unless they proved robust.
- Another competing option was to favor ACF anisotropy/orientation if PSD proved too ambiguous for spacing interpretation.

## Review Notes
- Rationale for testing:
  - Module 4 already has strong centroid-based order descriptors, but none of them provide a direct spectral view of the full calibrated height field.
  - PSD was tested to see whether it could add a stable periodicity and anisotropy interpretation layer for cross-surface comparison.
- Expected use during testing:
  - supplementary periodicity diagnostic
  - cross-check against `g(r)` and neighbor-shell spacing
  - field-level directional review against Module 3 and ACF orientation evidence
- Non-goal:
  - replacing the existing centroid-based Module 4 interpretation stack
- Outcome from testing:
  - the PSD workflow did not yield results strong enough to justify keeping it in the active Module 4 code path
  - the radial PSD curve did not add enough clear comparison value beyond existing Module 4 metrics to justify retaining a new public-facing workflow
  - the 2D PSD map remained interesting as a diagnostic image, but not compelling enough to keep as an implemented feature
  - the dominant spectral component remained too ambiguous to assign a reliable physical interpretation worth promoting
- Current recommendation:
  - do not keep PSD in the active `analyzeSpatialOrder` implementation
  - keep this testing document as the historical record of the PSD evaluation
  - if spectral methods are revisited later, treat them as a fresh comparison exercise against `g(r)`, ACF anisotropy/orientation, and Module 3 orientation evidence rather than as a paused near-final feature
