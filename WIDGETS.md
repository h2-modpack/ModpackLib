# Widgets, Nav, and Storage

Current live coverage:
- storage typing and packing
- immediate-mode widgets
- navigation helpers

It does not describe a declarative UI tree/runtime anymore.

## Storage

Storage lives under `lib.storage`.

Built-in root types:
- `bool`
- `int`
- `string`
- `packedInt`

Supported helpers:
- `lib.storage.validate(storage, label)`
- `lib.storage.getRoots(storage)`
- `lib.storage.getAliases(storage)`
- `lib.storage.getPackWidth(node)`
- `lib.storage.valuesEqual(node, a, b)`
- `lib.storage.toHash(node, value)`
- `lib.storage.fromHash(node, str)`
- `lib.storage.readPackedBits(...)`
- `lib.storage.writePackedBits(...)`

Storage is now the only typed schema layer left in Lib.

## Widgets

Widgets live under `lib.widgets`.

Current built-ins:
- `separator`
- `text`
- `button`
- `confirmButton`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `packedDropdown`
- `radio`
- `mappedRadio`
- `packedRadio`
- `stepper`
- `steppedRange`
- `checkbox`
- `packedCheckboxList`

These are direct immediate-mode helpers.

They are not:
- prepared nodes
- registry entries
- declarative widget descriptors

Typical call shape:

```lua
lib.widgets.dropdown(ui, uiState, "Mode", {
    label = "Mode",
    values = { "Vanilla", "Chaos" },
    controlWidth = 180,
})
```

All bound widgets return:
- `true` when they changed staged `uiState`
- `false` otherwise

## Common concepts

### Bound widgets

Most widgets bind to one alias in `uiState.view`:
- `checkbox`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `radio`
- `mappedRadio`
- `stepper`

Some bind to packed roots and therefore also need `store`:
- `packedDropdown`
- `packedRadio`
- `packedCheckboxList`

One binds to two aliases:
- `steppedRange(minAlias, maxAlias, ...)`

### Labels and tooltips

Most leaf widgets support:
- `label`
- `tooltip`

The label is rendered inline by the widget itself.
If you need more custom layout, write the surrounding ImGui yourself and use the widget with an empty label.

### Colors

Some widgets support value coloring:
- `text.color`
- `checkbox.color`
- `dropdown.valueColors`
- `mappedDropdown` option colors
- `radio.valueColors`
- `mappedRadio` option colors
- packed widget `valueColors`

Colors are RGBA tables:

```lua
{ 1, 0.8, 0, 1 }
```

## Base widgets

### `lib.widgets.separator(imgui)`

Thin wrapper around `imgui.Separator()`.

Use when:
- you want a Lib-level helper for consistency

### `lib.widgets.text(imgui, text, opts?)`

Options:
- `color`
- `tooltip`
- `alignToFramePadding`

Use when:
- you want a text line with optional color or tooltip

Example:

```lua
lib.widgets.text(ui, "Underworld", {
    color = { 0.8, 0.7, 0.4, 1 },
    alignToFramePadding = true,
})
```

### `lib.widgets.button(imgui, label, opts?)`

Options:
- `id`
- `tooltip`
- `onClick(imgui)`

Notes:
- returns whether the button was clicked
- `onClick` is optional convenience only; you can ignore it and use the boolean return directly

### `lib.widgets.confirmButton(imgui, id, label, opts?)`

Renders a button that opens a confirmation popup.

Options:
- `tooltip`
- `confirmLabel`
- `cancelLabel`
- `onConfirm(imgui)`

Notes:
- returns `true` only when the confirm action is taken
- this is good for destructive or global reset actions

## Input widget

### `lib.widgets.inputText(imgui, uiState, alias, opts?)`

Options:
- `label`
- `tooltip`
- `maxLen`
- `controlWidth`
- `controlGap`

Behavior:
- reads current text from `uiState.view[alias]`
- writes the edited string back through `uiState.set(alias, nextValue)`

Use when:
- the bound alias is a string field
- you need plain text entry or a simple filter box

## Choice widgets

### `lib.widgets.dropdown(imgui, uiState, alias, opts?)`

Options:
- `label`
- `tooltip`
- `values`
- `default`
- `displayValues`
- `valueColors`
- `controlWidth`
- `controlGap`

Behavior:
- binds one alias to one value from `values`
- preview text comes from `displayValues[value]` when present, else `tostring(value)`
- if the staged value is invalid, it falls back to:
  - a valid `default`
  - else the first entry in `values`

Use when:
- the widget owns a fixed explicit choice list

### `lib.widgets.mappedDropdown(imgui, uiState, alias, opts?)`

Options:
- `label`
- `tooltip`
- `controlWidth`
- `controlGap`
- `getPreview(view)`
- `getPreviewColor(view)`
- `getOptions(view)`

Each returned option may include:
- `id`
- `label`
- `value`
- `color`
- `onSelect(option, uiState)`

Behavior:
- the option list is computed from live staged state
- if an option provides `onSelect`, that callback owns the write behavior
- otherwise the widget writes `option.value` to `alias`

Use when:
- the choice list is dynamic
- preview text depends on derived state
- selecting an option needs custom logic

Example:

```lua
lib.widgets.mappedDropdown(ui, uiState, "SelectedRoot", {
    label = "Root",
    controlWidth = 220,
    getPreview = function(view)
        return view.SelectedRoot ~= "" and view.SelectedRoot or "Choose Root"
    end,
    getOptions = function(view)
        return {
            { label = "Aphrodite", value = "Aphrodite" },
            { label = "Apollo", value = "Apollo" },
            {
                label = "Clear",
                onSelect = function(_, state)
                    state.set("SelectedRoot", "")
                    return true
                end,
            },
        }
    end,
})
```

