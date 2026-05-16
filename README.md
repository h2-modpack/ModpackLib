# adamant-ModpackLib

Reusable runtime library for Hades II mod authors building modpacks, large
configuration-heavy mods, or coordinated feature bundles.

ModpackLib provides the common plumbing that those projects usually need:

- typed storage definitions for module settings
- a staged UI `session` model for responsive ImGui config screens
- a persistent `store` model for runtime hook logic
- profile and hash helpers for saving, loading, and identifying settings
- mutation helpers for modules that patch run data
- module host helpers for coordinated and standalone usage
- reusable ImGui widgets and navigation helpers

The library is designed around immediate-mode UI. Module authors write normal
draw functions, then expose them through a module host:

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        id = "ExampleModule",
        name = "Example Module",
        ...
    },
    registerHooks = logic.registerHooks,
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
host.tryActivate()
```

`pluginGuid` is the stable lifecycle identity; Lib owns the internal hot-reload
state for hooks, overlays, integrations, mutation runtime, and structural reload
tracking. Pass `registerHooks` when the module uses `lib.hooks.*`.
`host.tryActivate()` registers the live host for coordinated discovery and standalone hosting.
Every module definition must declare a stable `id` and display `name`; `modpack`
is optional and marks modules that participate in Framework coordination.

## Docs

- [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)
  Start here for the core concepts, file roles, and first module flow.
- [API.md](API.md)
  Public namespaces, functions, and data contracts.
- [docs/MODULE_AUTHORING.md](docs/MODULE_AUTHORING.md)
  Deeper authoring guide for storage, sessions, lifecycle, and hosting.
- [docs/WIDGETS.md](docs/WIDGETS.md)
  Widget and navigation helpers for module UIs.
- [docs/UI_PERFORMANCE.md](docs/UI_PERFORMANCE.md)
  Render-path guidance for responsive ImGui screens.
- [docs/IMGUI_LUA_REFERENCE.md](docs/IMGUI_LUA_REFERENCE.md)
  Notes on the Dear ImGui Lua binding used by the stack.
- [docs/RELOAD_MODUTIL_CHALK_REFERENCE.md](docs/RELOAD_MODUTIL_CHALK_REFERENCE.md)
  Third-party stack reference for ReLoad, ModUtil, and Chalk behavior.
- [docs/HOT_RELOAD_ARCHITECTURE.md](docs/HOT_RELOAD_ARCHITECTURE.md)
  Stack hot-reload contract for Lib, Framework, Core, and coordinated modules.
- [docs/MIGRATING_MUTATIONS.md](docs/MIGRATING_MUTATIONS.md)
  Migration notes for the patch-only runtime mutation API.
- [docs/MIGRATING_PLUGIN_GUID_RUNTIME.md](docs/MIGRATING_PLUGIN_GUID_RUNTIME.md)
  Migration notes for ownerless module lifecycle identity.
- [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
  Accepted architecture boundaries and runtime constraints.
- [docs/FUTURE_RISKS.md](docs/FUTURE_RISKS.md)
  Forward-looking design notes for tempting changes with non-obvious tradeoffs.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib contract.

## Public Surface

- `lib.config`
- `lib.coordinator`
- `lib.mutation`
- `lib.hashing`
- `lib.hooks`
- `lib.overlays`
- `lib.integrations`
- `lib.gameObject`
- `lib.imguiHelpers`
- `lib.widgets`
- `lib.nav`

Common top-level helpers:
- `lib.createModule(...)`
- `lib.tryCreateModule(...)`
- `lib.standaloneHost(...)`
- `lib.standaloneUiBridge(...)`
- `lib.getLiveModuleHost(...)`
- `lib.coordinator.isRegistered(...)`
- `lib.resetStorageToDefaults(...)`

Most authors start with `lib.createModule(...)`.
Pack orchestrators that should skip invalid modules instead of stopping sibling
modules can use `lib.tryCreateModule(...)` plus `host.tryActivate()`.
See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for the recommended project shape.

## Validation

```bash
cd adamant-ModpackLib
lua52.exe tests/all.lua
```
