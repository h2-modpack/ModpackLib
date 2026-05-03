# Known Limitations

This file documents current design constraints that are intentional or accepted for now.

These are not hidden bugs. They are boundaries the current architecture chooses to live with until the underlying runtime, Framework surface, or project requirements change.

## Structural Rebuilds Are Immediate

When a coordinated module changes its structural contract during hot reload, Lib requests a Framework rebuild as soon as the replacement host is published.

The module rebuild path is:

- `prepareDefinition(...)`
- `createStore(...)`
- `createModuleHost(...)`
- `standaloneHost(...)`

The Framework rebuild is correct, but it is not coalesced across a multi-module reload wave.

Example:

- module A structurally reloads
- Framework rebuilds
- module B structurally reloads right after
- Framework rebuilds again

Why this exists:

- ReturnOfModdingBase reloads modules through an internal file-watcher queue
- that queue drain boundary is not exposed to Lua
- neither ROM nor ModUtil currently provides a clean "hot reload wave complete" callback

What would remove it:

- a ROM-side callback such as `mods.on_hot_reload_wave_complete(...)`
- or another clean Lua-visible boundary after `process_file_watcher_queue()` drains

## Infrastructure Hot Reload Is Best-Effort

Author-facing module hot reload is the supported fast path. Lib and Framework hot reload are infrastructure development paths, with a full game process restart as the correctness boundary.

What this means in practice:

- existing module hosts may close over old Lib implementation closures until the owning module reloads
- active mutation runtime is durable across module reload, not arbitrary Lib implementation reload
- a Framework file reload does not update an existing pack object until Core or a coordinator rebuild calls `Framework.init(...)` again
- retained HUD layout changes may require HUD recreation or a game HUD refresh

Why this exists:

- fully live infrastructure reload would require more persistent dispatch machinery and durable mutation bookkeeping across Lib reloads
- that complexity is not justified by normal module-author workflows
- infrastructure edits are less frequent and can use full process restart for correctness validation

What would remove it:

- persistent Lib mutation runtime across Lib implementation reloads
- host methods routed through stable late-bound Lib dispatch
- an explicit infrastructure reload protocol that forces module and Framework convergence

## Private Module `internal` Usage Is Convention-Driven

Lib provides clean state funnels for module authors:

- prepared definitions for structural contract
- managed storage for persisted state
- transient session state for UI/runtime staging
- host methods for behavior

But private module `internal` tables remain module-owned implementation detail. Lib does not enforce what authors store there.

Why this exists:

- `internal` is intentionally flexible module-private composition state
- trying to centrally structure or lock it down would fight legitimate module-local implementation needs

What this means in practice:

- first-party modules should use transient/session state for real UI state
- private `internal` caching is still possible, even when it is less clean
- enforcement here is by convention, review, and first-party examples, not runtime guards

What would remove it:

- a more opinionated module-internal framework layer
- which is currently considered more complexity than the problem justifies

## No General Purpose Non-UI Per-Frame Lua Callback

ROM exposes:

- `gui.add_imgui(...)`
- `gui.add_always_draw_imgui(...)`
- `gui.add_to_menu_bar(...)`

These are useful, but they are still render/UI-oriented hooks. There is no clean general-purpose Lua `on_update` or `on_tick` callback for pack logic.

Why this matters:

- it makes deferred rebuild scheduling or end-of-frame coordination awkward
- UI callbacks are the wrong abstraction for non-UI pack orchestration

What would remove it:

- a ROM-side per-frame logic callback
- or a dedicated post-hot-reload drain callback

## Some Removed Hooks Can Leave Inert Wrappers

Lib hook dispatch prevents normal hot reload from stacking active wrappers for stable owner/path/key registrations.

One development-only caveat remains: if the same wrap or context-wrap site is removed, hot reloaded, re-added, and hot reloaded again within one live game process, an inert wrapper can remain until restart.

Why this exists:

- ModUtil path wraps are compositional and do not expose precise removal for every wrapper shape
- Lib can make omitted registrations inert, but cannot always erase the physical wrapper already installed in ModUtil

What would remove it:

- ModUtil support for keyed wrapper replacement/removal
- or a full process restart, which clears wrapper chains
