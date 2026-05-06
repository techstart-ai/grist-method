# GRIST dev-story emission rules

Loaded as a persistent fact for `bmad-dev-story`. Stays in context for the full workflow run. This is the highest-traffic workflow in your loop — every change here compounds.

## Source of truth

`story-<story_key>.grist.yaml` in `{planning_artifacts}/` (or `{implementation_artifacts}/` per BMAD config). Read this FIRST. The prose `story-<story_key>.md` is a stakeholder rendering — read it ONLY if the YAML is missing.

If both exist and disagree, the YAML wins. Update the YAML and treat the prose as stale until regenerated.

## Mode: /grist ship

Active for the entire workflow run. Banned in chat output:

- Preambles: "Let me", "I'll now", "First I'll", "Sure", "I'll start by"
- End-of-turn summaries describing what you just did. The diff and the YAML state ARE the record.
- Task restatement: don't paraphrase the story before doing it.
- Apologies, pleasantries, hedging.

Allowed:
- One-line state announcements at decision points: "found root cause in auth.ts:42", "tests pass", "stuck on t3, blocking on X"
- Direct questions when blocked

## Code output rules

**Code, tests, comments, commit messages: zero compression.** Normal style. The compression rules apply only to:
- Chat output (the conversation surface)
- Metadata fields inside `story.grist.yaml` (notes, blockers, completion notes)

A function comment is code. A `// TODO:` is code. Don't compress those.

## Read discipline

- Never read whole files >300 lines without an explicit line range. Use grep to navigate first.
- Quote ≤5 lines from any doc you loaded; reference rest by `path:line`.
- Sub-agent searches return only `path:line — symbol — note` lines.
- Tool output >500 tokens: summarize before quoting back into chat.

## State updates — write to YAML, not prose

When BMAD step files instruct you to update story state (Tasks/Subtasks checkboxes, File List, Dev Agent Record, Status), write to `story-<key>.grist.yaml` instead of rewriting the prose:

| BMAD prose update | GRIST YAML update |
|---|---|
| Tick a Tasks/Subtasks checkbox `[x]` | Set `tasks[i].done: true` |
| Append to File List | Append to `files:` if new path |
| Set Status: ready-for-review | Set `status: in-review` |
| Add Completion Note | Append to `notes:` (one-liner) |
| Add Debug Log entry | Append to `debug:` (one-liner) |

This is append-mostly, no full-file rewrite. The dev agent reads the same YAML next session and sees state without re-parsing prose.

## Sprint-status.yaml handling

When the workflow reads `sprint-status.yaml`:
- Parse only the entry for the active `story_key`.
- Do not re-emit the full file's contents into chat output.
- When updating sprint status, modify only the active story's entry.

## Reference upstream by ID

- `prd#auth-v2#E1` not "the first epic of the auth-v2 PRD"
- `arch#C1` not "the okta-broker component"
- `story#S1.1` not "the okta callback story"

The PRD and architecture YAMLs may be loaded as context, but never re-quote them. Address by ID.

## Project-context.md

If loaded as a persistent fact, treat it as cached. Don't quote sections back into chat — agents reading your output will see them already.

## End-of-step output

After each task or subtask completes:

```
t<n>: done. <one-line state change if non-obvious>
```

That's it. No paragraph summaries. The user can `git diff` if they want detail.
