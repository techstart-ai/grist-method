# gristats

Measure GRIST token impact. Two layers:

1. **Artifact size comparison** (offline, deterministic) — compares prose `.md` to `.grist.yaml` equivalents using bytes + token estimates.
2. **Claude Code session tracking** (real input/output tokens) — parses `~/.claude/projects/<hash>/<session>.jsonl` transcripts, groups token usage by GRIST phase (`design` / `iterate` / `ship`), reports cache hit rate.

No external dependencies required — falls back to a `chars/4` heuristic. Install `tiktoken` for accurate token counts.

## Install

```bash
# Option A: invoke directly
python3 gristats/gristats.py <subcommand>

# Option B: put on PATH
ln -s "$(pwd)/gristats/gristats" ~/.local/bin/gristats

# Optional: tiktoken for accurate token counts
pip install tiktoken
```

## Subcommands

### `gristats compare <a> <b>`

Pairwise file comparison.

```
$ gristats compare prd.md prd.grist.yaml

tokenizer: tiktoken-cl100k_base

file                                    bytes     tokens
--------------------------------------------------------
prd.md                                   1424        310
prd.grist.yaml                            982        220
--------------------------------------------------------
reduction                              31.0%      29.0%
```

### `gristats project <dir>`

Walks a directory tree for known `.md ↔ .grist.yaml` pairs and reports per-pair + totals. Handles BMAD's `_bmad-output/` layout, OpenSpec's `openspec/changes/` and `openspec/specs/`, and standalone artifact dirs.

Recognized pair patterns (case-insensitive, `.tight.` and other variants on the grist side accepted):

| Prose | GRIST |
|---|---|
| `PRD.md` / `prd.md` | `prd*.grist.yaml` |
| `architecture.md` | `architecture*.grist.yaml` |
| `proposal.md`, `design.md`, `tasks.md` | `change*.grist.yaml` (one-to-many) |
| `spec.md` | `spec*.grist.yaml` |
| `story-<key>.md` | `story-<key>*.grist.yaml` |

```
$ gristats project _bmad-output/

tokenizer: tiktoken-cl100k_base
scanning:  _bmad-output/
found:     7 prose ↔ grist pair(s)

pair                                                          prose tok  grist tok     cut
------------------------------------------------------------------------------------------
planning-artifacts/PRD.md  →  PRD.grist.yaml                       3142        412   86.9%
planning-artifacts/architecture.md  →  architecture.grist.yaml     5018        624   87.6%
planning-artifacts/story-S1.1.md  →  story-S1.1.grist.yaml          812        178   78.1%
planning-artifacts/story-S1.2.md  →  story-S1.2.grist.yaml          734        165   77.5%
planning-artifacts/story-S1.3.md  →  story-S1.3.grist.yaml          690        158   77.1%
planning-artifacts/story-S2.1.md  →  story-S2.1.grist.yaml          625        142   77.3%
planning-artifacts/story-S2.2.md  →  story-S2.2.grist.yaml          580        138   76.2%
------------------------------------------------------------------------------------------
TOTAL                                                              11601       1817   84.3%

overall ratio: 6.4× (prose / grist)
```

### `gristats sessions [--days N] [--project <substring>] [-v]`

Parses Claude Code session transcripts, groups by GRIST phase, reports input/output/cache.

Phase detection — looks for these patterns in user messages:

| Phase | Triggers |
|---|---|
| `design` | `/grist design`, `bmad-create-prd`, `bmad-create-architecture`, `bmad-create-story` |
| `iterate` | `/grist iterate`, `/openspec:proposal`, `/opsx:propose`, `/opsx:new`, `/opsx:continue`, `/opsx:ff` |
| `ship` | `/grist ship`, `bmad-dev-story`, `bmad-code-review`, `/opsx:apply`, `/opsx:verify` |
| `caveman` | `/caveman`, `/caveman-commit`, `/caveman-review`, `/caveman-compress` |
| `unlabeled` | turns before any phase command, or after `/grist off` |

Each turn keeps the most recent phase tag until another command flips it.

```
$ gristats sessions --days 7

Claude Code sessions (last 7d)
  sessions: 25
  turns:    1765
  input:    14.2k
  output:   1.19M
  cache:    117.04M read / 7.55M new — 94% hit rate

phase            turns       input    cache-read   cache-new    output
----------------------------------------------------------------------
design             385        2.2k        27.02M       1.96M    215.1k
ship               569        4.6k        52.77M       2.81M    395.0k
unlabeled          811        7.4k        37.25M       2.78M    577.3k
```

Columns:

- **input** — fresh (non-cached) input tokens. Most expensive per-token rate.
- **cache-read** — input read from prompt cache. ~90% cheaper per token.
- **cache-new** — first-time cache writes (creation). Slightly more expensive than fresh input.
- **output** — assistant output tokens.

`-v` adds a per-session breakdown.

`--project <substring>` filters to sessions whose project hash dir contains the substring. Useful when you have many parallel projects.

### `gristats summary [--dir <path>] [--days N]`

Combined dashboard — runs `project` and `sessions` together with one invocation.

```
$ gristats summary --dir _bmad-output --days 7
```

## Caveats

- **Tokenizer is approximate.** `tiktoken cl100k_base` is OpenAI's BPE; Claude uses a similar but not identical tokenizer. Ratios are accurate; absolute counts are estimates. Without `tiktoken`, the fallback is a `chars/4` heuristic — coarser but still usable for ratios.
- **Phase detection misses untagged sessions.** Anything before a `/grist` or BMAD slash command lands in `unlabeled`. Reduce by activating GRIST mode at session start.
- **Cache fields are session-local.** Anthropic prompt caching has a 5-min TTL; cache-read counts depend on session pacing, not just GRIST.
- **Honest comparison requires baseline.** A 6× artifact size cut implies token savings on every re-injection but doesn't directly prove session-level savings. For a real A/B, run identical workflows with and without `schema: grist` (OpenSpec) or BMAD overrides, then compare `gristats sessions` totals.

## Layout

```
gristats/
├── README.md          # this file
├── gristats           # bash wrapper for PATH installs
└── gristats.py        # all logic (single file, no deps required)
```
