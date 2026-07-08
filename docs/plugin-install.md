# Installing GRIST as a Claude Code Plugin

GRIST can be installed directly as a Claude Code plugin — no cloning or `./install.sh` required. The repo doubles as its own single-plugin marketplace.

## Install

```
/plugin marketplace add techstart-ai/grist-method
/plugin install grist@grist-method
```

To update later:

```
/plugin marketplace update grist-method
```

## What the plugin covers

- **`/grist` slash command** — the four modes: `/grist chat|design|iterate|ship`
- **GRIST skill** — auto-loaded guidance for token-efficient workflows (YAML planning artifacts, ID-addressed references)
- **Hooks** — read-discipline enforcement (PreToolUse on Read) and GRIST YAML validation (PostToolUse on Write/Edit)

## What the plugin does NOT cover

These still require running `./install.sh` from a clone of this repo:

- **BMAD / OpenSpec framework overlays** (`install-bmad.sh`, `install-openspec.sh`)
- **CLAUDE.md project-facts block** — the installer injects project-specific facts into your project's CLAUDE.md
- **`.grist/` project scaffolding** — per-project artifact directories and templates

## Plugin + install.sh coexistence

The plugin and the installer coexist safely: plugin hooks resolve via `${CLAUDE_PLUGIN_ROOT}`, while installer hooks live in your project's `.grist/hooks`. However, you should pick **one** hook source — prefer the plugin's. If both are installed, the same hook logic runs twice; disable one side by setting `GRIST_NO_HOOKS=1` in the environment of whichever source you want silenced.
