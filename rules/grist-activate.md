# GRIST always-on rules

Apply on every response unless user says "stop grist" / "normal mode".

## Read discipline

- Never read a whole file >300 lines without an explicit line range — grep/search the symbol first
- Quote ≤5 lines from any doc you loaded — reference rest by `path:line`
- Never re-paste code the user can open; cite `path:line`
- Sub-agent / search output: receive only `path:line — symbol — note` lines, never raw file dumps
- Tool output >500 tokens: summarize before quoting

## Address-by-ID

When GRIST artifacts (`*.grist.yaml`) are present, refer to slices by ID and resolve with the slice resolver — never whole-file reads:

- `prd#E1.S1.1` not "the first story under epic 1"
- `arch#C2` not "the session store component"
- `spec#auth-login#req-12` not "the login spec MFA requirement"
- Resolve: `python3 gristats/grist-get.py '<ref>'` (or `--list <type>` to discover ids)

## Artifact emission

When asked to write a PRD, architecture doc, story, or OpenSpec change proposal: emit `.grist.yaml` per the schema contract in `schemas/`, tight style — no comments, flow lists `[a, b]` for scalars, omit all empty/null optional keys, compact ids. Prose markdown only when the user explicitly says "as prose" / "for stakeholders".

## Context placement

Stable project facts live in CLAUDE.md / AGENTS.md `## Project facts` (cached prefix — never Read again). Volatile state in `.grist/volatile.md`, read only when phase-relevant. Durable discoveries: append one line to `.grist/facts.yaml` (`<slug>: <path:line> — <fact>`); load it at session start if present.

## Auto-clarity exception

Drop terse mode and use normal prose for: security warnings; irreversible-action confirmations (deletes, force-push, destructive migrations); multi-step sequences where fragment ambiguity risks misread; user asks same question twice or signals confusion. Resume after.

## Coding-phase output (when editing files, running tests, fixing bugs)

Banned: preambles ("Let me", "I'll now"); end-of-turn summaries — the diff shows it; task restatement; apologies, pleasantries, hedging.
Allowed: one-line state-change notes ("found root cause in auth.ts:42", "tests pass"); direct questions when blocked.

## Chat compression

Drop: articles, filler (just/really/basically/actually), pleasantries, hedging. Fragments fine. Technical terms exact. Code blocks, error strings, API names: never compress. No invented abbreviations (cfg/impl/req) — tokenizers gain nothing.

**Style ownership:** while a BMAD/OpenSpec phase is active (`.grist/session-state.json` exists, or /grist design|iterate|ship invoked), GRIST owns output style — coding-phase bans and artifact emission rules above apply; any other terse-output rule set (e.g. caveman) is deferred. Outside an active phase, defer output style to caveman (or whatever style is on); keep only the input-side rules above.

## Auto-activation

GRIST arms itself — no manual /grist needed:

- **Prompt triggers** (UserPromptSubmit hook): `/bmad*` commands → design (or ship for dev-story/code-review); `/opsx*` / OpenSpec commands → iterate; `/grist <mode>` → explicit.
- **Activity triggers** (PreToolUse hook): any Read/Write/Edit under `_bmad/`, `_bmad-output/`, `openspec/` arms the matching phase — catches resumed sessions.
- State persists in `.grist/session-state.json`; a one-line reminder is re-injected every prompt so the mode never drifts. Exit: "stop grist" / `/grist off`.
- **Auto-recall** (PostToolUse hook): opening a `*.grist.yaml` artifact auto-resolves the refs it declares (`epic: prd#E1`, `arch: arch#C2`) 1 hop and injects those slices — do not re-read source artifacts for content already injected. Audit with `gristats recall`.
