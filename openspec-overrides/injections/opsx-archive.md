<!-- GRIST:BEGIN — managed by grist-method installer. Do not edit between markers. -->

## GRIST ARCHIVE MERGE:

For each entry in `delta.add`, `delta.modify`, `delta.remove` in `change.grist.yaml`:
1. Locate the target spec at `openspec/specs/<spec>/spec.grist.yaml` (preferred) or `openspec/specs/<spec>/spec.md` (legacy fallback).
2. If target is `.grist.yaml`: structural YAML merge — append/replace/remove req entries by `id`.
3. If target is `.md`: best-effort markdown merge (OpenSpec standard archive logic).

After merge, move the change folder to `openspec/changes/archive/<YYYY-MM-DD>-<change-id>/` as OpenSpec normally does. Do not delete `change.grist.yaml` — archive preserves it.

<!-- GRIST:END -->
