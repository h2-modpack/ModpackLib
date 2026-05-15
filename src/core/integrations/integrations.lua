local internal = AdamantModpackLib_Internal
local registry = import 'core/integrations/private_registry.lua'

public.integrations = public.integrations or {}
internal.integrations = internal.integrations or {}

local ActiveProviderStack = {}

function internal.integrations.beginTransaction()
    local transaction = registry.beginTransaction()

    return {
        commit = function()
            registry.closeTransaction(transaction)
        end,
        rollback = function()
            if transaction.closed then
                return
            end
            for index = #transaction.changes, 1, -1 do
                local change = transaction.changes[index]
                local bucket = registry.getBucket(change.id, change.existed)
                if change.existed then
                    bucket.providers[change.providerId] = change.api
                    registry.insertProviderOrder(bucket, change.providerId, change.orderIndex)
                else
                    registry.removeProviderFromBucket(bucket, change.providerId)
                    registry.pruneBucket(change.id, bucket)
                end
            end
            registry.closeTransaction(transaction)
        end,
    }
end

---@param providerId string Stable provider id.
---@param register fun()
function internal.integrations.refresh(providerId, register)
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "internal.integrations.refresh: providerId must be a non-empty string")
    end
    if type(register) ~= "function" then
        internal.violate("integrations.invalid_args", "internal.integrations.refresh: register must be a function")
    end

    local refresh = registry.getProviderRefresh(providerId, true)
    refresh.generation = refresh.generation + 1
    refresh.refreshing = true

    ActiveProviderStack[#ActiveProviderStack + 1] = providerId
    local ok, err = pcall(register)
    ActiveProviderStack[#ActiveProviderStack] = nil
    refresh.refreshing = false

    if ok then
        for key, slot in pairs(refresh.slots) do
            if slot.generation ~= refresh.generation then
                public.integrations.unregister(slot.id, slot.providerId)
                refresh.slots[key] = nil
            end
        end
    else
        for key, slot in pairs(refresh.slots) do
            if slot.generation == refresh.generation then
                refresh.slots[key] = nil
            end
        end
        error(err, 0)
    end
end

--- Registers or replaces an optional cross-module integration provider.
--- Re-registering the same `id` and `providerId` updates the API in place.
---@param id string Domain-named integration id, e.g. "run-director.god-availability".
---@param providerId string Stable provider id, usually `definition.id`.
---@param api table Provider API table exposed to consumers.
---@return table api The registered API table.
function public.integrations.register(id, providerId, api)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: id must be a non-empty string")
    end
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: providerId must be a non-empty string")
    end
    if type(api) ~= "table" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: api must be a table")
    end

    local bucket = registry.getBucket(id, true)
    registry.recordRegistrationChange(id, providerId, bucket)
    registry.recordProviderSlot(ActiveProviderStack[#ActiveProviderStack] or providerId, id, providerId)
    registry.insertProviderOrder(bucket, providerId)
    bucket.providers[providerId] = api
    return api
end

--- Unregisters one provider for one integration id.
---@param id string Integration id.
---@param providerId string Stable provider id.
---@return boolean removed True when a provider was removed.
function public.integrations.unregister(id, providerId)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.unregister: id must be a non-empty string")
    end
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.unregister: providerId must be a non-empty string")
    end

    local bucket = registry.getBucket(id, false)
    local removed = registry.removeProviderFromBucket(bucket, providerId)
    registry.pruneBucket(id, bucket)
    return removed
end

--- Unregisters a provider from all integration ids.
---@param providerId string Stable provider id.
---@return number count Number of removed provider registrations.
function public.integrations.unregisterProvider(providerId)
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate(
            "integrations.invalid_args",
            "lib.integrations.unregisterProvider: providerId must be a non-empty string"
        )
    end

    local count = 0
    for id, bucket in pairs(registry.getRegistry()) do
        if registry.removeProviderFromBucket(bucket, providerId) then
            count = count + 1
            registry.pruneBucket(id, bucket)
        end
    end
    registry.clearProviderRefresh(providerId)
    return count
end

--- Returns the preferred provider API for an integration id.
--- When multiple providers exist, the most recently registered provider wins.
---@param id string Integration id.
---@return table|nil api Provider API table, or nil when absent.
---@return string|nil providerId Provider id for the returned API.
function public.integrations.get(id)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.get: id must be a non-empty string")
    end

    return registry.getPreferredProvider(id)
end

--- Resolves the current preferred provider and invokes one method immediately.
--- This is the preferred consumer path because it avoids caching stale provider APIs.
---@param id string Integration id.
---@param methodName string Provider API method name.
---@param fallback any Value returned when the provider or method is absent, or when the method fails.
---@return any result Provider method result, or fallback.
---@return string|nil providerId Provider id that handled the call.
function public.integrations.invoke(id, methodName, fallback, ...)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.invoke: id must be a non-empty string")
    end
    if type(methodName) ~= "string" or methodName == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.invoke: methodName must be a non-empty string")
    end

    local api, providerId = registry.getPreferredProvider(id)
    local method = api and api[methodName] or nil
    if type(method) ~= "function" then
        return fallback, providerId
    end

    local ok, result = pcall(method, ...)
    if not ok then
        internal.violate(
            "integrations.provider_failed",
            "%s.%s provider '%s' failed: %s",
            tostring(id),
            tostring(methodName),
            tostring(providerId),
            tostring(result))
        return fallback, providerId
    end

    return result, providerId
end

--- Lists all providers for an integration id in registration order.
---@param id string Integration id.
---@return table[] providers Array of `{ providerId = string, api = table }` entries.
function public.integrations.list(id)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.list: id must be a non-empty string")
    end

    local bucket = registry.getBucket(id, false)
    local providers = {}
    if not bucket then
        return providers
    end

    for _, providerId in ipairs(bucket.order) do
        local api = bucket.providers[providerId]
        if api ~= nil then
            table.insert(providers, {
                providerId = providerId,
                api = api,
            })
        end
    end

    return providers
end
