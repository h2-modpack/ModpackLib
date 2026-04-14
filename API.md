# adamant-ModpackLib API

This is the current preferred Lib surface.

Preferred usage is namespaced:
- `lib.store.*`
- `lib.definition.*`
- `lib.mutation.*`
- `lib.ui.*`
- `lib.storage.*`
- `lib.special.*`
- `lib.coordinator.*`
- `lib.logging.*`
- `lib.accessors.*`
- `lib.registry.*`

Old flat `lib.*` names still exist, but only as compatibility aliases through:
- [legacy_api.lua](/home/ayyatma/Projects/modding/modpack/run-director-modpack/adamant-ModpackLib/src/compat/legacy_api.lua)

## Core Model

Modules now declare:
- `definition.storage`
- `definition.ui`
- optional `definition.customTypes`

There is no supported compatibility layer for:
- `definition.options`
- `definition.stateSchema`

Storage owns persistence and hashing.
UI owns widgets and layout.

## `lib.store`

### `lib.store.create(config, definition, dataDefaults?)`

Creates the managed store facade around persisted module config.

`dataDefaults` is the static table returned by `import("config.lua")`.
When provided, Lib uses it to seed storage-node defaults for nodes that do not
declare an explicit `default`.

Before storage/UI validation, Lib also runs:
- `lib.definition.validate(definition, label?)`

Normal access on the returned store:
- `store.read(keyOrAlias)`
- `store.write(keyOrAlias, value)`

Raw packed access on the returned store:
- `store.readBits(configKey, offset, width)`
- `store.writeBits(configKey, offset, width, value)`

Managed state on the returned store:
- `store.storage`
- `store.ui`
- `store.uiState` when `definition.storage` exists

Rules:
- pass the full `public.definition`
- root storage aliases default to `configKey` when omitted
- packed child aliases are required
- widgets bind by alias, not raw `configKey`
- `store.read/write` accept either a storage alias or a raw config key

What this helper does:
- validates the module definition
- validates storage and UI declarations when present
- prepares storage alias/root metadata
- creates `store.uiState` when `definition.storage` exists
- exposes a small managed runtime for reading and writing persisted values

Important behavior:
- transient aliases are not readable or writable through `store.read(...)` / `store.write(...)`
- packed child aliases read and write through their owning packed root automatically
- raw config-path fallback still works when no storage alias matches
- if `definition.ui` exists without `definition.storage`, Lib warns and does not create `uiState`

Typical use:

```lua
public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store
```

### `store.read(keyOrAlias)`

Reads:
- a root storage alias
- a packed child alias
- or a raw config key fallback

Examples:

```lua
store.read("Enabled")
store.read("BridalGlowTargetBoon")
store.read("AttackBanned")
store.read({ "Nested", "Flag" })
```

### `store.write(keyOrAlias, value)`

Writes:
- a root storage alias
- a packed child alias
- or a raw config key fallback

Packed child writes re-encode the owning packed root automatically.

### `store.readBits(configKey, offset, width)`

Raw numeric packed read.

Use this when you intentionally want:
- no alias lookup
- no bool coercion
- no storage-node semantics

### `store.writeBits(configKey, offset, width, value)`

Raw numeric packed write.

Behavior:
- clamps to the target bit width
- updates only the selected bit range

## `lib.definition`

### `lib.definition.validate(def, label?)`

Runs the early definition warning pass for the flat module definition table.

Current warnings cover:
- unknown top-level definition keys
- wrong value types for known definition fields
- regular-only fields used on specials
- special-only fields used on regular modules
- incomplete manual lifecycle declarations like `apply` without `revert`
- `affectsRunData = true` without any supported lifecycle

This helper does not replace storage/UI validation.

## `lib.mutation`

### `lib.mutation.inferShape(def)`

Infers the mutation lifecycle shape for a module definition:
- `patch`
- `manual`
- `hybrid`
- or `nil`

### `lib.mutation.mutatesRunData(def)`

Returns whether a module definition declares `affectsRunData = true`.

### `lib.mutation.createBackup()`

Returns:
- `backup(tbl, ...)`
- `restore()`

Used for reversible table mutations.

### `lib.mutation.createPlan()`

Creates a reversible mutation plan with these methods:
- `plan.set(...)`
- `plan.setMany(...)`
- `plan.transform(...)`
- `plan.append(...)`
- `plan.appendUnique(...)`
- `plan.removeElement(...)`
- `plan.setElement(...)`
- `plan.apply()`
- `plan.revert()`

This is the main helper for patch-plan modules.

Typical use:

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "Enabled", true)
    plan:appendUnique(SomeTable, "Pool", "NewEntry")
