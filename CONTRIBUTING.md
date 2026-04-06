# Contributing to adamant-ModpackLib

`adamant-ModpackLib` owns the shared module contract for the modpack stack. Keep the public surface small, explicit, and aligned with the template repo.

## Read This First

- [README.md](README.md) for package overview
- [API.md](API.md) for the supported public API
- [MODULE_AUTHORING.md](MODULE_AUTHORING.md) for regular/special module authoring and the `affectsRunData` lifecycle paths
- [FIELD_REGISTRY.md](FIELD_REGISTRY.md) for the field type registry, primitives, widgets, and layout types

## Contribution Rules

- Do not widen the public API casually. Treat `store`, `uiState`, lifecycle helpers, and field types as release-facing contract.
- Keep docs and templates aligned with code in the same change.
- Prefer documenting the live contract over preserving migration history.
- Unknown module-side misuse should degrade safely where intended. Lib-owned contract breakage should fail loudly.

## Validation

```bash
cd adamant-ModpackLib
lua tests/all.lua
```
