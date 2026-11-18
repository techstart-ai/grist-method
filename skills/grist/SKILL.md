---
name: grist
description: >
  Token-efficient mode for BMAD-method, OpenSpec workflows, PR code review, and general chat. Five phase-bound modes:
  /grist chat (cheap-context Q&A), /grist design (BMAD planning), /grist iterate (OpenSpec changes), /grist ship (coding),
  /grist review (PR / MR review in any repo — no framework needed).
  Auto-triggers on /grist, "grist mode", "ship mode", BMAD phase transitions, OpenSpec proposal commands, gh pr / glab mr / /code-review.
---

Compress context, not just chat. Compress artifacts to YAML. Suppress coding-phase narration. Code itself never compressed.

## Persistence

Active every response after activation. No drift across turns. Off only on "stop grist" / "normal mode" / `/grist off`.

Default mode if just `/grist`: **ship**. Switch: `/grist chat|design|iterate|ship|review`.

## Always-on rules (every mode)

**Read discipline** (enforced by hooks when installed; obey regardless):
- Never read a whole file >300 lines without a line range. Grep/search for the symbol first.
- Quote ≤5 lines from anything you loaded; reference the rest by `path:line`.
- Sub-agent searches return only `path:line — symbol — note` lines, never raw file dumps.
- Tool output >500 tokens: summarize before quoting back into chat.
- Never re-paste code the user can open. Cite `path:line` instead.

**Address by ID, resolve by slice:**
- `prd#E1.S1.1` not "the first story under epic 1"; `arch#C2` not "the session store component".
- Resolve refs with `gristats/grist-get.py '<ref>' --dir <artifacts-dir>` (also `--list <type>` to discover ids). Never re-read a whole artifact file to answer one slice.

**Tight emission style** (all YAML artifacts): no comments; flow lists `[a, b, c]` for scalars; omit ALL empty/null optional keys (never `stakeholders: []` or `pm: null`); one-line scalars ≤200 chars; compact ids (`E1`, `S1.1`, `d1`, `r1`). Read the lean schema contract in `schemas/` on first emission; open `schemas/examples/` only if unsure of shape.

**Context placement:** stable project facts (invariants, load-bearing decisions, glossary, conventions) belong in CLAUDE.md `## Project facts` — loaded once into the cached prefix, never Read again. Volatile state (sprint, in-progress story) lives in `.grist/volatile.md`, read only when phase-relevant. Don't re-quote either back to the user.

**Auto-clarity** — drop terse style, use normal prose for: security warnings; irreversible-action confirmations (deletes, force-push, destructive migrations); multi-step sequences where fragment ambiguity risks misread; user confused or repeats a question; anything persisted outside chat (code, comments, commits, docs, issues, PRs, memory files, messages to third parties — `.grist.yaml` artifacts keep their tight emission style); a harness-required status line or confirmation; questions or options you put to the user. Confirm irreversible actions in full sentences first. Resume mode after.

## Modes

### /grist chat — Q&A, debugging, exploration (no framework needed)

The default for general codebase questions. Chat compression is the smallest win here — the rules that matter are input-side:

- All always-on rules above, especially read discipline and never-re-paste-code.
- Delegate broad searches to a sub-agent; accept only `path:line — symbol — note` back.
- **Session facts:** when you discover a durable fact about the codebase ("payments flow starts at `create-session.ts:40`"), append one line to `.grist/facts.yaml` (`<slug>: <path:line> — <fact>`). Load that file at session start if present — it replaces re-exploration.
- **Coexistence:** in chat mode (no BMAD/OpenSpec phase active), if another terse-output rule set (e.g. caveman) is already active, defer output style to it entirely; apply only the input-side rules. Never stack two compression styles. While a design/iterate/ship phase is active (auto-detected or explicit), GRIST owns output style and defers to nothing.
- Chat: ultra (per Compression rules below) when no other style owns output. If no other style is on, the Compression rules below apply in full.
- No YAML artifacts emitted.

### /grist design — BMAD Analysis / Planning / Solutioning

For `bmad-create-prd`, `bmad-create-architecture`, `bmad-create-epics-and-stories`, research.

- Chat: lite — drop filler/hedging, keep full sentences for stakeholder readability.
- Emit `.grist.yaml` per `schemas/` contracts, tight style. PRD → `prd.grist.yaml`, Architecture → `architecture.grist.yaml`, Story → `story-<id>.grist.yaml`. Reasoning goes in `why:`/`alts:` fields, not prose.
- No narration before/after artifact writes. Reference upstream by ID (`brief#problem`, `prd#E1`), never re-paste.
- Prose rendering only when a stakeholder asks. Default is YAML.

### /grist iterate — OpenSpec change proposals

For `/openspec:proposal`, spec deltas.

- Chat: ultra.
- Single `change.grist.yaml` replaces the four-file (proposal/design/tasks/specs) layout.
- Never re-paste `openspec/specs/<feature>/spec.md`; reference `spec#<feature>#<req-id>` and resolve via grist-get.
- Deltas are the contract: `add:` / `modify:` / `remove:`. Rationale in `design.approach` + `design.alts`. Tasks one line each: `<id>: <action>`.

### /grist ship — Implementation

For `bmad-dev-story`, `bmad-code-review`, OpenSpec tasks, any edits serving a known story/spec.

- Chat: ultra. Code/comments/tests/commits: zero compression, normal style.
- Banned: preambles ("Let me…", "I'll now…"); end-of-turn summaries (diff shows it); task restatement; apologies/pleasantries.
- Allowed: one-line state-change notes ("root cause auth.ts:42", "tests pass"); direct questions when blocked.
- Load the story via `grist-get 'story#<id>'`, not by opening planning dirs.

