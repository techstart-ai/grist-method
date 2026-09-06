# GRIST schemas

Each `<name>.grist.yaml` is the lean **contract**: keys, required/optional markers, and
one-line constraints. `examples/<name>.example.grist.yaml` is a filled artifact in tight
emission style — valid YAML, no placeholders.

| Contract | Example | Artifact it governs |
|---|---|---|
| `prd.grist.yaml` | `examples/prd.example.grist.yaml` | `prd.grist.yaml` (BMAD PRD) |
| `architecture.grist.yaml` | `examples/architecture.example.grist.yaml` | `architecture.grist.yaml` |
| `story.grist.yaml` | `examples/story.example.grist.yaml` | `story-S<n>.<m>.grist.yaml` |
| `review.grist.yaml` | `examples/review-pr.example.grist.yaml` (standalone), `examples/review.example.grist.yaml` (BMAD) | `.grist/reviews/review-<key>.grist.yaml` — render with `gristats/grist-render.py` |
| `change.grist.yaml` | `examples/change.example.grist.yaml` | OpenSpec `change.grist.yaml` |
| `spec.grist.yaml` | `examples/spec.example.grist.yaml` | OpenSpec `spec.grist.yaml` |

## When to read which

- **Contract**: read once per session, before the first emission of that artifact type.
- **Example**: read only if uncertain about the shape after reading the contract. Do not
  read it routinely — it costs tokens the contract already saves.

## Tight emission style (all emitted artifacts)

- No comments in emitted artifacts.
- Flow style `[a, b, c]` for lists of scalars.
- Omit ALL empty/null optional keys — never `stakeholders: []` or `pm: null`.
- One-line scalars, ≤200 chars.
- Compact ids: `E1`, `S1.1`, `d1`, `r1`.
- No trailing blank sections.
