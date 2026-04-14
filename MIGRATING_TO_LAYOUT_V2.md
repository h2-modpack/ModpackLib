# Migrating To Layout V2

This guide is for modules moving from the v1 `field_registry` layout surface to
the v2 layout substrate on the `layout-substrate-v2` branch.

This is a **first-pass migration guide**. It captures the intentional contract
changes already made in Lib. It should be updated again after the first real
module migration proves which parts are clear and which parts are still rough.

## Scope

This guide is about:
- layout and widget rendering migration
- custom widget/layout contract changes
- node shape changes authors must make in module `definition.ui`

This guide is **not** about:
- storage redesign
- alias/state redesign
- special vs regular module split
- hashing or persistence changes

Those foundations remain the same. The breaking surface here is the layout
runtime.

## The Big Change

V1 was built around:
- `panel`
- `group`
- `horizontalTabs`
- `verticalTabs`
- slot geometry and ambient cursor flow

V2 is built around:
- `vstack`
- `hstack`
- `split`
- `scrollRegion`
- `collapsible`
- `tabs`

The runtime is now rect-based internally:
- parent assigns `x`, `y`, `availWidth`, `availHeight`
- child renders inside that assigned box
- child returns `consumedWidth`, `consumedHeight`, `changed`

Core layout logic no longer uses old layout types and should not depend on
`SameLine()` for sibling placement.

## What Broke

The following layout node types are removed:
- `separator`
- `group`
- `horizontalTabs`
- `verticalTabs`
- `panel`

The following widget draw contract changed:

Old:

```lua
draw = function(imgui, node, bound, width, uiState)
    return changed
end
```

New:

```lua
draw = function(imgui, node, bound, x, y, availWidth, availHeight, uiState)
    return consumedWidth, consumedHeight, changed
end
```

`availHeight` rules:
- `nil` means unconstrained
- numeric values mean a real vertical constraint

## What Did Not Change

These module concepts are still valid:
- `definition.storage`
- `definition.ui`
- `definition.customTypes`
- alias binds
- transient vs persisted storage
- `lib.drawUiNode(...)`
- `lib.drawUiTree(...)`

Module authors still provide declarative trees. The rendering substrate under
that tree changed.

## New Layout Primitives

### `vstack`

Use `vstack` for vertical lists and form sections.

Example:

```lua
{
    type = "vstack",
    gap = 8,
    children = {
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
        { type = "text", text = "Status" },
    },
}
```

### `hstack`

Use `hstack` for horizontal rows.

Example:

```lua
{
    type = "hstack",
    gap = 8,
    children = {
        { type = "text", text = "Mode" },
        { type = "dropdown", binds = { value = "Mode" }, values = { "A", "B" } },
    },
}
```

### `tabs`

Use `tabs` for both horizontal and vertical tab sets.

Required:
- `id`
- children with `tabLabel`

Optional:
- `orientation = "horizontal" | "vertical"`
- `binds.activeTab`
- `navWidth` for vertical tabs

Example:

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

### `collapsible`

Use `collapsible` where v1 previously used `group.collapsible = true`.

Example:

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

### `scrollRegion`

Use `scrollRegion` when the content itself needs a child-window-backed scroll
container.

Required:
- `id`

Optional:
- `width`
- `height`
- `border`

### `split`

Use `split` for two-pane layouts.

Required:
- exactly two children

Optional:
- `orientation = "horizontal" | "vertical"`
- `gap`
- `firstSize`
- `secondSize`
- `ratio`

Use `split` for structures like:
- sidebar + detail
- header pane + content pane

## Mapping From V1 To V2

### `panel`

V1 `panel` encoded rows and columns indirectly.

V2 replacement:
- outer vertical grouping becomes `vstack`
- each logical row becomes `hstack`
- repeated aligned rows should use consistent composition, not `panel.column`

Old:

```lua
{
    type = "panel",
    columns = {
        { name = "label", start = 0 },
        { name = "control", start = 220, width = 180 },
    },
    children = {
        { type = "text", text = "Enabled", panel = { column = "label", line = 1 } },
        { type = "checkbox", binds = { value = "Enabled" }, panel = { column = "control", line = 1 } },
    },
}
```

New:

```lua
{
    type = "hstack",
    gap = 12,
    children = {
        { type = "text", text = "Enabled" },
        { type = "checkbox", binds = { value = "Enabled" } },
    },
}
```

