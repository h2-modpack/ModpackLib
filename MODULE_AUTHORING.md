# Module Authoring

This guide describes the current supported module contract in Lib.

It is written for the live v2 surface:
- namespaced public API
- rect-based UI runtime
- `vstack` / `hstack` / `tabs` / `split` layout model

It does **not** document the old v1 layout system.

## Scope

This guide covers:
- regular vs special modules
- `public.definition`
- `lib.store.create(...)`
- storage authoring
- UI authoring
- custom widgets and layouts
- standalone helpers

It does **not** cover:
- built-in widget and layout registry details
- internal file organization
- full storage type contracts

Those are covered in:
- [FIELD_REGISTRY.md](FIELD_REGISTRY.md)

## Preferred Lib Surface

New module code should use the namespaced API:

- `lib.store.create(...)`
- `lib.definition.validate(...)`
- `lib.mutation.apply(...)`
- `lib.mutation.revert(...)`
- `lib.mutation.reapply(...)`
- `lib.mutation.setEnabled(...)`
- `lib.ui.validate(...)`
- `lib.ui.drawNode(...)`
- `lib.ui.drawTree(...)`
- `lib.storage.validate(...)`
- `lib.storage.getAliases(...)`
- `lib.special.runPass(...)`
- `lib.special.runDerivedText(...)`
- `lib.special.getCachedPreparedNode(...)`
- `lib.special.standaloneUI(...)`
- `lib.coordinator.register(...)`
- `lib.coordinator.isEnabled(...)`
- `lib.coordinator.standaloneUI(...)`
- `lib.registry.widgetHelpers.drawStructuredAt(...)`

Flat `lib.*` aliases still exist for compatibility, but new modules should not
introduce more of them.

## Shared Module Shape

Every module follows the same basic pattern:

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
}

public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store
```

The meaningful authoring fields are:
- metadata
- `storage`
- `ui`
- optional `customTypes`
- optional mutation lifecycle exports

There is no supported use of:
- `definition.options`
- `definition.stateSchema`

## Definition Overview

Lib and Framework read different parts of the flat `definition` table.

Framework discovery and routing:
- `modpack`
- `special`
- `id`
- `name`
- `shortName`
- `category`
- `subgroup`
- `tooltip`
- `default`

Lib store and UI:
- `storage`
- `ui`
- `customTypes`

Quick UI:
- `selectQuickUi`

Mutation and run-data lifecycle:
- `affectsRunData`
- `patchPlan`
- `apply`
- `revert`

Hash/profile encoding may also read:
- `hashGroups`

The table stays flat, but you should think about fields by consumer.

## Regular vs Special

Use a **regular** module when:
- it belongs under Framework category/subgroup routing
- the UI can be expressed through `definition.ui`
- Quick Setup should come from declarative `quick = true` nodes
- the stable hash namespace should be `definition.id`

Use a **special** module when:
- the module owns its own dedicated sidebar tab
- it needs caller-owned draw orchestration
- it needs `DrawTab` and/or `DrawQuickContent`
- category/subgroup routing does not make sense

Practical rule:
- choose regular unless you have a concrete reason to choose special

## Regular Modules

Example:

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    category = "Run Mods",
    subgroup = "General",
    tooltip = "What this module does.",
    default = false,
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 },
    },
    ui = {
        {
            type = "vstack",
            gap = 8,
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", quick = true },
                {
                    type = "dropdown",
                    binds = { value = "Mode" },
                    label = "Mode",
                    values = { "Vanilla", "Chaos" },
                    controlWidth = 180,
                },
            },
        },
    },
}

public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store
```

Rules:
- `definition.id` is the regular-module hash namespace
- storage aliases should stay stable after release
- widgets bind by alias
- `quick = true` marks quick candidates
- `quickId` is optional but recommended when runtime quick filtering is used
- `selectQuickUi(...)` may filter the quick candidates shown by Framework

Standalone helper:

```lua
rom.gui.add_to_menu_bar(lib.coordinator.standaloneUI(public.definition, public.store))
```

## Special Modules

Example:

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
    id = "ExampleSpecial",
    name = "Example Special",
    shortName = "Example",
    special = true,
    default = false,
    affectsRunData = true,
    storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "A", maxLen = 16 },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    },
    ui = {},
}

