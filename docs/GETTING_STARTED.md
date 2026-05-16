# Getting Started

This guide is for first-time module authors using adamant ModpackLib and ModpackFramework.

It explains:
- what the main concepts are
- what each source file is for
- how data moves through a module
- how to build a minimal working module from the template

For the exact API surface, use [API.md](../API.md). For the fuller authoring contract, use [MODULE_AUTHORING.md](MODULE_AUTHORING.md).

## Starting A New Repo

If you are starting from scratch, use the scaffold scripts before writing code.

- new pack shell repo:
  [`Setup/scaffold/new_pack.py`](https://github.com/h2-modpack/Setup/blob/main/scaffold/new_pack.py)
- new module inside an existing shell repo:
  [`Setup/scaffold/new_module.py`](https://github.com/h2-modpack/Setup/blob/main/scaffold/new_module.py)

Those scripts handle the repo and submodule chores so you can get to actual module authoring quickly.

Use them when you need:

- a new modpack shell with Lib, Framework, Setup, and a coordinator already wired
- a new module repo created from the template and registered as a shell submodule

After scaffolding, come back to this guide for the actual code model.

If you want the script workflow and setup details, read the
[Setup README.md](https://github.com/h2-modpack/Setup/blob/main/README.md).

## The Core Model

A module is built from four main pieces:

- `definition`
  Declares required module identity/display metadata, optional storage, and hash layout hints.
- `store`
  Persisted runtime state. Read this from gameplay and hook code.
- `session`
  Staged UI state. Draw code edits this and host/framework plumbing commits it later.
- `host`
  The author-facing view returned by `lib.createModule(...)`. Call `host.tryActivate()` after construction so Framework and standalone hosting can use the registered live host.

Typical module flow:

1. `main.lua` calls `lib.createModule(...)`.
2. The returned author host is kept local in `main.lua`.
3. `host.tryActivate()` registers hooks, overlays, integrations, and the live host.
4. UI code edits staged values through the session passed into draw callbacks.
5. Host/framework plumbing commits staged persistent values when appropriate.
6. Gameplay logic reads persisted state through `store.read(...)`.

## The Most Important Rule

Use the right state object for the right job:

- draw/UI code uses `session`
- gameplay/runtime logic uses `store`

If you ignore that boundary, the module will still often "work", but you will create drift between the UI and the persisted state model.

`lib.createModule(...)` owns the normal construction pipeline so store/session
ownership stays paired. Use the lower-level construction functions only when the
module needs custom setup.
The same `owner` table is used for structural hot-reload tracking and hook
refresh ownership.

## File Roles

The template is split into four files on purpose.

### `src/main.lua`

Owns module wiring:

- imports Lib and stack dependencies
- imports `data.lua`, `logic.lua`, and `ui.lua`
- creates the module through `lib.createModule(...)`
- activates the returned host
- wires optional standalone UI

Keep store/session/host creation here even if the module grows.

### `src/data.lua`

Owns static module data:

- `definition.storage`
- `definition.hashGroupPlan`
- option lists
- lookup tables derived after game import

Use this file to declare module data. UI belongs in `ui.lua`; gameplay behavior belongs in `logic.lua`.

### `src/ui.lua`

Owns immediate-mode UI:

- `internal.DrawTab(imgui, session, host)`
- optional `internal.DrawQuickContent(imgui, session, host)`

This code should read and write staged values through the author-facing `session` it receives from the host.

### `src/logic.lua`

Owns gameplay and mutation behavior:

- `internal.RegisterHooks(host, store)`
- optional `internal.BuildPatchPlan(...)`

This code should read persisted state through the `store` passed to
`RegisterHooks(...)`, patch mutation callbacks, or narrower access/read closures
derived from that store.

## First Module Checklist

Start with the template, then fill in these pieces in order.

### 1. Set module identity in `main.lua`

At minimum:

```lua
local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
    },
    drawTab = function() end,
})
host.tryActivate()
```

Every module must declare `id` and `name`. Coordinated modules also declare
`modpack`. Modules with no custom settings may omit `storage`; Lib still
injects the built-in `Enabled` and `DebugMode` aliases.

Use `lib.tryCreateModule(...)` and `host.tryActivate()` at pack orchestration
boundaries when one invalid module should be skipped without stopping sibling
modules:

```lua
local host, store, err = lib.tryCreateModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
    },
    drawTab = function() end,
})

if host then
    local ok, activateErr = host.tryActivate()
end
```

The `try*` helpers preserve the construction/activation split. They wrap the
same hard-fail APIs, log a module-scoped warning, and return an error instead
of throwing.

### 2. Declare storage in `data.lua`

Example:

```lua
local function BuildStorage()
    return {
        { type = "bool", alias = "FeatureEnabled", default = false },
        { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
    }
end
```

Then attach it to the module definition:

```lua
local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
        storage = BuildStorage(),
    },
    drawTab = function() end,
})
host.tryActivate()
```

Rules:

- `alias` is the store/session key and the persisted backing key
- aliases are direct flat storage identifiers
- normal values persist, stage, and hash by default
- transient values use `persist = false, hash = false`
- transient values live only in session state
- table values use one `type = "table"` root with a uniform `row` schema
- draw code should still access both through `session`
- `Enabled` and `DebugMode` are reserved Lib-owned aliases; do not declare them

For persistent runtime markers that should not appear in UI staging, profiles, or
hashes, declare `stage = false, hash = false` and use
`store.writeUnstaged(...)`.

### 3. Create the module in `main.lua`

```lua
local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
        storage = internal.BuildStorage(),
    },
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
host.tryActivate()
```

The draw path receives the restricted author-facing session through the live host.
The returned store is kept only when gameplay logic needs runtime reads.

### 4. Build the UI in `ui.lua`

Example:

```lua
function internal.DrawTab(ui, session, host)
    lib.widgets.checkbox(ui, session, "FeatureEnabled", {
        label = "Enable Feature",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = internal.MODE_VALUES,
        controlWidth = 180,
    })
end
```

Draw callbacks receive the author-facing session API:

- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`

Commit and reload operations are handled by host/framework plumbing.

### 5. Register gameplay logic in `logic.lua`

If the module only changes configuration/UI, `logic.lua` can stay minimal.

If the module changes live run data:

```lua
local function BuildPatchPlan(plan, host, store)
    if store.read("FeatureEnabled") then
        plan:set(SomeGameTable, "SomeKey", true)
        host.logIf("Enabled SomeGameTable.SomeKey")
    end
end
```

Use `registerPatchMutation` for live run-data edits. If a mutation is not
naturally expressed by the current patch-plan surface, add a patch-plan
operation instead of bypassing the tracked lifecycle.

If the module installs runtime hooks, declare them through ownerless `lib.hooks.*`
calls from `internal.RegisterHooks(...)`:

```lua
function internal.RegisterHooks(host, store)
    lib.hooks.Wrap("SomeGameFunction", function(base, ...)
        local result = base(...)

        if host.isEnabled() and store.read("FeatureEnabled") then
            -- apply module-specific logic to the wrapped call here
        end

        return result
    end)
end
```

### 6. Create the module in `main.lua`

```lua
local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "Example Module",
        storage = internal.BuildStorage(),
    },
    registerPatchMutation = internal.BuildPatchPlan,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
host.tryActivate()
```

This is the main module export.

Framework uses it for coordinated modules. Standalone hosting uses it for module windows and menu items.

If the module has no runtime hooks, `registerHooks` may be omitted.

## Coordinated vs Standalone

### Coordinated

If the module belongs to a Framework-managed pack:

- `host.tryActivate()` registers the module in Lib's live-host registry
- Framework calls `host.drawTab(...)`
- optional quick setup uses `host.drawQuickContent(...)`

### Standalone

If the module is not coordinated:

```lua
local PLUGIN_GUID = _PLUGIN.guid
internal.standaloneUi = lib.standaloneHost(PLUGIN_GUID)
```

Then wire:

- `internal.standaloneUi.renderWindow()` into `rom.gui.add_imgui(...)`
- `internal.standaloneUi.addMenuBar()` into `rom.gui.add_to_menu_bar(...)`

Standalone hosting automatically suppresses itself when the module is coordinated.

## How State Actually Flows

This is the part most new authors get wrong.

### Persisted values

Persisted storage roots live in Chalk config and are exposed through `store.read(...)`.

The UI stages edits in `session`, then host/framework plumbing commits those edits later.

Lib injects two persisted staged aliases into every prepared module definition:

- `Enabled`, the module behavior toggle
- `DebugMode`, diagnostic-only and excluded from hashes/profiles

Module authors should not put these in `definition.storage` or `config.lua`.

### Transient values

Transient aliases never hit persisted config. They only live in `session`.

Examples:

- filter text
- temporary selection state
- ephemeral editor helpers

### Runtime cache values

Runtime cache aliases persist through config but do not enter `session`, profiles,
or hashes. They are for module-owned intent/state that gameplay code needs across
reloads:

```lua
{ type = "bool", alias = "RecordingActive", default = false, stage = false, hash = false }
```

Read and write them through:

```lua
store.writeUnstaged("RecordingActive", true)
local active = store.read("RecordingActive") == true
```

### Packed values

Packed widgets can edit packed child aliases, but storage still persists the packed root. Lib handles the repacking automatically.

### Table values

Table storage models compact ordered rows with one shared row schema:

```lua
{
    type = "table",
    alias = "Tiers",
    maxRows = 10,
    defaultRows = 1,
    row = {
        { type = "bool", alias = "Enabled", default = true },
        { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
    },
}
```

Use `session.table("Tiers")` for staged UI edits and `store.table("Tiers")` for read-only runtime access.
Table handles use colon method syntax, such as `tiers:read(rowIndex, alias)`.
Use `tiers:rowHandle(rowIndex)` when a widget or helper should operate on one row's aliases.

## Common Mistakes

### Reading transient values from `store`

Transient aliases live in `session`. Read them with `session.read(...)` or `session.view`.

### Writing persisted config directly from draw code

Normal draw code should stage values through `session` and let the host/framework commit them.

### Putting gameplay logic in `ui.lua`

Keep UI and game mutation separate. UI edits state; logic applies state.

### Putting UI outside draw functions

Author UI through draw functions such as `internal.DrawTab(ui, session, host)`.

## LuaLS Setup

The template already shows the pattern that gives good editor inference:

```lua
---@type AdamantModpackLib
lib = mods["adamant-ModpackLib"]
```

And for the module internal table:

```lua
---@class TemplateModuleInternal
---@field DrawTab fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil
---@field DrawQuickContent fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil
```

That lets LuaLS infer the author `session` and `host` types through
`internal.DrawTab = function(...)`.

## Recommended Next Reads

After this guide:

1. Read [MODULE_AUTHORING.md](MODULE_AUTHORING.md) for the fuller authoring contract.
2. Use [API.md](../API.md) when you need exact function names and behavior.
3. Use the template source files as the concrete code reference.
