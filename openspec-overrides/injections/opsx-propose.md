<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST YAML EMISSION:

Before writing any files, emit `change.grist.yaml` in the change folder:
1. Read `{project-root}/openspec/schemas/grist/schema.yaml` for the field contract.
2. Read `{project-root}/openspec/schemas/grist/templates/change.grist.yaml` as the filled example.
3. Emit `openspec/changes/<change-name>/change.grist.yaml` — single YAML document carrying proposal + design + spec deltas + tasks.
4. Then emit `openspec/changes/<change-name>/tasks.md` — checkbox mirror of `tasks:` only. One line per task. No other prose.

Do NOT write the old 4-file layout (proposal.md, design.md, tasks.md in prose, spec.md edit). The YAML is the primary artifact.

Style rules:
- One-line strings for `why`, `design.approach`, `delta[].req`. ≤200 chars.
- Reference existing specs by ID: `spec#<feature>#req-<n>` — never re-paste.
- Design rationale lives in `design.approach` + `design.alts`. No prose paragraphs.
- Tasks: imperative one-liners in `do:`. Optionally `files:` list the read/write scope.

<!-- GRIST:END -->
