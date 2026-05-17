# Function Output Notes

This folder is the running reference for the SOLF VK4 analysis tool. Each markdown file explains what a function returns, what the outputs measure, and why those outputs matter physically for laser-processed mound surfaces.

This folder is the concise output-reference layer.

For the deeper scientific-methods layer, use:

- [Module_Docs](../Module_Docs/README.md)

Start here when:

- a new metric is added and needs a plain-language explanation
- a field name is not immediately obvious
- we want to keep the MATLAB code technical while keeping the interpretation easy to follow

Current detailed priority:

- `analyzeMoundShape_outputs.md` is the most complete document right now because Module 3 is the active development focus.

Planned maintenance rule:

- whenever a function gains a new public output, add it to that function's markdown page in this folder in the same edit pass

Related documentation roles:

- [Module_Docs](../Module_Docs/README.md)
  - finalized long-form module methodology
- [Module_Docs/Testing](../Module_Docs/Testing/)
  - temporary testing/provisional methodology
- `SESSION_NOTES_*.md`
  - chronological history
- [LSCM_Project_Plans.md](../LSCM_Project_Plans.md)
  - backlog and unresolved planning items
