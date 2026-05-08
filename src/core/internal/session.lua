local internal = AdamantModpackLib_Internal
local storageInternal = internal.storage
local storeInternal = internal.store
local ClonePersistedValue = storeInternal.ClonePersistedValue
local NormalizeStorageValue = storageInternal.NormalizeStorageValue
local DecodePackedChild = storageInternal.DecodePackedChild

---@param modConfig table
---@param configBackend ConfigBackend|nil
---@param storage StorageSchema
---@return Session
function internal.store.createSession(modConfig, configBackend, storage)
    local stageRootNodes = storageInternal.getStageRoots(storage)
    local aliasNodes = storageInternal.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = {}

    if configBackend then
        for _, root in ipairs(stageRootNodes) do
            if root._persist then
                configEntries[root.alias] = configBackend.getEntry(root._storageKey)
            end
        end
    else
        configEntries = nil
    end

    local function readConfigValue(root)
        if not root._persist then
            return nil
        end
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            return entry:get()
        end
        return modConfig[root._storageKey]
    end

    local function writeConfigValue(root, value)
        if not root._persist then
            return
        end
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            entry:set(value)
            return
        end
        modConfig[root._storageKey] = value
    end

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases or {}) do
            staging[child.alias] = DecodePackedChild(child, packedValue)
        end
    end

    local function writeRootToStaging(root, value)
        local normalized = NormalizeStorageValue(root, value)
        local current = staging[root.alias]
        if storageInternal.valuesEqual(root, current, normalized) then
            return false
        end
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
        if root._persist then
            dirtyRoots[root.alias] = true
            dirty = true
        end
        return true
    end

    local function loadStageRootIntoStaging(root)
        local value = readConfigValue(root)
        if value == nil then
            value = ClonePersistedValue(root.default)
        end
        local normalized = NormalizeStorageValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
    end

    local function copyConfigToStaging()
        for _, root in ipairs(stageRootNodes) do
            loadStageRootIntoStaging(root)
        end
    end

    local function copyStagingToConfig()
        for _, root in ipairs(stageRootNodes) do
            if dirtyRoots[root.alias] then
                writeConfigValue(root, staging[root.alias])
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(stageRootNodes) do
            if dirtyRoots[root.alias] then
                table.insert(snapshot, {
                    root = root,
                    value = ClonePersistedValue(readConfigValue(root)),
                })
            end
        end
        return snapshot
    end

    local function restoreConfigSnapshot(snapshot)
        for _, entry in ipairs(snapshot or {}) do
            writeConfigValue(entry.root, ClonePersistedValue(entry.value))
        end
    end

    local function clearDirty()
        dirty = false
        dirtyRoots = {}
    end

    local sessionReadBackend = {
        readRoot = function(root)
            return staging[root.alias]
        end,
        canRead = function(node, alias)
            if not node._stage then
                internal.violate(
                    "session.invalid_read_surface",
                    "session.read: alias '%s' is not staged; use store.read()",
                    tostring(alias)
                )
                return false
            end
            return true
        end,
        onUnknownRead = function(alias)
            internal.violate("session.unknown_read_alias", "session.read: unknown alias '%s'", tostring(alias))
        end,
    }

    local sessionWriteBackend = {
        readRoot = function(root)
            if staging[root.alias] == nil then
                loadStageRootIntoStaging(root)
            end
            return staging[root.alias]
        end,
        writeRoot = writeRootToStaging,
        writeAliasValue = function(node, aliasValue)
            staging[node.alias] = aliasValue
        end,
        canWrite = function(node, alias)
            if not node._stage then
                internal.violate(
                    "session.invalid_write_surface",
                    "session.write: alias '%s' is not staged; use store.writeUnstaged()",
                    tostring(alias)
                )
                return false
            end
            return true
        end,
        onUnknownWrite = function(alias)
            internal.violate("session.unknown_write_alias", "session.write: unknown alias '%s'", tostring(alias))
        end,
    }

    local readonlyProxy = setmetatable({}, {
        __index = function(_, key)
            local value = staging[key]
            local node = aliasNodes[key]
            if node and node.type == "table" then
                return ClonePersistedValue(value)
            end
            return value
        end,
        __newindex = function()
            internal.violate("session.readonly_view_write", "session.view is read-only; use session.write")
        end,
        __pairs = function()
            return function(_, key)
                local nextKey, value = next(staging, key)
                local node = aliasNodes[nextKey]
                if node and node.type == "table" then
                    value = ClonePersistedValue(value)
                end
                return nextKey, value
            end, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return storageInternal.readAlias(aliasNodes, sessionReadBackend, alias)
    end

    local function writeStagingValue(alias, value)
        storageInternal.writeAlias(aliasNodes, sessionWriteBackend, alias, value)
    end

    local function getTableHandle(alias)
        local node = type(alias) == "string" and aliasNodes[alias] or nil
        if not node then
            internal.violate("session.unknown_table_alias", "session.table: unknown alias '%s'", tostring(alias))
            return nil
        end
        if node.type ~= "table" or node._isBitAlias then
            internal.violate("session.invalid_table_alias", "session.table: alias '%s' is not table storage", tostring(alias))
            return nil
        end
        if not node._stage then
            internal.violate(
                "session.invalid_table_surface",
                "session.table: alias '%s' is not staged; use store.table()",
                tostring(alias)
            )
            return nil
        end

        return storageInternal.CreateTableHandle(node, {
            readRoot = function(root)
                if staging[root.alias] == nil then
                    loadStageRootIntoStaging(root)
                end
                return staging[root.alias]
            end,
            writeRoot = writeRootToStaging,
            normalizedRoot = true,
        })
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            internal.violate("session.unknown_reset_alias", "session.reset: unknown alias '%s'", tostring(alias))
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    copyConfigToStaging()
    clearDirty()

    return {
        view = readonlyProxy,
        read = function(alias)
            return readStagingValue(alias)
        end,
        table = function(alias)
            return getTableHandle(alias)
        end,
        write = function(alias, value)
            writeStagingValue(alias, value)
        end,
        reset = function(alias)
            resetAliasValue(alias)
        end,
        _reloadFromConfig = function()
            copyConfigToStaging()
            clearDirty()
        end,
        _flushToConfig = function()
            copyStagingToConfig()
            clearDirty()
        end,
        _captureDirtyConfigSnapshot = captureDirtyConfigSnapshot,
        _restoreConfigSnapshot = restoreConfigSnapshot,
        isDirty = function()
            return dirty
        end,
        auditMismatches = function()
            local mismatches = {}
            for _, root in ipairs(stageRootNodes) do
                if not root._persist then
                    goto continue_root
                end
                local persistedValue = readConfigValue(root)
                if persistedValue == nil then
                    persistedValue = ClonePersistedValue(root.default)
                end
                persistedValue = NormalizeStorageValue(root, persistedValue)
                if not storageInternal.valuesEqual(root, persistedValue, staging[root.alias]) then
                    table.insert(mismatches, root.alias)
                end
                if root.type == "packedInt" then
                    for _, child in ipairs(root._bitAliases or {}) do
                        local childValue = DecodePackedChild(child, persistedValue)
                        if not storageInternal.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
                ::continue_root::
            end
            return mismatches
        end,
    }
end
