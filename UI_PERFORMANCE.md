# Immediate-Mode UI Performance

Reference for writing or auditing module draw code without re-deriving render-path performance analysis from scratch.

This guidance applies to the current lean module contract:
- `DrawTab(ui, uiState)`
- optional `DrawQuickContent(ui, uiState)`
- `lib.widgets.*`
- raw ImGui for structure

## Why Draw Paths Need Care

Current module UI is immediate-mode:
- `DrawTab(ui, uiState)`
- optional `DrawQuickContent(ui, uiState)`

These run every imgui frame.
Any unnecessary allocation or repeated C-boundary call inside those paths shows up immediately.

## Current Contract Assumptions

This document assumes:
- raw `config` stays local to `main.lua`
- `public.store = lib.store.create(config, public.definition, dataDefaults)` is the storage boundary
- draw code reads staged values from `uiState.view`
- runtime/gameplay code reads persisted values through `store.read(...)`
- framework/host own `uiState` commit timing
- standalone UI goes through `lib.host.standaloneUI(...)`

## Per-Frame Checklist

### 1. Avoid string concatenation in hot draw loops

Bad:

```lua
ui.Text("Equipped: " .. tostring(currentWeapon))
```

Better:
- cache slow-changing derived strings
- or compute once per draw function, not repeatedly inside loops

If the text really is stable across many frames:
- cache it on module state
- invalidate that cache only when the source values change

### 2. Avoid inline table literals in draw paths

Bad:

```lua
local color = opts.color or { 1, 1, 1, 1 }
```

Better:
- use a module-level constant

This applies to:
- colors
- repeated option lists
- repeated tab definitions
- static label maps

### 3. Cache repeated ImGui getters inside one draw function

Bad:

```lua
ui.SetCursorPosX(ui.GetWindowWidth() * 0.5)
ui.PushItemWidth(ui.GetWindowWidth() * 0.3)
```

Better:

```lua
local winW = ui.GetWindowWidth()
ui.SetCursorPosX(winW * 0.5)
ui.PushItemWidth(winW * 0.3)
```

Do the same for:
- `GetContentRegionAvail()`
- `GetFrameHeight()`
- `GetStyle().ItemSpacing.x` if you are already using it repeatedly in one function

### 4. Default to `uiState.view` for reads

Use:
- `uiState.view.SomeAlias`

Prefer this over raw mutable staging values unless you have a concrete reason not to.

### 5. Let host/framework own commit timing

Do not hand-roll flush logic inside draw code.

Current ownership:
- framework-hosted modules commit after `DrawTab` / `DrawQuickContent`
- standalone modules should go through `lib.host.standaloneUI(...)`

The module’s job is:
- render from `uiState`
- stage edits into `uiState`

Not:
- custom flush timing
- custom rollback timing

### 6. Keep layout immediate and local

Prefer:
- one readable draw flow
- small helper functions that directly draw
- direct ImGui for spacing, grouping, child regions, and tab bars

Avoid:
- rebuilding an internal retained layer
- introducing generic builder indirection just to avoid a few repeated lines

### 7. Keep dynamic option builders out of inner loops when possible

If a dropdown/radio option list only changes when one or two aliases change:
- compute it once per draw function
- or cache it off the relevant source state

Do not rebuild the same large option table multiple times in the same frame.

## Good Current Patterns

- use `lib.widgets.*` for common controls
- use `lib.nav.verticalTabs(...)` for simple vertical nav rails
- keep draw helpers local and concrete
- duplicate small UI when that makes render order clearer
- compute derived view text only when it actually improves readability
- keep packed-widget filtering data outside the innermost draw loop when practical

## Bad Current Patterns

- rebuilding unnecessary tables in hot loops
- caching abstractions that only survive one frame
- reintroducing retained/prepared UI layers for simple screens
- splitting one draw flow into extra lifecycle phases without a real need
- calling `store.read(...)` repeatedly inside draw code for values already present in `uiState.view`
- doing config writes directly from draw code instead of staging through `uiState`
