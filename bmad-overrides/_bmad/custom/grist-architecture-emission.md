# GRIST architecture emission rules

Loaded as a persistent fact for `bmad-create-architecture`. Stays in context for the full workflow run.

## Primary artifact

`architecture.grist.yaml` — written next to BMAD's `architecture.md` in `{planning_artifacts}/`. The YAML is the source of truth for the Dev agent and downstream tooling. Prose `architecture.md` is a stakeholder rendering only.

## Schema

See `{project-root}/_bmad/custom/grist-schemas/architecture.grist.yaml`. Use the field names verbatim. ID patterns: `C<n>` for components, `d<n>` for decisions, `i<n>` for interfaces, `ar<n>` for arch-level risks.

## Style

- `stack`: flat dict, ≤8 entries, one keyword per slot. `runtime: node20`, not "we use Node.js LTS version 20".
- `components`: each is an ID + name + type + tech + responsibility list + deps. Responsibilities ≤5 one-liners. No prose component descriptions.
- `decisions`: this is where rationale lives. `{id, decision, why, alts}`. `alts` is a list of `{option, rejected: <reason>}`. Replaces ADR prose entirely.
- `interfaces`: contract-line per interface. `"POST /auth/okta/callback → 302 + sess cookie"` — protocol + endpoint + return shape on one line.
- `nfrs`: measurable, copy from PRD nfrs + add arch-specific ones.

## What NOT to write

- No "System Overview" prose section. The components + interfaces graph IS the overview.
- No re-paste of PRD content. Reference by `prd: prd#<slug>`.
- No technology comparison tables — collapse to a single decision entry with `alts:`.
- No diagrams as ASCII art. If a diagram is needed, reference an external file (`diagram: docs/auth-v2.mermaid`).

## Workflow integration

Write the prose `architecture.md` as BMAD's step files instruct, **and** append to `architecture.grist.yaml` incrementally. At Step 8 (completion), the `on_complete` script validates the YAML.

## Mode

`/grist design` throughout. Reasoning lives in `why:` and `alts:` fields, not narrative paragraphs.