public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store
```

Rules:
- special-module hash namespace is the module `modName`
- `shortName` is optional
- `category`, `subgroup`, and `selectQuickUi` do not matter for special modules
- aliases are still the UI-facing access surface

Supported special entrypoints:
- `public.DrawQuickContent(ui, uiState, theme)`
- `public.DrawTab(ui, uiState, theme)`
- optional hooks:
  - `public.BeforeDrawQuickContent(ui, uiState, theme)`
  - `public.AfterDrawQuickContent(ui, uiState, theme, changed)`
  - `public.BeforeDrawTab(ui, uiState, theme)`
  - `public.AfterDrawTab(ui, uiState, theme, changed)`

If `public.DrawTab` is absent and `definition.ui` exists, Lib can render
`definition.ui` automatically.

Standalone helper:

```lua
local specialUi = lib.special.standaloneUI(
    public.definition,
    public.store,
    public.store.uiState,
    {
        getDrawQuickContent = function() return public.DrawQuickContent end,
        getDrawTab = function() return public.DrawTab end,
        getBeforeDrawTab = function() return public.BeforeDrawTab end,
        getAfterDrawTab = function() return public.AfterDrawTab end,
    }
)

rom.gui.add_imgui(specialUi.renderWindow)
rom.gui.add_to_menu_bar(specialUi.addMenuBar)
```

Use special modules when the module needs caller-owned draw orchestration, not
just a bigger declarative tree.

## Store and State Rules

After store creation:
- use `store.read(alias)` and `store.write(alias, value)` for persisted module state
- use `store.uiState` for transient or staged UI state
- keep raw Chalk config local to `main.lua`

Avoid:

```lua
if config.Strict then
    -- ...
end
```

Use:

```lua
if store.read("Strict") then
    -- ...
end
```

`uiState` surface:
- `uiState.view`
- `uiState.get(alias)`
- `uiState.set(alias, value)`
- `uiState.update(alias, fn)`
- `uiState.toggle(alias)`
- `uiState.reset(alias)`
- `uiState.reloadFromConfig()`

Rules:
- persisted aliases stage in `uiState` and commit later
- transient aliases live only in `uiState`
- do not write alias-backed config directly during draw

## Storage Authoring

### Scalar roots

```lua
{ type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
{ type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 }
{ type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 }
```

### Transient roots

Use `lifetime = "transient"` for UI-only aliases:

```lua
{ type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 }
{ type = "string", alias = "FilterMode", lifetime = "transient", default = "all", maxLen = 16 }
```

Rules:
- persisted roots use `configKey`
- transient roots use `lifetime = "transient"`
- `configKey` and `lifetime` are mutually exclusive
- transient roots must declare an explicit `alias`
- transient roots do not persist and do not hash

### Packed storage

Use `packedInt` when you need alias-addressable packed children:

```lua
{
    type = "packedInt",
    alias = "PackedAphrodite",
    configKey = "PackedAphrodite",
    bits = {
        { alias = "AttackBanned", offset = 0, width = 1, type = "bool", default = false },
        { alias = "RarityOverride", offset = 4, width = 2, type = "int", default = 0 },
    },
}
```

If a module only treats a packed value as a raw mask, keep it as a plain root
`int` instead.

## UI Authoring

The old layout surface is gone.

Do **not** use:
- `panel`
- `group`
- `horizontalTabs`
- `verticalTabs`
- widget `geometry`

Use:
- `vstack`
- `hstack`
- `collapsible`
- `tabs`
- `scrollRegion`
- `split`

### Basic widgets

Examples:

```lua
{ type = "text", text = "Section Title" }
{ type = "separator" }
{ type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }
{ type = "inputText", binds = { value = "FilterText" }, label = "Filter", controlWidth = 180 }
{ type = "dropdown", binds = { value = "Mode" }, label = "Mode", values = { "Vanilla", "Chaos" }, controlWidth = 180 }
{ type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1, valueWidth = 48, valueAlign = "center" }
{ type = "button", label = "Reset", onClick = function(uiState) uiState.reset("FilterText") end }
```

### Layouts

Vertical section:

```lua
{
    type = "vstack",
    gap = 8,
    children = {
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
        { type = "dropdown", binds = { value = "Mode" }, label = "Mode", values = { "A", "B" } },
    },
}
```

Simple row:

```lua
{
    type = "hstack",
    gap = 12,
    children = {
        { type = "text", text = "Mode" },
        { type = "dropdown", binds = { value = "Mode" }, values = { "A", "B" }, controlWidth = 160 },
    },
}
```

Collapsible section:

```lua
{
    type = "collapsible",
    label = "Advanced",
    defaultOpen = false,
    children = {
        { type = "checkbox", binds = { value = "Strict" }, label = "Strict" },
    },
}
```

Tabbed surface:

```lua
{
    type = "tabs",
    id = "MainTabs",
    orientation = "vertical",
    navWidth = 180,
    binds = { activeTab = "SelectedTab" },
    children = {
        {
            tabId = "settings",
            tabLabel = "Settings",
            type = "vstack",
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
            },
        },
    },
}
```

Two-pane split:

```lua
{
    type = "split",
    orientation = "horizontal",
    gap = 12,
    firstSize = 220,
    children = {
        { type = "vstack", children = { { type = "text", text = "Sidebar" } } },
        { type = "vstack", children = { { type = "text", text = "Detail" } } },
    },
}
```

## Visibility

Any widget or layout may declare `visibleIf`.

Forms:

```lua
visibleIf = "Enabled"
visibleIf = { alias = "Mode", value = "Forced" }
visibleIf = { alias = "Mode", anyOf = { "Forced", "Chaos" } }
```

Invisible nodes are not drawn and do not consume layout space.

## Quick UI

Any declarative node may opt into Quick Setup:

```lua
quick = true
```

Quick ids are:
- `node.quickId` when explicitly provided
- otherwise derived from `node.binds`

Modules may optionally filter them:

```lua
public.definition.selectQuickUi = function(store, uiState, quickNodes)
    return { "value=Enabled" }
