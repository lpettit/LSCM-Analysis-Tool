# AGENTS.md

## Purpose
This repository has two complementary documentation layers for the scientific analysis modules:

- `Function_Output_Notes/`
  - concise output-reference pages
  - field-by-field meaning, interpretation, and naming guidance
- `Module_Docs/`
  - long-form scientific-methods pages
  - workflow, assumptions, rationale, interpretation, and figure guidance

Use both layers together. Do not replace one with the other.

## Scope
This documentation workflow currently applies to:

- Module 1: `analyzeMounds.m`
- Module 2: `analyzeCavities.m`
- Module 3: `analyzeMoundShape.m`
- Module 4: `analyzeSpatialOrder.m`

It does not yet require long-form module-methods documents for:

- `runSOLFAnalysis.m`
- `SOLFAnalysisApp.m`
- `launchSOLFAnalysisApp.m`
- helper utilities outside Modules 1-4

## Documentation Roles
Use the repo documents in these roles:

- `Module_Docs/*.md`
  - finalized scientific-methods documentation
- `Module_Docs/Testing/<Module_Name>/*.md`
  - provisional testing documents grouped by module
  - each file should be named for the specific functionality being tested
- `Function_Output_Notes/*_outputs.md`
  - concise public-output reference pages
- `SESSION_NOTES_*.md`
  - chronological work log and session history
- `LSCM_Project_Plans.md`
  - backlog, planning themes, and unresolved decisions
- `LSCM_Project_Handoff.md`
  - project status and continuity context

Session notes may mention methodology, but they are not the authoritative home for current finalized methodology.

## Finalized vs Testing Rule
All new or modified functionality must start in the module's testing folder as its own functionality-specific testing document.

Rules:

- If a feature is experimental, under review, or still being tuned:
  - document it only in the appropriate module folder under `Module_Docs/Testing/...`
- Do not update the finalized module-methods document while the feature is still in testing.
- Do not treat passing code checks or smoke tests alone as finalization.
- A feature moves from testing documentation into finalized documentation only after explicit user approval that it is finalized.
- If a testing feature never becomes finalized, keep its testing document as a historical record instead of deleting or merging it away.

## Required Update Workflow
When functionality changes, follow this workflow:

1. Determine whether the change is still testing or is explicitly finalized.
2. If testing:
   - create or update the module's functionality-specific testing document
   - include the current hypothesis, workflow, temporary assumptions, figures under review, and promotion criteria
3. If finalized:
   - update the module's finalized document in `Module_Docs/`
   - update the matching `Function_Output_Notes/*_outputs.md` page if public outputs changed
   - update the module's figure guide if figures changed, were added, or were removed
   - move the relevant testing content into the finalized module document
4. Keep session notes chronological, but do not rely on them as the only documentation of methodology.

## Git Branch Workflow
Before adding or changing any code:

1. immediately create a new git branch intended for GitHub
2. name the branch based on the primary function being changed

Examples:

- `analyzeSpatialOrder-acf-2026-05-09`
- `analyzeMoundShape-q50-footprint-2026-05-09`

Do this before editing code files so implementation work is isolated from the start.

## Finalized Module-Doc Structure
Each finalized module document should keep the same top-level structure so readers can find information quickly:

1. Module purpose and scientific questions answered
2. Inputs, dependencies, and upstream assumptions
3. Recommended reading path
4. Calculation workflow
5. Analysis groups within the workflow
6. Output interpretation
7. Assumptions, choices, and why they were made
8. Diagnostics and figure guide
9. Known limitations and caution points
10. Change log for finalized methodology

Default organization style:

- workflow-first
- grouped into natural analysis families where that improves clarity

## Testing-Doc Structure
Each testing document should remain clearly provisional and should include:

- feature under test
- current hypothesis or intended behavior
- current algorithm/workflow
- temporary assumptions and open decisions
- outputs/figures being reviewed
- what would need to be true for promotion
- unresolved risks or competing options
- promotion status

Valid promotion-status labels:

- `testing`
- `needs review`
- `approved for finalization`

Do not copy content from a testing doc into a finalized doc until explicit user approval is given.

## Testing-Doc Organization
Testing documents should be organized like this:

- `Module_Docs/Testing/Module1_MoundDetection/*.md`
- `Module_Docs/Testing/Module2_CavityAnalysis/*.md`
- `Module_Docs/Testing/Module3_MoundShapeAndRoughness/*.md`
- `Module_Docs/Testing/Module4_SpatialOrder/*.md`

Naming rule:

- name each testing document for the functionality being tested, not just the module

Examples:

- `surface_height_autocorrelation_testing.md`
- `q50_footprint_plane_testing.md`
- `reflection_correction_threshold_testing.md`

## Figure Documentation Policy
Each finalized module document must include a figure guide that documents the canonical figure set for that module.

For each figure type, document:

- figure name or filename pattern
- where it fits in the workflow
- what it shows
- how to interpret it
- common failure modes or misleading appearances
- whether it is diagnostic, process, distribution, surface-visualization, or summary/comparison focused

Use a reference-first style:

- explain standard figure names and how to read them
- avoid embedding large numbers of images directly into the markdown
- representative embedded examples can be added later if they clearly improve interpretation

## Cross-Linking Rule
Keep the layers connected:

- each finalized module doc should link to its matching `Function_Output_Notes` page
- each testing doc should link to the matching finalized module doc
- each testing doc may link to relevant session notes or plans when useful for context

## Default Tone and Depth
The module-methods docs should be:

- scientifically clear
- easy to scan
- conceptual first
- supported by key equations only where they materially help interpretation

Do not default to equation-heavy derivations unless specifically requested.
