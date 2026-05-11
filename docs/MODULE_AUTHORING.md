# Module Authoring

This guide describes the supported module contract in Lib:
- namespaced public API
- managed storage and explicit `session`
- immediate-mode widgets
- direct draw-function authoring through `internal.DrawTab(ui, session)`

## Lib Surface

Module code should use:
- `lib.config`
- `lib.createModule(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`
- `lib.hooks.*`
- `lib.hashing.*`
- `lib.mutation.*`
- `lib.lifecycle.*`
- `lib.widgets.*`
- `lib.nav.*`

Use the namespaced API directly.

## Basic Module Shape

Typical coordinated module:

```lua
function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "EnabledFlag", {
        label = "Enabled",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 180,
    })
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 140,
    })
end

local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "Example Module",
        tooltip = "What this module does.",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
            { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
        },
    },
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
host.activate()
```

This example assumes coordinated/framework hosting.
For standalone-only modules, `DrawQuickContent` is optional and only matters if some external host uses it.
If the module does not register runtime hooks, omit `registerHooks`.

`lib.createModule(...)` is the recommended path. The lower-level
`prepareDefinition(...)`, `createStore(...)`, and `createModuleHost(...)`
functions remain available when a module needs custom construction.
For `createModule(...)`, `owner` is the single persistent owner for structural
hot-reload tracking and hook refresh ownership.
Call `host.activate()` after construction. That activation step publishes the
live host, registers hooks, runs integrations, and syncs initial runtime behavior.
When `registerHooks` is provided, Lib calls it as
`registerHooks(authorHost, store)`. Modules that use shared runtime helper files
should pass the needed store or narrower access/read closures into those helpers:

```lua
function internal.RegisterHooks(host, store)
    lib.hooks.Wrap(internal, "SomeGameFunction", function(base, ...)
        if not host.isEnabled() then
            return base(...)
        end
        if store.read("FeatureEnabled") then
            -- Runtime behavior reads persisted state through store.
        end
        return base(...)
    end)
end
```

Callback argument order follows a stable convention:
- work surface first when a callback has one, such as `imgui` for draw callbacks or `plan` for patch mutation callbacks
- state/context handle next, using `session` for staged UI state and `host` for runtime/module context
- `store` last when persisted runtime values are needed

Examples: `drawTab(imgui, session, host)`, `registerHooks(host, store)`,
`registerPatchMutation(plan, host, store)`, and manual mutation
`apply(host, store)` / `revert(host, store)`.

## Definition Rules

Meaningful prepared definition fields:
- `modpack`
- `id`
- `name`
- `shortName`
- `tooltip`
- `storage`
- `hashGroupPlan`

Lib rejects any definition key outside the list above so typos and stale author code fail at module load.

Coordinated modules should declare:
- `modpack`
- `id`
- `name`

Modules with no custom settings may omit `storage`; Lib injects built-in
`Enabled` and `DebugMode` aliases during preparation.

Framework behavior:
- every coordinated module gets its own tab
- `shortName` is used as the shorter tab label when present

## Store and State Rules

After store creation:
- use `store.read(alias)` for persisted runtime state
- use the callback-provided `session` for staged UI state
- keep raw Chalk config local to `main.lua`

Draw code should usually read from:
- `session.view`

Runtime/gameplay code should usually read from:
- `store.read(...)`

Host/framework plumbing owns built-in state changes:
- `Enabled` is toggled by Framework or the standalone host
- `DebugMode` is toggled by Framework or the standalone host

Hash/profile plumbing should stage arbitrary decoded aliases through:
- `session.write(alias, value)`
- `session._flushToConfig()`

