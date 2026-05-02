# Contributing to adamant-ModpackLib

`adamant-ModpackLib` owns the shared module contract for the modpack stack.

Keep the public surface:
- small
- explicit
- namespaced
- aligned with immediate-mode module authoring

## Read This First

- [README.md](README.md)
- [API.md](API.md)
- [docs/MODULE_AUTHORING.md](docs/MODULE_AUTHORING.md)
- [docs/HOT_RELOAD_ARCHITECTURE.md](docs/HOT_RELOAD_ARCHITECTURE.md)
- [docs/WIDGETS.md](docs/WIDGETS.md)

## Contribution Rules

- Do not widen the public API casually.
- Keep docs aligned with code in the same change.
- Document the supported contract directly.
- Keep storage schema behavior behind `lib.createStore` / internal storage; keep UI authoring in `lib.widgets` / `lib.nav`.
- Unknown module misuse may warn and degrade where intended. Lib-owned contract breakage should fail loudly.

## Validation

```bash
cd adamant-ModpackLib
lua52.exe tests/all.lua
```
