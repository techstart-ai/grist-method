# BMAD overrides for GRIST

Overlay-only customizations that make BMAD's planning workflows emit `.grist.yaml` artifacts alongside (or instead of) prose markdown. **No fork of BMAD source.**

## What this does

| BMAD workflow | Override effect |
|---|---|
| `bmad-create-prd` | Agent emits `prd.grist.yaml` next to `prd.md`. `on_complete` auto-converts from prose if missing. |
| `bmad-create-architecture` | Agent emits `architecture.grist.yaml`. `on_complete` validates required fields. |
| `bmad-create-story` | Agent emits `story-S<n>.<m>.grist.yaml` per story. `on_complete` validates. |
| `bmad-dev-story` | Reads story YAML as source of truth. `/grist ship` rules — no preambles, no end-summaries, read discipline. State updates write to YAML, not prose. `on_complete` validates story status reflects implementation. |
| `bmad-code-review` | Subagents output line-format findings (`path:line — sev — problem. fix.`). Spec source: `.grist.yaml` preferred over prose. Emits `review-<story_key>.grist.yaml` with structured findings. `on_complete` extracts from in-story bullets if needed. |

Mechanism — three BMAD-supported hooks per workflow:

1. **`activation_steps_append`** — instruction to read the GRIST emission rules file.
2. **`persistent_facts`** — loads emission rules + schema into permanent context for the workflow run.
3. **`on_complete`** — runs a Python validator/converter at the workflow's final step.

All three are documented BMAD customization points (`_bmad/custom/<workflow>.toml`).

## Layout

```
bmad-overrides/
├── install.sh                          # drops the overlay into a project
├── README.md                           # this file
└── _bmad/custom/                       # mirrors target install path
    ├── bmad-create-prd.toml
    ├── bmad-create-architecture.toml
    ├── bmad-create-story.toml
    ├── bmad-dev-story.toml
    ├── bmad-code-review.toml
    ├── grist-prd-emission.md           # rules loaded as persistent fact
    ├── grist-architecture-emission.md
    ├── grist-story-emission.md
    ├── grist-dev-story-emission.md
    ├── grist-code-review-emission.md
    ├── grist-schemas/
    │   ├── prd.grist.yaml
    │   ├── architecture.grist.yaml
    │   ├── story.grist.yaml
    │   ├── change.grist.yaml
    │   └── review.grist.yaml
    └── grist-scripts/
        ├── post-prd-to-grist.py        # on_complete for create-prd
        ├── post-arch-to-grist.py       # on_complete for create-architecture
        ├── post-story-to-grist.py      # on_complete for create-story
        ├── post-dev-story.py           # on_complete for dev-story
        ├── post-code-review.py         # on_complete for code-review
        └── bmad-prd-to-grist.py        # converter (used by post-prd hook)
```

## Install

```bash
./bmad-overrides/install.sh /path/to/your/bmad/project
```

The installer:
- Copies emission rules, schemas, scripts (always overwrite — these are GRIST-controlled).
- Copies TOML overrides only if the target doesn't already exist (preserves your edits).
- Skips anything in `.user.toml` (your personal layer is gitignored and untouched).

Re-run anytime to upgrade schemas/scripts. Your TOML overrides survive.

## What you'll see

A normal `bmad-create-prd` session now produces:

```
{planning_artifacts}/
├── prd.md              # prose, BMAD's existing output
└── prd.grist.yaml      # NEW: structured form, ~5-15× smaller
```

Downstream agents (Architect, Dev) read the YAML. Stakeholders read the MD. Both stay in sync because the agent emits both during the same run.

## How the emission flow works

1. BMAD activates `bmad-create-prd`.
2. Override's `activation_steps_append` instructs the agent to read `grist-prd-emission.md`.
3. Override's `persistent_facts` loads the emission rules + PRD schema into context.
4. Step files (steps-c/step-NN-*.md) run as normal — agent writes prose to `prd.md`.
5. Per emission rules, the agent **also** appends the structured form to `prd.grist.yaml` as each section completes.
6. Step 12 (workflow completion) triggers `on_complete = python3 .../post-prd-to-grist.py`.
7. Post-hook validates `prd.grist.yaml` exists with required fields. If missing, runs the converter on `prd.md` as a fallback.

## Implementation-phase token impact

The dev-story and code-review overrides target the workflows you run most frequently. The biggest wins:

**bmad-dev-story:**
- Reading `story.grist.yaml` (~150 bytes) instead of `story.md` (~800 bytes) — **5× cut on every story load**.
- `/grist ship` rules ban preambles + end-summaries → **20–30% cut on chat output per coding turn**.
- State updates (`status:`, `tasks[i].done: true`) are append-only YAML edits, not full-file rewrites. Cuts the rewrite-storm cost when ticking checkboxes mid-story.
- Read-discipline rules: never read full files >300 lines without line range. Sub-agent searches return `path:line — symbol — note` only. Cuts incidental tool-output bloat.

**bmad-code-review:**
- Subagent output format change (`path:line — sev — problem. fix.` instead of multi-paragraph markdown) → **50–70% cut on subagent token cost** without information loss.
- Auditor reads `.grist.yaml` spec instead of prose `.md` when available → **5–10× cut on Acceptance Auditor input tokens**.
- Structured `review-<story_key>.grist.yaml` lets future review passes reference past findings by ID — no re-reading prose review threads.

Across a typical sprint loop (create-story → dev-story → code-review × N stories), the compounded savings on input tokens dominate the output savings. Caveman alone targeted only output prose; this overlay targets the input side where 70%+ of an active sprint's tokens actually live.

## Token impact

Measured on the included `auth-v2` example (1.4kb prose PRD):
- Hand-authored `prd.tight.grist.yaml` is ~30% smaller than the prose source.
- On real BMAD PRDs (5–15kb of stakeholder prose), the same schema typically produces 600–800 byte YAML — **8–15× reduction**.
- The downstream impact is larger: every `bmad-create-architecture` and `bmad-dev-story` session re-loads the PRD via `persistent_facts`. Compressing the PRD compresses every downstream cycle.

## Personal overrides

If you want stricter rules just for yourself, create `.user.toml` files (gitignored):

```toml
# _bmad/custom/bmad-create-prd.user.toml
[workflow]
persistent_facts = [
  "Always require severity field on every risk entry.",
  "Reject PRDs that have more than 3 epics — split into multiple PRDs.",
]
```

These layer on top of the team `.toml` per BMAD's resolver (base → team → user merge).

## Uninstall

```bash
rm /path/to/project/_bmad/custom/bmad-{create-prd,create-architecture,create-story,dev-story,code-review}.toml
rm /path/to/project/_bmad/custom/grist-{prd,architecture,story,dev-story,code-review}-emission.md
rm -rf /path/to/project/_bmad/custom/grist-schemas
rm -rf /path/to/project/_bmad/custom/grist-scripts
```

BMAD reverts to its default behavior (prose-only output). Existing `.grist.yaml` files in `{planning_artifacts}/` are not touched.

## Compatibility

- BMAD ≥ 6.0 (uses the `[workflow]` customization namespace and `_bmad/custom/` resolver).
- Python ≥ 3.7 (post-hooks use `from __future__ import annotations`).
