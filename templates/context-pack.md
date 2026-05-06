# Project context pack

> Cache-aware: stable content only. Volatile (current sprint, in-progress story) lives in `.grist/volatile.md`.
> Aim ≥1024 tokens stable so Anthropic prompt cache holds it. Re-emitted verbatim every session — agents must NOT re-quote.

## Project

`name`: <project>
`stack`: see `arch#stack`
`prd`: prd#<slug>
`arch`: arch#<slug>

## Invariants (from PRD)

<!-- Copy the `invariants:` list from prd.grist.yaml verbatim. These rarely change. -->
- <invariant 1>
- <invariant 2>

## Architecture decisions (load-bearing)

<!-- Copy the `decisions:` list from architecture.grist.yaml. Drop the `alts:` field — too noisy for context. -->
- d1: <decision> — <why>
- d2: <decision> — <why>

## Glossary

<!-- Project-specific terms that newcomers (or agents) need to disambiguate. ≤1 line each. -->
- <term>: <definition>

## Conventions

<!-- Replaces BMAD's project-context.md. Keep terse. -->
- file naming: <pattern>
- test framework: <name>
- commit style: conventional commits, ≤50 char subject
- branch naming: <pattern>
- review SLA: <duration>

## NFRs (active)

<!-- From prd.nfrs + arch.nfrs, deduplicated. -->
- <nfr 1>
- <nfr 2>

## External dependencies

- <name> — <one-line purpose, doc link or `arch#external`>

---

# Volatile — DO NOT INCLUDE IN PACK

Live in `.grist/volatile.md`:
- current sprint #
- in-progress story IDs
- recent decisions not yet promoted to arch.decisions
- temporary blockers
