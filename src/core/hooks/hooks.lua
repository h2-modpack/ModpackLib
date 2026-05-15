public.hooks = public.hooks or {}
public.hooks.Context = public.hooks.Context or {}
AdamantModpackLib_Internal.hooks = AdamantModpackLib_Internal.hooks or {}

local internal = AdamantModpackLib_Internal
local registry = import 'core/hooks/private_registry.lua'
local ActiveOwnerStack = {}

local function parseRegistrationArgs(path, keyOrValue, maybeValue, valueName)
    if type(path) ~= "string" or path == "" then
        internal.violate("hooks.invalid_registration", "lib.hooks: path must be a non-empty string")
    end
    if maybeValue == nil then
        if keyOrValue == nil then
            internal.violate("hooks.invalid_registration", "lib.hooks: %s is required", valueName)
        end
        return path, keyOrValue
    end
    return tostring(keyOrValue), maybeValue
end

local function getActiveOwner(apiName)
    local owner = ActiveOwnerStack[#ActiveOwnerStack]
    if not owner then
        internal.violate(
            "hooks.no_active_owner",
            "lib.hooks.%s requires an active registerHooks context; use %sOwned(owner, ...) outside module activation",
            apiName,
            apiName
        )
    end
    return owner
end

--- Registers or updates a stable ModUtil Path.Wrap dispatcher using the active module owner.
---@param path string ModUtil path to wrap.
---@param keyOrHandler string|function Explicit hook key, or handler when no key is needed.
---@param maybeHandler function|nil Handler when an explicit key is supplied.
function public.hooks.Wrap(path, keyOrHandler, maybeHandler)
    return public.hooks.WrapOwned(getActiveOwner("Wrap"), path, keyOrHandler, maybeHandler)
end

--- Registers or updates a stable ModUtil Path.Wrap dispatcher for an explicit owner.
--- Re-running with the same owner/path/key updates the wrapped handler without stacking another wrapper.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to wrap.
---@param keyOrHandler string|function Explicit hook key, or handler when no key is needed.
---@param maybeHandler function|nil Handler when an explicit key is supplied.
function public.hooks.WrapOwned(owner, path, keyOrHandler, maybeHandler)
    local key, handler = parseRegistrationArgs(path, keyOrHandler, maybeHandler, "handler")
    if type(handler) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Wrap: handler must be a function")
    end

    local state, ownerRegistry = registry.getSlot(owner, "wrap", path, key)
    if ownerRegistry.refreshing then
        state.pendingHandler = handler
        return
    end

    state.pendingHandler = handler
    registry.applyWrapState(state)
    registry.clearPendingState(state)
end

--- Registers or updates a stable ModUtil Path.Override using the active module owner.
---@param path string ModUtil path to override.
---@param keyOrReplacement string|any Explicit hook key, or replacement when no key is needed.
---@param maybeReplacement any|nil Replacement when an explicit key is supplied.
function public.hooks.Override(path, keyOrReplacement, maybeReplacement)
    return public.hooks.OverrideOwned(getActiveOwner("Override"), path, keyOrReplacement, maybeReplacement)
end

--- Registers or updates a stable ModUtil Path.Override for an explicit owner.
--- Function replacements use a dispatcher so hot reloads update behavior without re-overriding.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to override.
---@param keyOrReplacement string|any Explicit hook key, or replacement when no key is needed.
---@param maybeReplacement any|nil Replacement when an explicit key is supplied.
function public.hooks.OverrideOwned(owner, path, keyOrReplacement, maybeReplacement)
    local key, replacement = parseRegistrationArgs(path, keyOrReplacement, maybeReplacement, "replacement")
    local state, ownerRegistry = registry.getSlot(owner, "override", path, key)
    if ownerRegistry.refreshing then
        state.pendingReplacement = replacement
        return
    end

    state.pendingReplacement = replacement
    registry.applyOverrideState(state)
    registry.clearPendingState(state)
end

--- Registers or updates a stable ModUtil Path.Context.Wrap dispatcher using the active module owner.
---@param path string ModUtil path to context-wrap.
---@param keyOrContext string|function Explicit hook key, or context function when no key is needed.
---@param maybeContext function|nil Context function when an explicit key is supplied.
function public.hooks.Context.Wrap(path, keyOrContext, maybeContext)
    return public.hooks.Context.WrapOwned(getActiveOwner("Context.Wrap"), path, keyOrContext, maybeContext)
end

--- Registers or updates a stable ModUtil Path.Context.Wrap dispatcher for an explicit owner.
--- Removed context wraps become inert during host hook refresh; ModUtil has no safe path-level restore for one context wrapper.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to context-wrap.
---@param keyOrContext string|function Explicit hook key, or context function when no key is needed.
---@param maybeContext function|nil Context function when an explicit key is supplied.
function public.hooks.Context.WrapOwned(owner, path, keyOrContext, maybeContext)
    local key, context = parseRegistrationArgs(path, keyOrContext, maybeContext, "context")
    if type(context) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Context.Wrap: context must be a function")
    end

    local state, ownerRegistry = registry.getSlot(owner, "contextWrap", path, key)
    if ownerRegistry.refreshing then
        state.pendingContext = context
        return
    end

    state.pendingContext = context
    registry.applyContextWrapState(state)
    registry.clearPendingState(state)
end

--- Starts a rollback boundary for hook refreshes owned by one persistent owner.
---@param owner table Persistent module/framework internal table.
function internal.hooks.beginTransaction(owner)
    local ownerRegistry = registry.getRegistry(owner)
    local snapshot = registry.snapshotRegistry(ownerRegistry)
    local closed = false

    return {
        commit = function()
            closed = true
        end,
        rollback = function()
            if closed then
                return
            end
            registry.restoreRegistry(ownerRegistry, snapshot)
            closed = true
        end,
    }
end

--- Runs hook registration as one reload generation and deactivates registrations omitted by the callback.
---@param owner table Persistent module/framework internal table.
---@param register fun()
function internal.hooks.refresh(owner, register)
    if type(register) ~= "function" then
        internal.violate("hooks.invalid_registration", "internal.hooks.refresh: register must be a function")
    end

    local ownerRegistry = registry.getRegistry(owner)
    ownerRegistry.generation = ownerRegistry.generation + 1
    ownerRegistry.refreshing = true

    ActiveOwnerStack[#ActiveOwnerStack + 1] = owner
    local ok, err = pcall(register)
    ActiveOwnerStack[#ActiveOwnerStack] = nil
    ownerRegistry.refreshing = false

    if ok then
        for id, state in pairs(ownerRegistry.slots) do
            if state.generation ~= ownerRegistry.generation then
                registry.deactivateSlot(state)
                ownerRegistry.slots[id] = nil
            elseif state.kind == "wrap" then
                registry.applyWrapState(state)
                registry.clearPendingState(state)
            elseif state.kind == "override" then
                registry.applyOverrideState(state)
                registry.clearPendingState(state)
            elseif state.kind == "contextWrap" then
                registry.applyContextWrapState(state)
                registry.clearPendingState(state)
            end
        end
    else
        for id, state in pairs(ownerRegistry.slots) do
            if state.generation == ownerRegistry.generation then
                registry.clearPendingState(state)
                if not state.registered then
                    ownerRegistry.slots[id] = nil
                end
            end
        end
    end

    if not ok then
        error(err, 0)
    end
end