### `group`

V1 `group` served two roles:
- plain vertical grouping
- optional collapsible section

V2 replacement:
- plain grouping -> `vstack`
- collapsible grouping -> `collapsible`

### `horizontalTabs` / `verticalTabs`

V2 replacement:
- `tabs`

Use:
- `orientation = "horizontal"` for old `horizontalTabs`
- `orientation = "vertical"` for old `verticalTabs`

### `separator`

There is no dedicated v2 layout node for the old `separator` yet.

For now:
- use a `text` node or a small custom widget where a true visual separator still
  matters
- avoid depending on old `separator` nodes during migration

If separator-like structure proves common enough, it can return later as a
simple widget rather than as a layout node.

## Custom Widget Migration

### New draw contract

Every custom widget must move to:

```lua
draw = function(imgui, node, bound, x, y, availWidth, availHeight, uiState)
    return consumedWidth, consumedHeight, changed
end
```

Rules:
- render from the assigned `x`, `y`
- treat `availWidth` / `availHeight` as constraints, not as the current cursor
- return honest consumed size
- do not rely on ambient cursor position as the widget contract

### Atomic custom widgets

Atomic custom widgets may still use raw ImGui internally.

Recommended pattern:
- set cursor to the positions you need inside the assigned box
- render your internal controls
- return the footprint you actually consumed

The widget may still call `lib.WidgetHelpers.drawStructuredAt(...)` for local
atomic drawing. That helper is now compatible with the current positioned
runtime and is still useful for freeform custom widgets.

### Custom layouts

Custom layouts should follow the same high-level contract as built-in layouts:

```lua
render = function(imgui, node, drawChild, x, y, availWidth, availHeight, uiState, bound)
    return consumedWidth, consumedHeight, changed
end
```

`drawChild(...)` should be treated as a positioned child renderer.

## Geometry Migration

V1 widget slot geometry still exists in Lib internals for built-in widget
composition, but modules should treat it as a legacy authoring surface.

Migration guidance:
- do not build new module layout around `panel` + `geometry.slots`
- use `vstack` / `hstack` first
- only keep slot geometry when it is truly widget-internal

This is one of the main goals of v2:
- outer and inner composition should converge on the same mental model

## Recommended Migration Order

Migrate modules in this order:

1. simplest declarative subtree
2. no custom region behavior
3. no bespoke picker widget
4. no deep nested tabs

Good first candidates:
- settings subtrees
- simple regular modules with list/form UIs

Bad first candidates:
- multi-pane custom pickers
- branch-specific experimental special tabs
- heavily nested tab trees

For a single module, recommended order is:

1. replace top-level layout node types
2. replace nested rows/sections with `vstack` / `hstack`
3. migrate custom widgets to the new draw signature
4. reintroduce region nodes (`tabs`, `split`, `scrollRegion`) only where needed

## Performance Rules

Performance is a design rule in v2, not a later pass.

When migrating:
- avoid per-frame table allocation for simple geometry plumbing
- pass scalar `x`, `y`, `availWidth`, `availHeight` values through hot paths
- do not build ad hoc rect tables in every draw call
- reuse prepared nodes and stable caches where the module already has good
  invalidation boundaries

If a migration works functionally but regresses steady-state redraw cost, treat
that as a design bug, not just polish debt.

## Current Rough Edges

This guide is intentionally ahead of the first real migrated subtree.

Expect these sections to get refined after the first module slice proves:
- whether a dedicated separator widget returns
- whether shared cross-row sizing needs a first-class surface earlier
- whether `split` sizing rules need tightening
- where custom widget helpers are still too low-level

## Migration Checklist

For each module:

1. find and remove old layout node types
2. replace them with `vstack`, `hstack`, `tabs`, `collapsible`, `split`, `scrollRegion`
3. update custom widget `draw(...)` signatures
4. make custom widgets return `(consumedWidth, consumedHeight, changed)`
5. verify active-tab binds still work through `binds.activeTab`
6. retest layout for:
   - overlap
   - missing height settlement
   - broken scroll regions
   - broken tab selection
7. profile steady-state redraw cost

## Status

This is a branch-local migration guide for the active v2 substrate rewrite.

It should be treated as:
- real enough to guide migration work now
- not yet final enough to be copied back to `main`

Once the first BoonBans slice lands cleanly, update this guide with the concrete
lessons from that migration.
