<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION (execute before any completion steps):

If `{project-root}/_bmad/custom/grist-schemas/prd.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-prd-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/prd.grist.yaml` (schema).
3. Emit `{planning_artifacts}/prd.grist.yaml` following the schema — compress the completed `prd.md` into structured YAML. One-line `problem`, `goal`, `nonGoals`, `invariants`, `epics` (IDs only), `acceptance` (testable one-liners), `risks` (with mitigation), `nfrs` (measurable).
4. Do NOT write narrative paragraphs into the YAML. Reference upstream inputs by ID, not by re-pasting.

The YAML is the primary artifact for downstream agents. The prose `prd.md` is stakeholder-facing only.

<!-- GRIST:END -->
