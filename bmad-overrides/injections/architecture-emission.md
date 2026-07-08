<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION:

If `{project-root}/_bmad/custom/grist-schemas/architecture.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-architecture-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/architecture.grist.yaml` (lean contract). Only if unsure of shape, read `grist-schemas/examples/architecture.example.grist.yaml`.
3. Emit `{planning_artifacts}/architecture.grist.yaml` following the contract. Components use ID `C<n>`, decisions use `d<n>`, interfaces use `i<n>`. `stack` is a flat dict ≤8 entries. Responsibilities ≤5 one-liners per component. Technology rationale lives in `decisions[].alts`, not in prose.
4. Tight style: no comments in emitted YAML; flow lists `[a, b, c]` for scalars; omit ALL empty/null optional keys (never `deps: []` or `alts: []`); one-line scalars ≤200 chars; no trailing blank sections. Reference the PRD by `prd: prd#<slug>` — do NOT re-paste PRD content.

The YAML is the source of truth for the Dev agent. Prose `architecture.md` is stakeholder-facing.

<!-- GRIST:END -->
