# Field Registry

This document describes the current field-registry surface in Lib.

It covers:
- storage types
- widget types
- layout types
- the UI preparation and draw contract
- custom registry extension points

It does **not** cover:
- store lifecycle
- mutation lifecycle
- coordinator behavior
- special-module state passes

Those are documented elsewhere.

## Registry Surface

Lib exposes four registry surfaces:
- `lib.registry.storage`
- `lib.registry.widgets`
- `lib.registry.layouts`
- `lib.registry.widgetHelpers`

And one validator:
- `lib.registry.validate()`

The registries are initialized in
[src/field_registry/init.lua](src/field_registry/init.lua).

Current internal ownership is split across:
- [src/field_registry/internal/registry.lua](src/field_registry/internal/registry.lua)
- [src/field_registry/internal/ui.lua](src/field_registry/internal/ui.lua)
- [src/field_registry/internal/widgets.lua](src/field_registry/internal/widgets.lua)

## Design Split

The field registry is deliberately split by responsibility:

- storage types
  - validation
  - normalization
  - hashing / serialization
  - prepared alias/root metadata
- widget types
  - interaction
  - rendering
  - widget-local validation
- layout types
  - composition
  - child placement
  - structural UI rules

This is the v2 model. The old field-centric v1 surface is gone.

## Storage Types

Storage types live on `lib.registry.storage`.

Current built-ins:
- `bool`
- `int`
- `string`
- `packedInt`

The public storage helpers live on `lib.storage.*` and are implemented in
[src/field_registry/storage.lua](src/field_registry/storage.lua).

### Required contract

Every storage type must provide:
- `validate(node, prefix)`
- `normalize(node, value)`
- `toHash(node, value)`
- `fromHash(node, str)`

Optional:
- `packWidth(node)`
- `equals(node, a, b)`

### Root rules

Every storage root declares:
- `type`
- either `configKey`
- or `lifetime = "transient"`

Persistent roots:
- persist to Chalk config
- participate in hashing

Transient roots:
- exist only in UI state
- do not persist or hash

Example:

```lua
{ type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
```

Transient example:

```lua
{ type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 }
```

### `packedInt`

`packedInt` is a persistent root whose logical children are alias-addressable bit partitions.

Example:

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

Rules:
- child aliases must be unique across the storage schema
- bit ranges may not overlap
- the root is what persists and hashes
- child aliases are exposed through prepared alias metadata, not as independent roots

## Widget Types

Widget types live on `lib.registry.widgets`.

Current built-ins:
- `text`
- `separator`
- `button`
- `confirmButton`
- `checkbox`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `packedDropdown`
- `radio`
- `mappedRadio`
- `packedRadio`
- `stepper`
- `steppedRange`
- `packedCheckboxList`

Widget implementations live under
[src/field_registry/widgets](src/field_registry/widgets).

### Required contract

Every widget type must provide:
- `binds`
- `validate(node, prefix)`
- `draw(imgui, node, bound, x, y, availWidth, availHeight, uiState)`

The v2 draw contract is rect-based:
- parent assigns `x`, `y`, `availWidth`, `availHeight`
- widget renders inside that assignment
- widget returns:
  - `consumedWidth`
  - `consumedHeight`
  - `changed`

`availHeight` rules:
- `nil` means unconstrained
- numeric value means real vertical constraint

### Binding

Widgets bind by alias through `node.binds`.

Example:

```lua
{ type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }
```

At draw time, Lib builds a `bound` table:
- `bound.<name>.get()`
- `bound.<name>.set(value)`
- `bound.<name>.node`

For packed-root binds, Lib may also expose:
- `bound.<name>.children`

That is how packed widgets receive packed child rows.

### Visibility

Any widget or layout node may declare `visibleIf` to conditionally hide itself.

Forms:
- `visibleIf = "AliasName"` — visible when the alias value is truthy
- `visibleIf = { alias = "AliasName", value = someValue }` — visible when the alias equals `someValue`
- `visibleIf = { alias = "AliasName", anyOf = { v1, v2, ... } }` — visible when the alias matches any listed value

Invisible nodes are not drawn and do not consume layout space.

### Geometry

The old widget `geometry` surface is removed.

There is no supported `geometry = { ... }` block on widget nodes anymore.
If a module still carries one, it is legacy noise and should be removed.

Widget-local replacements that still exist:
- `inputText.controlWidth`
- `dropdown.controlWidth`
- `mappedDropdown.controlWidth`
- `stepper.valueWidth`
- `stepper.valueAlign`
- `steppedRange.valueWidth`
- `steppedRange.valueAlign`
- `text.width`

Everything else should be expressed by composing layout nodes:
- `vstack`
- `hstack`
- `split`
- `tabs`
- `scrollRegion`
- `collapsible`

### Built-in behavior notes

`text`
- presentational only
- supports `text`, `label`, optional `width`, optional `color`

`separator`
- presentational only
- draws a full-width rule

`button`
- no binds
- optional `onClick(uiState, node, imgui)`

`confirmButton`
- no binds
- popup-based confirmation flow
- optional `confirmLabel`
- optional `cancelLabel`
- optional `onConfirm(uiState, node, imgui)`

`checkbox`
- expects bool storage

`inputText`
- expects string storage
- supports `controlWidth`

`dropdown` / `radio`
- expect direct choice storage backed by `string` or `int`
- support `values`
- support optional `displayValues[value]`
- support optional `valueColors[value]`

