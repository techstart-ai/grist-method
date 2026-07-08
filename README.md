# grist

> Token-efficient mode for AI coding agents. Replaces prose planning artifacts with structured YAML. Drop-in for BMAD-method, OpenSpec, Cursor, Claude Code, Google Antigravity, and Windsurf.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python 3.7+](https://img.shields.io/badge/python-3.7+-blue.svg)](https://www.python.org/downloads/)

GRIST cuts the tokens your AI coding agents spend on planning artifacts (PRDs, architecture docs, change proposals, stories) by 5–15× — without losing any technical signal. It does this by replacing prose Markdown templates with structured YAML schemas that agents can read, write, and reference by ID.

It is not a model fine-tune, a proxy, or a fork of any tool. It is a small set of overlays — a custom OpenSpec schema, BMAD `_bmad/custom/` overrides, agent rules for Cursor / Claude Code / Google Antigravity / Windsurf, and a stats CLI — that you drop into your project alongside whatever you already use.

---

## Why

A typical sprint loop with an AI coding agent re-reads the same planning artifacts over and over: the PRD when scoping a story, the architecture when picking an approach, the spec when writing tests, the past review when fixing a regression. Caveman-style output compression cuts the assistant's prose, but **most of the token bill is on the input side** — re-injected context every turn.

GRIST attacks the input side directly:

1. **Compress the artifacts themselves.** A 5-page PRD becomes a 30-line YAML with the same load-bearing facts. Every re-injection is now several times cheaper (the bundled fixture measures 4.4×).
2. **Resolve references as slices, not files.** Handoffs use ID references (`prd#E1.S1.1`, `arch#C2`), and the `grist-get` resolver returns just that YAML node — a 30-token slice instead of a whole-file read.
3. **Enforce read discipline with hooks, not hope.** A PreToolUse hook denies whole-file reads >300 lines (use a line range or grep first); a PostToolUse hook validates emitted `.grist.yaml`. Prompt rules drift; hooks don't.
4. **Kill coding-phase narration.** Ship mode bans preambles, end-of-turn summaries, task restatement.
5. **Put stable facts where the cache already is.** Project invariants live in CLAUDE.md `## Project facts` (loaded once into the cached prefix, never re-Read); volatile state stays in `.grist/volatile.md`.
6. **Measure it.** `gristats` parses your Claude Code transcripts: per-phase token breakdowns, cache hit rate, and a `rereads` report showing which files you re-read most and what YAML siblings would save.

---

## Quick start

### Claude Code — plugin install (recommended, no clone needed)

```
/plugin marketplace add techstart-ai/grist-method
/plugin install grist@grist-method
```

The plugin ships the grist skill, the `/grist` command, and both enforcement hooks. `/grist chat` and `/grist ship` work immediately — no project files required. You only need `install.sh` for BMAD/OpenSpec overlays, the CLAUDE.md project-facts block, and non-Claude tools. See [docs/plugin-install.md](docs/plugin-install.md).

### Everything else — installer

```bash
git clone https://github.com/techstart-ai/grist-method.git
cd grist-method
```

### Auto-detect Installation

The unified installer auto-detects your project type (BMAD npm, Claude Code skills, Cursor skills, Google Antigravity skills, OpenSpec) and installs the correct overrides:

```bash
./install.sh /path/to/your/project
```

Or force a specific installation:
```bash
./install.sh --claude-code /path/to/your/project
./install.sh --cursor /path/to/your/project
./install.sh --antigravity /path/to/your/project
./install.sh --codex /path/to/your/project        # AGENTS.md rules only
./install.sh --bmad-npm /path/to/your/project
./install.sh --openspec /path/to/your/project
```

* **BMAD-method:** Five workflows emit `.grist.yaml` artifacts alongside the prose. See [bmad-overrides/README.md](bmad-overrides/README.md) for details.
* **OpenSpec:** A custom `grist` schema replaces the default 4-file layout with a single `change.grist.yaml`. See [openspec-overrides/README.md](openspec-overrides/README.md).

### For Cursor / Claude Code / Google Antigravity / Windsurf

Copy `rules/grist-activate.md` into your agent's rule directory:

| Agent | Path | Frontmatter to add |
|---|---|---|
| Claude Code | `.claude/skills/grist/SKILL.md` | (use `./install.sh --claude-code`) |
| Cursor | `.cursor/skills/grist/SKILL.md` + `.cursor/rules/grist.mdc` | (use `./install.sh --cursor`) |
| Google Antigravity | `.agents/skills/grist/SKILL.md` | (use `./install.sh --antigravity`) |
| Windsurf | `.windsurf/rules/grist.md` | `trigger: always_on` |
| Cline | `.clinerules/grist.md` | (none — auto-discovered) |
| Copilot | `.github/copilot-instructions.md` | (append) |
| Codex | `AGENTS.md` | (use `./install.sh --codex`) |

The skill also runs on claude.ai chat: zip `skills/grist/` and upload it under Settings → Capabilities → Skills (hooks don't apply there; chat mode doesn't need them).

Activate per session with `/grist chat`, `/grist design`, `/grist iterate`, or `/grist ship`.

### Measure impact

```bash
# Compare prose to GRIST artifacts in a project
python3 gristats/gristats.py project /path/to/project

# Track real token usage from Claude Code transcripts, by phase
python3 gristats/gristats.py sessions --days 7

# Combined dashboard
python3 gristats/gristats.py summary --dir /path/to/project --days 7
```

Optional: `pip install tiktoken` for accurate token counts (otherwise a `chars/4` heuristic).

---

## What's included

```
.
├── .claude-plugin/             # Claude Code plugin + marketplace manifests
├── skills/grist/SKILL.md       # Four-mode behavior spec (chat / design / iterate / ship)
├── rules/grist-activate.md     # Always-on rules for Cursor / Windsurf / Claude / Cline / Copilot / Codex
├── cursor-rules/grist.mdc      # Cursor-specific always-on .mdc rule
├── hooks/                      # Enforcement: read-discipline (PreToolUse), YAML validation (PostToolUse)
├── schemas/                    # Lean YAML contracts (prd, architecture, story, review, change, spec)
│   └── examples/               # Filled examples — read only when unsure of shape
├── templates/
│   └── context-pack.md         # Checklist: what belongs in CLAUDE.md `## Project facts`
├── converters/                 # Prose → YAML migrators: bmad-{prd,architecture,story}-to-grist.py
├── bmad-overrides/             # BMAD plugin overlay (5 workflows)
├── openspec-overrides/         # OpenSpec custom schema bundle
├── gristats/                   # Measurement CLI + grist-get.py slice resolver
├── commands/                   # /grist slash-command for Claude Code
├── docs/plugin-install.md      # Plugin vs installer coverage
└── examples/auth-v2/           # Realistic fixtures (4.4× measured compression)
```

---

## Coverage

| Tool | Status | Wiring |
|---|---|---|
| BMAD-method (`bmad-create-prd`, `bmad-create-architecture`, `bmad-create-story`, `bmad-dev-story`, `bmad-code-review`) | Shipped | `bmad-overrides/` |
| OpenSpec (custom `grist` schema replacing `spec-driven`) | Shipped | `openspec-overrides/` |
| Claude Code (skill + persistent fact loading + step injection) | Shipped | `bmad-overrides/install-claude-code.sh` |
| Cursor (skill + .mdc rule + step injection) | Shipped | `bmad-overrides/install-cursor.sh` |
| Google Antigravity (skill + step injection + AGENTS.md) | Shipped | `bmad-overrides/install-antigravity.sh` |
| Windsurf (always-on rule via `.windsurf/rules/`) | Shipped | `rules/grist-activate.md` |
| Cline (`.clinerules/`) | Shipped | `rules/grist-activate.md` |
| GitHub Copilot (`copilot-instructions.md`) | Shipped | `rules/grist-activate.md` |
| Codex (`AGENTS.md`) | Shipped | `./install.sh --codex` |
| Claude Code plugin (skill + command + hooks, no clone) | Shipped | `.claude-plugin/` |
| Enforcement hooks (read discipline, YAML validation) | Shipped | `hooks/` |
| `grist-get` slice resolver (`prd#E1` → 30-token node) | Shipped | `gristats/grist-get.py` |
| `gristats` (phase breakdown, cache rate, re-read report) | Shipped | `gristats/` |
| Hermes-agent (persistent memory adapter) | Planned | Roadmap |

---

## How it works

### Four modes

GRIST runs in one of four modes, each tuned to a phase of your workflow:

| Mode | Phase | Behavior |
|---|---|---|
| `/grist chat` | General Q&A / Debugging | Cheap-context mode, no framework needed. Read discipline, never re-paste code (cite `path:line`), sub-agent searches return `path:line — symbol — note` only, durable discoveries appended to `.grist/facts.yaml` so the next session skips re-exploration. Defers output style to caveman if active. |
| `/grist design` | BMAD Analysis / Planning / Solutioning | Lite chat. Emit PRDs, Architecture, Stories as structured YAML. No narration before/after artifact writes. |
| `/grist iterate` | OpenSpec change proposals | Ultra chat. Single `change.grist.yaml` replaces 4-file proposal. Reference specs by ID; never re-paste. |
| `/grist ship` | Implementation | Ultra chat. Zero compression in code/tests/commits. No preambles, no end-of-turn summaries, no task restatement. Read-discipline rules. |

### Address by ID, not by paraphrase

Every artifact in GRIST is structurally addressable:

```yaml
# prd.grist.yaml
prd: auth-v2
epics:
  - id: E1
    stories: [S1.1, S1.2, S1.3]
```

Downstream agents reference slices like `prd#auth-v2#E1.S1.1` instead of re-pasting the relevant prose section. A 50-character reference replaces a 500-token paragraph — and the resolver makes it real:

```bash
$ python3 gristats/grist-get.py 'prd#E1'
# examples/auth-v2/PRD.grist.yaml:15
- id: E1
  title: Okta OIDC integration
  stories: [S1.1, S1.2, S1.3]

$ python3 gristats/grist-get.py --list prd    # discover addressable ids
```

Zero dependencies (PyYAML optional). Agents resolve a slice in ~30 tokens instead of reading the whole artifact.

### Context placement

Claude Code caches the whole conversation prefix automatically. GRIST puts stable project facts (PRD invariants, load-bearing decisions, glossary, conventions) in CLAUDE.md under `## Project facts` — loaded once at session start into that cached prefix, never Read again. Volatile state (current sprint, in-progress story) lives in `.grist/volatile.md`, read only when phase-relevant, so it never churns the prefix. `templates/context-pack.md` is the checklist for what goes where.

### Read discipline — enforced, not requested

Rules that bite every turn:

- Never read whole files >300 lines without an explicit line range.
- Quote ≤5 lines from any document; reference the rest by `path:line`.
- Sub-agent searches return only `path:line — symbol — note` lines.
- Tool output >500 tokens is summarized before quoting back into chat.

Prompt rules drift over long sessions, so GRIST also ships hooks: `hooks/read-discipline.py` (PreToolUse) denies whole-file reads >300 lines with guidance to use a range or grep first (`*.grist.yaml`, CLAUDE.md, AGENTS.md exempt; `GRIST_NO_HOOKS=1` to bypass), and `hooks/validate-grist-yaml.py` (PostToolUse) blocks malformed artifact writes before they poison downstream agents. Installed automatically by the plugin, or wired into `.claude/settings.json` by `install.sh`.

---

## Example: a PRD before and after

### Before — BMAD's default `PRD.md` (excerpt)

```markdown
## Problem Statement

Enterprise customers cannot use the product because we do not support SSO. Three deals worth a combined $480k ARR are blocked in procurement awaiting OIDC support. Every week we delay loses one expansion conversation.

## Goal

Ship OIDC-based SSO with Okta as the first IdP, generic OIDC support to follow within the same quarter. The existing email/password path must continue to work for non-enterprise tenants without behavioural change.

## Non-Goals

- SAML support (slated for next quarter)
- Social login (Google/GitHub) — not requested by enterprise pipeline
- MFA redesign (current TOTP flow remains)

[... continues for 2-5 more pages ...]
```

### After — GRIST's `prd.grist.yaml`

```yaml
prd: auth-v2
phase: planning
inputs: [brief.md]
problem: 3 enterprise deals ($480k ARR) blocked on SSO
goal: OIDC SSO via Okta; generic OIDC follows same quarter
nonGoals: [SAML, social-login, MFA-redesign]
invariants:
  - sessions ≤ 8h
  - no PII in JWT
  - email/pwd path unchanged
epics:
  - id: E1
    title: Okta OIDC integration
    why: gates 3 deals
    stories: [S1.1, S1.2, S1.3]
acceptance:
  - id: ac1
    criterion: okta signin works for test tenant
risks:
  - id: r1
    risk: token-rotation race
    mitigation: refresh cron + exp backoff
nfrs:
  - p95 < 200ms for /auth/*
```

Same load-bearing facts, a fraction of the tokens. The bundled fixture measures it honestly: `gristats project examples/auth-v2/` reports a 2,500-word realistic PRD compressing to 77.4% fewer tokens (4.4× ratio), and `test/smoke-test-ratio.sh` guards that ≥3× in CI. Stakeholder readers get a parallel `prd.md` rendering on request; downstream agents read the YAML.

---

## Measuring impact

The `gristats` CLI parses Claude Code transcripts and reports usage by phase:

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

A 94% cache hit rate is a direct sign GRIST's cache-aware layout is paying off — only 6% of input tokens are billed at the full rate.

For artifact-level comparisons:

```
$ gristats project _bmad-output/

found: 7 prose ↔ grist pair(s)

pair                                        prose tok  grist tok    cut
-----------------------------------------------------------------------
PRD.md          → PRD.grist.yaml                3142        412   86.9%
architecture.md → architecture.grist.yaml       5018        624   87.6%
story-S1.1.md   → story-S1.1.grist.yaml          812        178   78.1%
[... per story ...]
-----------------------------------------------------------------------
TOTAL                                          11601       1817   84.3%

overall ratio: 6.4× (prose / grist)
```

And the re-read multiplier — which files your sessions actually re-read, and what YAML siblings would save:

```
$ gristats rereads --days 7

file                                    reads  sessions  est-tok/read  est-total
---------------------------------------------------------------------------------
docs/planning/payment-plan.md               9         1         10484      94.4k
...
total Reads observed: 1243 across 427 distinct files — est 4.52M tokens re-read
planning artifacts: 39 reads / est 286.7k tokens — 8 .grist.yaml (7.1k tok), 11 prose .md (279.6k tok)
potential savings: (prose − grist) × reads for every paired file
```

Savings = size cut × re-read frequency; `rereads` measures the second factor on your real transcripts.

See [gristats/README.md](gristats/README.md) for caveats and full subcommand reference.

---

## Compatibility

- **BMAD-method**: ≥ 6.0 (uses the `[workflow]` customization namespace and `_bmad/custom/` resolver).
- **OpenSpec**: any version that supports custom schemas via `openspec/schemas/<name>/`. See [OpenSpec customization docs](https://github.com/Fission-AI/OpenSpec/blob/main/docs/customization.md).
- **Python**: ≥ 3.7 for the converter and `gristats` (uses `from __future__ import annotations`).
- **Claude Code**, **Cursor**, **Google Antigravity**, **Windsurf**, **Cline**, **Copilot**, **Codex**: rule-file injection works on all current versions.

GRIST adds no required runtime dependencies. Optional: `pip install tiktoken` for more accurate token counts in `gristats`.

---

## Roadmap

- **Hermes-agent adapter** — map `architecture.grist.yaml` invariants → `MEMORY.md`, user-specific preferences → `USER.md`, behavioral rules → `SOUL.md`.
- **CI sync workflow** — single source of truth for schemas + auto-distribute to `.cursor/`, `.windsurf/`, etc., similar to caveman's existing GitHub Actions sync.
- **Spec-merge command** — `gristats merge-deltas` that applies a `change.grist.yaml.delta` block to a `spec.grist.yaml` outside the OpenSpec archive flow.
- **A/B harness** — run identical workflows with and without GRIST, report token-cost delta directly.

Open an issue or PR if you want to take any of these on.

---

## Contributing

PRs welcome. The repo's structure is small and self-contained:

- Schema changes live in `schemas/`. The schemas are the contract — keep them backwards-compatible or version-bump.
- BMAD overrides are in `bmad-overrides/_bmad/custom/`. Each `<workflow>.toml` pairs with a `grist-<workflow>-emission.md` and (optionally) a `grist-scripts/post-<workflow>.py`.
- OpenSpec schema is a standard custom-schema bundle in `openspec-overrides/schemas/grist/`.
- Tests / smoke tests for converters live alongside their scripts. Run them with `python3 -m unittest` or invoke them on the included `examples/auth-v2/` fixtures.

Before submitting:

1. Update the relevant README if you change behavior.
2. Run `gristats project examples/auth-v2/` to confirm the example fixtures still load.
3. Re-run any converter you touched against `examples/auth-v2/PRD.md` to confirm round-trip.

---

## Acknowledgements

GRIST builds on ideas from the [caveman](https://github.com/JuliusBrussee/caveman) project — specifically the always-on rule pattern, the persistence-across-turns model, and the philosophy that token efficiency comes from disciplined output style, not just model selection. Where caveman compresses prose, GRIST compresses the *artifacts that prose lives in* — and adds workflow-specific overlays for BMAD-method and OpenSpec that caveman intentionally stays out of.

Built on top of:

- [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) — the agile multi-agent framework GRIST overlays for greenfield development.
- [OpenSpec](https://openspec.dev) — the spec-driven framework GRIST extends with a custom schema for iteration.
- [Anthropic prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching) — the 5-minute TTL / 1024-token prefix model that informs GRIST's `context-pack.md` structure.

---

## License

MIT — see [LICENSE](LICENSE).
