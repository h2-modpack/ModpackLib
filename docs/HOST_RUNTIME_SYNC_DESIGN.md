# Host Runtime Sync Design

This document describes the target host runtime-sync model for module hot
reload. It is a design note, not the current implementation contract.

The goal is simple: a candidate host should not be discoverable until every
managed runtime effect it owns is usable. If activation fails, the old host
stays live and candidate-owned effects are disposed.

This design is best-effort. Lua modules can still touch game globals, ROM APIs,
and ModUtil directly. Lib can only contain effects that pass through its managed
surfaces.

## Design Goals

- Remove author owner tokens from normal module authoring.
- Keep `pluginGuid` as the explicit stable module identity because ROM
  guarantees plugin GUID uniqueness and Lib cannot reliably infer the originating
  plugin from shared Lib call sites.
- Use the full host object as the per-generation runtime owner for managed
  effects.
- Keep `definition.id` as Framework/domain identity and `modpack` as coordinator
  grouping, not as the Lib host uniqueness boundary.
- Centralize candidate/current swapping in host activation.
- Replace subsystem-specific hot-reload homework with a small host-owned
  receipt contract.
- Stage candidate effects where practical so public lookup/dispatch does not
  observe failed candidates.
- Treat candidate runtime sync failure as activation failure.
- Accept that Lib itself is backbone infrastructure; hot reloading Lib-created
  host closures may require a full reload.
- Make future managed subsystems cheap to add by having them return receipts
  instead of inventing their own activation transaction model.

## Identity Model

The lifecycle uses two identities:

```text
pluginGuid -> stable logical module slot
host object -> runtime generation owner
```

`pluginGuid` is passed explicitly by the module because shared Lib code runs from
Lib's call site, not from the feature module's originating plugin context.

The full host object is created by Lib for one activation generation. It owns
hooks, integrations, overlays, mutation sync receipts, and activation metadata.
The author-facing `authorHost` stays restricted to safe module operations.

`definition.id` remains the Framework/domain id used for UI entries,
profile/hash keys, display metadata, ordering, and pack-local semantics.
`modpack` remains coordinator grouping. Neither replaces `pluginGuid` as the Lib
host replacement key.

## Managed Effects

The host transaction composes these effects:

- hooks registered by `registerHooks`
- integrations registered by `registerIntegrations`
- overlays registered by `registerOverlays`
- active patch-plan mutation state
- live run-data recompute
- live host publication
- coordinator rebuild/runtime-sync decision
- standalone runtime attachment, if needed

Direct game-data writes outside these surfaces are outside the managed
transaction contract.

## Effect Receipts

Each subsystem should install candidate effects through a host-owned receipt.

```lua
---@class HostEffectReceipt
---@field commit fun(): boolean, string?
---@field dispose fun(): boolean, string?
```

`commit()` makes staged candidate effects current. `dispose()` removes only the
effects owned by that host. Receipts should be idempotent where practical.

Target internal surfaces:

```lua
internal.integrations.installForHost(host, registerIntegrations, authorHost, store)
internal.hooks.installForHost(host, registerHooks, authorHost, store)
internal.overlays.installForHost(host, registerOverlays, authorHost, store)
internal.mutation.syncForHost(host, mutationBundle, authorHost, store, opts)
```

The host carries `pluginGuid`, prepared definition, store/session, callbacks,
and activation metadata, so subsystem entry points should not need separate
owner tokens.

## Integration Contract

Integrations are table-backed provider registrations, so they are the simplest
receipt target.

Target behavior:

- register candidate providers under the candidate host receipt
- keep old providers visible until commit
- make candidate providers current on commit
- dispose candidate providers on activation failure
- dispose old providers after candidate commit

Public integration lookup should never observe a candidate provider before
activation succeeds.

Provider ids can remain integration-domain keys. The host receipt owns the
candidate registration lifecycle even when the provider id is explicit.

## Hook Contract

Hooks need a path-global dispatcher model. The dispatcher deduplicates physical
ModUtil wrappers, while host-owned slots provide generation-specific behavior.

Target behavior:

- install one physical wrapper per hook path/kind where possible
- store handlers in Lib-owned dispatcher state
- index handlers by host and hook key
- build candidate host slots without making them current
- point dispatchers at candidate slots only on commit
- dispose old host slots after candidate commit

Conceptual shape:

```lua
HookDispatchers[path].installed = true
HookDispatchers[path].hosts[host].slots[key] = handler
HookDispatchers[path].currentHost = committedHost
```

This replaces the current stable-owner refresh model for module hooks. The host
is the runtime hook bucket. Lib/Framework system hooks that are not module-host
owned should be kept on separate explicit system-owned surfaces, not mixed into
module lifecycle ownership.

## Overlay Contract

Overlays are close to host ownership because retained overlay registries are
already keyed by an owner. Their main dependency is hook cleanup, because
retained overlay `afterHook(...)` registration uses the hook subsystem.

