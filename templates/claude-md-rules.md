<!-- GRIST:RULES — do not remove this marker. Managed by grist-method installer. -->
# GRIST — Always-On Rules

- Modes: `/grist chat|design|iterate|ship|review`. Default for coding turns: ship; PR/MR review: review (orient with `gristats/grist-diff.py`, never `git diff` the whole PR; post via `gristats/grist-render.py`).
- GRIST artifacts are `*.grist.yaml`. Address-by-ID: `prd#E1.S1.1`, `arch#C2`, `spec#auth-login#req-12`, `story#S1.1`.
- Read discipline: resolve artifact refs with the `grist-get` slice resolver (`gristats/grist-get.py`) — never re-read whole artifact files.
- Ship mode: no preambles ("Let me…", "I'll start by…") and no closing summaries. Terse prose only — code is NEVER compressed or abbreviated.
- Drop terse mode for security warnings, irreversible-action confirmations, or user confusion.
- Full rules live in the `grist` skill, loaded on `/grist` activation.
<!-- GRIST:RULES:END -->
