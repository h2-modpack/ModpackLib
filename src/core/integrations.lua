local internal = AdamantModpackLib_Internal

public.integrations = public.integrations or {}
local integrations = public.integrations

internal.integrations = internal.integrations or {
    registry = {},
}

local registry = internal.integrations.registry

local function getBucket(id, create)
    local bucket = registry[id]
    if not bucket and create then
        bucket = {
            providers = {},
            order = {},
        }
        registry[id] = bucket
    end
    return bucket
end

local function removeProviderFromBucket(bucket, providerId)
    if not bucket or bucket.providers[providerId] == nil then
        return false
    end

    bucket.providers[providerId] = nil
    for index, currentProviderId in ipairs(bucket.order) do
        if currentProviderId == providerId then
            table.remove(bucket.order, index)
            break
        end
    end

    return true
end

local function pruneBucket(id, bucket)
    if bucket and #bucket.order == 0 then
        registry[id] = nil
    end
end

local function getPreferredProvider(id)
    local bucket = getBucket(id, false)
    if not bucket then
        return nil, nil
    end

    for index = #bucket.order, 1, -1 do
        local providerId = bucket.order[index]
        local api = bucket.providers[providerId]
        if api ~= nil then
            return api, providerId
        end
    end

    return nil, nil
end

--- Registers or replaces an optional cross-module integration provider.
--- Re-registering the same `id` and `providerId` updates the API in place.
---@param id string Domain-named integration id, e.g. "run-director.god-availability".
---@param providerId string Stable provider id, usually `definition.id`.
---@param api table Provider API table exposed to consumers.
---@return table api The registered API table.
function integrations.register(id, providerId, api)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: id must be a non-empty string")
    end
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: providerId must be a non-empty string")
    end
    if type(api) ~= "table" then
        internal.violate("integrations.invalid_args", "lib.integrations.register: api must be a table")
    end

    local bucket = getBucket(id, true)
    if bucket.providers[providerId] == nil then
        table.insert(bucket.order, providerId)
    end
    bucket.providers[providerId] = api
    return api
end

--- Unregisters one provider for one integration id.
---@param id string Integration id.
---@param providerId string Stable provider id.
---@return boolean removed True when a provider was removed.
function integrations.unregister(id, providerId)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.unregister: id must be a non-empty string")
    end
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.unregister: providerId must be a non-empty string")
    end

    local bucket = getBucket(id, false)
    local removed = removeProviderFromBucket(bucket, providerId)
    pruneBucket(id, bucket)
    return removed
end

--- Unregisters a provider from all integration ids.
---@param providerId string Stable provider id.
---@return number count Number of removed provider registrations.
function integrations.unregisterProvider(providerId)
    if type(providerId) ~= "string" or providerId == "" then
        internal.violate(
            "integrations.invalid_args",
            "lib.integrations.unregisterProvider: providerId must be a non-empty string"
        )
    end

    local count = 0
    for id, bucket in pairs(registry) do
        if removeProviderFromBucket(bucket, providerId) then
            count = count + 1
            pruneBucket(id, bucket)
        end
    end
    return count
end

--- Returns the preferred provider API for an integration id.
--- When multiple providers exist, the most recently registered provider wins.
---@param id string Integration id.
---@return table|nil api Provider API table, or nil when absent.
---@return string|nil providerId Provider id for the returned API.
function integrations.get(id)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.get: id must be a non-empty string")
    end

    return getPreferredProvider(id)
end

--- Resolves the current preferred provider and invokes one method immediately.
--- This is the preferred consumer path because it avoids caching stale provider APIs.
---@param id string Integration id.
---@param methodName string Provider API method name.
---@param fallback any Value returned when the provider or method is absent, or when the method fails.
---@return any result Provider method result, or fallback.
---@return string|nil providerId Provider id that handled the call.
function integrations.invoke(id, methodName, fallback, ...)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.invoke: id must be a non-empty string")
    end
    if type(methodName) ~= "string" or methodName == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.invoke: methodName must be a non-empty string")
    end

    local api, providerId = getPreferredProvider(id)
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
function integrations.list(id)
    if type(id) ~= "string" or id == "" then
        internal.violate("integrations.invalid_args", "lib.integrations.list: id must be a non-empty string")
    end

    local bucket = getBucket(id, false)
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
