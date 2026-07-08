<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION (execute before any completion steps):

If `{project-root}/_bmad/custom/grist-schemas/prd.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-prd-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/prd.grist.yaml` (lean contract). Only if unsure of shape, read `grist-schemas/examples/prd.example.grist.yaml`.
3. Emit `{planning_artifacts}/prd.grist.yaml` — compress the completed `prd.md` into the contract. One-line `problem`, `goal`, `nonGoals`, `invariants`, `epics` (IDs only), `acceptance` (testable one-liners), `risks` (with mitigation), `nfrs` (measurable).
4. Tight style: no comments in emitted YAML; flow lists `[a, b, c]` for scalars; omit ALL empty/null optional keys (never `stakeholders: []` or `pm: null`); one-line scalars ≤200 chars; compact ids (`E1`, `ac1`, `r1`); no trailing blank sections. No narrative paragraphs; reference upstream inputs by ID.

The YAML is the primary artifact for downstream agents. The prose `prd.md` is stakeholder-facing only.

<!-- GRIST:END -->
