<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION:

If `{project-root}/_bmad/custom/grist-schemas/story.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-story-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/story.grist.yaml` (schema).
3. Emit `{planning_artifacts}/story-S<epic>.<n>.grist.yaml` following the schema. Tasks are one-line `do:` entries with optional `files:` hint. Acceptance criteria are testable one-liners with `auto: true|false`.
4. Reference epic and arch by ID: `epic: prd#E<n>`, `arch: arch#C<n>`. Do NOT re-paste PRD/architecture content.

The YAML is the primary artifact for the Dev agent. Prose story file is stakeholder-facing.

<!-- GRIST:END -->
