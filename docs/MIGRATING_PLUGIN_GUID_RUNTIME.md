# Migrating To Plugin-Guid Runtime Identity

This note covers the module lifecycle identity change that removes normal
module-authored `owner` tokens.

## What Changed

- `lib.createModule(...)` and `lib.tryCreateModule(...)` no longer accept
  `owner`.
- `pluginGuid` is the single stable lifecycle identity for a module host.
- Lib owns the internal per-plugin runtime slot used for structural hot-reload
  tracking, hook refresh ownership, overlay ownership, integration refresh,
  mutation runtime, and live-host lookup.
- `definition.id` remains the module's domain/UI/profile/hash identity.
- `modpack` remains coordinator grouping.

## Module Migration

Before:

```lua
local host = lib.tryCreateModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = internal.definition,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
})
```

After:

```lua
local definition = import("mods/definition.lua")
local logic = import("mods/logic.lua")
local ui = import("mods/ui.lua")

local host = lib.tryCreateModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = definition,
    registerHooks = logic.registerHooks,
    drawTab = ui.drawTab,
})
```

Modules should use `lib.standaloneUiBridge(pluginGuid)` for stable standalone
GUI callbacks instead of keeping private persistent tables for standalone UI
handles. Private persistent tables are still valid for truly module-owned cached
data, but they should not be passed to Lib as lifecycle owners.

## Hook And Overlay Notes

Normal module hooks stay ownerless inside `registerHooks(host, store)`:

```lua
local function registerHooks(host, store)
    lib.hooks.Wrap("SomeGameFunction", function(base, ...)
        return base(...)
    end)
end
```

Lib scopes those declarations to the module's `pluginGuid`. Explicit-owned APIs
such as `lib.hooks.WrapOwned(...)` and `lib.overlays.defineOwned(...)` remain
for Lib, Framework, and advanced system-owned surfaces.

## Integration Notes

`registerIntegrations(host, store)` is refreshed by the module's `pluginGuid`.
The `providerId` passed to `lib.integrations.register(id, providerId, api)` is
still the public integration provider identity, not the lifecycle owner. It can
remain a module/domain id chosen for consumers.
