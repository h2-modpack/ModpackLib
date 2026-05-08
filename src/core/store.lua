local internal = AdamantModpackLib_Internal
local chalk = rom.mods['SGG_Modding-Chalk']
local storageInternal = internal.storage
local storeInternal = internal.store
local ClonePersistedValue = storeInternal.ClonePersistedValue
local NormalizeStorageValue = storageInternal.NormalizeStorageValue

---@class ConfigBackendEntry
---@field get fun(self: ConfigBackendEntry): any
---@field set fun(self: ConfigBackendEntry, value: any)

---@class ConfigBackend
---@field rawConfig table
---@field getEntry fun(alias: string): ConfigBackendEntry|nil
---@field ensureValue fun(alias: string, value: any): boolean
---@field readValue fun(alias: string): any
---@field writeValue fun(alias: string, value: any): boolean

---@class Session
---@field view table<string, any>
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableSession|nil
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field _flushToConfig fun()
---@field _reloadFromConfig fun()
---@field _captureDirtyConfigSnapshot fun(): table[]
---@field _restoreConfigSnapshot fun(snapshot: table[]|nil)
---@field isDirty fun(): boolean
---@field auditMismatches fun(): string[]

---@class ModuleDefinition
---@field modpack string|nil
---@field id string|nil
---@field name string|nil
---@field shortName string|nil
---@field tooltip string|nil
---@field default boolean|nil
---@field affectsRunData boolean|nil
---@field storage StorageSchema|nil
---@field hashGroupPlan table|nil
---@field patchPlan fun(store: ManagedStore): table|nil
---@field apply fun(store: ManagedStore)|nil
---@field revert fun(store: ManagedStore)|nil
---@field onSettingsCommitted fun(store: ManagedStore)|nil

---@class ManagedStore
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field writeUnstaged fun(alias: string, value: any)

local ConfigBackendCache = setmetatable({}, { __mode = "k" })
---@param config table
---@return ConfigBackend|nil
local function GetConfigBackend(config)
    if not chalk then
        return nil
    end

    local ok, rawConfig = pcall(chalk.original, config)
    if not ok or type(rawConfig) ~= "table" or type(rawConfig.entries) ~= "table" then
        return nil
    end

    local backend = ConfigBackendCache[rawConfig]
    if backend then
        return backend
    end

    local entryIndex = {}
    for descriptor, entry in pairs(rawConfig.entries) do
        local section = descriptor.section
        local key = descriptor.key
        if section ~= nil and key ~= nil then
            local sectionEntries = entryIndex[section]
            if not sectionEntries then
                sectionEntries = {}
                entryIndex[section] = sectionEntries
            end
            sectionEntries[key] = entry
        end
    end

    local pathEntryCache = {}
    backend = {}

    function backend.getEntry(alias)
        local cached = pathEntryCache[alias]
        if cached ~= nil then
            return cached or nil
        end

        local entry = entryIndex.config and entryIndex.config[alias] or nil
        if entry then
            pathEntryCache[alias] = entry
            return entry
        end

        pathEntryCache[alias] = false
        return nil
    end

    function backend.ensureValue(alias, value)
        local entry = backend.getEntry(alias)
        if entry then
            return true
        end

        if type(alias) ~= "string" or alias == "" or type(rawConfig.bind) ~= "function" then
            return false
        end

        entry = rawConfig:bind("config", alias, value, "")
        if not entry then
            return false
        end

        local sectionEntries = entryIndex.config
        if not sectionEntries then
            sectionEntries = {}
            entryIndex.config = sectionEntries
        end
        sectionEntries[alias] = entry
        pathEntryCache[alias] = entry

        if type(rawConfig.save) == "function" then
            rawConfig:save()
        end
        return true
    end

    function backend.readValue(alias)
        local entry = backend.getEntry(alias)
        if entry then
            return entry:get()
        end
        return nil
    end

    function backend.writeValue(alias, value)
        local entry = backend.getEntry(alias)
        if entry then
            entry:set(value)
            return true
        end
        return false
    end

    backend.rawConfig = rawConfig
    ConfigBackendCache[rawConfig] = backend
    return backend
end