### `lib.widgets.packedDropdown(imgui, uiState, alias, store, opts?)`

Single-choice dropdown over a packed root.

Options:
- `label`
- `tooltip`
- `controlWidth`
- `controlGap`
- `displayValues`
- `valueColors`
- `noneLabel`
- `multipleLabel`
- `selectionMode`

`selectionMode`:
- `singleEnabled`
- `singleRemaining`

Behavior:
- resolves packed children from `store.getPackedAliases(alias)` first
- falls back to `uiState.getAliasNode(alias)._bitAliases` if needed
- classifies current packed state as:
  - none
  - single
  - multiple

Use when:
- a packed root represents one selected child out of many
- or the inverse "all except one" style via `singleRemaining`

Example:

```lua
lib.widgets.packedDropdown(ui, uiState, "PackedForcedBoon", store, {
    label = "Force 1",
    noneLabel = "None",
    selectionMode = "singleEnabled",
    displayValues = {
        PackedForcedBoon_Attack = "Attack",
        PackedForcedBoon_Special = "Special",
        PackedForcedBoon_Cast = "Cast",
    },
    controlWidth = 180,
})
```

### `lib.widgets.radio(imgui, uiState, alias, opts?)`

Options:
- `label`
- `values`
- `default`
- `displayValues`
- `valueColors`
- `optionsPerLine`
- `optionGap`

Use when:
- the choice list is small and visible all at once is better than a combo

### `lib.widgets.mappedRadio(imgui, uiState, alias, opts?)`

Options:
- `label`
- `optionsPerLine`
- `optionGap`
- `getOptions(view)`

Each returned option may include:
- `label`
- `value`
- `color`
- `selected`
- `onSelect(option, uiState)`

Use when:
- the visible options are dynamic
- you need custom selection behavior

### `lib.widgets.packedRadio(imgui, uiState, alias, store, opts?)`

Packed single-choice radio surface.

Options:
- `label`
- `displayValues`
- `valueColors`
- `noneLabel`
- `selectionMode`
- `optionsPerLine`
- `optionGap`

Use when:
- the packed root is better represented as always-visible choices rather than a combo

## Numeric widgets

### `lib.widgets.stepper(imgui, uiState, alias, opts?)`

Stepper with `-` and `+` buttons around a rendered value.

Options:
- `label`
- `default`
- `min`
- `max`
- `step`
- `displayValues`
- `valueWidth`
- `buttonSpacing`

Behavior:
- normalizes through integer storage rules
- clamps against `min` / `max`
- can show friendly names through `displayValues[number]`

Use when:
- the value is small and ordinal
- button stepping is more readable than typing

### `lib.widgets.steppedRange(imgui, uiState, minAlias, maxAlias, opts?)`

Two coupled steppers rendered as:
- min stepper
- `"to"`
- max stepper

Options:
- all `StepperOpts`
- `defaultMax`
- `rangeGap`

Behavior:
- min stepper is limited by current max
- max stepper is limited by current min

Use when:
- both ends of the range should stay visible together
- you want stepper interaction instead of two dropdowns

## Boolean widgets

### `lib.widgets.checkbox(imgui, uiState, alias, opts?)`

Options:
- `label`
- `tooltip`
- `color`

Behavior:
- binds one boolean alias

Use when:
- the field is a plain toggle

### `lib.widgets.packedCheckboxList(imgui, uiState, alias, store, opts?)`

Checkbox list over packed child aliases.

Options:
- `filterText`
- `filterMode`
- `valueColors`
- `slotCount`
- `optionsPerLine`
- `optionGap`

`filterMode`:
- `all`
- `checked`
- `unchecked`

Behavior:
- resolves packed children from `store.getPackedAliases(alias)` first
- text filter is case-insensitive substring match on option labels
- items are laid out inline according to `optionsPerLine`
- rendering stops after `slotCount` matches

Use when:
- a packed root is really a bitmask of many independent bool choices
- boon-ban style lists

Example:

```lua
lib.widgets.packedCheckboxList(ui, uiState, "PackedBannedAphrodite", store, {
    filterText = uiState.view.BanFilterText,
    optionsPerLine = 2,
    valueColors = {
        PackedBannedAphrodite_Attack = { 1, 0.8, 0.8, 1 },
        PackedBannedAphrodite_Special = { 1, 0.8, 0.8, 1 },
    },
})
```

## Choosing the right widget

Use:
- `dropdown` when the choices are static
- `mappedDropdown` when the choices or preview are dynamic
- `packedDropdown` when one packed child is effectively selected
- `radio` when the static choices should stay visible
- `mappedRadio` when visible choices are dynamic
- `packedRadio` when packed single-choice state should stay visible
- `checkbox` for one bool
- `packedCheckboxList` for many packed bool flags
- `stepper` for one bounded int
- `steppedRange` for two coupled ints

## Nav

Navigation helpers live under `lib.nav`.

Current surface:
- `lib.nav.verticalTabs(ui, opts)`
- `lib.nav.isVisible(uiState, condition)`

`verticalTabs(...)` is the current replacement for the old vertical tab layout runtime.

Example:

```lua
activeKey = lib.nav.verticalTabs(ui, {
    id = "ExampleTabs",
    navWidth = 220,
    activeKey = activeKey,
    tabs = {
        { key = "settings", label = "Settings" },
        { key = "advanced", label = "Advanced", color = { 1, 0.8, 0, 1 } },
    },
})
```

## What Was Removed

The old field-registry/declarative UI surface is no longer the live model.

Do not write new code around:
- widget registries
- layout registries
- `prepareUiNode(...)`
- `prepareWidgetNode(...)`
- `drawTree(...)`
- quick-node collection
- custom widget/layout registry extension

If a module still carries that shape, it is historical compatibility residue, not the preferred contract.
