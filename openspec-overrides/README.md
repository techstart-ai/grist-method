# OpenSpec overrides for GRIST

A custom OpenSpec schema (`grist`) that replaces the default `spec-driven` schema's 4-file output with a single `change.grist.yaml` + a thin `tasks.md` mirror.

**No fork of OpenSpec.** Pure schema overlay using OpenSpec's documented schema customization model (`openspec/schemas/<name>/`).

## What this does

| Default `spec-driven` workflow | With `grist` schema |
|---|---|
| `/opsx:propose` writes 4 files: `proposal.md`, `design.md`, `tasks.md`, `specs/<cap>/spec.md` | `/opsx:propose` writes 2 files: `change.grist.yaml` (everything) + `tasks.md` (checkbox mirror) |
| Per-change cost: 3–8 kb prose across 4 files | Per-change cost: 400–800 bytes single YAML |
| `/opsx:apply` runs default mode | `/opsx:apply` runs `/grist ship` mode (no preambles, no end-summaries, read discipline) |
| `/opsx:archive` merges prose deltas into `spec.md` files | Same — but if target is `spec.grist.yaml`, structural YAML merge |

Token cost per change drops 5–15× without information loss. Long-lived specs (under `openspec/specs/`) can also be migrated to `spec.grist.yaml` form via the included converter.

## Layout

```
openspec-overrides/
├── install.sh                          # idempotent installer
├── README.md                           # this file
├── config.yaml.example                 # sample openspec/config.yaml
├── schemas/grist/                      # the schema bundle
│   ├── schema.yaml                     # 2 artifacts: change, tasks
│   ├── README.md
│   └── templates/
│       ├── change.grist.yaml
│       └── tasks.md
└── scripts/
    └── openspec-spec-to-grist.py       # spec.md → spec.grist.yaml migrator
```

## Install

```bash
./openspec-overrides/install.sh /path/to/your/openspec/project
```

The installer:
- Copies `schemas/grist/` into `<project>/openspec/schemas/grist/` (always upgrades).
- Copies the spec converter into `<project>/openspec/scripts/`.
- Activates `schema: grist` in `openspec/config.yaml` if no config exists. If a config exists, prints the line to add manually.
- Runs `openspec schema validate grist` if the CLI is on `PATH`.

Re-run anytime to upgrade. Your `openspec/config.yaml` is never overwritten if it already exists.

## Use

After install, OpenSpec slash commands work identically — they just emit GRIST artifacts:

```
/opsx:propose add-okta-mfa
  → openspec/changes/add-okta-mfa/
      ├── change.grist.yaml      # proposal + design + spec deltas + tasks
      └── tasks.md               # checkbox mirror for /opsx:apply tracker
```

Then implement:

```
/opsx:apply add-okta-mfa
  → reads change.grist.yaml, executes tasks, ticks tasks.md boxes
  → operates in /grist ship mode (terse, no preambles)
```

Then archive:

```
/opsx:archive add-okta-mfa
  → merges change.grist.yaml.delta into openspec/specs/<spec>/
  → moves change folder to openspec/changes/archive/<date>-<change-id>/
```

## Migrating existing specs

If you have a project already on OpenSpec's `spec-driven` schema with prose specs at `openspec/specs/<capability>/spec.md`, migrate to YAML form:

```bash
# Single capability
python3 openspec/scripts/openspec-spec-to-grist.py --in-place openspec/specs/auth-login/spec.md

# All capabilities at once
for d in openspec/specs/*/; do
  python3 openspec/scripts/openspec-spec-to-grist.py --in-place "$d/spec.md"
done
```

The converter parses OpenSpec's `### Requirement: <name>` + `#### Scenario: <name>` (`WHEN`/`THEN`) format and emits a YAML conforming to [schemas/spec.grist.yaml](../schemas/spec.grist.yaml).

You can keep the prose `spec.md` alongside the YAML — OpenSpec's archive merge prefers the `.grist.yaml` if both exist, falls back to the `.md` otherwise. Once you trust the migration, delete the prose.

## Apply phase = /grist ship

The schema's `apply.instruction` activates `/grist ship` for implementation:

- **Banned in chat:** preambles ("Let me", "I'll now", "First I'll"), end-of-turn summaries, task restatement, apologies.
- **Code/tests/comments/commits:** zero compression, normal style. Compression rules apply only to chat output and YAML metadata.
- **Read discipline:** never read whole files >300 lines without line range. Quote ≤5 lines from any doc — reference rest by `path:line`.
- **State sync:** when ticking a `tasks.md` box, also set `tasks[i].done: true` in `change.grist.yaml`.

This is intentionally identical to the BMAD `bmad-dev-story` override. Same mental model whether you're running BMAD or OpenSpec.

## Archive merge

The schema's `archive.instruction` describes the delta merge:

- For each entry in `delta.add` / `delta.modify` / `delta.remove`, locate the target spec at `openspec/specs/<spec>/spec.grist.yaml` (preferred) or `openspec/specs/<spec>/spec.md` (fallback).
- `.grist.yaml` target → structural YAML merge (append req entries, replace by id, remove by id).
- `.md` target → standard OpenSpec markdown merge.

The merge logic itself runs through OpenSpec's archive command — the schema's `archive.instruction` just tells the agent how to handle the YAML target.

## Compatibility

- OpenSpec ≥ the version that supports custom schemas (see [docs/customization.md](https://github.com/Fission-AI/OpenSpec/blob/main/docs/customization.md))
- Python ≥ 3.7 (converter uses `from __future__ import annotations`)

## Uninstall

```bash
rm -rf /path/to/project/openspec/schemas/grist
rm /path/to/project/openspec/scripts/openspec-spec-to-grist.py
# Edit openspec/config.yaml: revert `schema: grist` to `schema: spec-driven` (or remove the line)
```

OpenSpec falls back to `spec-driven`. Existing `change.grist.yaml` files in change folders are not touched (you can convert them back to prose with a custom script if needed; not provided since the typical migration is one-way).
