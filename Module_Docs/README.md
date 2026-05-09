# Module Documentation System

This folder is the long-form scientific-methods documentation layer for the LSCM Analysis Tool.

It sits alongside the existing concise output-reference pages in [Function_Output_Notes](../Function_Output_Notes/README.md).

## What Lives Here

### Finalized scientific-methods docs
These are the main module references:

- [Module1_MoundDetection.md](./Module1_MoundDetection.md)
- [Module2_CavityAnalysis.md](./Module2_CavityAnalysis.md)
- [Module3_MoundShapeAndRoughness.md](./Module3_MoundShapeAndRoughness.md)
- [Module4_SpatialOrder.md](./Module4_SpatialOrder.md)

Use these when you want to understand:

- how the module calculates its outputs
- what assumptions and scientific choices were made
- why those choices were made
- what the outputs mean physically
- how the module figures support interpretation

These pages are workflow-first and are intended to be readable by a researcher or scientist trying to understand the analysis behind the scenes.

### Testing-methods docs
The testing pages live in [Testing](./Testing/).

Use them when:

- a feature is still experimental
- the methodology is being tuned
- the outputs or figures are being reviewed before finalization
- a decision still needs explicit user approval

Testing docs are intentionally provisional. They are not the authoritative final methodology.

## How This Differs From Other Repo Documents

### `Function_Output_Notes`
See [Function_Output_Notes](../Function_Output_Notes/README.md).

Those pages are the concise output-reference layer:

- field names
- output meanings
- compact physical interpretation

Use them when you already know the module and mainly need to decode outputs quickly.

### Session notes
See files such as [SESSION_NOTES_2026-05-02.md](../SESSION_NOTES_2026-05-02.md).

Those are chronological records of what changed and when. They are useful for history and continuity, but they are not the authoritative final methodology docs.

### Project plans
See [LSCM_Project_Plans.md](../LSCM_Project_Plans.md).

That file is for backlog items, future ideas, unresolved decisions, and planning themes. It is not the finalized methods reference.

## Maintenance Rule
Use the repo-root [AGENTS.md](../AGENTS.md) policy:

- new or modified functionality starts in the appropriate testing doc
- finalized module docs are updated only after explicit user approval
- if public outputs change after finalization, update both:
  - the finalized module doc
  - the matching `Function_Output_Notes` page

## Recommended Reading Strategy

- Start with a finalized module doc when you want the full scientific story.
- Use the matching `Function_Output_Notes` page when you need fast output lookup.
- Use a testing doc when reviewing an in-progress method before finalization.
- Use session notes when you need chronology or implementation history.