`mappedDropdown` / `mappedRadio`
- delegate preview/option semantics to callbacks
- are for nontrivial option surfaces that do not map 1:1 to a static `values` list

`packedRadio`
- packed-root choice surface over child aliases of a `packedInt`

`stepper`
- expects int-like storage
- supports `step`, `fastStep`
- supports `valueWidth`, `valueAlign`
- supports optional `displayValues[value]`
- supports optional `valueColors[value]`

`steppedRange`
- binds to existing `min` and `max` aliases
- supports `valueWidth`, `valueAlign`

`packedDropdown`
- packed-root choice surface presented as a dropdown
- child aliases of a `packedInt` populate the option list

`packedCheckboxList`
- expects `binds.value` to target a `packedInt` root alias
- optionally accepts `binds.filterText` — filters visible rows by text match
- optionally accepts `binds.filterMode` — `"all"`, `"checked"`, or `"unchecked"`
- renders visible packed child aliases as checkbox rows

## Layout Types

Layout types live on `lib.registry.layouts`.

Current built-ins:
- `vstack`
- `hstack`
- `collapsible`
- `tabs`
- `scrollRegion`
- `split`

Layout implementations live in
[src/field_registry/layouts.lua](src/field_registry/layouts.lua).

The old v1 layout types are gone:
- `panel`
- `group`
- `horizontalTabs`
- `verticalTabs`

### Required contract

Every layout type must provide:
- `validate(node, prefix)`
- `render(imgui, node, drawChild, x, y, availWidth, availHeight, uiState, bound)`

The render contract is:
- layout owns child placement
- layout calls `drawChild(child, childX, childY, childAvailWidth, childAvailHeight)`
- layout returns:
  - `consumedWidth`
  - `consumedHeight`
  - `changed`

### Notes on built-ins

`vstack`
- vertical flow container
- optional `gap`

`hstack`
- horizontal flow container
- optional `gap`

`collapsible`
- collapsible section using ImGui header behavior
- optional `defaultOpen`

`tabs`
- unified horizontal/vertical tab container
- requires `id`
- child nodes require `tabLabel`
- optional `orientation`
- optional `binds.activeTab`
- optional `navWidth` for vertical tabs

`scrollRegion`
- child-window-backed scroll container
- requires `id`
- optional `width`, `height`, `border`

`split`
- two-pane container
- exactly two children
- optional:
  - `orientation`
  - `gap`
  - `firstSize`
  - `secondSize`
  - `ratio`

## UI Runtime Surface

The public UI runtime lives on `lib.ui.*` and is implemented in
[src/field_registry/ui.lua](src/field_registry/ui.lua).

Main entrypoints:
- `lib.ui.validate(uiNodes, label, storage, customTypes)`
- `lib.ui.prepareNode(node, label, storage, customTypes)`
- `lib.ui.prepareWidgetNode(node, label, customTypes)`
- `lib.ui.prepareNodes(nodes, label, storage, customTypes)`
- `lib.ui.isVisible(node, view)`
- `lib.ui.drawNode(imgui, node, uiState, availWidth, customTypes)`
- `lib.ui.drawTree(imgui, uiNodes, uiState, availWidth, customTypes)`
- `lib.ui.collectQuick(uiNodes, uiState, customTypes)`
- `lib.ui.getQuickId(node)`

Validation and drawing merge custom registry extensions through:
- `internal.registry.ValidateCustomTypes(...)`
- `internal.registry.MergeCustomTypes(...)`

## Custom Registry Extensions

Modules may extend the built-in registries with:
- `definition.customTypes.widgets`
- `definition.customTypes.layouts`

Rules:
- custom widget names may not collide with built-in widget or layout names
- custom layout names may not collide with built-in widget or layout names

### Custom widget contract

Custom widgets must provide:
- `binds`
- `validate(node, prefix)`
- `draw(imgui, node, bound, x, y, availWidth, availHeight, uiState)`

Custom widgets are expected to be leaf renderers by default.
They may do local immediate-mode composition internally, but they should not
control surrounding sibling flow by cursor side effects.

### Custom layout contract

Custom layouts must provide:
- `validate(node, prefix)`
- `render(imgui, node, drawChild, x, y, availWidth, availHeight, uiState, bound)`

They participate in the same rect-based child-placement contract as built-in layouts.

## Widget Helpers

`lib.registry.widgetHelpers` is the public home for small widget-authoring helpers.

Current helpers:
- `lib.registry.widgetHelpers.drawStructuredAt(...)`
- `lib.registry.widgetHelpers.estimateRowAdvanceY(...)`

These come from
[src/field_registry/internal/ui.lua](src/field_registry/internal/ui.lua).

They are useful for:
- local freeform custom widget composition
- estimating row advancement without re-implementing the style fallback logic

## Registry Validation

`lib.registry.validate()` hard-validates registry contracts.

It checks:
- storage type method completeness
- widget type method completeness
- widget `binds` presence
- layout type method completeness

Implementation:
- [src/field_registry/internal/registry.lua](src/field_registry/internal/registry.lua)

## Minimal Example

```lua
public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = {
        { type = "bool", alias = "Enabled", configKey = "Enabled", default = false },
        { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
    },
    ui = {
        {
            type = "vstack",
            gap = 8,
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
                { type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 },
            },
        },
    },
}
```
