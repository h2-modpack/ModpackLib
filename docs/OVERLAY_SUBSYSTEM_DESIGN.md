# Retained Overlay Subsystem Design

## Purpose

The overlay subsystem provides owner-scoped retained UI elements for module HUD projections.
Modules declare the maximum retained structure they need, then update named elements from explicit
projection events.

Lib owns:

- Retained overlay handles, layout, cleanup, and hot-reload refresh.
- Owner scoping and name collision prevention.
- Activation rollback for overlay declarations and subscriptions.
- Event dispatch for supported overlay projection triggers.

Modules own:

- Domain state.
- Projection from domain state into overlay line/table values.
- Visibility rules that are specific to module settings.

## Non-Goals

- Do not add a general custom event bus in the overlay subsystem.
- Do not allow overlay callbacks to mutate store values directly.
- Do not make overlay callbacks equivalent to hooks; overlay callbacks are projection callbacks.
- Do not expose low-level HUD/stacked renderer primitives as module-author APIs.

## Module API

Modules declare retained overlays through an optional module definition callback:

```lua
registerOverlays = function(overlays, host, store)
end
```

`registerOverlays` is called during host activation. It uses the same stable module owner as hooks and
integrations. Overlay activation participates in host activation rollback.

## Owner Scoping

Overlay element names are local to the owner:

```lua
overlays.createLine("summary.igt", spec)
overlays.createTable("runs", spec)
```

Lib builds globally stable backing identifiers from:

- Owner identity.
- Local overlay name.
- Retained table row slot, when applicable.
- Column key, when applicable.

Two modules may use the same local overlay name without colliding.

## System Overlays

Framework and Lib may need retained overlays that are not declared by a module. These use an explicit
stable owner API instead of ownerless retained declarations:

```lua
lib.overlays.defineOwned(owner, function(overlays)
    overlays.createLine("hash.marker", spec)
end)
```

Ownerless low-level overlay APIs may remain for compatibility, but new retained overlay declarations
must be owner-scoped.

## Retained Elements

### Lines

A line is a single retained display row. The name intentionally avoids `row` so table row language stays
unambiguous.

```lua
overlays.createLine("summary.igt", {
    region = "middleRightStack",
    order = 100,
    visible = function()
        return true
    end,
    columnGap = 20,
    columns = {
        {
            key = "label",
            minWidth = 40,
            justify = "Left",
            textArgs = { Font = "P22UndergroundSCMedium" },
        },
        {
            key = "time",
            minWidth = 80,
            justify = "Left",
            textArgs = { Font = "NumericP22UndergroundSCMedium" },
        },
    },
})
```

Projection callbacks update lines by name:

```lua
ctx.setLine("summary.igt", { label = "IGT:", time = "12:34.56" })
ctx.setLine("message", "Ready")
```

String values are a convenience for one-column lines.

### Tables

A table is a fixed retained table projection with named columns and a maximum row count.

```lua
overlays.createTable("runs", {
    region = "middleRightStack",
    order = 200,
    maxRows = 11,
    visible = function()
        return true
    end,
    columnGap = 10,
    columns = {
        {
            key = "label",
            minWidth = 96,
            justify = "Left",
            textArgs = { Font = "P22UndergroundSCMedium" },
        },
        {
            key = "igt",
            minWidth = 78,
            justify = "Left",
            visible = function()
                return store.read("ShowIGT") == true
            end,
            textArgs = { Font = "NumericP22UndergroundSCMedium" },
        },
    },
})
```

Projection callbacks update tables by name:

```lua
ctx.setTable("runs", {
    { key = "run1", label = "Run 1", igt = "01:23.45" },
    { key = "current", label = "Current", igt = "00:12.34" },
})
```

Table behavior:

- Fixed column definitions.
- Per-column visibility is evaluated during refresh.
- Visible columns are compacted.
- Rows beyond `maxRows` are ignored.
- Unused retained rows are hidden.
- No sorting, scrolling, selection, dynamic columns, row actions, or custom row widgets in v1.

## Projection Context

Overlay callbacks receive a small projection context:

```lua
callback(ctx, event)
```

The context exposes:

```lua
ctx.read(alias)
ctx.isEnabled()
ctx.log(fmt, ...)
ctx.logIf(fmt, ...)
ctx.setLine(name, values)
ctx.setTable(name, rows)
ctx.setCell(tableName, rowKey, columnKey, value)
ctx.refresh(name)
ctx.refreshRegion(region)
ctx.refreshAll()
```

The context does not expose:

- `store.write`.
- The full store object.
- The full host object.
- Mutation plans.
- Hook registration.

The context is not a durable public object family like store, session, or host. It is an event callback
projection surface.

## Supported Events

The retained overlay event surface is intentionally fixed:

- Settings commit projections.
- Interval projections.
- After-hook projections.

Custom module events are outside the v1 overlay subsystem. If module-emitted events become necessary,
they should be designed as a separate Lib capability and then made available to overlays.

### Settings Commit

```lua
overlays.onCommit(function(ctx, commit)
    ctx.setTable("runs", BuildRunRows())
    ctx.refreshRegion("middleRightStack")
end)
```

Commit ordering:

