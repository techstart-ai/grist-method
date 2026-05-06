# GRIST story emission rules

Loaded as a persistent fact for `bmad-create-story`. Stays in context for the full workflow run.

## Primary artifact

`story-S<epic>.<n>.grist.yaml` — written next to BMAD's prose story file in `{planning_artifacts}/`. The YAML is what the Dev agent reads in `/grist ship` mode.

## Schema

See `{project-root}/_bmad/custom/grist-schemas/story.grist.yaml`. ID pattern: `S<epic>.<n>` (e.g. `S1.1`, `S1.2`, `S2.1`).

## Style

- `title`: one-line, action-oriented (`Okta OIDC handshake endpoint`).
- `why`: one line of user/business value. Drop if obvious from epic.
- `tasks`: ordered list of one-line `do:` actions, each with optional `files:` hint. No "the developer should…" — imperative ("POST /auth/okta/callback receives code").
- `ac`: testable one-liners + `auto: true|false` flag. `"callback returns 302 + cookie for valid code"` not "the endpoint should respond correctly".
- `files`: explicit list of `{path, op: new|modify}`. This is the dev agent's read scope — keep it tight.
- `deps`: list of upstream story IDs that must be done first.
- `status`: one of `backlog|in-progress|in-review|done|blocked`. Sprint tracker reads this.

## What NOT to write

- No PRD-context section. Reference `prd: prd#<slug>` and `epic: prd#E<n>`.
- No architecture-context section. Reference `arch: arch#C<n>`.
- No "Notes for Developer" prose paragraph. If it matters, it's a task or an AC.
- No story-point estimate unless your team uses it — and if so, add a `points:` field, not prose.

## Workflow integration

Write BMAD's prose story file as the step files instruct, **and** emit `story-S<n>.<m>.grist.yaml` alongside. At Step 6 (completion), the `on_complete` script validates the YAML and updates `sprint-status.grist.yaml` if present.

## Mode

`/grist design`. The Dev agent will switch to `/grist ship` when implementing — keep the story file machine-readable so that handoff is clean.
