local deps = ...

local internal = deps.internal
local storageInternal = deps.storage
local values = deps.values
local managedStoreState = deps.state.managedStores
local ClonePersistedValue = values.deepCopy
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

local function bindManagedStore(store, state)
    managedStoreState[store] = state
end

local function writePersisted(store, alias, value)
    local state = store and managedStoreState[store] or nil
    if not state then
        internal.violate("store.invalid_managed_store", "internal.store.writePersisted expects a managed store")
    end
    return state.write(alias, value)
end

local function create(modConfig, backend, storage)
    local store = {}
    local runtimeValues = {}

    local aliasNodes = storageInternal.getAliases(storage)
    local unstagedAliases = {}
    local tableHandles = {}
    for _, node in ipairs(storageInternal.getRuntimeCacheRoots(storage)) do
        if type(node.alias) == "string" and node.alias ~= "" then
            unstagedAliases[node.alias] = node
        end
    end

    local function readRaw(alias)
        local raw
        if backend then
            raw = backend.readValue(alias)
        end
        if raw == nil then
            raw = modConfig[alias]
        end
        return raw
    end

    local function writeRaw(alias, value)
        if backend and backend.writeValue(alias, value) then
            return
        end
        modConfig[alias] = value
    end

    local function readRootNode(root)
        if root._persist then
            local raw = readRaw(root._storageKey)
            if raw ~= nil then
                return raw
            end
        else
            local raw = runtimeValues[root]
            if raw ~= nil then
                return raw
            end
        end
        return ClonePersistedValue(root.default)
    end

    local function writeRootNode(root, value)
        if root._persist then
            writeRaw(root._storageKey, NormalizeStorageValue(root, value))
        else
            runtimeValues[root] = NormalizeStorageValue(root, value)
        end
    end

    local function hydratePersistRoot(root)
        if not root._persist then
            return
        end

        local raw = readRaw(root._storageKey)
        local source = raw
        if source == nil then
            source = ClonePersistedValue(root.default)
        end
        local normalized = NormalizeStorageValue(root, source)
        if raw ~= nil and values.deepEqual(raw, normalized) then
            return
        end

        if raw == nil and backend and backend.ensureValue(root._storageKey, normalized) then
            return
        end
        writeRaw(root._storageKey, normalized)
    end

    for _, root in ipairs(storageInternal.getPersistRoots(storage)) do
        hydratePersistRoot(root)
    end

    local storeReadBackend = {
        readRoot = readRootNode,
        canRead = function(node, alias)
            if not node._persist and node._stage then
                internal.violate(
                    "store.invalid_read_surface",
                    "store.read: alias '%s' is staged-only; use session for UI-only state",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownRead = function(alias)
            internal.violate("store.unknown_read_alias", "store.read: unknown storage alias '%s'", tostring(alias))
        end,
    }

    local storeWriteBackend = {
        readRoot = readRootNode,
        writeRoot = function(root, rootValue)
            writeRootNode(root, rootValue)
            return true
        end,
        canWrite = function(node, alias)
            if not node._persist and node._stage then
                internal.violate(
                    "store.invalid_write_surface",
                    "internal.store.writePersisted: alias '%s' is staged-only; use session for UI-only state",
                    tostring(alias))
                return false
            end
            return true
        end,
        onUnknownWrite = function(alias)
            internal.violate("store.unknown_write_alias", "internal.store.writePersisted: unknown storage alias '%s'",
                tostring(alias))
        end,
    }

    function store.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    function store.table(alias)
        local cached = tableHandles[alias]
        if cached then
            return cached
        end

        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            internal.violate("store.unknown_table_alias", "store.table: unknown storage alias '%s'", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            internal.violate("store.invalid_table_alias", "store.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        if not node._persist and node._stage then
            internal.violate("store.invalid_table_surface", "store.table: alias '%s' is staged-only; use session.table()",
                tostring(alias))
            return nil
        end
        local handle = storageInternal.table.CreateTableHandle(node, {
            readRoot = readRootNode,
            normalizedRoot = true,
        })
        tableHandles[alias] = handle
        return handle
    end

    local function writeStoreValue(alias, value)
        storageInternal.writeAlias(aliasNodes, storeWriteBackend, alias, value)
    end

    function store.writeUnstaged(alias, value)
        if not unstagedAliases[alias] then
            internal.violate(
                "store.invalid_unstaged_write",
                "store.writeUnstaged: alias '%s' is not declared with stage = false",
                tostring(alias)
            )
            return false
        end
        writeStoreValue(alias, value)
        return true
    end

    bindManagedStore(store, {
        write = writeStoreValue,
    })

    return store
end

return {
    create = create,
    writePersisted = writePersisted,
}
