local internal = AdamantModpackLib_Internal
local storageInternal = internal.storage

local function readNestedPath(tbl, key)
    if type(key) == "table" then
        if #key == 0 then return nil, nil, nil end
        for i = 1, #key - 1 do
            tbl = tbl[key[i]]
            if not tbl then return nil, nil, nil end
        end
        return tbl[key[#key]], tbl, key[#key]
    end
    return tbl[key], tbl, key
end

local function writeNestedPath(tbl, key, value)
    if type(key) == "table" then
        for i = 1, #key - 1 do
            tbl[key[i]] = tbl[key[i]] or {}
            tbl = tbl[key[i]]
        end
        tbl[key[#key]] = value
        return
    end
    tbl[key] = value
end

local function ClonePersistedValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function NormalizeStorageValue(node, value)
    local storageType = node and node.type and storageInternal.types[node.type] or nil
    if storageType and type(storageType.normalize) == "function" then
        return storageType.normalize(node, value)
    end
    return value
end

---@param modConfig table
---@param configBackend ConfigBackend|nil
---@param storage StorageSchema
---@return Session
function internal.store.createSession(modConfig, configBackend, storage)
    local persistedRootNodes = storageInternal.getRoots(storage)
    local transientRootNodes = type(storage) == "table" and (rawget(storage, "_transientRootNodes") or {}) or {}
    local aliasNodes = storageInternal.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = {}

    if configBackend then
        for _, root in ipairs(persistedRootNodes) do
            configEntries[root.alias] = configBackend.getEntry(root.configKey)
        end
    else
        configEntries = nil
    end

    local function readConfigValue(root)
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            return entry:get()
        end
        return readNestedPath(modConfig, root.configKey)
    end

    local function writeConfigValue(root, value)
        local entry = configEntries and configEntries[root.alias] or nil
        if entry then
            entry:set(value)
            return
        end
        writeNestedPath(modConfig, root.configKey, value)
    end

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases or {}) do
            local rawValue = storageInternal.readPackedBits(packedValue, child.offset, child.width)
            if child.type == "bool" then
                rawValue = rawValue ~= 0
            end
            staging[child.alias] = NormalizeStorageValue(child, rawValue)
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
        if root._lifetime ~= "transient" then
            dirtyRoots[root.alias] = true
            dirty = true
        end
        return true
    end

    local function loadPersistedRootIntoStaging(root)
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

    local function loadTransientRootIntoStaging(root)
        local value = ClonePersistedValue(root.default)
        staging[root.alias] = NormalizeStorageValue(root, value)
    end

    local function copyConfigToStaging()
        for _, root in ipairs(persistedRootNodes) do
            loadPersistedRootIntoStaging(root)
        end
    end

    local function resetTransientToDefaults()
        for _, root in ipairs(transientRootNodes) do
            loadTransientRootIntoStaging(root)
        end
    end

    local function copyStagingToConfig()
        for _, root in ipairs(persistedRootNodes) do
            if dirtyRoots[root.alias] then
                writeConfigValue(root, staging[root.alias])
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(persistedRootNodes) do
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

    local readonlyProxy = setmetatable({}, {
        __index = function(_, key)
            return staging[key]
        end,
        __newindex = function()
            error("session.view is read-only; use session.write", 2)
        end,
        __pairs = function()
            return next, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return staging[alias]
    end

    local function writeStagingValue(alias, value)
        local node = aliasNodes[alias]
        if not node then
            if internal.logging and internal.logging.warnIf then
                internal.logging.warnIf("session.write: unknown alias '%s'; value will not be persisted", tostring(alias))
            end
            return
        end

        if node._isBitAlias then
            local parent = node.parent
            local packedValue = staging[parent.alias]
            if packedValue == nil then
                if parent._lifetime == "transient" then
                    loadTransientRootIntoStaging(parent)
                else
                    loadPersistedRootIntoStaging(parent)
                end
                packedValue = staging[parent.alias]
            end
            local normalized = NormalizeStorageValue(node, value)
            if storageInternal.valuesEqual(node, staging[node.alias], normalized) then
                return
            end
            local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
            local nextPacked = storageInternal.writePackedBits(packedValue, node.offset, node.width, encoded)
            if storageInternal.valuesEqual(parent, packedValue, nextPacked) then
                staging[node.alias] = normalized
                return
            end
            writeRootToStaging(parent, nextPacked)
            staging[node.alias] = normalized
            return
        end

        writeRootToStaging(node, value)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            if internal.logging and internal.logging.warnIf then
                internal.logging.warnIf("session.reset: unknown alias '%s'; value will not be reset", tostring(alias))
            end
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    copyConfigToStaging()
    resetTransientToDefaults()
    clearDirty()

    return {
        view = readonlyProxy,
        read = function(alias)
            return readStagingValue(alias)
        end,
        write = function(alias, value)
            writeStagingValue(alias, value)
        end,
        reset = function(alias)
            resetAliasValue(alias)
        end,
        _reloadFromConfig = function()
            copyConfigToStaging()
            resetTransientToDefaults()
            clearDirty()
        end,
        flushToConfig = function()
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
            for _, root in ipairs(persistedRootNodes) do
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
                        local childValue = storageInternal.readPackedBits(persistedValue, child.offset, child.width)
                        if child.type == "bool" then
                            childValue = childValue ~= 0
                        end
                        childValue = NormalizeStorageValue(child, childValue)
                        if not storageInternal.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
            end
            return mismatches
        end,
    }
end
