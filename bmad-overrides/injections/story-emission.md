<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION:

If `{project-root}/_bmad/custom/grist-schemas/story.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-story-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/story.grist.yaml` (lean contract). Only if unsure of shape, read `grist-schemas/examples/story.example.grist.yaml`.
3. Emit `{planning_artifacts}/story-S<epic>.<n>.grist.yaml` following the contract. Tasks are one-line `do:` entries with optional `files:` hint. Acceptance criteria are testable one-liners with `auto: true|false`.
4. Tight style: no comments in emitted YAML; flow lists `[a, b, c]` for scalars; omit ALL empty/null optional keys (never `deps: []` or `blockers: []`); one-line scalars ≤200 chars; compact ids (`S1.1`, `t1`, `ac1`); no trailing blank sections. Reference epic and arch by ID (`epic: prd#E<n>`, `arch: arch#C<n>`) — do NOT re-paste PRD/architecture content.

The YAML is the primary artifact for the Dev agent. Prose story file is stakeholder-facing.

<!-- GRIST:END -->