Target behavior:

- use the full host as the retained overlay owner
- derive renderer element ids from host metadata plus activation generation when
  candidate and old elements can coexist
- stage overlay entries if they must stay invisible until commit
- keep overlay after-hook plumbing owned by the overlay registry's internal hook
  owner
- dispose candidate overlays on activation failure
- dispose old host overlays after candidate commit

## Mutation Contract

Mutation has two phases:

1. raw table sync
2. live run-data recompute

Raw table sync applies or reverts tracked patch plans against game data tables.
Live recompute calls the base game `SetupRunData()` function so derived game
state reflects the raw edits.

Mutation owns raw table rollback. The host/coordinator transaction owns when
live recompute happens.

One active raw mutation plan should exist per `pluginGuid`. The candidate host
owns the activation receipt, but the active raw patch slot remains
plugin-guid-scoped so hot reload replaces a module patch instead of stacking
patches.

A mutation receipt should track:

- previous active raw patch plan
- candidate raw patch plan
- whether the previous raw patch was reverted
- whether the candidate raw patch was applied
- whether `SetupRunData()` ran after candidate apply
- whether the receipt committed

Candidate sync may temporarily revert the old active patch and apply the
candidate patch. If candidate apply fails, mutation restores the old active patch
before returning failure.

If `SetupRunData()` fails after candidate apply, rollback reverts the candidate
patch, restores the old active patch, and calls `SetupRunData()` again as a
best-effort derived-state restore. If rollback recompute also fails, the old
host remains the live host pointer, but derived game state is uncertain. Log
that rollback failure loudly while preserving the original activation failure as
the primary error.

`SetupRunData()` is a trusted base-game recompute boundary for valid game data,
not an atomic commit primitive. The game calls it unprotected, but Lib should
call it through protected control flow during candidate activation so invalid
candidate patch data becomes a recoverable activation failure where possible.

Batch operations should avoid one `SetupRunData()` call per module. Startup
sync, profile load, pack enable/disable, and other coordinated operations should
apply all raw mutation receipts first, then run one protected recompute for the
batch. Each receipt must still know whether recompute happened so rollback can
decide whether raw restore alone is enough or whether a second recompute is
needed.

## Activation Transaction

Activation should publish late.

Recommended order:

1. Validate candidate host and prepared definition.
2. Capture old live host pointer from `internal.liveModuleHosts[pluginGuid]`.
3. Install candidate integrations under the candidate host owner.
4. Install candidate hooks under the candidate host owner.
5. Install candidate overlays under the candidate host owner.
6. Sync candidate runtime mutation if policy says to do it now.
7. Commit candidate effect receipts.
8. Publish candidate as `internal.liveModuleHosts[pluginGuid]`.
9. Retire old host-owned resources.

The Framework should not be able to discover a candidate until the candidate is
fully usable.

Steps 7 and 8 are the commit point. They should run as a short no-yield block
with no author callbacks between them, because committed hooks, integrations,
overlays, or mutation state may become observable just before the live host
pointer is updated.

## Rollback Transaction

Rollback runs in reverse order:

1. Unpublish candidate if it was published.
2. Dispose candidate mutation receipt.
3. Dispose candidate overlays.
4. Dispose candidate hooks.
5. Dispose candidate integrations.
6. Restore old live host pointer if needed.

Rollback errors should be collected and logged. The original activation error
remains the primary returned error.

The old host remains live until commit. If candidate activation fails and
rollback succeeds, the old host continues as the last known good host. This
design deliberately avoids a separate discard/quarantine host mechanism until a
concrete future failure mode requires it.

## Host Metadata

Each constructed full host should carry enough metadata for transaction,
debugging, and later rebuild work:

- plugin guid
- prepared definition
- store and session
- mutation bundle
- hook registration callback
- integration registration callback
- overlay registration callback
- draw callbacks
- coordinator pack id and module id
- activation generation/id
- effect receipts

This does not require reconstructing from raw author options everywhere. It
means central host lifecycle code can activate, abort, retire, or resync a host
without subsystem-specific guesswork.

## Implementation Order

Build the receipt system in dependency order:

1. Integrations.
2. Hooks.
3. Overlays.
4. Mutation host-sync receipt.
5. Host activation transaction.

Integrations are first because they are table-backed and have no physical
external wrapper. Hooks come before overlays because overlays depend on hook
cleanup for `afterHook(...)`. Mutation comes after the simpler receipt shapes so
the host transaction can treat it as one participant.

## Design Constraint

Do not make every subsystem fully transactional in isolation. Each subsystem
only needs to provide:

- install/register through a host-owned runtime owner
- commit staged effects
- dispose/unregister through the same host-owned runtime owner

The host activation transaction composes those receipts and decides commit vs
rollback.
