# Changelog

All notable changes to this project will be documented in this file.


## [Unreleased]

Initial public release of the adamant Modpack Lib surface.

### Added

- managed module storage through `lib.createStore(config, definition, dataDefaults?)`
- explicit staged UI state through the returned `session`
- host-based module wiring through `lib.createModuleHost(...)`
- standalone window/menu hosting through `lib.standaloneHost(...)`
- lifecycle helpers under `lib.lifecycle.*`
- mutation helpers under `lib.mutation.*`
- hashing and packed-bit helpers under `lib.hashing.*`
- immediate-mode widget helpers under `lib.widgets.*`
- immediate-mode navigation helpers under `lib.nav.*`
- shared logging helpers under `lib.logging.*`
- managed storage support for:
  - `bool`
  - `int`
  - `string`
  - `packedInt`
- transactional session commit/resync support for host and framework flows
- coordinated-pack enable-state support through `lib.isModuleCoordinated(...)` and `lib.isModuleEnabled(...)`
- standalone and framework-friendly module authoring contract based on:
  - `public.definition`
  - `public.host`
  - direct draw functions such as `DrawTab(imgui, session)`
- reload-stable ModUtil hook registration through:
  - `lib.hooks.Wrap(...)`
  - `lib.hooks.Override(...)`
  - `lib.hooks.Context.Wrap(...)`
- pack-level coordinated host registry version queries through `lib.getModuleRegistryVersion(packId)`
- hot-reload architecture guide under `docs/HOT_RELOAD_ARCHITECTURE.md`

### Changed

- `lib.createModuleHost(...)` now supports `hookOwner` and `registerHooks` for host-owned hook refresh
- coordinated module hosts now publish their current `{ definition, host }` surface into the Lib registry on host creation
- mutation runtime tracking now persists across recreated stores and reloads keyed by stable module identity when available
- `lib.lifecycle.applyOnLoad(...)` now reverts active tracked mutation state when a module reloads disabled
- long-form guides and reference docs now live under `docs/`

### Fixed

- standalone/coordinated checks now read the persistent coordinator registry instead of a transient captured table
- fallback HUD marker hook registration no longer stacks raw ModUtil wraps across reloads

[Unreleased]: https://github.com/h2-modpack/adamant-ModpackLib/compare/HEAD
