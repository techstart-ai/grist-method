# Contributing to grist

Thanks for considering a contribution. The repo is small and self-contained; most contributions land cleanly without coordination.

## Repo structure

```
schemas/                   # YAML schemas — the contract. Backwards-compatible changes only.
skills/grist/              # Three-mode behavior spec for AI agents.
rules/grist-activate.md    # Always-on rules for Cursor / Windsurf / Claude / Cline / Copilot.
templates/                 # Cache-aware project context template.
converters/                # Prose → YAML migrators.
bmad-overrides/            # BMAD plugin overlay (5 workflows).
openspec-overrides/        # OpenSpec custom schema bundle.
gristats/                  # Token-impact measurement CLI.
examples/                  # Filled fixtures used by smoke tests.
commands/                  # Claude Code slash commands.
```

## Before you submit

1. **Run smoke tests** on the example fixtures:

   ```bash
   python3 gristats/gristats.py project examples/auth-v2/
   python3 converters/bmad-prd-to-grist.py examples/auth-v2/PRD.md > /tmp/check.yaml
   ```

   Both should exit 0 and produce sane output.

2. **Update relevant READMEs.** Each module (bmad-overrides, openspec-overrides, gristats) has its own README. If you change behavior, update it.

3. **Schema changes are versioned.** Bump the schema's `version` field if you change required fields or rename keys. Backwards-compatible additions don't need a version bump but should be documented.

4. **Keep emission rules and TOML overrides in sync.** Each `bmad-overrides/_bmad/custom/<workflow>.toml` pairs with a `grist-<workflow>-emission.md`. If you change one, check the other.

## Pull request expectations

- Small, focused PRs. One concern per PR.
- Describe the user-visible change in one paragraph at the top of the PR body.
- Include before/after token deltas when adding compression rules — `gristats compare` is the standard tool for this.
- Hold off on adding dependencies unless there's a strong reason. The current code uses only Python stdlib (with optional `tiktoken` for accurate token counts).

## Scope

In scope:

- Better compression for any artifact GRIST already covers.
- New BMAD workflow overrides (anything under `bmad-bmm-*`).
- New OpenSpec schema variants (e.g. `grist-staged` with multi-artifact OpenSpec flow).
- Adapters for other agent frameworks (Hermes, custom in-house frameworks).
- More converters, especially for prose → YAML migrations.
- Performance work on `gristats` (faster transcript parsing, better phase detection).

Out of scope (for now):

- Forks of BMAD or OpenSpec source.
- A model-side fine-tune or proxy.
- Integration with paid services.

## Reporting issues

Open a GitHub issue with:

- What you ran
- What you expected
- What happened (including any `gristats` numbers if relevant)
- The version of BMAD / OpenSpec / Python you're on

For schema bugs, please include a minimal reproducer YAML.

## License

By contributing, you agree your contributions will be licensed under the MIT License (see [LICENSE](LICENSE)).
