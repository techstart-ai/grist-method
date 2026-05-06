# GRIST — Always-On Rules

<!-- GRIST:RULES — do not remove this marker. Managed by grist-method installer. -->

These rules apply to EVERY session, even without `/grist` activation. They reduce token waste
on the input and output side without affecting code quality.

## Banned preambles (coding turns)

Never write these at the start of a coding turn:
- "Let me…", "I'll now…", "First I'll…", "Sure, I can help with that"
- "I'll start by reading…", "Let me take a look at…"
- "Great question!", "Absolutely!", "Of course!"

Exception: security warnings, irreversible-action confirmations, and multi-step ambiguity.

## Read discipline

- Never read whole file >300 lines without an explicit line range. Use grep to find the relevant section first.
- Quote ≤5 lines from any document you loaded. Reference the rest by `path:line`.
- Sub-agent / search output: receive only `path:line — symbol — note` lines, never raw file dumps.
- Tool output >500 tokens: summarize before quoting back into chat.

## Address-by-ID

When BMAD or OpenSpec artifacts are present, refer to slices by structured ID:
- `prd#E1.S1.1` not "the first story under epic 1"
- `arch#C2` not "the session store component"
- `spec#auth-login#req-12` not "the login spec MFA requirement"
- `story#S1.1` not "the okta callback story"

## Artifact emission

When writing a PRD, architecture doc, story, or review — if a grist schema exists at
`_bmad/custom/grist-schemas/<type>.grist.yaml`, emit the `.grist.yaml` form alongside (or
instead of) the prose markdown. The YAML is the primary artifact for downstream agents.

## Auto-clarity exception

Drop terse mode and use normal prose for:
- Security warnings or risk callouts
- Irreversible-action confirmations (deletes, force-push, destructive migrations)
- Multi-step sequences where fragment ambiguity could mislead
- User asks same question twice or signals confusion

Resume after.

<!-- GRIST:RULES:END -->
