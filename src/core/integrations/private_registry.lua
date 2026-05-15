local internal = AdamantModpackLib_Internal

internal.integrations = internal.integrations or {
    registry = {},
    providerRegistry = {},
    transactions = {},
}
internal.integrations.registry = internal.integrations.registry or {}
internal.integrations.providerRegistry = internal.integrations.providerRegistry or {}
internal.integrations.transactions = internal.integrations.transactions or {}

local registry = internal.integrations.registry
local providerRegistry = internal.integrations.providerRegistry
local transactions = internal.integrations.transactions

local function GetRegistry()
    return registry
end

local function GetBucket(id, create)
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

local function RemoveProviderFromBucket(bucket, providerId)
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

local function PruneBucket(id, bucket)
    if bucket and #bucket.order == 0 then
        registry[id] = nil
    end
end

local function GetPreferredProvider(id)
    local bucket = GetBucket(id, false)
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

local function GetProviderOrderIndex(bucket, providerId)
    for index, currentProviderId in ipairs(bucket.order) do
        if currentProviderId == providerId then
            return index
        end
    end
    return nil
end

local function InsertProviderOrder(bucket, providerId, index)
    if GetProviderOrderIndex(bucket, providerId) then
        return
    end
    if index and index <= #bucket.order then
        table.insert(bucket.order, index, providerId)
    else
        table.insert(bucket.order, providerId)
    end
end

local function BeginTransaction()
    local transaction = {
        seen = {},
        changes = {},
        closed = false,
    }
    transactions[#transactions + 1] = transaction
    return transaction
end

local function CloseTransaction(transaction)
    if transaction.closed then
        return
    end
    for index = #transactions, 1, -1 do
        if transactions[index] == transaction then
            table.remove(transactions, index)
            break
        end
    end
    transaction.closed = true
end

local function RecordRegistrationChange(id, providerId, bucket)
    local transaction = transactions[#transactions]
    if not transaction then
        return
    end

    local key = id .. "\0" .. providerId
    if transaction.seen[key] then
        return
    end

    transaction.seen[key] = true
    transaction.changes[#transaction.changes + 1] = {
        id = id,
        providerId = providerId,
        existed = bucket.providers[providerId] ~= nil,
        api = bucket.providers[providerId],
        orderIndex = GetProviderOrderIndex(bucket, providerId),
    }
end

local function GetProviderRefresh(providerId, create)
    local refresh = providerRegistry[providerId]
    if not refresh and create then
        refresh = {
            generation = 0,
            refreshing = false,
            slots = {},
        }
        providerRegistry[providerId] = refresh
    end
    return refresh
end

local function RecordProviderSlot(refreshProviderId, id, providerId)
    local refresh = GetProviderRefresh(refreshProviderId, false)
    if not refresh or not refresh.refreshing then
        return
    end

    local key = id .. "\0" .. providerId
    refresh.slots[key] = {
        id = id,
        providerId = providerId,
        generation = refresh.generation,
    }
end

local function ClearProviderRefresh(providerId)
    providerRegistry[providerId] = nil
end

return {
    getRegistry = GetRegistry,
    getBucket = GetBucket,
    removeProviderFromBucket = RemoveProviderFromBucket,
    pruneBucket = PruneBucket,
    getPreferredProvider = GetPreferredProvider,
    getProviderOrderIndex = GetProviderOrderIndex,
    insertProviderOrder = InsertProviderOrder,
    beginTransaction = BeginTransaction,
    closeTransaction = CloseTransaction,
    recordRegistrationChange = RecordRegistrationChange,
    getProviderRefresh = GetProviderRefresh,
    recordProviderSlot = RecordProviderSlot,
    clearProviderRefresh = ClearProviderRefresh,
}
