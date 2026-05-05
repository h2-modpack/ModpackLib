# adamant-ModpackLib API

This is the public Lib surface.

Preferred usage uses top-level module authoring helpers plus namespaces for specialized APIs:
- `lib.prepareDefinition(...)`
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`
- `lib.hashing.*`
- `lib.hooks.*`
- `lib.overlays.*`
- `lib.integrations.*`
- `lib.gameObject.*`
- `lib.mutation.*`
- `lib.lifecycle.*`
- `lib.logging.*`
- `lib.widgets.*`
- `lib.nav.*`
- `lib.imguiHelpers.*`

The top-level `lib.config` export also exposes Lib's Chalk config.

## Core Model

Modules declare:
- `definition.modpack`
- `definition.id`
- `definition.name`
- `definition.storage`
- optional mutation lifecycle fields:
  - `affectsRunData`
  - `patchPlan`
  - `apply`
  - `revert`
- optional post-commit observer:
  - `onSettingsCommitted`

Modules create a behavior host:
- `lib.createModuleHost(...)`

That host owns:
- `drawTab`
- optional `drawQuickContent`
- built-in lifecycle/state helpers for Framework and standalone hosting

Module behavior is hosted through Lib's live host registry.

## `lib.config`

Live Lib config loaded from Chalk.

Meaningful field:
- `lib.config.DebugMode`

## `lib.integrations`

Small registry for optional cross-module cooperation. Modules can publish a
domain-named integration API, and consumers can use it when present while
remaining fully functional when absent.

Typical provider:

```lua
lib.integrations.register("run-director.god-availability", internal.definition.id, {
    isActive = function()
        return lib.isModuleEnabled(store, internal.definition.modpack)
    end,
    isAvailable = function(godKey)
        return true
    end,
})
```

Typical consumer:

```lua
local active = lib.integrations.invoke("run-director.god-availability", "isActive", false)
if active then
    return lib.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey) ~= false
