# adamant-ModpackLib API

This is the supported Lib surface for modules and coordinators.

## Core Surface

### `lib.createStore(config, definition?)`

Creates the module-owned store facade around persisted config.

Returns:
- `store.read(key)`
- `store.write(key, value)`
- `store.uiState` when `definition.options` or `definition.stateSchema` declares managed fields

Rules:
- pass the full `public.definition`, not a raw schema/options array
- regular `definition.options` keys must be flat strings
- special `definition.stateSchema` keys may use nested path arrays

### `lib.isEnabled(store, packId?)`

Returns `true` only when:
- the module store has `Enabled = true`
- and, if coordinated, the pack-level `ModEnabled` flag is also true

### `lib.affectsRunData(def)`

Returns whether successful lifecycle or config changes require run-data rebuild behavior.

## Mutation Lifecycle

### `lib.inferMutationShape(def)`

Infers one of:
- `patch`
- `manual`
- `hybrid`
- `nil`

### `lib.applyDefinition(def, store)`

Applies a module definition using the inferred lifecycle shape.

### `lib.revertDefinition(def, store)`

Reverts a module definition using the inferred lifecycle shape.

### `lib.reapplyDefinition(def, store)`

Reverts then reapplies a definition. Stops if revert fails.

### `lib.setDefinitionEnabled(def, store, enabled)`

Transactional enable/disable helper:
- runs lifecycle work first
- only writes `Enabled` after success

Behavior:
- `false -> true`: apply
- `true -> true`: reapply
- `true -> false`: revert
- `false -> false`: no-op

### `lib.createBackupSystem()`

Returns:
- `backup(tbl, ...)`
- `restore()`

Use this for manual mutation modules that need first-write backup/restore semantics.

### `lib.createMutationPlan()`

Creates a reversible patch plan for data-mutation modules.

Supported operations:
- `plan:set(tbl, key, value)`
- `plan:setMany(tbl, kv)`
- `plan:transform(tbl, key, fn)`
- `plan:append(tbl, key, value)`
- `plan:appendUnique(tbl, key, value, equivalentFn?)`
- `plan:apply()`
- `plan:revert()`

## Managed UI State

`store.uiState` exists when the definition declares managed fields.

Surface:
- `uiState.view`
- `uiState.get(path)`
- `uiState.set(path, value)`
- `uiState.update(path, fn)`
- `uiState.toggle(path)`
- `uiState.reloadFromConfig()`
- `uiState.flushToConfig()`
- `uiState.isDirty()`

### `lib.runUiStatePass(opts)`

Runs one draw pass for managed state and flushes/commits if dirty.

Important options:
- `uiState`
- `draw(imgui, uiState, theme)`
- `commit(uiState)` optional transactional commit hook
- `onFlushed()` optional success callback

### `lib.commitUiState(def, store, uiState)`

Transactional managed-state commit helper.

Behavior:
- snapshots dirty persisted values
- flushes staged values
- if needed, reapplies runtime state
- on failure, restores persisted values and reloads `uiState`

### `lib.auditAndResyncUiState(name, uiState)`

Audits staged state against persisted config, warns on drift, then reloads staged values.

## Field Helpers

### `lib.drawField(imgui, field, value, width?)`

Renders one field using its registered field type.

### `lib.isFieldVisible(field, values)`

Resolves `visibleIf` against the current flat values table.

### `lib.validateSchema(schema, label)`

Validates schema/options declarations and prepares runtime metadata.

### `lib.getSchemaConfigFields(schema)`

Returns only config-backed fields, excluding separators.

### `lib.valuesEqual(field, a, b)`

Semantic equality helper used by:
- `uiState` audit
- hash default elision

Uses field-type `equals(...)` when provided, otherwise deep structural equality.

### `lib.FieldTypes`

The field-type registry.

Built-in field types are Lib-owned and validated strictly.

## Standalone Helpers

### `lib.standaloneUI(def, store)`

Returns a menu-bar callback for regular modules running without a coordinator.

### `lib.standaloneSpecialUI(def, store, uiState?, opts?)`

Returns `{ renderWindow, addMenuBar }` for special modules running without a coordinator.

## Path Helpers

### `lib.readPath(tbl, key)`

Reads from a flat key or nested path array.

### `lib.writePath(tbl, key, value)`

Writes to a flat key or nested path array, creating intermediate tables as needed.

## Warnings and Logging

### `lib.warn(packId, enabled, fmt, ...)`

Debug-gated framework warning.

### `lib.contractWarn(packId, fmt, ...)`

Always-on framework contract/compatibility warning.

### `lib.log(name, enabled, fmt, ...)`

Module-local debug trace helper.
