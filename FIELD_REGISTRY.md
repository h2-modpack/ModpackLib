# Storage and UI Registries

This document replaces the old field-centric model.

Lib now has three registries:
- `lib.StorageTypes`
- `lib.WidgetTypes`
- `lib.LayoutTypes`

These registries are separate on purpose.

## Why the Split Exists

The old field model mixed:
- persistence
- hashing
- staging
- widget rendering
- layout

The new model separates those concerns:
- storage owns persistence and hashing
- widgets own interaction
- layout owns presentation structure

## Storage Types

Storage types validate, normalize, and serialize persisted values.

Required methods:
- `validate(node, prefix)`
- `normalize(node, value)`
- `toHash(node, value)`
- `fromHash(node, str)`

Built-ins:
- `bool`
- `int`
- `string`
- `packedInt`

### Root storage nodes

Every root storage node must have:
- `type`
- `configKey`

`alias` is optional on roots:
- if omitted, it defaults to the stringified `configKey`
- explicit aliases are still recommended when you want the UI/runtime name to differ from the persisted key

Example:

```lua
{ type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
```

### Packed storage nodes

`packedInt` is a root storage type whose children are alias-addressable packed partitions.

Use `packedInt` when you want to reduce Chalk config entries by co-locating related flags. For most modules, separate `bool` roots are the right choice.

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
- packed child aliases must be unique across the module
- packed bit ranges may not overlap
- packed child defaults are encoded into the root default when the root default is omitted
- only the root persists and hashes directly

By default each storage root hashes as its own key. Framework supports optional `hashGroups` for coordinators that want to compress multiple independent small roots into a single base62 token — see the coordinator guide. This is an optimization; modules do not need to declare `hashGroups` for hashing to work correctly.

`hashGroups` may include:
- root `bool`
- root `int`
- root `packedInt` with a derivable width

`hashGroups` may not include packed child aliases from inside a `packedInt`.

## Widget Types

Widget types own rendering and interaction only.

Required methods:
- `validate(node, prefix)`
- `draw(imgui, node, bound, width?)`

Built-ins:
- `checkbox`
- `dropdown`
- `radio`
- `stepper`
- `steppedRange`
- `packedCheckboxList`

Widgets bind by alias:

```lua
{ type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }
```

Each declared bind becomes a bound entry passed into `draw(...)`:

- `bound.<name>.get()`
- `bound.<name>.set(value)`

For widgets bound to a packed root, Lib may also expose:

- `bound.<name>.children`

which is how `packedCheckboxList` receives packed child rows.

Some widgets also support a widget-local `geometry` bag for manual horizontal placement.

First-pass built-in support:
- `dropdown`: `label`, `control`
- `radio`: `label`, dynamic `option:N`
- `stepper`: `label`, `decrement`, `value`, `increment`, optional `fastDecrement`, `fastIncrement`
- `steppedRange`: `label`, `min.*`, `separator`, `max.*`
- `packedCheckboxList`: dynamic `item:N` when `slotCount` is declared

Geometry is expressed through `geometry.slots`, a list of slot descriptors.
Each slot descriptor may declare:
- `name`
- `line`
- `start`
- `width`
- `align`

`line` defaults to `1` and must be a positive integer when present.
`start` is relative to the current row origin after any `indent`.
`width` must be positive when present.
`align` may be `center` or `right` and requires an explicit `width`.
Slots are rendered in ascending `line`.
Within the same line, slots with explicit `start` values are ordered by `start`.
Otherwise declaration order breaks ties and preserves slots without explicit `start`.
`radio` supports `option:N` slot names for each entry in `node.values`.
`packedCheckboxList` supports `item:N` slot names when `slotCount` is declared.

`slotCount` is the declaration-time slot capacity for `packedCheckboxList`. Packed children may be omitted at runtime, but the widget does not invent new slots beyond the declared count.

At draw time, `lib.drawUiNode(...)` may also receive a runtime geometry override using the same `geometry.slots` shape.
Runtime overrides are validated against the already-declared slot schema and may additionally set:
- `hidden`

`hidden = true` skips rendering that slot without reflowing the remaining slots.

