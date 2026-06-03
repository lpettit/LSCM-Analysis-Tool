# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```
Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## Project-Specific Instructions

Before adding or changing code, immediately create a new git branch intended for GitHub. Name the branch based on the primary function or workstream being changed, for example:

- `analyzeSpatialOrder-acf-2026-05-09`
- `analyzeMoundShape-q50-footprint-2026-05-09`

For any functionality change in Modules 1-4, read and follow the full documentation workflow in `Project_Docs/AI_Documentation_Workflow.md` before editing. In short:

- use `Module_Docs/Testing/...` for experimental, under-review, or still-tuned functionality
- update finalized `Module_Docs/*.md` only after explicit user approval that the methodology is finalized
- update `Function_Output_Notes/*_outputs.md` when finalized public outputs change
- keep `SESSION_NOTES_*.md` chronological, but do not treat session notes as the authoritative methodology source

Project context files:

- `LSCM_Project_Handoff.md` is the compact current project status and continuity reference
- `LSCM_Project_Plans.md` is the backlog, planning, and unresolved-decision reference
- `Module_Docs/README.md` explains the module-documentation system
- `Function_Output_Notes/README.md` explains the output-reference system
