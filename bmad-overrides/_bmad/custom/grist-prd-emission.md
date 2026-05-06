# GRIST PRD emission rules

Loaded as a persistent fact for `bmad-create-prd`. Stays in context for the full workflow run.

## Primary artifact

`prd.grist.yaml` — written next to BMAD's `prd.md` in `{planning_artifacts}/`. The YAML is the source of truth for downstream agents (Architect, PM-for-stories, Dev). The prose `prd.md` is a stakeholder-facing rendering only — keep it short and don't duplicate detail that's in the YAML.

## Schema

See `{project-root}/_bmad/custom/grist-schemas/prd.grist.yaml` (also loaded as a persistent fact). Use it verbatim — required fields, field names, ID patterns.

## Style

- `problem`: ≤200 chars, one sentence. Quantify if possible (`3 deals worth $480k ARR blocked on SSO`).
- `goal`: ≤200 chars, one sentence. Action verb + outcome.
- `nonGoals`: bare list, no prose.
- `invariants`: bare list, MUST-hold constraints. Drop fluff ("the system should…" → "session ≤ 8h").
- `epics`: each gets `id`, `title`, `why` (one-line rationale), `stories` (IDs only — actual stories live in story files).
- `acceptance`: testable one-liners. No "the user should be able to…" — just "okta signin works for test tenant".
- `risks`: `risk` + `mitigation` + optional `severity` (low|med|high). Mitigation is concrete, not "TBD".
- `nfrs`: measurable. "p95 < 200ms for /auth/*" not "should be fast".

## What NOT to write

- No stakeholder narrative paragraphs.
- No "Executive Summary" prose section — the `problem` + `goal` lines ARE the summary.
- No re-paste of `brief.md` content — reference as `inputs: [brief.md]`.
- No future-tense aspirational text ("we will…", "the system should…"). Imperative or declarative only.

## Workflow integration

When BMAD step files (steps-c/step-NN-*.md) instruct you to write a section to `prd.md`:

1. Write the prose section to `prd.md` as normal (BMAD's existing flow).
2. **Also** append the structured form to `prd.grist.yaml` in the same dir, building it incrementally as steps complete.
3. At Step 12 (workflow completion), the `on_complete` script will validate `prd.grist.yaml` exists and is well-formed; if missing, it back-fills from the prose `prd.md` via the converter.

## Mode

Operate in `/grist design` style throughout: lite chat (drop filler/hedging, keep stakeholder-readable sentences), no narration before/after artifact writes, address upstream artifacts by ID.
