# Hard-Cut Migration Guide

This patch is not additive.

The old field-centric declaration model is removed and replaced with:
- `definition.storage`
- `definition.ui`

There is no compatibility layer for:
- `definition.options`
- `definition.stateSchema`
- `lib.validateSchema`
- `lib.prepareField`
- `lib.drawField`
- `lib.drawSteppedRange`
- `lib.FieldTypes`

## New Mental Model

Split the old field descriptor into two layers:

- storage
  - persistence
  - hashing
  - staging identity
  - packed alias ownership
- UI
  - widgets
  - layout
  - alias bindings

## Direct Mappings

### Old scalar field

Old:

```lua
{ type = "checkbox", configKey = "EnabledFlag", label = "Enabled", default = false }
```

New:

```lua
storage = {
    { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
}

ui = {
    { type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" },
}
```

### Old dropdown or radio

Old:

```lua
{ type = "dropdown", configKey = "Mode", label = "Mode", values = { "A", "B" }, default = "A" }
```

New:

```lua
storage = {
    { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
}

ui = {
    { type = "dropdown", binds = { value = "Mode" }, label = "Mode", values = { "A", "B" } },
}
```

### Old stepper

Old:

```lua
{ type = "stepper", configKey = "Count", label = "Count", default = 3, min = 1, max = 9 }
```

New:

```lua
storage = {
    { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
}

ui = {
    { type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 },
}
```

### Old `steppedRange`

Old:
- one composite field pretending to own two config keys

New:
- two storage nodes
- one widget node

```lua
storage = {
    { type = "int", alias = "DepthMin", configKey = "DepthMin", default = 1, min = 1, max = 10 },
    { type = "int", alias = "DepthMax", configKey = "DepthMax", default = 10, min = 1, max = 10 },
}

ui = {
    { type = "steppedRange", binds = { min = "DepthMin", max = "DepthMax" }, label = "Depth", min = 1, max = 10, step = 1 },
}
```

### Old separator/layout field

Old:

```lua
{ type = "separator", label = "Options" }
```

New:

```lua
ui = {
    { type = "separator", label = "Options" },
}
```

No storage node is created.

## Store Migration

### Normal access

Old:

```lua
store.read("EnabledFlag")
store.write("EnabledFlag", true)
```

New:

```lua
store.read("EnabledFlag")
store.write("EnabledFlag", true)
```

This still works when the alias matches the old config key.

### Packed access

Old mixed form:

```lua
store.read("PackedAphrodite", "AttackBanned")
store.write("PackedAphrodite", "AttackBanned", true)
```

New preferred forms:

```lua
store.read("AttackBanned")
store.write("AttackBanned", true)
```

Raw numeric escape hatch:

```lua
store.readBits("PackedAphrodite", 0, 1)
store.writeBits("PackedAphrodite", 0, 1, 1)
```

## UI Migration

### Hosted module UI

Old hosted regular modules rendered `definition.options`.

New hosted regular modules render `definition.ui`.

### Special module reusable UI

Old special modules reused field tables and field helpers.

New special modules should:
- declare reusable UI nodes
- call `lib.prepareUiNode(node, label, definition.storage)` once at load time
- render with `lib.drawUiNode(...)` or `lib.drawUiTree(...)`

`prepareUiNode(...)` accepts raw `definition.storage`; it does not require store creation first.

Example:

```lua
local node = {
    type = "checkbox",
    binds = { value = "EnabledFlag" },
    label = "Enabled",
}

lib.prepareUiNode(node, "MySpecial", definition.storage)
lib.drawUiNode(ui, node, store.uiState)
```

## Validation Changes

Old validation surface:
- `lib.validateSchema`

New validation surface:
- `lib.validateStorage`
- `lib.validateUi`
- `lib.prepareUiNode`

## Registry Changes

Old:
- `lib.FieldTypes`

New:
- `lib.StorageTypes`
- `lib.WidgetTypes`
- `lib.LayoutTypes`

## Migration Checklist

For each module:

1. Replace `definition.options` or `definition.stateSchema` with `definition.storage`.
2. Add `definition.ui` for any declarative hosted UI.
3. Give every storage node a stable `alias`.
4. Convert widget `configKey` references into `binds`.
5. Update special-module custom UI code to use alias-backed `uiState`.
6. Replace old packed partition reads or writes with alias or raw bit helpers.
7. Re-run Lib and Framework tests.

Notes:
- root storage aliases may be omitted when they should match `configKey`
- packed child aliases are still required

## Scope Notes

This patch intentionally avoids a compatibility layer.

That means:
- module code must be updated in the same campaign as Lib
- old declarations are expected to hard-fail instead of degrading silently
