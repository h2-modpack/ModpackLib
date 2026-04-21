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

Framework also owns pack freshness checks:
- it stores the init params used to build each pack session
- it rebuilds a pack when Framework itself reloads
- it rebuilds a pack when a coordinated module republishes its host

### Lib

Lib owns the shared reload-sensitive plumbing:
- coordinator registration
- coordinated module host publication
- module registry versions
- stable ModUtil hook dispatch
- mutation runtime persistence
- standalone host suppression for coordinated modules

### Modules

Modules own their local rebuild:
- recreate `definition`, `store`, `session`, and `public.host` in `init`
- keep `chalk`, `reload`, and raw config local to `main.lua`
- keep persisted runtime reads on `store`
- keep staged UI edits on the author-facing `session`
- declare runtime hooks from `internal.RegisterHooks()`

## Bootstrap Pattern

The steady-state plugin pattern is:

```lua
local loader = reload.auto_single()

local function init()
    -- rebuild current state
end

modutil.once_loaded.game(function()
    rom.gui.add_imgui(renderWindow)
    rom.gui.add_always_draw_imgui(alwaysDraw)
    rom.gui.add_to_menu_bar(addMenuBar)
    loader.load(nil, init)
end)
```

The important part is the split:
- stable GUI registration happens once
- the active state rebuild happens from `init`

## Coordinated Module Publication

`lib.createModuleHost(...)` is the publishing boundary for a coordinated module.

When host creation succeeds:
- the module host closes over the current `definition`, `store`, and `session`
- if `hookOwner` and `registerHooks` are provided, Lib refreshes that owner's hook registrations
- if `definition.modpack` and `definition.id` are present, Lib publishes `{ definition, host }` into the coordinated module registry
- Lib increments the registry version for that `packId`

That means one module reload republishes the module's live surface for the coordinator pack.

## Framework Pack Refresh

Framework stores three things per pack session:
- `initParams`
- `frameworkGeneration`
- `moduleRegistryVersion`

Its renderer, menu-bar callback, and always-draw callback all run a freshness check before using the pack.

Framework rebuilds the pack when:
- Framework reloaded and its generation changed
- a coordinated module republished its host and the pack registry version changed

The rebuild path reruns `Framework.init(pack.initParams)` and refreshes discovery, HUD, hash, and UI state from the latest module surfaces.

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

## Safety By Scenario

### Normal player use

Safe.

Players who are not editing files do not exercise the hot-reload path. The stack boots from scratch and uses the same runtime contracts without reload churn.

### Developer doing module work

Supported.

Module reload republishes the module host, bumps the pack registry version, and lets Framework rebuild the pack on the next callback.

### Developer doing Lib or Framework work

Supported.

Persistent Lib registries survive Lib reload. Core late-reads Framework callbacks. Framework rebuilds pack state when its generation changes.

### Developer reloading Lib and modules in one session

Supported.

The coordinated module registry, coordinator registry, mutation runtime, and Framework freshness checks are designed to converge back to the latest live surfaces.

## Practical Rules

- keep `chalk`, `reload`, and raw config local to `main.lua`
- recreate `definition`, `store`, `session`, and `public.host` in `init`
- keep `session` local to `main.lua`; draw callbacks receive the restricted author session through the host
- register runtime hooks through `internal.RegisterHooks()` and `lib.hooks.*`
- pass `hookOwner` and `registerHooks` to `lib.createModuleHost(...)` when the module owns runtime hooks
- keep stable GUI callbacks outside `init`
- late-read current framework or module state from those stable callbacks when a stale closure would matter
- do not use raw ModUtil path wraps for repo-owned hot-reload-sensitive hook sites
- do not replace persistent internal registries on reload; update their contents instead