1. Framework commits staged session values and actions.
2. Module `onSettingsCommitted(host, store, commit)` runs.
3. Overlay `onCommit(ctx, commit)` callbacks run.

This lets module logic consume staged actions and update module state before overlays project the final
state.

### Intervals

```lua
overlays.onInterval("tick", 0.05, function(ctx)
    UpdateSnapshot()
    ctx.setLine("summary.igt", BuildIgtLine())
    ctx.refresh("summary.igt")
end, {
    when = function()
        return HasActiveDisplayLoop()
    end,
})
```

Lib owns interval lifecycle. Intervals are removed on hot-reload omission, activation rollback, and module
replacement. `when` controls callback execution; it does not unregister the interval.

### After Hooks

```lua
overlays.afterHook("StartNewRun", function(ctx, event)
    ctx.setTable("runs", BuildInitialRunRows(event.result))
    ctx.refreshRegion("middleRightStack")
end)
```

After-hook subscriptions are observers:

- They run after the normal hook stack and base function complete.
- They receive hook arguments and results.
- They cannot alter arguments or return values.
- They do not replace normal hook registration.

The event payload starts with:

```lua
event.args
event.result
```

The implementation should not block a future `event.results` shape for multi-return hooks.

## Hot Reload And Rollback

Overlay refresh follows the same owner-refresh principle as hooks and integrations:

```lua
internal.overlays.refresh(owner, registerFn)
```

Refresh behavior:

- Execute the registration callback against a fresh declaration pass.
- Mark seen retained elements and event subscriptions.
- Remove omitted elements and subscriptions after a successful refresh.
- Preserve previous overlay state if refresh fails.

Activation behavior:

- Host activation refreshes overlays alongside hooks and integrations.
- If a later activation step fails, rollback restores the previous overlay registrations.
- Failed activation must not leave newly created overlay elements or subscriptions active.

## Renderer Internals

The retained API builds on private HUD component and stacked-layout renderer functions. Module authors
should not register HUD components or stacked rows directly.

- `lib.overlays.defineOwned` is the retained system-overlay entry point.
- Module `registerOverlays` is the retained module-overlay entry point.
- `lib.overlays.suppressForUi` remains public because Framework and standalone module UIs need to hide
  overlays while foreground configuration UI is open.

New code should use retained owner-scoped declarations only.

## Timer Target Shape

The Speedrun Timer should become a retained overlay consumer with structure similar to:

```lua
function timerApi.RegisterOverlays(overlays, host, store)
    overlays.createLine("summary.igt", summaryIgtSpec)
    overlays.createLine("summary.rta", summaryRtaSpec)
    overlays.createLine("summary.lrt", summaryLrtSpec)
    overlays.createTable("batch", batchTableSpec)
    overlays.createTable("splits", splitsTableSpec)

    overlays.onCommit(function(ctx, commit)
        ApplyCommittedDisplayState(commit)
        ctx.setLine("summary.igt", BuildSummaryLine("igt"))
        ctx.setLine("summary.rta", BuildSummaryLine("rta"))
        ctx.setLine("summary.lrt", BuildSummaryLine("lrt"))
        ctx.setTable("batch", BuildBatchRows())
        ctx.setTable("splits", BuildSplitRows())
        ctx.refreshRegion("middleRightStack")
    end)

    overlays.onInterval("tick", TIMER_REFRESH_INTERVAL, function(ctx)
        UpdateTimerSnapshot()
        ctx.setLine("summary.igt", BuildSummaryLine("igt"))
        ctx.setLine("summary.rta", BuildSummaryLine("rta"))
        ctx.setLine("summary.lrt", BuildSummaryLine("lrt"))
        ctx.setTable("batch", BuildBatchRows())
        ctx.setTable("splits", BuildLiveSplitRows())
        ctx.refreshRegion("middleRightStack")
    end, {
        when = HasActiveDisplayLoop,
    })

    overlays.afterHook("StartNewRun", function(ctx)
        ctx.setTable("batch", BuildBatchRows())
        ctx.setTable("splits", BuildSplitRows())
        ctx.refreshRegion("middleRightStack")
    end)
end
```

Timer code should stop owning retained overlay handles directly. It should expose projection builders that
return line values and table rows.

## Test Checklist

Lib tests:

- `registerOverlays` activates and receives an overlay declaration surface.
- `createLine` creates an owner-scoped retained line.
- `setLine` updates retained line values.
- `createTable` creates fixed-capacity retained rows.
- `setTable` shows provided rows up to `maxRows` and hides unused rows.
- Column visibility compacts visible table columns.
- Omitted retained declarations are cleaned up after successful refresh.
- Failed overlay refresh preserves previous declarations.
- Failed activation rolls back overlay declarations and subscriptions.
- `onCommit` runs after module `onSettingsCommitted`.
- `onInterval` runs while active and is cleaned up on refresh/removal.
- `afterHook` observes hook args/results and cannot alter return values.
- `defineOwned` supports system-owned overlays and cleans omitted system declarations.

Timer tests:

- Staged recording actions commit through `onSettingsCommitted`.
- Timer projection builders produce expected summary lines.
- Timer projection builders produce expected batch and split rows.
- Interval projection updates retained summary values.
- Settings commit updates column visibility and structure.
