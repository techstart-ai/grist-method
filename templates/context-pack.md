# Project facts checklist

> Stable project facts belong in your CLAUDE.md under a `## Project facts` heading.
> CLAUDE.md loads once at session start and sits in the always-cached prompt prefix —
> no Read call ever needed. Keep volatile facts OUT of it (they go in `.grist/volatile.md`,
> read on demand) so the prefix stays stable and lean.

## Sections for CLAUDE.md `## Project facts`

Copy the sections below into CLAUDE.md, fill the placeholders, keep terse.

### Project
- `name`: <project>
- `prd`: prd#<slug> · `arch`: arch#<slug> (stack: see `arch#stack`)

### Invariants (from PRD)
<!-- Copy the `invariants:` list from prd.grist.yaml verbatim. These rarely change. -->
- <invariant 1>
- <invariant 2>

### Architecture decisions (load-bearing)
<!-- From architecture.grist.yaml `decisions:`. Drop the `alts:` field — too noisy. -->
- d1: <decision> — <why>
- d2: <decision> — <why>

### Glossary
<!-- Project-specific terms agents must disambiguate. ≤1 line each. -->
- <term>: <definition>

### Conventions
- file naming: <pattern>
- test framework: <name>
- commit style: conventional commits, ≤50 char subject
- branch naming: <pattern>
- review SLA: <duration>

### NFRs (active)
<!-- From prd.nfrs + arch.nfrs, deduplicated. -->
- <nfr 1>
- <nfr 2>

### External dependencies
- <name> — <one-line purpose, doc link or `arch#external`>

## Volatile — keep OUT of CLAUDE.md

Lives in `.grist/volatile.md`; agents read it only when phase-relevant:
- current sprint #
- in-progress story IDs
- recent decisions not yet promoted to arch.decisions
- temporary blockers

## Referencing artifacts

Reference artifacts by ID (`prd#E1`, `arch#C2`), resolved via the `grist-get`
slice resolver (`gristats/grist-get.py`). Never re-read whole artifact files.
