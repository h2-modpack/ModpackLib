# adamant-ModpackLib

Shared utility library for adamant modpack modules.

It owns:
- the store contract
- managed `uiState`
- field types
- lifecycle helpers for `affectsRunData` modules
- standalone regular/special UI helpers

## Docs

- [API.md](API.md)
- [MODULE_AUTHORING.md](MODULE_AUTHORING.md)
- [FIELD_TYPES.md](FIELD_TYPES.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Validation

```bash
cd adamant-ModpackLib
lua tests/all.lua
```
