# Hot Reload Architecture

This document describes the supported hot-reload model of the adamant stack.

It covers how `adamant-ModpackLib`, `adamant-ModpackFramework`, coordinator shells, and coordinated modules stay coherent when files reload inside one live Hades II process.

For the raw behavior of `SGG_Modding-ReLoad`, `SGG_Modding-ModUtil`, and `SGG_Modding-Chalk`, read [RELOAD_MODUTIL_CHALK_REFERENCE.md](RELOAD_MODUTIL_CHALK_REFERENCE.md) first.

## Goals

- keep normal player sessions safe without requiring code edits
- support module development with live module reloads
- support Lib and Framework development without leaving the stack on stale hosts or stale callbacks
- keep ownership of reload-sensitive responsibilities explicit

## Process Model

Hot reload reruns Lua files inside the live game process.

Important consequences:
- a full game process restart clears mod globals, wrapper chains, and reload state
- loading a save, starting a run, or returning to title is not a full process restart
- persistent module globals survive when code reuses them with `X = X or {}`

The stack relies on that persistence for stable internal registries.

## Persistent Internal Globals

The stack deliberately stores reload-sensitive state on `_G` tables:

- `AdamantModpackLib_Internal`
- `AdamantModpackFramework_Internal`
- each module's `RunDirector*_Internal` table

These tables are initialized with `X = X or {}` so they survive a file reload in the same game process.

Safe to rebuild on every module `init`:
- `definition`
- `store`
- `session`
- live module host created by `lib.createModuleHost(...)`
- UI draw closures
- lookup tables derived from current imports

Expected to persist across reloads:
- Lib coordinator registrations
- Lib mutation runtime state
- Lib hook registries keyed by persistent hook owner tables
- Framework pack registry and stable GUI callbacks
- module-local hook owner tables

Do not replace an entire persistent `*_Internal` table during reload. Mutate fields on the existing table instead. Replacing the table breaks hook ownership, mutation tracking, and any live closures that intentionally point at the persistent owner.

## Layer Responsibilities

### Core

Core owns coordinator bootstrap and stable GUI callback registration.

Core responsibilities:
- register stable `rom.gui` callbacks once behind `modutil.once_loaded.game(...)`
- call `Framework.init(...)` from the reload body
- late-read Framework factories so a Framework reload does not leave Core holding stale closures

### Framework

Framework owns pack-level coordinator state:
- discovery
- hashing
- HUD
- coordinator UI

Framework owns the current pack object for each `packId`.
Coordinator/Core code owns the init parameters and re-calls `Framework.init(...)`
when the coordinator/framework layer reloads or when Lib requests a coordinated
structural rebuild.

### Lib

Lib owns the shared reload-sensitive plumbing:
- coordinator registration
- coordinated module startup/runtime sync
- stable ModUtil hook dispatch
- mutation runtime persistence
- standalone host suppression for coordinated modules

### Modules

Modules own their local rebuild:
- recreate `definition`, `store`, `session`, and the Lib-created live host in `init`
- keep `chalk`, `reload`, and raw config local to `main.lua`
- keep persisted runtime reads on `store`
- keep staged UI edits on the author-facing `session`
- declare runtime hooks from `internal.RegisterHooks()`

## Bootstrap Pattern

The steady-state plugin pattern is:

```lua
local loader = reload.auto_single()

local function registerGui()
    rom.gui.add_imgui(renderWindow)
    rom.gui.add_always_draw_imgui(alwaysDraw)
    rom.gui.add_to_menu_bar(addMenuBar)
end

local function init()
    -- rebuild current state
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

The important part is the split:
- stable GUI registration happens once
- the active state rebuild happens from `init`

## Coordinated Module Host Refresh

`lib.createModuleHost(...)` is the behavior refresh boundary for a coordinated module.

When host creation succeeds:
- the module host closes over the current `definition`, `store`, and `session`
- if `hookOwner` and `registerHooks` are provided, Lib refreshes that owner's hook registrations
- if the coordinator for `definition.modpack` is already registered, Lib immediately runs `host.applyOnLoad()`

That means one coordinated module reload refreshes its live runtime behavior immediately without forcing a pack rebuild.

## Framework Pack Refresh

Framework replaces the current pack object when the coordinator calls
`Framework.init(params)` again for the same `packId`. The replacement keeps the
pack's stable HUD/index slot while rebuilding discovery, HUD, hash, and UI state
from the current live module hosts.

Core registers GUI callbacks once and those callback closures remain valid across
reloads by late-reading the current Framework renderer/menu factories from
`rom.mods`.

The invariant is:
- stable callbacks survive reloads
- coordinator/Core owns `Framework.init(params)` re-entry
- ordinary coordinated module behavior reloads do not require a pack rebuild

Framework reload is an infrastructure path, not the fast module-authoring path.
Rebuilding a pack is allowed to recreate Framework UI state from scratch. The
mod window may close, the selected tab may reset, and transient profile/import
feedback may be lost. Persist only correctness-critical state across Framework
reloads; module behavior state should refresh through Lib hosts instead.

HUD marker text is safe to refresh in place. HUD marker layout is not: the game
creates retained HUD components from `ScreenData.HUD.ComponentData`, so changing
that table only affects future HUD construction. A Framework change that moves
or restyles the marker structurally must recreate the HUD component or wait for a
game HUD refresh.

## Hook Model

Raw ModUtil path hooks do not deduplicate. The stack solves that through `lib.hooks`.

Supported public hook entrypoints:
- `lib.hooks.Wrap`
- `lib.hooks.Override`
- `lib.hooks.Context.Wrap`

The model is:
- use a persistent owner table, typically the module `internal`
- register hook sites from `internal.RegisterHooks()`
- pass `hookOwner` and `registerHooks` into `lib.createModuleHost(...)`
- Lib runs the full registration pass during host creation

Behavior:
- the same owner/path/key updates the live handler instead of stacking another wrapper
- function overrides dispatch through a stable wrapper
- omitted wrap and context-wrap registrations become inert
- omitted override registrations are restored

This keeps hot-reloaded logic live without accumulating normal duplicate wrappers.

### Hook Caveat

There is one accepted development-only caveat.

If the same wrap or context-wrap site is:
- removed
- hot reloaded
- re-added
- hot reloaded again

within one live game process, inert wrappers can accumulate for that path.

This is:
- dev-only
- functionally safe
- cleared by a full game process restart

The stack does not currently engineer around that case.

## Mutation Model

Mutation runtime is persisted on `AdamantModpackLib_Internal`, not on recreated store objects.

Important properties:
- active tracked mutation state survives store recreation
- active state is keyed by stable module identity when available
- `applyOnLoad` synchronizes live mutation state to the module's effective enabled state
- if a module is disabled on reload, tracked active mutation state is reverted

This keeps run-data patch lifecycles coherent across reloads.

## Coordinator And Standalone Behavior

Coordinator metadata is persisted on `AdamantModpackLib_Internal.coordinators`.

Important consequences:
- a Lib reload does not forget which packs are coordinated
- standalone module windows remain suppressed for coordinated modules
- standalone startup lifecycle applies only when the module is not coordinated

Framework calls `applyOnLoad()` for discovered coordinated modules during pack init.
`lib.standaloneHost(...)` calls `applyOnLoad()` for standalone modules during standalone startup.
`lib.createModuleHost(...)` also calls `applyOnLoad()` immediately when the module is already coordinated, so behavior-only module reloads resync live runtime state without a pack rebuild.

## Safety By Scenario

### Normal player use

Safe.

Players who are not editing files do not exercise the hot-reload path. The stack boots from scratch and uses the same runtime contracts without reload churn.

### Developer doing module work

Supported.

Module reload replaces the module's live host surface. Framework snapshots that host on the next UI/hash operation, and Lib immediately resyncs live mutation state if the module is already coordinated.

### Developer doing Lib or Framework work

Supported.

Persistent Lib registries survive Lib reload. Core late-reads Framework callbacks.
Coordinator/Core re-calls `Framework.init(params)` to rebuild pack state.

### Developer reloading Lib and modules in one session

Supported.

The coordinator registry, mutation runtime, live-host registry, and coordinator
rebuild callback are designed to converge back to the latest live surfaces.

### Structural edits

Handled by coordinated rebuild when a coordinator rebuild callback is registered;
otherwise full reload is required.

Changes to:
- `definition.id`
- `definition.modpack`
- `definition.name` or `shortName`
- `definition.storage`
- `definition.hashGroupPlan` / host hash hints
- module presence or discovery shape

should be treated as structural compatibility work. In coordinated packs, Lib can
request a Framework rebuild after the replacement host is created. Outside that
coordinated path, use a full reload.

## Practical Rules

- keep `chalk`, `reload`, and raw config local to `main.lua`
- recreate `definition`, `store`, `session`, and the Lib-created live host in `init`
- keep `session` local to `main.lua`; draw callbacks receive the restricted author session through the host
- register runtime hooks through `internal.RegisterHooks()` and `lib.hooks.*`
- pass `hookOwner` and `registerHooks` to `lib.createModuleHost(...)` when the module owns runtime hooks
- keep stable GUI callbacks outside `init`
- late-read current framework or module state from those stable callbacks when a stale closure would matter
- do not use raw ModUtil path wraps for repo-owned hot-reload-sensitive hook sites
- do not replace persistent internal registries on reload; update their contents instead
