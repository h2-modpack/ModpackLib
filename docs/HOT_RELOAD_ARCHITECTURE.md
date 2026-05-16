# Hot Reload Architecture

This document describes the supported hot-reload model of the adamant stack.

It covers how `adamant-ModpackLib`, `adamant-ModpackFramework`, coordinator shells, and coordinated modules stay coherent when files reload inside one live Hades II process.

For the raw behavior of `SGG_Modding-ReLoad`, `SGG_Modding-ModUtil`, and `SGG_Modding-Chalk`, read [RELOAD_MODUTIL_CHALK_REFERENCE.md](RELOAD_MODUTIL_CHALK_REFERENCE.md) first.

For the proposed next-generation host runtime transaction design, read
[HOST_RUNTIME_SYNC_DESIGN.md](HOST_RUNTIME_SYNC_DESIGN.md).

## Goals

- keep normal player sessions safe without requiring code edits
- support module development with live module reloads
- document Lib and Framework reloads as infrastructure development paths with a full restart as the correctness boundary
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

These tables are initialized with `X = X or {}` so they survive a file reload in the same game process.

Safe to rebuild on every module `init`:
- `definition`
- `store`
- `session`
- live module host created by `lib.createModule(...)` and activated by `host.tryActivate()`
- UI draw closures
- lookup tables derived from current imports

Expected to persist across reloads:
- Lib coordinator registrations
- Lib per-plugin module runtime slots keyed by `pluginGuid`
- Lib hook registries owned by those per-plugin runtime slots
- Framework pack registry and stable GUI callbacks
- module-owned ROM GUI callbacks that call Lib bridge functions from
  `lib.standaloneUiBridge(pluginGuid)`

Modules pass `pluginGuid` as their lifecycle identity. Lib owns the internal
runtime slot used for structural hot-reload tracking, hook refresh ownership,
overlay ownership, integration refresh, mutation runtime, and live-host lookup.

## Layer Responsibilities

### Core

Core owns coordinator bootstrap and stable GUI callback registration.

Core responsibilities:
- register stable `rom.gui` callbacks once behind `modutil.once_loaded.game(...)`
- register coordinator metadata from `mods.on_all_mods_loaded(...)`
- call `Framework.init(...)` from the reload body
- late-read Framework factories so a Framework reload does not leave Core holding stale closures

`mods.on_all_mods_loaded(...)` is intentional coordinator timing, not a generic
readiness gate. ROM calls these callbacks after the full mod graph loads, and it
also replays a module's callbacks when that module hot reloads after the
all-mods-loaded milestone. That gives Core both properties the coordinator
beacon needs: initial registration happens after coordinated modules have loaded,
and later Core reloads refresh Lib's stored rebuild callback closure.

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
- integration provider refresh
- retained overlay registration and refresh
- mutation runtime tracking for module reloads
- standalone host suppression for coordinated modules

### Modules

Modules own their local rebuild:
- recreate `definition`, `store`, `session`, and the Lib-created live host in `init`
- keep `chalk`, `reload`, and raw config local to `main.lua`
- keep persisted runtime reads on `store`
- keep staged UI edits on the author-facing `session`
- declare runtime hooks from a local or imported `registerHooks(host, store)` callback
- declare retained overlays from `registerOverlays(overlays, host, store)`

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

`lib.createModule(...)` plus `host.tryActivate()` is the normal behavior refresh boundary for a coordinated module.

During module creation and activation:
- the module host closes over the current `definition`, `store`, and `session`
- `host.tryActivate()` publishes the live host
- Lib refreshes hook registrations for the module's `pluginGuid`; absent hook registrations for that module are deactivated
- Lib refreshes integration registrations under the module's `pluginGuid`; absent integration providers for that module are removed
- if the coordinator for `definition.modpack` is already registered, Lib immediately syncs live mutation state

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
reloads. Module behavior state refreshes through Lib hosts.

A Framework file reload does not, by itself, rebuild an existing pack object.
The coordinator must call `Framework.init(params)` again, either from its reload
body or through a coordinated structural rebuild request.

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
- register hook sites from `registerHooks(host, store)`
- pass `pluginGuid` and `registerHooks` into `lib.createModule(...)`
- call `host.tryActivate()` after construction
- Lib runs the full registration pass during module activation

Behavior:
- the same plugin-guid/path/key updates the live handler and keeps one active wrapper
- function overrides dispatch through a stable wrapper
- omitted wrap and context-wrap registrations become inert
- omitted override registrations are restored

This keeps hot-reloaded logic live without accumulating normal duplicate wrappers.

### Hook Caveat

There is one accepted development-only caveat.

If the same wrap or context-wrap site is:
- omitted from a registration pass
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

Mutation runtime is durable across module reloads, not across arbitrary Lib
implementation reloads.

Important properties:
- active tracked mutation state survives store recreation during module reload
- active module-host state is keyed by `pluginGuid`
- host startup sync synchronizes live mutation state to the module's effective enabled state
- if a module is disabled on reload, tracked active mutation state is reverted

This keeps run-data patch lifecycles coherent across reloads.

Lib reload is an infrastructure development path. If Lib's mutation internals
reload while mutations are already active, use a full game process restart as the
correctness boundary before validating mutation rollback behavior.

## Coordinator And Standalone Behavior

Coordinator metadata is persisted on `AdamantModpackLib_Internal.coordinators`.

Important consequences:
- a Lib reload does not forget which packs are coordinated
- standalone module windows remain suppressed for coordinated modules
- standalone startup lifecycle applies only when the module is not coordinated

Framework calls `host.applyOnLoad()` for discovered coordinated modules during pack init.
`lib.standaloneHost(...)` calls `host.applyOnLoad()` for standalone modules during standalone startup.
Activation also syncs live mutation state immediately when the module is already coordinated, so non-structural module reloads resync live runtime state without a pack rebuild.

## Safety By Scenario

### Normal player use

Safe.

Players who are not editing files do not exercise the hot-reload path. The stack boots from scratch and uses the same runtime contracts without reload churn.

### Developer doing module work

Supported.

Module reload replaces the module's live host surface. Framework snapshots that host on the next UI/hash operation, and Lib immediately resyncs live mutation state if the module is already coordinated.

### Developer doing Lib or Framework work

Best-effort infrastructure development path.

Persistent Lib registries survive Lib reload, and Core late-reads Framework
callbacks. Existing module hosts may still close over prior Lib implementation
closures until the owning module reloads. Coordinator/Core must re-call
`Framework.init(params)` to rebuild Framework pack state after Framework changes.
Use a full process restart as the correctness boundary for infrastructure
changes that affect mutation internals, top-level registration, or retained HUD
layout.

### Developer reloading Lib and modules in one session

Best-effort.

The coordinator registry, live-host registry, and coordinator rebuild callback
are designed to converge back to the latest live surfaces after the relevant
modules rebuild their hosts. Active mutation runtime is not a Lib reload
persistence guarantee.

### Structural edits

Handled by coordinated rebuild when a coordinator rebuild callback is registered;
otherwise full reload is required.

Changes to:
- `definition.id`
- `definition.modpack`
- `definition.name`
- `definition.shortName`
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
- register runtime hooks through `registerHooks(host, store)` and ownerless `lib.hooks.*`
- pass `pluginGuid` and `registerHooks` to `lib.createModule(...)` when the module owns runtime hooks
- call `host.tryActivate()` after construction
- keep stable GUI callbacks outside `init`
- late-read current framework or module state from those stable callbacks when a stale closure would matter
- do not use raw ModUtil path wraps for repo-owned hot-reload-sensitive hook sites
- keep persistent internal registries stable across reloads; update their contents in place
