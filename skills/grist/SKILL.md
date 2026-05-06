---
name: grist
description: >
  Token-efficient mode for BMAD-method and OpenSpec workflows. Three phase-bound modes:
  /grist design (BMAD planning), /grist iterate (OpenSpec changes), /grist ship (coding).
  Auto-triggers on /grist, "grist mode", "ship mode", BMAD phase transitions, OpenSpec proposal commands.
---

Compress chat. Compress artifacts to YAML. Suppress coding-phase narration. Code itself never compressed.

## Persistence

Active every response after activation. No drift across turns. Off only on "stop grist" / "normal mode" / `/grist off`.

Default mode if just `/grist`: **ship** (most-used phase). Switch: `/grist design|iterate|ship`.

## Modes

### /grist design — BMAD Analysis / Planning / Solutioning

Use when running BMAD `bmad-create-prd`, `bmad-create-architecture`, `bmad-create-epics-and-stories`, brainstorming, market/domain/technical research.

**Chat:** lite — drop filler/hedging, keep full sentences for stakeholder readability.

**Artifacts:** emit `.grist.yaml` form per `schemas/`. PRD → `prd.grist.yaml`, Architecture → `architecture.grist.yaml`, Story → `story.grist.yaml`. Reasoning preserved in `why:` and `alts:` fields, not prose paragraphs.

**Rules:**
- No narration before/after artifact writes ("I'll now create the PRD…" — banned).
- Reference upstream artifacts by ID (`brief#problem`, `prd#E1`), never paraphrase or re-paste.
- One YAML doc per artifact. No mixing.
- Optional prose version: only when stakeholder asks. Default is YAML.

### /grist iterate — OpenSpec change proposals

Use when running OpenSpec `/openspec:proposal`, modifying existing specs, applying spec deltas.

**Chat:** ultra.

**Artifact:** single `change.grist.yaml` replaces the four-file (`proposal.md` + `design.md` + `tasks.md` + `specs/`) layout.

**Rules:**
- Refuse to re-paste existing `openspec/specs/<feature>/spec.md`. Reference by `spec#<feature>#<req-id>`.
- Spec deltas are the contract. Use `add:` / `modify:` / `remove:` keys.
- Design rationale lives in `design.approach` + `design.alts`, not prose paragraphs.
- Tasks: one line each, `<id>: <action>`.

### /grist ship — Implementation phase

Use when running BMAD `bmad-dev-story`, `bmad-code-review`, OpenSpec coding tasks, any direct file edits in service of a known story/spec.

**Chat:** ultra. Code/comments/tests/commits: zero compression, normal style.

**Banned in ship mode:**
- Preambles: "Let me…", "I'll now…", "First I'll…", "Sure, I can…"
- End-of-turn summaries: "I've updated X to do Y, and added a test for Z." Diff shows it.
- Task restatement: don't paraphrase the story before doing it.
- Apologies / pleasantries.

**Read discipline:**
- Never read full file >300 lines without line range.
- Quote ≤5 lines from any doc you just loaded; reference rest by `path:line`.
- Sub-agent searches return only `path:line — symbol — note` lines.
- Tool output >500 tokens → summarize before quoting back.

## Always-on rules (every mode)

**Auto-clarity** — drop to normal prose when:
- Security warnings or risk callouts
- Irreversible action confirmations (deletes, force-pushes, destructive migrations)
- Multi-step sequences where fragment ambiguity could mislead
- User confused or asks same question twice

Resume mode after.

**Cache hygiene:**
- Load `.grist/context-pack.md` once per session if present. Don't re-quote it.
- Stable content (PRD invariants, arch decisions, glossary) goes in pack — gets cached.
- Volatile content (current sprint status) stays out of pack.

**Address by ID:**
- `prd#E1.S1.1` not "the first story under epic 1"
- `arch#C2` not "the session store component"
- `spec#auth-login#req-12` not "the login spec, requirement about MFA"

## Compression rules (chat)

Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries, hedging.
Fragments OK. Short synonyms. Technical terms exact. Errors quoted exact. Code unchanged.

Pattern: `[thing] [action] [reason]. [next step].`

Ultra adds: abbreviate prose words (DB/auth/config/req/res/fn/impl), arrows for causality (X → Y), one word when enough. Code symbols + API names + error strings never abbreviated.

## Examples

**Bad (default Claude in coding):**
> Sure! Let me help you with that. I'll first read the file to understand the current implementation, then I'll make the changes you requested. After that, I'll verify the changes work correctly. Let me start by reading the file.
> [reads file]
> Now I have a good understanding of the code. I'll now make the modifications…
> [edits]
> I've successfully updated the file. The changes I made are: 1) renamed the variable, 2) added error handling, 3) updated the test. Let me know if you need any other changes!

**Good (`/grist ship`):**
> [reads file with line range]
> [edits]
> Done. Test passes.

**design — PRD output:**

Bad: 3-page markdown PRD with sections "Problem Statement" / "Goals" / "Non-Goals" / "User Stories" / etc.

Good: `prd.grist.yaml` per schema. ~15% the tokens. Same information. Addressable by ID.

## File map

- Modes + rules: this file
- Schemas: `schemas/{prd,architecture,story,change}.grist.yaml`
- Always-on activation rule: `rules/grist-activate.md`
- Cache template: `templates/context-pack.md`
- Converters: `converters/bmad-prd-to-grist.py`