end
return true
```

Surface:
- `lib.integrations.register(id, providerId, api)`
- `lib.integrations.unregister(id, providerId)`
- `lib.integrations.unregisterProvider(providerId)`
- `lib.integrations.invoke(id, methodName, fallback, ...)`
- `lib.integrations.get(id)`
- `lib.integrations.list(id)`

Rules:
- integration ids should describe domain behavior, not consumer names
- absence means the optional enhancement is inactive
- provider APIs should be safe to call when their module is disabled
- consumers should prefer `invoke(...)` so Lib resolves current provider behavior at call time
- when multiple providers exist, `get(id)` returns the most recently registered provider

## `lib.gameObject`

Namespaced state buckets attached to live game object tables such as `CurrentRun`, room data, or loot data.

Use this for object-owned runtime state whose lifetime should follow that game table. It is not persisted, staged, hashed, profiled, or reset by Lib.

Typical use:

```lua
local state = lib.gameObject.get(CurrentRun, PACK_ID, MODULE_ID, "run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

Surface:
- `lib.gameObject.get(object, packId, moduleId, key, factory?)`
- `lib.gameObject.peek(object, packId, moduleId, key)`
- `lib.gameObject.clear(object, packId, moduleId, key)`

Rules:
- `object` must be a table
- `packId`, `moduleId`, and `key` must be non-empty strings
- `factory` runs only when the bucket is missing
- `factory` must return a table when provided
- state is namespaced under one Lib-owned root on the object

## Store And Session

### `lib.prepareDefinition(owner, dataDefaultsOrDefinition, definition?)`

Creates the canonical definition object for a module from a raw authored definition table.

What it does:
- clones the authored definition into a Lib-owned table
- hydrates missing persistent storage defaults from `dataDefaults` when provided
- validates top-level definition keys and types
- prepares `definition.storage` metadata for later `createStore(...)` use
- preserves optional `definition.hashGroupPlan` hash-compaction hints as structural contract data
- records a structural fingerprint on the persistent `owner` table when provided
- warns and marks `owner.requiresFullReload = true` when a later hot reload changes structural definition shape

Structural reload checks cover:
- `modpack`
- `id`
- `name`
- `shortName`
- `affectsRunData`
- `storage`
- `hashGroupPlan`

Behavior-only fields such as:
- `patchPlan`
- `apply`
- `revert`
- `onSettingsCommitted`

do not trigger a structural reload warning.

Typical use:

```lua
local definition = lib.prepareDefinition(internal, dataDefaults, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = internal.BuildStorage(dataDefaults),
    hashGroupPlan = internal.BuildHashGroupPlan(),
    patchPlan = internal.BuildPatchPlan,
})
```

When a module does not need `dataDefaults`, the two-argument form is still valid:

```lua
local definition = lib.prepareDefinition(internal, {
    id = "ExampleModule",
    name = "Example Module",
    storage = internal.BuildStorage(),
})
```

Treat the returned definition as the authoritative module contract and pass it to `createStore(...)` and `createModuleHost(...)`.

`hashGroupPlan` is the preferred author-facing input for complex hash layouts:

```lua
hashGroupPlan = {
    {
        keyPrefix = "global",
        items = {
            { "EnabledFlag", "Tier" },
            "DebugFlag",
        },
    },
}
```

Rules:
- `keyPrefix` names a hash-group family
- `items` is an ordered list of logical bundles
- each item may be a single alias string or a list of aliases that must stay together
- Framework may use these hints to pack multiple persisted roots into shorter canonical hash tokens

### `lib.createStore(config, definition)`

Creates the managed store facade around persisted module config.
`definition.storage` is required.

What it does:
- warns on malformed top-level definition fields
- validates and prepares `definition.storage`
- returns a separate `session` for staged UI state
- exposes persisted read helpers

Typical use:

```lua
local store, session = lib.createStore(config, definition)
```

Ownership rule: `store` and `session` are a matched pair created for one prepared
`definition` and one backing config table. Pass them together to
`lib.createModuleHost(...)`, and do not mix a store from one `createStore(...)`
call with a session from another. Recreate the pair together on module reload.

Returned surface:
- `store.read(keyOrAlias)`
- `store.getRuntimeState()`

Persisted writes happen through semantic helpers or session flushes:

```lua
lib.lifecycle.setEnabled(def, store, enabled)
lib.lifecycle.setDebugMode(store, enabled)
```

Use `setEnabled` for module enabled toggles. It persists the `Enabled` flag and applies/reverts mutation state as needed. Use `setDebugMode` for module debug toggles. Module/host plumbing can use `session.write(...)` plus `session._flushToConfig()` for immediate persisted writes such as profile/hash import. Ordinary draw-code edits stay staged and commit through the host/framework flow.

Rules:
- keep each `store, session` pair together for its lifetime
- widgets and draw code should usually read staged values from `session.view`
- runtime/gameplay code should read persisted values through `store.read(...)`
- module-owned runtime markers declared with `runtime = true` should write through `store.getRuntimeState()`
- enabled toggles should write through `lib.lifecycle.setEnabled(def, store, enabled)`
- debug toggles should write through `lib.lifecycle.setDebugMode(store, enabled)`
- profile/hash plumbing should stage values through `session.write(...)` and flush them through `session._flushToConfig()`
- transient aliases are read from `session`
- transient aliases stay out of persisted config
- runtime aliases are excluded from session, hash, profile, and reset-to-defaults surfaces

Runtime-only persisted storage is declared on ordinary storage nodes:

```lua
{
    type = "bool",
    alias = "BatchRecordingArmed",
    configKey = "BatchRecordingArmed",
    default = false,
    runtime = true,
}
```

Use it for module-owned runtime intent or small reload/restart markers that should not affect UI staging, profiles, or config hashes:

```lua
local runtime = store.getRuntimeState()
runtime.write("BatchRecordingArmed", true)
local armed = runtime.read("BatchRecordingArmed") == true
```

`runtime.write(alias, value)` only accepts aliases declared with `runtime = true`.

### `session`

Managed staged UI state for the module.

Useful surface:
- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`
- `session.isDirty()`
- `session.auditMismatches()`

Host/framework plumbing methods:
- `session._flushToConfig()`
- `session._reloadFromConfig()`
- `session._captureDirtyConfigSnapshot()`
- `session._restoreConfigSnapshot(snapshot)`

When a module is rendered through `lib.createModuleHost(...)`, draw callbacks receive a restricted author-facing session view with:
- `view`
- `read(alias)`
- `write(alias, value)`
- `reset(alias)`
- `resetToDefaults(opts?)`

Behavior:
- persisted aliases stage in `session` and only hit config on flush/commit
- transient aliases live only in `session`
- packed child aliases re-encode their owning packed root automatically

`session.read(alias)` returns:
- current staged value

## Reset Helpers

### `lib.resetStorageToDefaults(storage, session, opts?)`

Resets changed persistent storage roots back to their defaults in the staged `session`.

Returns:
- `changed`
- `count`

Options:
- `exclude = { Alias = true }` skips specific root aliases.

## `lib.hooks`

Reload-stable wrappers around ModUtil path hooks.

Use a persistent owner table, typically the module's `internal` table.

### `lib.hooks.Wrap(owner, path, handler)`

Registers or updates a stable `modutil.mod.Path.Wrap(...)` dispatcher.

Also supports:
- `lib.hooks.Wrap(owner, path, key, handler)`

Use the keyed form when one owner registers more than one wrap against the same path.

### `lib.hooks.Override(owner, path, replacement)`

Registers or updates a stable `modutil.mod.Path.Override(...)`.

Also supports:
- `lib.hooks.Override(owner, path, key, replacement)`

Function replacements are dispatched through a stable wrapper so reloading updates behavior without stacking another override.

### `lib.hooks.Context.Wrap(owner, path, context)`

Registers or updates a stable `modutil.mod.Path.Context.Wrap(...)` dispatcher.

Also supports:
- `lib.hooks.Context.Wrap(owner, path, key, context)`

### Typical module pattern

```lua
function internal.RegisterHooks()
    lib.hooks.Wrap(internal, "GetEligibleLootNames", function(base, ...)
        local result = base(...)
        -- inspect or transform the wrapped call here
        return result
    end)
end

local PLUGIN_GUID = _PLUGIN.guid

lib.createModuleHost({
    pluginGuid = PLUGIN_GUID,
    definition = internal.definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
})
```

When `createModuleHost(...)` receives `hookOwner` and `registerHooks`, it runs the registration pass as part of host creation and deactivates hooks omitted by a later pass for the same owner.

## `lib.overlays`

Retained HUD text helpers for shared overlay placement.

Overlay visibility has two layers:
- Lib applies a global game-HUD gate, currently based on `ShowingCombatUI`.
- Each overlay can also provide its own `visible` boolean or callback.
- Overlays can declare an `owner`; callers can suppress that owner while its configuration UI is being drawn.

When the global gate is closed, lib hides all retained overlay components even if their own `visible` callback returns true. Text callbacks may still be refreshed so the display is current when the game HUD returns.

Current managed region:
- `middleRightStack`: a right-anchored vertical stack used for framework markers and module status text.

Order bands:
- `lib.overlays.order.framework`
- `lib.overlays.order.module`
- `lib.overlays.order.debug`

### `lib.overlays.registerStackedText(opts)`

Registers one text box in a managed stack region.

Useful for single-line overlays where the whole line can share one font and alignment.

### `lib.overlays.registerStackedRow(opts)`

Registers one multi-column row in a managed stack region.

Columns are declared left-to-right:

```lua
lib.overlays.registerStackedRow({
    id = "example.timer",
    owner = PLUGIN_GUID,
    region = "middleRightStack",
    order = lib.overlays.order.module,
    columnGap = 6,
    columns = {
        {
            key = "label",
            minWidth = 42,
            justify = "Right",
            text = "IGT:",
            textArgs = { Font = "P22UndergroundSCMedium" },
        },
        {
            key = "time",
            minWidth = 96,
            justify = "Right",
            text = function() return "00:00.00" end,
            textArgs = { Font = "MonospaceTypewriterBold" },
        },
    },
})
```

`minWidth` reserves layout space so columns line up across rows. It does not clip text.

Stacked handles expose two refresh paths:
- `refresh()` recomputes region layout, visibility, and text.
- `refreshText()` updates retained text only and is intended for hot paths where row visibility/order is known to be stable.

### `lib.overlays.setOwnerSuppressed(owner, suppressed)`

Hides or restores every overlay registered with `owner = owner`. Suppressed overlays are also removed from managed stack layout, so remaining entries close the gap.

Framework uses this to hide a module's runtime overlay while that module's `drawTab` or `drawQuickContent` surface is being drawn.

## `lib.hashing`

Hash/profile serialization and packed-bit helpers.

### `lib.hashing.getRoots(storage)`

Returns prepared persisted root nodes for hash/profile serialization.

### `lib.hashing.getAliases(storage)`

Returns the prepared alias map.

Includes:
- persisted root aliases
- transient root aliases
- packed child aliases

### `lib.hashing.valuesEqual(node, a, b)`

Storage-aware equality helper for comparing persisted/hash values.

### `lib.hashing.getPackWidth(node)`

Returns the derived pack width for a node type that supports packing.

### `lib.hashing.toHash(node, value)`

Encodes one storage value for hash/profile serialization.

### `lib.hashing.fromHash(node, str)`

Decodes one storage value from hash/profile serialization.

### `lib.hashing.readPackedBits(packed, offset, width)`

Raw numeric bit extraction helper.

### `lib.hashing.writePackedBits(packed, offset, width, value)`

Raw numeric bit write helper.

## `lib.mutation`

### `lib.mutation.createBackup()`

Returns:
- `backup(tbl, ...)`
- `restore()`

For reversible table mutation capture.

### `lib.mutation.createPlan()`

Creates a reversible mutation plan with:
- `plan:set(...)`
- `plan:setMany(...)`
- `plan:transform(...)`
- `plan:append(...)`
- `plan:appendUnique(...)`
- `plan:removeElement(...)`
- `plan:setElement(...)`
- `plan:apply()`
- `plan:revert()`


## `lib.lifecycle`

Framework/host-facing helpers for module lifecycle orchestration, built-in module controls, and staged session commits.

### `lib.lifecycle.inferMutation(def)`

Infers the mutation lifecycle shape:
- `patch`
- `manual`
- `hybrid`
- or `nil`

### `lib.lifecycle.registerCoordinator(packId, config)`

Registers coordinator config for a pack. Framework uses this during coordinator initialization.

### `lib.lifecycle.setEnabled(def, store, enabled)`

Transitions persisted enabled state and applies/reverts mutation state as needed.

### `lib.lifecycle.setDebugMode(store, enabled)`

Writes the persisted debug-mode flag for a module store.

### `lib.lifecycle.affectsRunData(def)`

Returns whether the module definition opts into live run-data mutation behavior.

### `lib.lifecycle.applyMutation(def, store)`

Applies the module's mutation lifecycle.
Manual lifecycle hooks receive the same store as `apply(store)`.

### `lib.lifecycle.revertMutation(def, store)`

Reverts the module's mutation lifecycle.
Manual lifecycle hooks receive the same store as `revert(store)`.

### `lib.lifecycle.reapplyMutation(def, store)`

Reverts and reapplies the module's mutation lifecycle.

### `lib.lifecycle.applyOnLoad(def, store)`

Syncs live mutation state to the module's effective enabled state on load. Framework calls this for coordinated modules; `lib.standaloneHost(...)` calls it for standalone modules.

### `lib.lifecycle.resyncSession(def, session)`

Audits staged state against persisted config, logs drift, then reloads staged values from config.

### `lib.lifecycle.commitSession(def, store, session)`

Transactional commit helper for staged `session`.

Behavior:
- flushes staged persisted values to config
- if the module is enabled and `affectsRunData`, reapplies mutation state
- calls `definition.onSettingsCommitted(store)` after a successful dirty commit when present
- on failure, restores the previous config snapshot and reloads `session`

`onSettingsCommitted` is a post-commit observer for rebuilding derived runtime/UI structures. It is not transactional; callback errors are warned and do not roll back the committed config.

### `lib.lifecycle.notifySettingsCommitted(def, store)`

Runs `definition.onSettingsCommitted(store)` when present. Host flush paths use this after direct staged writes, so profile/hash imports and normal UI commits share the same observer boundary.

## Standalone Host

### `lib.createModuleHost(opts)`

Creates a behavior-only host object around:
- `pluginGuid`
- `definition`
- `store`
- `session`
- optional `hookOwner`
- optional `registerHooks`
- `drawTab`
- optional `drawQuickContent`

`drawTab` and `drawQuickContent` receive a restricted author session:
- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`

Commit and reload behavior stays on the host object.

If `registerHooks` is provided:
- `hookOwner` must be a persistent table
- the host runs `registerHooks()` during host creation
- hook declarations made through `lib.hooks.*` are refreshed as one registration pass for that owner

Returned surface:
- `host.getIdentity()`
- `host.getMeta()`
- `host.affectsRunData()`
- `host.getHashHints()`
- `host.getStorage()`
- `host.read(aliasOrKey)`
- `host.writeAndFlush(aliasOrKey, value)`
- `host.stage(aliasOrKey, value)`
- `host.flush()`
- `host.reloadFromConfig()`
- `host.resync()`
- `host.resetToDefaults(opts?)`
- `host.commitIfDirty()`
- `host.isEnabled()`
- `host.setEnabled(enabled)`
- `host.setDebugMode(enabled)`
- `host.applyOnLoad()`
- `host.applyMutation()`
- `host.revertMutation()`
- `host.drawTab(imgui)`
- `host.drawQuickContent(imgui)`

Use this as the bridge between module state and either:
- Framework hosting
- standalone window/menu hosting

Behavior:
- when a coordinator is already registered for `definition.modpack`, host creation immediately syncs the module's live mutation state through `host.applyOnLoad()`
- otherwise startup sync is owned by Framework or standalone hosting

### `lib.standaloneHost(pluginGuid)`

Initializes standalone module hosting and returns window/menu-bar renderers.

Useful when the module is not framework-hosted.

`pluginGuid` must be the same plugin guid passed to `lib.createModuleHost(...)`.

Returned surface:
- `runtime.renderWindow()`
- `runtime.addMenuBar()`

Behavior:
- resolves the module's live host through the explicit `pluginGuid`
- applies on-load lifecycle state for non-coordinated modules
- suppresses the standalone window/menu when the module is coordinated
- renders built-in controls for:
  - `Enabled`
  - `Debug Mode`
  - `Resync Session`
- then calls `moduleHost.drawTab(...)`
- commits dirty staged state through `moduleHost.commitIfDirty()`

## Module Coordination Queries

### `lib.isModuleCoordinated(packId)`

Returns whether a pack id is registered.

### `lib.isModuleEnabled(store, packId?)`

Returns whether a module should currently be treated as enabled, taking pack-level coordination into account when present.

## `lib.logging`

### `lib.logging.warnIf(packId, enabled, fmt, ...)`

Conditionally emits a module-scoped warning.

### `lib.logging.warn(packId, fmt, ...)`

Unconditionally emits a module-scoped warning.

### `lib.logging.logIf(name, enabled, fmt, ...)`

Conditionally emits a module-scoped log line.

## `lib.widgets`

Immediate-mode widget helpers.

Built-ins:
- `lib.widgets.separator(imgui)`
- `lib.widgets.text(imgui, text, opts?)`
- `lib.widgets.button(imgui, label, opts?)`
- `lib.widgets.confirmButton(imgui, id, label, opts?)`
- `lib.widgets.inputText(imgui, session, alias, opts?)`
- `lib.widgets.dropdown(imgui, session, alias, opts?)`
- `lib.widgets.mappedDropdown(imgui, session, alias, opts?)`
- `lib.widgets.packedDropdown(imgui, session, alias, store, opts?)`
- `lib.widgets.radio(imgui, session, alias, opts?)`
- `lib.widgets.mappedRadio(imgui, session, alias, opts?)`
- `lib.widgets.packedRadio(imgui, session, alias, store, opts?)`
- `lib.widgets.stepper(imgui, session, alias, opts?)`
- `lib.widgets.steppedRange(imgui, session, minAlias, maxAlias, opts?)`
- `lib.widgets.checkbox(imgui, session, alias, opts?)`
- `lib.widgets.packedCheckboxList(imgui, session, alias, store, opts?)`

These are direct immediate-mode helpers.

## `lib.imguiHelpers`

Low-level ImGui binding helpers used by Lib widgets and available to module UI code.

Exports:
- `lib.imguiHelpers.ImGuiComboFlags`
- `lib.imguiHelpers.ImGuiCol`
- `lib.imguiHelpers.ImGuiTreeNodeFlags`
- `lib.imguiHelpers.unpackColor(color)`

The enum tables normalize ReturnOfModding ImGui constants that are passed as raw integers in Lua.

## `lib.nav`

### `lib.nav.verticalTabs(imgui, opts)`

Simple immediate-mode vertical tab rail.

Inputs:
- `id`
- `tabs`
- `activeKey`
- optional `navWidth`
- optional `height`

Each tab entry may include:
- `key`
- `label`
- optional `group`
- optional `color`

Returns:
- next `activeKey`

### `lib.nav.isVisible(session, condition)`

Evaluates a `visibleIf`-style condition against `session.view`.

Supported forms:
- `"AliasName"`
- `{ alias = "AliasName", value = ... }`
- `{ alias = "AliasName", anyOf = { ... } }`