end
```

Return:
- `nil` to show all quick candidates
- one quick id string
- an array of quick ids
- or a `{ [quickId] = true }` set

## Built-in Widget Notes

`confirmButton`
- popup-based confirmation flow
- supports optional `confirmLabel`, `cancelLabel`, `onConfirm`

`inputText` / `dropdown` / `mappedDropdown`
- use `controlWidth` when you want a fixed control width

`stepper` / `steppedRange`
- use `valueWidth` and `valueAlign`
- `steppedRange` binds to two aliases: `binds = { min = "DepthMin", max = "DepthMax" }`

`text`
- supports optional `width`
- supports optional `color`

`packedCheckboxList`
- renders one visible packed child per line
- optional:
  - `binds.filterText`
  - `binds.filterMode`

## Custom Types

Modules may declare:

```lua
public.definition.customTypes = {
    widgets = {},
    layouts = {},
}
```

These are module-local extensions to the built-in registries.

### Custom widgets

Contract:

```lua
myWidget = {
    binds = {
        value = { storageType = "int" },
    },
    validate = function(node, prefix) end,
    draw = function(imgui, node, bound, x, y, availWidth, availHeight, uiState)
        return consumedWidth, consumedHeight, changed
    end,
}
```

Rules:
- custom widgets are leaf renderers by default
- the draw contract is rect-based
- return honest consumed size
- do not rely on ambient cursor state as your surrounding layout contract

Widget bind specs may declare:
- `storageType`
- optional `rootType`
- optional `optional = true`

For local custom widget composition, prefer:
- `lib.registry.widgetHelpers.drawStructuredAt(...)`
- `lib.registry.widgetHelpers.estimateRowAdvanceY(...)`

### Custom layouts

Contract:

```lua
myLayout = {
    validate = function(node, prefix) end,
    render = function(imgui, node, drawChild, x, y, availWidth, availHeight, uiState, bound)
        return consumedWidth, consumedHeight, changed
    end,
}
```

Rules:
- layouts own child placement
- `drawChild(...)` is a positioned child renderer
- return honest consumed size

## Caching and Derived Text

Lib-owned mechanical caches already exist for:
- prepared node metadata
- registry merge results
- bound/preparation plumbing

Module-owned semantic caches should stay module-side.

Use:
- `lib.special.getCachedPreparedNode(...)` for reusable prepared subtrees
- `lib.special.runDerivedText(...)` for derived display strings backed by your own cache

Rules:
- keep cache signatures module-side
- invalidate semantic caches explicitly when the meaning changes
- do not depend on Lib's internal caches directly

## Modules That Affect Run Data

Declare:

```lua
public.definition.affectsRunData = true
```

### Patch-only

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(RoomData.RoomA, "ForcedReward", "Devotion")
end
```

### Manual-only

```lua
local backup, restore = lib.mutation.createBackup()

public.definition.apply = function()
    backup(SomeTable, "SomeKey")
    SomeTable.SomeKey = 123
end

public.definition.revert = restore
```

### Hybrid

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "SomeKey", 123)
end

public.definition.apply = function()
    -- procedural remainder
end

public.definition.revert = function()
    -- procedural remainder revert
end
```

Ordering:
- apply: patch, then manual
- revert: manual, then patch

## Stability Rules

After release, treat these as compatibility-sensitive:
- regular `definition.id`
- special `modName`
- storage root aliases
- storage defaults
- storage type hash encodings

If an explicit root `alias` exists, that alias is the frozen hash/profile
surface. If a root omits `alias`, the stringified `configKey` effectively
becomes that stable surface.

## Minimal Example

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
    id = "HelloModule",
    name = "Hello Module",
    category = "Run Mods",
    subgroup = "General",
    default = false,
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
        { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
    },
    ui = {
        {
            type = "vstack",
            gap = 8,
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", quick = true },
                { type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 },
            },
        },
    },
}

public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store
```
