---
description: "Activate GRIST mode: chat (cheap-context Q&A), design (planning), iterate (specs), ship (coding), review (PR review)"
---

Activate GRIST mode: $ARGUMENTS.

Always-on across all modes: read discipline (never read whole file >300 lines without range; grep symbol first; quote ≤5 lines, cite rest by path:line; never re-paste code the user can open; summarize tool output >500 tokens). Address artifacts by ID (prd#E1.S1.1, arch#C2) and resolve slices via `python3 gristats/grist-get.py '<ref>'` — never whole-artifact reads. Stable facts live in CLAUDE.md `## Project facts`; volatile in `.grist/volatile.md`; append durable discoveries to `.grist/facts.yaml`. Auto-clarity: normal prose for security warnings, irreversible ops, ambiguous multi-step sequences, repeated questions. Persist mode for the session; do not drift.

If args is empty or 'ship': /grist ship — coding phase. Ultra-terse chat; ZERO compression in code/tests/commits. Banned: preambles ('Let me', 'I'll now'), end-of-turn summaries, task restatement, apologies. Load the active story via grist-get, not by opening planning dirs.

If args is 'chat': /grist chat — Q&A/debugging, no framework needed. Input-side rules dominate: delegate broad searches to sub-agents returning path:line — symbol — note only; maintain .grist/facts.yaml. If another terse-output style (e.g. caveman) is active, defer output style to it; keep input-side rules. No YAML artifacts.

If args is 'design': /grist design — BMAD planning. Lite chat (drop filler, keep sentences for stakeholders). Emit PRD/Architecture/Story as .grist.yaml per schemas/ contracts in tight style (no comments, flow lists, omit empty keys), NOT prose. Reasoning in `why:`/`alts:` fields. No narration around artifact writes. Reference upstream by ID.

If args is 'iterate': /grist iterate — OpenSpec changes. Ultra chat. Single change.grist.yaml replaces 4-file layout. Never re-paste openspec/specs/*/spec.md — reference spec#<feature>#<req-id>, resolve via grist-get. Deltas (add/modify/remove) are the contract; rationale in design.approach + design.alts.

If args starts with 'review': /grist review — PR / MR / diff review, any repo (BMAD/OpenSpec optional). Target = rest of args (PR number, !MR, URL, or base..head; default origin/main...HEAD). Ultra chat; you never write client-facing prose. Steps: (1) orient with `python3 gristats/grist-diff.py <range|--pr N|--mr N>` — never `git diff` the whole PR (hook denies above 200 lines; under it one `git diff -U3 <range> -- <paths>` is fine); (2) read hunks per file with -U3, context by line range, ≤3 context files, one read per range — never re-read to answer a second question; skip generated/lockfile/vendor/snapshot/minified files and list them under `skipped:`; (3) emit `.grist/reviews/review-<key>.grist.yaml` per schemas/review.grist.yaml (verdict, zone green|yellow|red, findings[], verified[], handoffs[], skipped[], counts) — refer to code by path:line, never quote diff; (4) `python3 gristats/grist-render.py <file> --target github|gitlab|md` renders the review body + inline comments, add `--post` to publish (confirm with the user first unless already asked). Round two: diff head_prev...head_new only, address prior findings by review#<key>#f<n> in resolutions[].

If args is 'off': stop GRIST. Resume normal prose.
