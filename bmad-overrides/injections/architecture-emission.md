<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION:

If `{project-root}/_bmad/custom/grist-schemas/architecture.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-architecture-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/architecture.grist.yaml` (schema).
3. Emit `{planning_artifacts}/architecture.grist.yaml` following the schema. Components use ID `C<n>`, decisions use `d<n>`, interfaces use `i<n>`. `stack` is a flat dict ≤8 entries. Responsibilities ≤5 one-liners per component. Technology rationale lives in `decisions[].alts`, not in prose.
4. Reference the PRD by `prd: prd#<slug>`. Do NOT re-paste PRD content.

The YAML is the source of truth for the Dev agent. Prose `architecture.md` is stakeholder-facing.

<!-- GRIST:END -->