Draw code stages schema-backed values through `session`. Under the host contract, draw callbacks receive an author session with:
- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`

Use `store.read(...)` from runtime/gameplay code for persisted values. Use `session` for transient aliases and UI edits.

## Storage Authoring

### Persisted roots

```lua
{ type = "int", alias = "Count", default = 3, min = 1, max = 9 }
{ type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 }
```

### Transient roots

```lua
{ type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 }
```

Rules:
- `alias` is the store/session key and persisted backing key
- aliases are direct flat storage identifiers
- normal roots persist, stage, and hash by default
- `persist = false` roots are session-only
- `stage = false` roots read through `store.read(...)` and write through `store.writeUnstaged(...)`
- `hash = false` roots are excluded from hash/profile serialization
- `hash = true` requires both `persist = true` and `stage = true`

Lib injects these built-in aliases into every prepared definition:

| Alias | Declaration | Purpose |
| --- | --- | --- |
| `Enabled` | `{ type = "bool", alias = "Enabled", default = false }` | Module behavior toggle |
| `DebugMode` | `{ type = "bool", alias = "DebugMode", default = false, hash = false }` | Diagnostic toggle |

Do not declare `Enabled` or `DebugMode` in module storage or `config.lua`.

Common shapes:

| Declaration | Use case |
| --- | --- |
| omitted flags | ordinary persisted module setting |
| `persist = false, hash = false` | transient UI state such as filters or active tabs |
| `stage = false, hash = false` | persistent runtime cache read through `store.read(...)` and written through `store.writeUnstaged(...)` |
| `hash = false` | persisted UI preference that should not affect profiles or shared hashes |

### Packed storage

Use `packedInt` when you need alias-addressable packed children:

```lua
{
    type = "packedInt",
    alias = "PackedAphrodite",
    bits = {
        { alias = "AttackBanned", offset = 0, width = 1, type = "bool", default = false },
        { alias = "RarityOverride", offset = 1, width = 2, type = "int", default = 0 },
    },
}
```

If the module treats the packed value as a raw mask, a plain root `int` is enough.

### Table storage

Use `table` for a compact ordered list of rows where every row shares the same schema:

```lua
{
    type = "table",
    alias = "Tiers",
    minRows = 0,
    maxRows = 10,
    defaultRows = 1,
    row = {
        { type = "bool", alias = "Enabled", default = true },
        { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
        {
            type = "packedInt",
            alias = "PackedChoices",
            bits = {
                { alias = "ChoiceA", offset = 0, width = 1, type = "bool", default = false },
                { alias = "ChoiceMode", offset = 1, width = 2, type = "int", default = 0 },
            },
        },
    },
}
```

Rules:
- the table root owns `persist`, `stage`, and `hash`
- row aliases are scoped to one row and do not leak into `session.read(...)`
- rows are compact ordered arrays with no holes
- `defaultRows` creates the default row count; each row uses the row field defaults
- packed child aliases work inside a row just like packed child aliases work globally

Access:

```lua
local tiers = session.table("Tiers")
tiers:append({ Enabled = true, ChoiceA = true })
tiers:write(1, "ChoiceMode", 2)
local mode = tiers:read(1, "ChoiceMode")

local row = tiers:rowHandle(1)
row.write("ChoiceMode", 2)
local selected = row.read("ChoiceMode")
```

Use `store.table(alias)` for read-only runtime access and `session.table(alias)` for staged UI edits.
Table handles are object methods, so call row operations with colon syntax:
`tiers:read(rowIndex, alias)`, `tiers:write(rowIndex, alias, value)`, and `tiers:append(rowValues)`.
Row handles are positional cursors into the current table rows. They expose `read(alias)` and
`getAliasSchema(alias)`, and session-backed row handles also expose `write(alias, value)` and
`reset(alias)`.

## Immediate-Mode UI

Module UI is authored directly in Lua draw functions.

Typical patterns:
- `lib.widgets.checkbox(...)`
- `lib.widgets.dropdown(...)`
- `lib.widgets.radio(...)`
- `lib.widgets.stepper(...)`
- `lib.widgets.packedCheckboxList(...)`
- `lib.nav.verticalTabs(...)`

Use raw ImGui layout as needed:
- `ui.Text(...)`
- `ui.SameLine()`
- `ui.BeginTabBar(...)`
- `ui.BeginChild(...)`

Lib widgets cover common controls. Use raw ImGui for custom structure and layout.

## Quick Content

Framework Quick Setup reads:
- coordinator `renderQuickSetup(ctx)`
- module `DrawQuickContent(ui, session)`

`DrawQuickContent` is a Framework Quick Setup hook.

## Runtime Hooks

Modules that register ModUtil path hooks should do that through `lib.hooks.*`.

Typical shape:

```lua
function internal.RegisterHooks(host, store)
    lib.hooks.Wrap(internal, "GetEligibleLootNames", function(base, ...)
        local result = base(...)
        if host.isEnabled() and store.read("FeatureEnabled") then
            -- inspect or transform the wrapped call here
        end
        return result
    end)
end

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
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
host.activate()
```

Rules:
- use a persistent owner table such as the module `internal`
- declare hook sites inside `RegisterHooks(authorHost, store)`
- call `host.activate()` after construction
- use the keyed overload when one owner needs several hooks on the same path

## Mutation Lifecycle

Register mutation callbacks only when the module actually mutates live run data.

Supported mutation shapes:
- patch only: `registerPatchMutation(plan, host, store)`
- manual only: `registerManualMutation = { apply = function(host, store) ..., revert = function(host, store) ... }`
- hybrid: both

Patch-plan example:

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
    registerPatchMutation = function(plan, host, store)
        plan:set(SomeTable, "Enabled", true)
        plan:appendUnique(SomeTable, "Pool", "NewEntry")
        host.logIf("Built patch plan")
    end,
    drawTab = internal.DrawTab,
})
host.activate()
```

Lib applies and reverts these mutations through the live host. Module authors
normally provide the callbacks and let `createModule(...)` wire the lifecycle.

## Coordinated Modules

Framework discovery requires:
- a live host registered by `host.activate()`
- `host.getIdentity()`
- `host.getMeta()`
- a prepared definition with `storage`

`lib.getLiveModuleHost(...)` exposes that full runtime host for Framework,
standalone hosting, and Lib internals. Module code should normally use the
author host returned by `lib.createModule(...)` instead.

Framework behavior:
- each coordinated module gets its own top-level tab
- `host.drawTab(...)` is the normal rendering contract
- `host.drawQuickContent(...)` participates only in Quick Setup

## Standalone Modules

For non-framework hosting, use:

```lua
local PLUGIN_GUID = _PLUGIN.guid

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
host.activate()

local runtime = lib.standaloneHost(PLUGIN_GUID)

local function registerGui()
    rom.gui.add_imgui(runtime.renderWindow)
    rom.gui.add_to_menu_bar(runtime.addMenuBar)
end
```

Notes:
- `lib.standaloneHost(...)` suppresses its window/menu when the module is coordinated
- `lib.standaloneHost(...)` applies startup lifecycle state for non-coordinated modules
- the standalone window includes built-in:
  - `Enabled`
  - `Debug Mode`
  - `Resync Session`
- the standalone window renders `DrawTab`; Framework Quick Setup renders `DrawQuickContent`

## Complete Example

This is a minimal end-to-end module shape showing:
- `main.lua`
- storage
- `DrawTab`
- optional `DrawQuickContent`
- standalone wiring

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
local chalk = mods["SGG_Modding-Chalk"]
local reload = mods["SGG_Modding-ReLoad"]
---@type AdamantModpackLib
lib = mods["adamant-ModpackLib"]

local config = chalk.auto("config.lua")

local PACK_ID = "example-pack"
local PLUGIN_GUID = _PLUGIN.guid
---@class ExampleModuleInternal
---@field standaloneUi StandaloneRuntime|nil
---@field RegisterHooks fun(host: AuthorHost, store: ManagedStore)|nil
---@field DrawTab fun(imgui: table, session: AuthorSession)|nil
---@field DrawQuickContent fun(imgui: table, session: AuthorSession)|nil
ExampleModule_Internal = ExampleModule_Internal or {}
---@type ExampleModuleInternal
local internal = ExampleModule_Internal

internal.standaloneUi = nil

local function init()
    import_as_fallback(rom.game)

    local host = lib.createModule({
        owner = internal,
        pluginGuid = PLUGIN_GUID,
        config = config,
        definition = {
            modpack = PACK_ID,
            id = "ExampleModule",
            name = "Example Module",
            shortName = "Example",
            tooltip = "Demonstrates the Lib module contract.",
            storage = {
                { type = "bool", alias = "FeatureEnabled", default = false },
                { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
                { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
                {
                    type = "packedInt",
                    alias = "PackedFlags",
                    default = 0,
                    bits = {
                        { alias = "PackedFlags_Attack", label = "Attack", type = "bool", offset = 0, width = 1, default = false },
                        { alias = "PackedFlags_Special", label = "Special", type = "bool", offset = 1, width = 1, default = false },
                    },
                },
            },
        },
        registerHooks = internal.RegisterHooks,
        drawTab = internal.DrawTab,
        drawQuickContent = internal.DrawQuickContent,
    })
    host.activate()

    internal.standaloneUi = lib.standaloneHost(PLUGIN_GUID)
end

function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "FeatureEnabled", {
        label = "Enable Feature",
        tooltip = "Turns the feature logic on for this module.",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 180,
    })

    lib.widgets.inputText(ui, session, "FilterText", {
        label = "Filter",
        controlWidth = 180,
    })

    ui.Separator()
    lib.widgets.text(ui, "Packed Flags")
    lib.widgets.packedCheckboxList(ui, session, "PackedFlags", {
        optionsPerLine = 2,
    })
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 140,
    })
end

function internal.RegisterHooks(host, store)
    lib.hooks.Wrap(internal, "SomeGameFunction", function(base, ...)
        if host.isEnabled() and store.read("FeatureEnabled") then
            -- Optional runtime behavior goes here.
        end
        return base(...)
    end)
end

local loader = reload.auto_single()

local function registerGui()
    rom.gui.add_imgui(function()
        if internal.standaloneUi and internal.standaloneUi.renderWindow then
            internal.standaloneUi.renderWindow()
        end
    end)

    rom.gui.add_to_menu_bar(function()
        if internal.standaloneUi and internal.standaloneUi.addMenuBar then
            internal.standaloneUi.addMenuBar()
        end
    end)
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

Notes on the example:
- `config` and `reload` stay local to `main.lua`
- `store` is passed to runtime hooks and mutation callbacks
- draw callbacks receive the restricted author session through the live host
- `host.activate()` owns live coordinated host registration
- `internal.RegisterHooks(authorHost, store)` is the normal place for `lib.hooks.*` declarations
- `DrawTab` uses raw ImGui for structure and `lib.widgets.*` for controls
- `DrawQuickContent` is optional
- packed widgets use the session or row handle passed to the draw path