--- Creates a managed store wrapper around a prepared module definition and its persisted config table.
---@param modConfig table Module config table used for persisted reads and writes.
---@param definition ModuleDefinition Prepared module definition declaring storage and mutation behavior.
---@return ManagedStore store Managed store instance for config and mutation lifecycle.
---@return Session session Staged UI/session state for storage-backed controls.
function public.createStore(modConfig, definition)
    if type(modConfig) ~= "table" then
        internal.violate("store.invalid_config", "createStore expects config to be a table")
    end
    if type(definition) ~= "table" or definition._preparedDefinition ~= true then
        internal.violate(
            "store.invalid_create_args",
            "createStore expects a prepared definition; call lib.prepareDefinition(...) first"
        )
    end
    local backend = GetConfigBackend(modConfig)
    local store = {}
    local storage = definition.storage
    local runtimeValues = {}

    local aliasNodes = storageInternal.getAliases(storage)
    local unstagedAliases = {}
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
        if not root._persist then
            local raw = runtimeValues[root]
            if raw == nil then
                raw = ClonePersistedValue(root.default)
            end
            return NormalizeStorageValue(root, raw)
        end

        local raw = readRaw(root._storageKey)
        if raw == nil then
            raw = ClonePersistedValue(root.default)
        end
        return NormalizeStorageValue(root, raw)
    end

    local function writeRootNode(root, value)
        if root._persist then
            writeRaw(root._storageKey, NormalizeStorageValue(root, value))
        else
            runtimeValues[root] = NormalizeStorageValue(root, value)
        end
    end

    local function ensureRootNode(root)
        if not root._persist then
            return
        end
        if readRaw(root._storageKey) ~= nil then
            return
        end

        local value = NormalizeStorageValue(root, ClonePersistedValue(root.default))
        if backend and backend.ensureValue(root._storageKey, value) then
            return
        end
        modConfig[root._storageKey] = value
    end

    for _, root in ipairs(storageInternal.getPersistRoots(storage)) do
        ensureRootNode(root)
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
            internal.violate("store.unknown_write_alias", "internal.store.writePersisted: unknown storage alias '%s'", tostring(alias))
        end,
    }

    --- Reads a storage value by declared alias.
    ---@param alias string Alias to read.
    ---@return any value Resolved value, normalized through the owning storage type when applicable.
    function store.read(alias)
        return storageInternal.readAlias(aliasNodes, storeReadBackend, alias)
    end

    --- Returns a read-only table-storage handle by declared table root alias.
    ---@param alias string
    ---@return StorageTableReadOnly|nil tableHandle
    function store.table(alias)
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
            internal.violate("store.invalid_table_surface", "store.table: alias '%s' is staged-only; use session.table()", tostring(alias))
            return nil
        end
        return storageInternal.CreateTableHandle(node, {
            readRoot = readRootNode,
            normalizedRoot = true,
        })
    end

    local function writeStoreValue(alias, value)
        storageInternal.writeAlias(aliasNodes, storeWriteBackend, alias, value)
    end

    --- Writes a declared stage=false alias through the managed store.
    --- Unstaged aliases are excluded from session, hash, and profile surfaces.
    ---@param alias string
    ---@param value any
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

    local function getPackedAliases(alias)
        local node = aliasNodes[alias]
        if not node or node.type ~= "packedInt" then
            return {}
        end

        local packedAliases = {}
        for _, child in ipairs(node._bitAliases or {}) do
            packedAliases[#packedAliases + 1] = {
                alias = child.alias,
                label = child.label or child.alias,
            }
        end
        return packedAliases
    end

    internal.store.bindManagedStore(store, {
        write = writeStoreValue,
        getPackedAliases = getPackedAliases,
    })

    local session = internal.store.createSession(modConfig, backend, storage)

    return store, session
end

--- Resets persistent storage roots to defaults in a staged session.
---@param storage StorageSchema Validated storage schema.
---@param session Session Staged session returned by `lib.createStore`.
---@param opts table|nil Optional `{ exclude = { Alias = true } }` map.
---@return boolean changed True when at least one alias was reset.
---@return number count Number of aliases reset.
function public.resetStorageToDefaults(storage, session, opts)
    if type(storage) ~= "table" or type(session) ~= "table" then
        return false, 0
    end

    local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
    local count = 0

    for _, node in ipairs(storageInternal.getStageRoots(storage) or {}) do
        local alias = node.alias
        if node._persist and alias ~= nil and not exclude[alias] then
            local current = session.read(alias)
            if not storageInternal.valuesEqual(node, current, node.default) then
                session.reset(alias)
                count = count + 1
            end
        end
    end

    return count > 0, count
end
