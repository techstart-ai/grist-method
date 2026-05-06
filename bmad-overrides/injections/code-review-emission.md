<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

#### GRIST YAML EMISSION (before completion summary):

If `{project-root}/_bmad/custom/grist-schemas/review.grist.yaml` exists:
1. Read `{project-root}/_bmad/custom/grist-code-review-emission.md` (emission rules).
2. Read `{project-root}/_bmad/custom/grist-schemas/review.grist.yaml` (schema).
3. Emit `{implementation_artifacts}/review-{story_key}.grist.yaml`. Each finding gets an entry: `{id, class: patch|decision|defer|dismiss, severity: low|med|high|crit, loc: path:line, title, detail, fix}`.
4. Subagent prompts for step-02-review.md: add this directive to each subagent: `Output one finding per line: <path>:<line> — <severity> — <one-line problem>. <one-line fix>. No preamble, no summary paragraphs.`

Future review passes reference findings by `review#<story_key>#f<n>` — no re-reading prose.

<!-- GRIST:END -->
