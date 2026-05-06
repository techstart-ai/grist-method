# GRIST code-review emission rules

Loaded as a persistent fact for `bmad-code-review`. Three areas of compression: subagent prompts, in-story findings, and the structured `review-<key>.grist.yaml` output.

## Source of truth for the spec

When step-01-gather-context.md sets `{spec_file}`:
- If the path ends in `.md`, look for a sibling `.grist.yaml` with the same stem.
- If found, treat the YAML as the spec — pass it to the Acceptance Auditor as the `{spec_file}` content. The YAML is denser; the Auditor gets full intent in fewer tokens.
- If not found, fall back to the prose `.md` as BMAD does today.

## Subagent prompts — line-format findings

When step-02-review.md launches the parallel review subagents (Blind Hunter, Edge Case Hunter, Acceptance Auditor), the prompt to each MUST include this output format directive:

```
Output format: one finding per line, no preamble, no summary. Format:
  <path>:<line> — <severity> — <one-line problem>. <one-line fix>.

severity ∈ {low, med, high, crit}. If location is unknown, use <path>:- or general:-.
Edge Case Hunter may continue to use its native JSON-array format if preferred.
Blind Hunter and Acceptance Auditor: line format only.
No multi-paragraph descriptions. No "I'll review…" preambles. No closing summaries.
```

This replaces the default markdown-list output. Cut subagent output ~50-70% with no information loss for triage.

## In-story findings format

Step-04-present.md appends findings as markdown bullets to the story file. Keep that for stakeholder readability, **but** also write the structured form to `review-<story_key>.grist.yaml` per the loaded schema.

In-story bullet format stays as BMAD specifies:
- `- [ ] [Review][Decision] <Title> — <Detail>`
- `- [ ] [Review][Patch] <Title> [<file>:<line>]`
- `- [x] [Review][Defer] <Title> [<file>:<line>] — deferred, pre-existing`

But each finding ALSO becomes an entry in `review-<story_key>.grist.yaml`:
```yaml
findings:
  - id: f1
    class: patch
    severity: high
    source: blind+edge
    loc: <path:line>
    title: <one-line>
    detail: <one-line>
    fix: <one-line>
```

Future review passes reference findings by `id` — `review#S1.1#f1` — without re-reading the prose.

## Mode: /grist ship for chat output

Banned in your own (orchestrator) chat output:
- "Let me launch the review subagents…" → just launch them.
- "I'll now triage the findings…" → just triage.
- Multi-paragraph triage rationale. The triage classifications are the rationale.

Step-04 ends with a one-line summary. Stick to it:
> **Code review complete.** <D> decision-needed, <P> patch, <W> defer, <R> dismissed.

No additional paragraphs.

## Read discipline

- The diff is the primary input. Don't load full files when diff hunks suffice.
- If a file MUST be read for context, read with line range covering ±20 lines around the diff hunk.
- Spec file: prefer `.grist.yaml` per above. If prose, read whole only if <300 lines.

## What NOT to do

- Don't re-quote diff hunks back into chat after subagents return — the user can `git show`.
- Don't paraphrase findings into prose. The triage labels are the categorization.
- Don't write a "Recommendations" or "Next Steps" prose section. The classifications drive next steps mechanically (decision-needed → ask user; patch → write fix; defer → log; dismiss → drop).