### /grist review — PR / MR / diff review (any repo; BMAD/OpenSpec optional)

For `/grist review <PR#|!MR|base..head>`, `gh pr review`, `glab mr review`, `/code-review`, `bmad-code-review`. Pipeline: pull → review → post. Model tokens are spent only in the middle step.

- Chat: ultra. Client-facing text (review body, inline comments) is never written by the model — the renderer writes full sentences from the YAML (auto-clarity by construction).
- **Orient before reading:** `python3 gristats/grist-diff.py <base>...<head>` (or `--pr N` / `--mr N`). One compact table: path, +/-, hunks, class. Never `git diff` the whole PR to decide what matters — the hook denies it above the threshold (200 lines, `GRIST_DIFF_THRESHOLD`). Under the threshold, one `git diff -U3 <range> -- <paths>` is allowed: fewer calls beats fewer bytes.
- **Exclude noise from reads:** lockfiles, generated code, `vendor/`, snapshots, minified assets, binaries. grist-diff classifies them (built-in rules + `.gitattributes` `linguist-generated` + `.grist/review-ignore` globs); copy its `skipped_yaml:` block into `skipped:`.
- **Read hunks, not files:** `git diff -U3 <range> -- <path>`; surrounding context by line range (`sed -n 'a,bp'` or Read with offset/limit), never whole files; cap 3 context files unless a `high|crit` finding needs more.
- **One read per range.** Never re-read a file to answer a second question about it — answer from context (hook denies identical re-reads in review phase). A second read of the same file must be a non-overlapping range.
- **Verify without new reads:** `verified[]` entries cite ranges already loaded. New reads for verification only when severity ≥ high.
- Never quote diff back in reasoning or the verdict; refer by `path:line`.
- Rubric lives in CLAUDE.md `## Review rubric` when the project has one (cached prefix, never re-read). Default otherwise: correctness, error handling, security, tests present for new logic, perf regressions, API/contract breaks.
- Sub-agents (if used) return one finding per line: `<path>:<line> — <severity> — <problem>. <fix>.` No preamble, no summary paragraphs.
- **Emit** `.grist/reviews/review-<key>.grist.yaml` per `schemas/review.grist.yaml` (key = `pr-42`, `mr-17`, or `<base>..<head>`): `verdict`, `zone` (green|yellow|red), `findings[]`, `verified[]`, `handoffs[]`, `skipped[]`, `counts`. Read the contract once; `schemas/examples/review-pr.example.grist.yaml` only if unsure of shape. Story/spec keys are optional BMAD enrichment.
- **Post** with `python3 gristats/grist-render.py <file> --target github|gitlab|md` (dry run), then `--post`. GitHub: one Pull Request Review with inline comments, `zone` → APPROVE / COMMENT / REQUEST_CHANGES. GitLab: one MR note + one discussion per finding. Confirm with the user before `--post` unless they already asked to publish.
- **Round two:** on a new push, diff `head_prev...head_new` only; address prior findings by `review#<key>#f<n>`, fill `resolutions[]`, never re-read the first-round files.

## Compression rules (chat)

Levels: **lite** = ceremony and hedging gone, articles and full sentences kept. **ultra** = also drop articles and conjunctions where cause-then-effect stays unambiguous; state each fact once.

- Answer first, then reason, then next step. Pattern: `[thing] [action] [reason]. [next step].`
- No greeting, recap, or closer ("Sure", "Let me", "Hope this helps"); no just/really/basically/actually/simply; no hedging.
- Short words ("fix", not "implement a solution for"). Standard acronyms (DB/API/HTTP) fine. No invented abbreviations (cfg/impl/req/fn) and no arrows — tokenizers split them same as the full word; zero saved, clarity lost.
- Articles optional, meaning never: keep not/never/no/only/except; numbers and units exact. One idea per sentence, ≤20 words, active voice, imperative for instructions, one term per thing.
- Payload verbatim: code, commands, paths, API names exact; errors quoted as the shortest decisive line. Code change in chat = changed lines + 1-2 context lines, not the whole file. Never delete or shorten an existing comment you were not asked to change.
- Tool runs: no text between routine calls; one line before a multi-step run, one per phase change, one with the result.
- Reply in the user's language (an explicit reply-language instruction wins); technical terms, commands, errors stay verbatim.
- Never perform the style: no "mode on", no decorative tables or emoji. Plain wording no longer than the terse form? Use plain.
- Before sending: opening line announces intent → delete; closing line recaps or offers help → delete; every negation, code span, path, number, error intact; any sentence with two readings → rewrite in full.

## Example

Bad (default): "Sure! Let me read the file first to understand the implementation… [reads whole file] …I've successfully updated the file. The changes I made are: 1)… Let me know if you need anything else!"

Good (`/grist ship`): [greps symbol] [reads 30-line range] [edits] "Done. Test passes."

## File map

- Modes + rules: this file
- Schema contracts: `schemas/*.grist.yaml`; filled examples: `schemas/examples/`
- Slice resolver: `gristats/grist-get.py`
- Review pipeline: `gristats/grist-diff.py` (orient + classify), `gristats/grist-render.py` (YAML → GitHub/GitLab/Markdown review)
- Enforcement hooks: `hooks/read-discipline.py`, `hooks/diff-discipline.py`, `hooks/validate-grist-yaml.py`
- Converters: `converters/bmad-{prd,architecture,story}-to-grist.py`
- Measurement: `gristats/gristats.py` (`project`, `sessions`, `rereads`, `summary`)
