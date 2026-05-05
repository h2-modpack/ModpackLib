# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Added `lib.prepareDefinition(...)` as the canonical definition-preparation step before store and host creation.
- Added a LuaLS public definition file at `src/def.lua` for the Lib module export, storage/session types, module host contract, lifecycle helpers, mutation plans, widgets, nav, hooks, integrations, hashing, logging, and ImGui helpers.
- Added Lib-owned live-host publication and lookup through `lib.getLiveModuleHost(...)`.
- Added reload-stable ModUtil hook registration through `lib.hooks.Wrap(...)`, `lib.hooks.Override(...)`, and `lib.hooks.Context.Wrap(...)`.
- Added coordinated pack rebuild callbacks through `lib.lifecycle.registerCoordinatorRebuild(...)` and `lib.lifecycle.requestCoordinatorRebuild(...)`.
- Added optional cross-module integration registration through `lib.integrations.*`.
- Added `lib.imguiHelpers.*` enum/value helpers for low-level ImGui binding use.
- Added `lib.overlays.*` retained HUD overlay helpers with managed `middleRightStack` layout, stacked text, stacked rows, owner suppression, and framework/module/debug order bands.
- Added `lib.gameObject.*` helpers for namespaced runtime state attached to live game object tables.
- Added runtime-only persisted storage aliases through `runtime = true` plus `store.getRuntimeState()`.
- Added `definition.onSettingsCommitted(store)` as a post-commit observer for rebuilding derived runtime/UI structures after staged config commits.
- Added docs for hot-reload architecture and known limitations under `docs/`.
- Added player-facing `THUNDERSTORE_README.md` packaging support.

### Changed

- Module authoring now uses the explicit `prepareDefinition(...) -> createStore(...) -> createModuleHost(...)` flow.
- Effective storage defaults are hydrated during definition preparation, before structural fingerprinting.
- Structural definition changes are fingerprinted separately from behavior-only changes.
- Coordinated modules can request a Framework rebuild when structural definition shape changes during hot reload.
- `createModuleHost(...)` now owns live-host publication and requires `drawTab`.
- Public module host surface was narrowed around stable host accessors and behavior calls; direct raw definition access was removed.
- `createModuleHost(...)` and `standaloneHost(...)` now require an explicit plugin guid captured at module load time.
- Manual lifecycle hooks now receive the active managed store as `apply(store)` and `revert(store)`.
- Mutation lifecycle state is tracked by stable module identity where available, making reload/reapply behavior more robust.
- `lib.lifecycle.applyOnLoad(...)` now reverts active tracked mutation state when a module reloads disabled.
- Store creation now requires prepared definitions with explicit storage.
- Runtime-only storage aliases are excluded from session staging, profile/hash surfaces, and reset-to-defaults flows.
- Host `writeAndFlush(...)`, `flush()`, and lifecycle `commitSession(...)` now notify `onSettingsCommitted` after successful dirty commits.
- The fallback HUD marker now participates in the shared overlay layout instead of owning a separate HUD placement path.
- Internal helper duplication was consolidated into shared internal value/store utilities.
- Widget packed dropdown/radio helpers avoid repeated packed-choice classification work per frame.
- Long-form guides and reference docs now live under `docs/`.
- Packaged README content moved out of `src/README.md`; package metadata now points at `THUNDERSTORE_README.md`.

### Fixed

- Fixed standalone/coordinated checks to read persistent coordinator state instead of transient captured tables.
- Fixed fallback HUD marker hook registration so it no longer stacks raw ModUtil wraps across reloads.
- Fixed manual mutation lifecycle paths so manual `apply`/`revert` receive the store consistently.
- Fixed storage default fingerprinting so config default changes are part of the structural contract.
- Fixed string hash serialization by escaping reserved token characters inside persisted keys and values.
- Fixed rebuild-request handling so rejected coordinator rebuild callbacks are not reported as successful.

### Documentation

- Expanded `API.md` to describe the current public Lib surface.
- Updated module authoring docs around prepared definitions, Lib-owned host publication, standalone hosting, lifecycle behavior, hooks, integrations, widgets, and hash helpers.
- Updated hot-reload docs around author-facing module reload support and infrastructure reload limitations.
- Moved known limitations into Lib docs so shared modpack constraints have one home.

### Tests

- Expanded test coverage for prepared definitions, lifecycle validation, stores/sessions, hooks, hashing, logging, mutation plans, nav, widgets, integrations, standalone hosting, and host publication.

## [1.0.0] - 2026-04-20

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

### Notes

- this release documents the current immediate-mode Lib contract
- legacy declarative UI authoring is not part of the supported public surface for this release

[unreleased]: https://github.com/h2-modpack/adamant-ModpackLib/compare/1.0.0...HEAD
[1.0.0]: https://github.com/h2-modpack/adamant-ModpackLib/compare/39bee9364299ddbc4447ec92c0e33662dbb43ab5...1.0.0
