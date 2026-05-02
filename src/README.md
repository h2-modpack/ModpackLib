# adamant-ModpackLib

Shared runtime and immediate-mode UI toolkit for adamant modpack modules.

Lib now owns:
- managed module storage and explicit `session`
- storage typing and normalization
- hash/profile encoding helpers
- mutation lifecycle helpers for `affectsRunData` modules
- standalone hosting helpers
- immediate-mode widgets and navigation helpers

Lib does not own a declarative UI tree/runtime anymore.
New module UI should be written directly in module draw functions such as
`internal.DrawTab(ui, session)` and optional `internal.DrawQuickContent(ui, session)`,
then published through `lib.createModuleHost(...)`.

## For Players

Install this when a mod or modpack lists it as a dependency. Most mod managers
install it automatically.

This package does not add gameplay content by itself. It provides shared runtime
helpers used by other adamant mods.

## For Mod Authors

Author-facing docs live in the repository root:
- `README.md`
- `API.md`
- `docs/GETTING_STARTED.md`
- `docs/MODULE_AUTHORING.md`
- `docs/WIDGETS.md`
- `docs/HOT_RELOAD_ARCHITECTURE.md`

## Current Public Namespaces

- `lib.config`
- `lib.logging`
- `lib.lifecycle`
- `lib.mutation`
- `lib.hashing`
- `lib.hooks`
- `lib.integrations`
- `lib.widgets`
- `lib.nav`
- `lib.imguiHelpers`

Common top-level helpers:
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`

This packaged README is intentionally short so it remains useful inside mod
manager package views.
