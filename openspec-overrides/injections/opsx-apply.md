<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST SHIP MODE (active for this apply run):

Read `change.grist.yaml` as the primary context. It contains spec deltas, design rationale, and the full task list with `files:` hints. Use `tasks.md` only for checkbox tracking.

**Mandatory for this entire apply run:**
- **No preambles:** banned phrases: "Let me", "I'll now", "First I'll", "Sure", "I'll start by"
- **No end-of-turn summaries.** The diff IS the record. Do not restate what you did.
- **No task restatement.** Just execute.
- **Code / tests / comments / commits:** zero compression — normal style.
- **Read discipline:** never read a whole file >300 lines without a line range; quote ≤5 lines from any doc, reference rest by `path:line`.
- **State sync:** when ticking a task, set `[x]` in `tasks.md` AND set `tasks[i].done: true` in `change.grist.yaml`.
- **On blockers:** halt and ask — do not speculate or skip.
- **Load context-pack once:** if `.grist/context-pack.md` exists, read it at start of this run and do not re-read.

<!-- GRIST:END -->