### `steppedRange`

`steppedRange` is a widget, not storage.

It binds to two existing aliases:
- `binds.min`
- `binds.max`

Example:

```lua
{ type = "steppedRange",
  label = "Depth",
  binds = { min = "DepthMin", max = "DepthMax" },
  geometry = {
    slots = {
      { name = "min.decrement", start = 0 },
      { name = "min.value", start = 24, width = 14, align = "center" },
      { name = "min.increment", start = 42 },
      { name = "separator", start = 260 },
      { name = "max.decrement", start = 300 },
      { name = "max.value", start = 324, width = 14, align = "center" },
      { name = "max.increment", start = 342 },
    },
  },
  min = 1,
  max = 10,
  step = 1 }
```

## Layout Types

Layout types never store data.

Required methods:
- `validate(node, prefix)`
- `render(imgui, node)`

Built-ins:
- `separator`
- `group`

Layout nodes may carry `children`.

Example:

```lua
{
    type = "group",
    label = "Options",
    children = {
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
    },
}
```

## Binding Rules

### Aliases

All storage access inside Lib-managed UI is alias-based.

That means:
- widgets bind by alias
- `visibleIf` can use:
  - a bool alias string
  - `{ alias = "...", value = ... }`
  - `{ alias = "...", anyOf = { ... } }`
- `uiState` stages by alias

### Raw keys

Raw `configKey` access still exists through:
- `store.read(keyOrAlias)`
- `store.write(keyOrAlias, value)`

But UI declarations should not bind to raw keys.

## Validation Rules

Lib validates:
- alias uniqueness
- root `configKey` uniqueness
- packed overlap
- widget/storage type compatibility
- `visibleIf` alias validity

Lib hard-validates registry contracts through:
- `lib.validateRegistries()`

## Built-In Behavior Notes

### `bool`
- normalizes to `true` or `false`
- hashes as `"1"` or `"0"`

### `int`
- clamps to declared `min` and `max` when present
- hashes as canonical decimal string

### `string`
- normalizes to string
- supports optional `maxLen` validation

### `checkbox`
- expects bool storage

### `dropdown` and `radio`
- expect string storage
- validate value lists
- `dropdown` supports optional `geometry`

### `stepper`
- expects int storage
- supports `step`, `fastStep`, and optional `geometry`

### `packedCheckboxList`
- expects a packed root bind
- renders checkbox rows for the packed child aliases under that root
- useful when a module wants a generic packed-flag checklist without hand-writing the child loop

### `separator`
- layout only
- no binding

### `group`
- layout only
- optional `children`
- optional `collapsible`

## Authoring Guidance

Prefer:
- storage nodes for persistence
- widget nodes for reusable UI
- layout nodes for structure

Do not:
- put persistence rules in widgets
- put widget bindings in storage
- use old field helpers or old schema contracts

## Module-Local Extensions

Modules may extend the built-in registries with:

- `definition.customTypes.widgets`
- `definition.customTypes.layouts`
- custom widgets must declare `binds`
- custom widgets must declare `draw(...)`

Rules:
- custom widget names may not collide with built-in widget or layout names
- custom layout names may not collide with built-in widget or layout names
- custom widgets must declare `binds`
- custom widgets must implement `validate(...)` and `draw(...)`
- custom widgets may optionally declare `slots = { ... }` to whitelist supported `node.geometry.slots[*].name` values
- custom widgets may optionally declare `dynamicSlots(node, slotName) -> ok, err` for declaration-time-dependent slot names
- custom layouts must implement `validate(...)` and `render(...)`

Today, `slots` is a validation surface. Custom widget `draw(...)` logic still reads `node.geometry` itself when it wants custom placement.

Custom types are merged into the registry surface for:
- `lib.validateUi(...)`
- `lib.prepareUiNode(...)`
- `lib.prepareUiNodes(...)`
- `lib.drawUiNode(...)`
- `lib.drawUiTree(...)`
- `lib.collectQuickUiNodes(...)`

## Minimal Example

```lua
public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = {
        { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
    },
    ui = {
        { type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" },
        { type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 },
    },
}
```
