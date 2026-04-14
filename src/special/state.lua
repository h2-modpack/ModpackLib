local internal = AdamantModpackLib_Internal
local shared = internal.shared

local function ClonePersistedValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function BuildConfigEntries(rootNodes, configBackend)
    if not configBackend then
        return nil
    end
    local configEntries = {}
    for _, root in ipairs(rootNodes) do
        configEntries[root.alias] = configBackend.getEntry(root.configKey)
    end
    return configEntries
end

local function NormalizeNodeValue(node, value)
    local storageType = shared.StorageTypes[node.type]
    if storageType and type(storageType.normalize) == "function" then
        return storageType.normalize(node, value)
    end
    return value
end

local function ReadConfigValue(root, modConfig, configEntries)
    local entry = configEntries and configEntries[root.alias] or nil
    if entry then
        return entry:get()
    end
    return public.accessors.readNestedPath(modConfig, root.configKey)
end

local function WriteConfigValue(root, modConfig, value, configEntries)
    local entry = configEntries and configEntries[root.alias] or nil
    if entry then
        entry:set(value)
        return
    end
    public.accessors.writeNestedPath(modConfig, root.configKey, value)
end

function shared.CreateUiState(modConfig, configBackend, storage)
    local persistedRootNodes = public.storage.getRoots(storage)
    local transientRootNodes = type(storage) == "table" and (rawget(storage, "_transientRootNodes") or {}) or {}
    local aliasNodes = public.storage.getAliases(storage)
    local staging = {}
    local dirty = false
    local dirtyRoots = {}
    local configEntries = BuildConfigEntries(persistedRootNodes, configBackend)

    local function syncPackedChildren(root, packedValue)
        for _, child in ipairs(root._bitAliases or {}) do
            local rawValue = public.accessors.readPackedBits(packedValue, child.offset, child.width)
            if child.type == "bool" then
                rawValue = rawValue ~= 0
            end
            staging[child.alias] = NormalizeNodeValue(child, rawValue)
        end
    end

    local function writeRootToStaging(root, value)
        local normalized = NormalizeNodeValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
        if root._lifetime ~= "transient" then
            dirtyRoots[root.alias] = true
            dirty = true
        end
    end

    local function loadPersistedRootIntoStaging(root)
        local value = ReadConfigValue(root, modConfig, configEntries)
        if value == nil then
            value = ClonePersistedValue(root.default)
        end
        local normalized = NormalizeNodeValue(root, value)
        staging[root.alias] = normalized
        if root.type == "packedInt" then
            syncPackedChildren(root, normalized)
        end
    end

    local function loadTransientRootIntoStaging(root)
        local value = ClonePersistedValue(root.default)
        staging[root.alias] = NormalizeNodeValue(root, value)
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
                WriteConfigValue(root, modConfig, staging[root.alias], configEntries)
            end
        end
    end

    local function captureDirtyConfigSnapshot()
        local snapshot = {}
        for _, root in ipairs(persistedRootNodes) do
            if dirtyRoots[root.alias] then
                table.insert(snapshot, {
                    root = root,
                    value = ClonePersistedValue(ReadConfigValue(root, modConfig, configEntries)),
                })
            end
        end
        return snapshot
    end

    local function restoreConfigSnapshot(snapshot)
        for _, entry in ipairs(snapshot or {}) do
            WriteConfigValue(entry.root, modConfig, ClonePersistedValue(entry.value), configEntries)
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
            error("uiState view is read-only; use state.set/update/toggle", 2)
        end,
        __pairs = function()
            return next, staging, nil
        end,
    })

    local function readStagingValue(alias)
        return staging[alias], aliasNodes[alias]
    end

    local function writeStagingValue(alias, value)
        local node = aliasNodes[alias]
        if not node then
            if shared.logging and shared.logging.warnIf then
                shared.logging.warnIf("uiState.set: unknown alias '%s'; value will not be persisted", tostring(alias))
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
            local normalized = NormalizeNodeValue(node, value)
            local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
            local nextPacked = public.accessors.writePackedBits(packedValue, node.offset, node.width, encoded)
            writeRootToStaging(parent, nextPacked)
            staging[node.alias] = normalized
            return
        end

        writeRootToStaging(node, value)
    end

    local function resetAliasValue(alias)
        local node = aliasNodes[alias]
        if not node then
            if shared.logging and shared.logging.warnIf then
                shared.logging.warnIf("uiState.reset: unknown alias '%s'; value will not be reset", tostring(alias))
            end
            return
        end

        local defaultValue = ClonePersistedValue(node.default)
        writeStagingValue(alias, defaultValue)
    end

    copyConfigToStaging()
    resetTransientToDefaults()
    clearDirty()

    local function snapshot()
        copyConfigToStaging()
        resetTransientToDefaults()
        clearDirty()
    end

    local function sync()
        copyStagingToConfig()
        clearDirty()
    end

    return {
        view = readonlyProxy,
        get = function(alias)
            return readStagingValue(alias)
        end,
        set = function(alias, value)
            writeStagingValue(alias, value)
        end,
        reset = function(alias)
            resetAliasValue(alias)
        end,
        update = function(alias, updater)
            local current = readStagingValue(alias)
            writeStagingValue(alias, updater(current))
        end,
        toggle = function(alias)
            local current = readStagingValue(alias)
            writeStagingValue(alias, not (current == true))
        end,
        reloadFromConfig = snapshot,
        flushToConfig = sync,
        _captureDirtyConfigSnapshot = captureDirtyConfigSnapshot,
        _restoreConfigSnapshot = restoreConfigSnapshot,
        isDirty = function()
            return dirty
        end,
        getAliasNode = function(alias)
            return aliasNodes[alias]
        end,
        collectConfigMismatches = function()
            local mismatches = {}
            for _, root in ipairs(persistedRootNodes) do
                local persistedValue = ReadConfigValue(root, modConfig, configEntries)
                if persistedValue == nil then
                    persistedValue = ClonePersistedValue(root.default)
                end
                persistedValue = NormalizeNodeValue(root, persistedValue)
                if not public.storage.valuesEqual(root, persistedValue, staging[root.alias]) then
                    table.insert(mismatches, root.alias)
                end
                if root.type == "packedInt" then
                    for _, child in ipairs(root._bitAliases or {}) do
                        local childValue = public.accessors.readPackedBits(persistedValue, child.offset, child.width)
                        if child.type == "bool" then
                            childValue = childValue ~= 0
                        end
                        childValue = NormalizeNodeValue(child, childValue)
                        if not public.storage.valuesEqual(child, childValue, staging[child.alias]) then
                            table.insert(mismatches, child.alias)
                        end
                    end
                end
            end
            return mismatches
        end,
    }
end
