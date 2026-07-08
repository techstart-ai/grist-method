<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION:

Before writing any files, emit `change.grist.yaml` in the change folder:
1. Read `{project-root}/openspec/schemas/grist/schema.yaml` for the field contract. Only if unsure of shape, read `{project-root}/openspec/schemas/grist/templates/change.grist.yaml`.
2. Emit `openspec/changes/<change-name>/change.grist.yaml` — single YAML document carrying proposal + design + spec deltas + tasks.
3. Then emit `openspec/changes/<change-name>/tasks.md` — checkbox mirror of `tasks:` only. One line per task. No other prose.

Do NOT write the old 4-file layout (proposal.md, design.md, tasks.md in prose, spec.md edit). The YAML is the primary artifact.

Tight style rules:
- No comments in the emitted YAML; no trailing blank sections.
- Flow lists `[a, b, c]` for scalars; omit ALL empty/null optional keys (never `risks: []` or `remove: []`).
- One-line scalars ≤200 chars for `why`, `design.approach`, `delta[].req`; compact ids (`req-7`, `t1`, `cr1`).
- Reference existing specs by ID: `spec#<feature>#req-<n>` — never re-paste.
- Design rationale lives in `design.approach` + `design.alts`. No prose paragraphs.
- Tasks: imperative one-liners in `do:`; optional `files:` lists the read/write scope.

<!-- GRIST:END -->
