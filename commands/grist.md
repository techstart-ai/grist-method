---
description: "Activate GRIST mode: chat (cheap-context Q&A), design (planning), iterate (specs), ship (coding)"
---

Activate GRIST mode: $ARGUMENTS.

Always-on across all modes: read discipline (never read whole file >300 lines without range; grep symbol first; quote ≤5 lines, cite rest by path:line; never re-paste code the user can open; summarize tool output >500 tokens). Address artifacts by ID (prd#E1.S1.1, arch#C2) and resolve slices via `python3 gristats/grist-get.py '<ref>'` — never whole-artifact reads. Stable facts live in CLAUDE.md `## Project facts`; volatile in `.grist/volatile.md`; append durable discoveries to `.grist/facts.yaml`. Auto-clarity: normal prose for security warnings, irreversible ops, ambiguous multi-step sequences, repeated questions. Persist mode for the session; do not drift.

If args is empty or 'ship': /grist ship — coding phase. Ultra-terse chat; ZERO compression in code/tests/commits. Banned: preambles ('Let me', 'I'll now'), end-of-turn summaries, task restatement, apologies. Load the active story via grist-get, not by opening planning dirs.

If args is 'chat': /grist chat — Q&A/debugging, no framework needed. Input-side rules dominate: delegate broad searches to sub-agents returning path:line — symbol — note only; maintain .grist/facts.yaml. If another terse-output style (e.g. caveman) is active, defer output style to it; keep input-side rules. No YAML artifacts.

If args is 'design': /grist design — BMAD planning. Lite chat (drop filler, keep sentences for stakeholders). Emit PRD/Architecture/Story as .grist.yaml per schemas/ contracts in tight style (no comments, flow lists, omit empty keys), NOT prose. Reasoning in `why:`/`alts:` fields. No narration around artifact writes. Reference upstream by ID.

If args is 'iterate': /grist iterate — OpenSpec changes. Ultra chat. Single change.grist.yaml replaces 4-file layout. Never re-paste openspec/specs/*/spec.md — reference spec#<feature>#<req-id>, resolve via grist-get. Deltas (add/modify/remove) are the contract; rationale in design.approach + design.alts.

If args is 'off': stop GRIST. Resume normal prose.
