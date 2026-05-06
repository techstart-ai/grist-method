# grist schema for OpenSpec

Token-efficient OpenSpec schema. Drop-in replacement for the default `spec-driven` schema.

## What changes

| Default (`spec-driven`) | This (`grist`) |
|---|---|
| `proposal.md` (1-2 pages prose) | `change.grist.yaml` — `why:` one-liner |
| `design.md` (~1-2 pages prose) | same file — `design.approach` + `design.alts` |
| `tasks.md` (checkbox list) | same file — `tasks:` YAML list, mirrored to `tasks.md` for tracker |
| `specs/<cap>/spec.md` (delta requirements with WHEN/THEN scenarios) | same file — `delta.add` / `delta.modify` / `delta.remove` |

Per-change token cost typically drops 5–15× without information loss.

## Layout

```
openspec/schemas/grist/
├── schema.yaml                # 2 artifacts: change, tasks (mirror)
├── README.md                  # this file
└── templates/
    ├── change.grist.yaml      # template with placeholders
    └── tasks.md               # checkbox mirror template
```

## Activate

```yaml
# openspec/config.yaml
schema: grist
```

Or per change: `/opsx:new my-change --schema grist`.

## Slash commands (unchanged)

OpenSpec's slash commands work identically — they just emit the new artifacts:

- `/opsx:propose <change-name>` → creates folder + writes `change.grist.yaml`, then `tasks.md` (mirror)
- `/opsx:apply <change-name>` → reads `change.grist.yaml`, executes tasks, ticks `tasks.md` boxes + sets `tasks[i].done: true`
- `/opsx:archive <change-name>` → merges `delta.*` entries into long-lived spec files

## Apply phase mode

The schema's `apply.instruction` activates `/grist ship` mode for implementation:
- No preambles, no end-summaries, no task restatement
- Code/tests/comments/commits: zero compression
- Read discipline: line ranges, ≤5-line quotes, sub-agent results in `path:line — symbol — note` format

Identical to the BMAD `bmad-dev-story` override semantics.

## Archive merge

On `/opsx:archive`, deltas are applied to long-lived specs at `openspec/specs/<spec>/`:

- If target is `spec.grist.yaml`: structural YAML merge (preferred)
- If target is `spec.md`: standard OpenSpec markdown merge (legacy fallback)

To migrate existing prose specs to YAML, run:

```bash
python3 openspec-overrides/scripts/openspec-spec-to-grist.py openspec/specs/<capability>/spec.md
```

Writes `spec.grist.yaml` next to the prose. Future archives will prefer it.
