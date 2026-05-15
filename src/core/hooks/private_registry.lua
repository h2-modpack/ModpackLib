local internal = AdamantModpackLib_Internal
local REGISTRY_KEY = "__adamantHooks"

local function getModUtil()
    local resolved = modutil
    if not resolved and rom and rom.mods then
        resolved = rom.mods["SGG_Modding-ModUtil"]
    end
    if not (resolved and resolved.mod and resolved.mod.Path) then
        internal.violate("hooks.modutil_unavailable", "lib.hooks: SGG_Modding-ModUtil is not available")
    end
    return resolved
end

local function getRegistry(owner)
    if type(owner) ~= "table" then
        internal.violate("hooks.invalid_registration", "lib.hooks: owner must be a persistent table")
    end

    local registry = owner[REGISTRY_KEY]
    if not registry then
        registry = {
            generation = 0,
            refreshing = false,
            slots = {},
        }
        owner[REGISTRY_KEY] = registry
    end
    return registry
end

local function slotId(kind, path, key)
    return kind .. "\0" .. path .. "\0" .. key
end

local function getSlot(owner, kind, path, key)
    local registry = getRegistry(owner)
    local id = slotId(kind, path, key)
    local state = registry.slots[id]
    if not state then
        state = {
            kind = kind,
            path = path,
            key = key,
            registered = false,
        }
        registry.slots[id] = state
    end
    if registry.refreshing then
        state.generation = registry.generation
    end
    return state, registry
end

local function clearPendingState(state)
    state.pendingHandler = nil
    state.pendingReplacement = nil
    state.pendingContext = nil
end

local function applyWrapState(state)
    if state.pendingHandler ~= nil then
        state.handler = state.pendingHandler
    end

    if not state.registered then
        getModUtil().mod.Path.Wrap(state.path, function(base, ...)
            local current = state.handler
            if current then
                return current(base, ...)
            end
            return base(...)
        end)
        state.registered = true
    end
end

local function applyOverrideState(state)
    local replacement = state.pendingReplacement

    state.replacement = replacement

    if type(replacement) == "function" then
        if not state.registered then
            getModUtil().mod.Path.Override(state.path, function(...)
                local current = state.replacement
                if type(current) ~= "function" then
                    internal.violate("hooks.inactive_override", "lib.hooks.Override: function replacement is inactive")
                end
                return current(...)
            end)
            state.registered = true
            state.usesDispatcher = true
        elseif not state.usesDispatcher then
            local resolvedModUtil = getModUtil()
            resolvedModUtil.mod.Path.Restore(state.path)
            resolvedModUtil.mod.Path.Override(state.path, function(...)
                local current = state.replacement
                if type(current) ~= "function" then
                    internal.violate("hooks.inactive_override", "lib.hooks.Override: function replacement is inactive")
                end
                return current(...)
            end)
            state.usesDispatcher = true
        end
        return
    end

    if state.registered then
        getModUtil().mod.Path.Restore(state.path)
    end
    getModUtil().mod.Path.Override(state.path, replacement)
    state.registered = true
    state.usesDispatcher = false
end

local function applyContextWrapState(state)
    if state.pendingContext ~= nil then
        state.context = state.pendingContext
    end

    if not state.registered then
        getModUtil().mod.Path.Context.Wrap(state.path, function(...)
            local current = state.context
            if current then
                return current(...)
            end
        end)
        state.registered = true
    end
end

local function deactivateSlot(state)
    if state.kind == "wrap" then
        state.handler = nil
        return
    end

    if state.kind == "contextWrap" then
        state.context = nil
        return
    end

    if state.kind == "override" then
        state.replacement = nil
        if state.registered then
            getModUtil().mod.Path.Restore(state.path)
            state.registered = false
        end
    end
end

local function snapshotSlot(state)
    return {
        kind = state.kind,
        path = state.path,
        key = state.key,
        generation = state.generation,
        registered = state.registered,
        handler = state.handler,
        replacement = state.replacement,
        context = state.context,
        usesDispatcher = state.usesDispatcher,
    }
end

local function snapshotRegistry(registry)
    local slots = {}
    for id, state in pairs(registry.slots) do
        slots[id] = snapshotSlot(state)
    end
    return {
        generation = registry.generation,
        refreshing = registry.refreshing,
        slots = slots,
    }
end

local function restoreWrapSlot(state, snapshot)
    state.generation = snapshot.generation
    state.registered = snapshot.registered
    state.handler = snapshot.handler
    state.replacement = nil
    state.context = nil
    state.usesDispatcher = nil
    clearPendingState(state)
end

local function restoreContextWrapSlot(state, snapshot)
    state.generation = snapshot.generation
    state.registered = snapshot.registered
    state.handler = nil
    state.replacement = nil
    state.context = snapshot.context
    state.usesDispatcher = nil
    clearPendingState(state)
end

local function restoreOverrideSlot(state, snapshot)
    state.generation = snapshot.generation
    clearPendingState(state)

    if snapshot.registered then
        state.pendingReplacement = snapshot.replacement
        applyOverrideState(state)
        clearPendingState(state)
    else
        deactivateSlot(state)
    end

    state.registered = snapshot.registered
    state.replacement = snapshot.replacement
    state.usesDispatcher = snapshot.usesDispatcher
end

local function restoreSlot(registry, id, snapshot)
    local state = registry.slots[id]
    if not state then
        state = {
            kind = snapshot.kind,
            path = snapshot.path,
            key = snapshot.key,
            registered = false,
        }
        registry.slots[id] = state
    end

    state.kind = snapshot.kind
    state.path = snapshot.path
    state.key = snapshot.key

    if snapshot.kind == "wrap" then
        restoreWrapSlot(state, snapshot)
    elseif snapshot.kind == "contextWrap" then
        restoreContextWrapSlot(state, snapshot)
    elseif snapshot.kind == "override" then
        restoreOverrideSlot(state, snapshot)
    end
end

local function restoreRegistry(registry, snapshot)
    for id, state in pairs(registry.slots) do
        if snapshot.slots[id] == nil then
            deactivateSlot(state)
            clearPendingState(state)
            if state.kind == "wrap" or state.kind == "contextWrap" then
                state.generation = snapshot.generation
            else
                registry.slots[id] = nil
            end
        end
    end

    for id, slotSnapshot in pairs(snapshot.slots) do
        restoreSlot(registry, id, slotSnapshot)
    end

    registry.generation = snapshot.generation
    registry.refreshing = snapshot.refreshing
end

return {
    getRegistry = getRegistry,
    getSlot = getSlot,
    clearPendingState = clearPendingState,
    applyWrapState = applyWrapState,
    applyOverrideState = applyOverrideState,
    applyContextWrapState = applyContextWrapState,
    deactivateSlot = deactivateSlot,
    snapshotRegistry = snapshotRegistry,
    restoreRegistry = restoreRegistry,
}
