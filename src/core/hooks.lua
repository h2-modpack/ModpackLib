public.hooks = public.hooks or {}
public.hooks.Context = public.hooks.Context or {}
AdamantModpackLib_Internal.hooks = AdamantModpackLib_Internal.hooks or {}

local hooks = public.hooks
local internalHooks = AdamantModpackLib_Internal.hooks
local REGISTRY_KEY = "__adamantHooks"

hooks.Refresh = nil

local function getPathApi()
    local pathApi = modutil and modutil.mod and modutil.mod.Path
    assert(pathApi, "lib.hooks: ModUtil Path API is not available")
    return pathApi
end

local function getRegistry(owner)
    assert(type(owner) == "table", "lib.hooks: owner must be a persistent table")

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

local function parseRegistrationArgs(path, keyOrValue, maybeValue, valueName)
    assert(type(path) == "string" and path ~= "", "lib.hooks: path must be a non-empty string")
    if maybeValue == nil then
        assert(keyOrValue ~= nil, "lib.hooks: " .. valueName .. " is required")
        return path, keyOrValue
    end
    return tostring(keyOrValue), maybeValue
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
    return state
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
            local pathApi = getPathApi()
            pathApi.Restore(state.path)
            state.registered = false
        end
    end
end

--- Registers or updates a stable ModUtil Path.Wrap dispatcher.
--- Re-running with the same owner/path/key updates the wrapped handler without stacking another wrapper.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to wrap.
---@param keyOrHandler string|function Explicit hook key, or handler when no key is needed.
---@param maybeHandler function|nil Handler when an explicit key is supplied.
function hooks.Wrap(owner, path, keyOrHandler, maybeHandler)
    local key, handler = parseRegistrationArgs(path, keyOrHandler, maybeHandler, "handler")
    assert(type(handler) == "function", "lib.hooks.Wrap: handler must be a function")

    local state = getSlot(owner, "wrap", path, key)
    state.handler = handler

    if not state.registered then
        getPathApi().Wrap(path, function(base, ...)
            local current = state.handler
            if current then
                return current(base, ...)
            end
            return base(...)
        end)
        state.registered = true
    end
end

--- Registers or updates a stable ModUtil Path.Override.
--- Function replacements use a dispatcher so hot reloads update behavior without re-overriding.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to override.
---@param keyOrReplacement string|any Explicit hook key, or replacement when no key is needed.
---@param maybeReplacement any|nil Replacement when an explicit key is supplied.
function hooks.Override(owner, path, keyOrReplacement, maybeReplacement)
    local key, replacement = parseRegistrationArgs(path, keyOrReplacement, maybeReplacement, "replacement")
    local state = getSlot(owner, "override", path, key)
    local pathApi = getPathApi()

    state.replacement = replacement

    if type(replacement) == "function" then
        if not state.registered then
            pathApi.Override(path, function(...)
                local current = state.replacement
                assert(type(current) == "function", "lib.hooks.Override: function replacement is inactive")
                return current(...)
            end)
            state.registered = true
            state.usesDispatcher = true
        elseif not state.usesDispatcher then
            pathApi.Restore(path)
            pathApi.Override(path, function(...)
                local current = state.replacement
                assert(type(current) == "function", "lib.hooks.Override: function replacement is inactive")
                return current(...)
            end)
            state.usesDispatcher = true
        end
        return
    end

    if state.registered then
        pathApi.Restore(path)
    end
    pathApi.Override(path, replacement)
    state.registered = true
    state.usesDispatcher = false
end

--- Registers or updates a stable ModUtil Path.Context.Wrap dispatcher.
--- Removed context wraps become inert during host hook refresh; ModUtil has no safe path-level restore for one context wrapper.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to context-wrap.
---@param keyOrContext string|function Explicit hook key, or context function when no key is needed.
---@param maybeContext function|nil Context function when an explicit key is supplied.
function hooks.Context.Wrap(owner, path, keyOrContext, maybeContext)
    local key, context = parseRegistrationArgs(path, keyOrContext, maybeContext, "context")
    assert(type(context) == "function", "lib.hooks.Context.Wrap: context must be a function")

    local state = getSlot(owner, "contextWrap", path, key)
    state.context = context

    if not state.registered then
        getPathApi().Context.Wrap(path, function(...)
            local current = state.context
            if current then
                return current(...)
            end
        end)
        state.registered = true
    end
end

--- Runs hook registration as one reload generation and deactivates registrations omitted by the callback.
---@param owner table Persistent module/framework internal table.
---@param register fun()
function internalHooks.refresh(owner, register)
    assert(type(register) == "function", "internal.hooks.refresh: register must be a function")

    local registry = getRegistry(owner)
    registry.generation = registry.generation + 1
    registry.refreshing = true

    local ok, err = pcall(register)
    registry.refreshing = false

    if ok then
        for id, state in pairs(registry.slots) do
            if state.generation ~= registry.generation then
                deactivateSlot(state)
                registry.slots[id] = nil
            end
        end
    end

    if not ok then
        error(err, 0)
    end
end