end
```

Operation notes:
- `set` and `setMany` replace values directly
- `transform` computes the next value from the current one during apply
- `append` and `appendUnique` require the target field to be a list when present
- `removeElement` and `setElement` operate on the first equivalent list entry
- `apply()` is one-shot until `revert()` is called
- `revert()` restores the original captured values from the last successful apply

### `lib.mutation.apply(def, store)`

Applies the module definition’s mutation lifecycle to live run data.

### `lib.mutation.revert(def, store)`

Reverts the module definition’s mutation lifecycle from live run data.

### `lib.mutation.reapply(def, store)`

Reverts and reapplies the module definition’s mutation lifecycle.

### `lib.mutation.setEnabled(def, store, enabled)`

Transitions the module’s enabled state and applies/reverts live mutation state
as needed.

## `lib.storage`

### `lib.storage.validate(storage, label)`

Validates and prepares a storage declaration table.

Validation covers:
- alias uniqueness
- root `configKey` uniqueness
- packed bit overlap
- packed child alias registration
- root lifetime validation

Preparation side effects:
- populates root-node metadata on each validated storage node
- builds alias lookup tables
- builds persistent-root lookup tables
- materializes packed child alias nodes under `packedInt` roots

Storage may be passed in raw declaration form.
Validation prepares it in place for later:
- `lib.storage.getRoots(...)`
- `lib.storage.getAliases(...)`
- `lib.store.create(...)`
- `lib.ui.validate(...)`

### `lib.storage.getRoots(storage)`

Returns the prepared persistent root storage nodes.

### `lib.storage.getAliases(storage)`

Returns the prepared alias map:

```lua
local aliases = lib.storage.getAliases(definition.storage)
local node = aliases.AttackBanned
```

Includes:
- root aliases
- packed child aliases
- transient root aliases

### `lib.storage.getPackWidth(node)`

Returns the packed width contributed by a storage node when the node type
supports packing.

### `lib.storage.valuesEqual(node, a, b)`

Semantic equality helper used by:
- UI state drift checks
- storage-aware comparisons

Uses storage-type `equals(...)` when provided, otherwise deep structural equality.

## `lib.ui`

### `lib.ui.validate(ui, label, storage, customTypes?)`

Validates a UI declaration table against storage.

The `storage` argument may be:
- raw `definition.storage`
- or already-prepared storage metadata

Validation covers:
- widget/layout node types
- alias existence
- widget/storage type compatibility
- `visibleIf` alias validity
- module-local custom widget/layout contracts when `customTypes` is provided

### `lib.ui.prepareNode(node, label?, storage, customTypes?)`

Validates and prepares one UI node in isolation.

Useful for special modules that build reusable widget/layout nodes at load time.

This mutates the node in place with prepared metadata such as:
- cached widget/layout type references
- derived quick ids
- stable ImGui ids for widgets

### `lib.ui.prepareWidgetNode(node, label?, customTypes?)`

Validates and prepares one direct-draw widget node without requiring storage binds.

### `lib.ui.prepareNodes(nodes, label?, storage, customTypes?)`

Validates and prepares an ordered UI node list.

Returns a small alias-to-node registry keyed by declared widget binds.
This is mainly useful for special modules that want stable references into a
prepared node tree.

### `lib.ui.isVisible(node, values)`

Evaluates `visibleIf` against the current alias-value table.

### `lib.ui.drawNode(imgui, node, uiState, width?, customTypes?)`

Draws one prepared UI node against alias-backed `uiState`.

Contract:
- pass prepared nodes created through `lib.ui.prepareNode(...)` / `lib.ui.prepareNodes(...)`
- Lib owns structured child start positions during draw
- structured children are expected to settle the cursor at the bottom of the space they consumed before returning

Return value:
- `true` when the draw mutated bound UI state or the widget/layout explicitly reported a change

Common use:
- draw one prepared special-module node
- draw one cached custom layout subtree

### `lib.ui.drawTree(imgui, nodes, uiState, width?, customTypes?)`

Draws an ordered UI node list.

This is the normal helper for:
- hosted regular module `definition.ui`
- simple special-module fallback rendering
- prepared multi-node fragments

### `lib.ui.collectQuick(nodes, out?, customTypes?)`

Returns all widget nodes marked `quick = true`, recursing through layout `children`.

Quick ids come from:
- `node.quickId` when provided
- otherwise a derived id based on declared binds

### `lib.ui.getQuickId(node)`

Returns the stable quick candidate id used by quick-selection callbacks.

## `lib.special`

### `lib.special.runPass(opts)`

Runs a special-module UI pass with optional:
- `beforeDraw`
- `draw`
- `afterDraw`
- `commit`
- `onFlushed`

Normal flow:
1. validate that `opts.uiState` has the required transactional shape
2. run `beforeDraw(imgui, uiState, theme)` when provided
3. run `draw(imgui, uiState, theme)`
4. run `afterDraw(imgui, uiState, theme, changed)` when provided
5. if `uiState` is dirty:
   - call `opts.commit(uiState)` when provided
   - otherwise flush directly with `uiState.flushToConfig()`
6. run `onFlushed()` after a successful flush/commit

This is the standard orchestration helper for special-module quick-content and tab passes.

### `lib.special.runDerivedText(uiState, entries, cache?)`

Recomputes derived text aliases for `uiState`.

Each entry may declare:
- `alias`
- `compute(uiState)`
- optional `signature(uiState)`

When `signature(...)` is provided and unchanged, the cached derived value is reused.

### `lib.special.getCachedPreparedNode(cacheEntry, signature, buildFn, opts?)`

Reuses or rebuilds a prepared UI node based on a caller-owned cache entry and
signature.

Return values:
- next cache entry
- current node
- whether the node was rebuilt
- previous node, when one existed

This is the standard helper for caller-owned prepared-node caches in special modules.

### `lib.special.auditAndResyncState(name, uiState)`

Audits staged UI state against persisted config values and reloads staged values
from config.

Useful when:
- a special module wants a manual “audit + resync” action
- external config changes may have drifted from staged UI state

### `lib.special.commitState(def, store, uiState)`

Flushes staged UI state to config and reapplies live mutation state when needed.

Behavior:
- no-ops when `uiState` is not dirty
- flushes dirty UI state to config
- reapplies live mutation state when the module mutates run data and is enabled
- rolls back config state when reapply fails

### `lib.special.standaloneUI(def, store, uiState?, opts?)`

Creates standalone window/menu-bar renderers for a special module.

Supported optional hooks/accessors include:
- `drawQuickContent`
- `beforeDrawQuickContent`
- `afterDrawQuickContent`
- `drawTab`
- `beforeDrawTab`
- `afterDrawTab`
- `getDrawQuickContent`
- `getBeforeDrawQuickContent`
- `getAfterDrawQuickContent`
- `getDrawTab`
- `getBeforeDrawTab`
- `getAfterDrawTab`

Return value:
- table with:
  - `renderWindow`
  - `addMenuBar`

Use this for special modules that want a standalone Lib-owned window instead of Framework hosting.

## `lib.coordinator`

### `lib.coordinator.register(packId, config)`

Registers coordinator metadata for a coordinated pack.

### `lib.coordinator.isCoordinated(packId)`

Returns whether a pack id is coordinated.

### `lib.coordinator.isEnabled(store, packId?)`

Returns whether a coordinated or standalone module should currently be treated
as enabled.

### `lib.coordinator.standaloneUI(def, store)`

Creates the standalone menu renderer for a regular module.

This is the regular-module counterpart to `lib.special.standaloneUI(...)`.

## `lib.logging`

### `lib.logging.warnIf(packId, enabled, fmt, ...)`

Emits a prefixed warning when `enabled` is true.

### `lib.logging.warn(packId, fmt, ...)`

Emits a prefixed warning unconditionally.

### `lib.logging.logIf(name, enabled, fmt, ...)`

Emits a prefixed log line when `enabled` is true.

## `lib.accessors`

### `lib.accessors.readNestedPath(tbl, key)`

Reads a value from a table using either a flat key or a nested key path.

### `lib.accessors.writeNestedPath(tbl, key, value)`

Writes a value into a table using either a flat key or a nested key path.

### `lib.accessors.readPackedBits(packed, offset, width)`

Reads a bitfield value from a packed integer.

### `lib.accessors.writePackedBits(packed, offset, width, value)`

Writes a bitfield value into a packed integer.

## `lib.registry`

### `lib.registry.storage`

Lib-owned storage registry.

### `lib.registry.widgets`

Lib-owned widget registry.

### `lib.registry.layouts`

Lib-owned layout registry.

### `lib.registry.widgetHelpers`

Public namespace for small widget-authoring helpers that do not belong on widget
type contract tables.

Current helpers:
- `lib.registry.widgetHelpers.drawStructuredAt(imgui, startX, startY, fallbackHeight, drawFn)`
- `lib.registry.widgetHelpers.estimateRowAdvanceY(imgui)`

Use these when a custom widget wants:
- local explicit positioning
- honest footprint settlement
- Lib-style row/height behavior without recursively rendering another structured widget tree

### `lib.registry.validate()`

Hard-validates registry contracts.

## Compatibility

Flat `lib.*` names still exist for compatibility, but new code should use the
namespaced surface described above.
