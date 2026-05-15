local internal = AdamantModpackLib_Internal
local chalk = rom.mods['SGG_Modding-Chalk']

internal.moduleState = internal.moduleState or {}
internal.moduleState.backend = internal.moduleState.backend or {}
internal.moduleState.backend.cache = internal.moduleState.backend.cache or setmetatable({}, { __mode = "k" })
internal.moduleState.managedStores = internal.moduleState.managedStores or setmetatable({}, { __mode = "k" })
internal.store = internal.store or {}

local backendModule = import('core/module_state/private_backend.lua', nil, {
    chalk = chalk,
    state = internal.moduleState.backend,
})

local managedStore = import('core/module_state/private_store.lua', nil, {
    internal = internal,
    storage = internal.storage,
    values = internal.values,
    state = {
        managedStores = internal.moduleState.managedStores,
    },
})

local sessionModule = import('core/module_state/private_session.lua', nil, {
    internal = internal,
    storage = internal.storage,
    values = internal.values,
})

---@class ConfigBackendEntry
---@field get fun(self: ConfigBackendEntry): any
---@field set fun(self: ConfigBackendEntry, value: any)

---@class ConfigBackend
---@field rawConfig table
---@field getEntry fun(alias: string): ConfigBackendEntry|nil
---@field ensureValue fun(alias: string, value: any): boolean
---@field readValue fun(alias: string): any
---@field writeValue fun(alias: string, value: any): boolean

---@class ModuleState
---@field store ManagedStore
---@field session Session

---@class ManagedStore
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field writeUnstaged fun(alias: string, value: any)

---@class Session
---@field view table<string, any>
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableSession|nil
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil
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
---@field storage StorageSchema|nil
---@field hashGroupPlan table|nil

--- Creates module state access surfaces around a prepared definition and config table.
---@param modConfig table Module config table used for persisted reads and writes.
---@param definition ModuleDefinition Prepared module definition declaring storage and mutation behavior.
---@return ModuleState state Managed state surfaces for runtime and staged UI access.
function internal.moduleState.create(modConfig, definition)
    if type(modConfig) ~= "table" then
        internal.violate("store.invalid_config", "createModuleState expects config to be a table")
    end
    if type(definition) ~= "table" or definition._preparedDefinition ~= true then
        internal.violate(
            "store.invalid_create_args",
            "createModuleState expects a prepared definition"
        )
    end

    local storage = definition.storage
    local backend = backendModule.getConfigBackend(modConfig)
    local store = managedStore.create(modConfig, backend, storage)
    local session = sessionModule.createSession(modConfig, backend, storage)

    return {
        store = store,
        session = session,
    }
end

-- Internal API: writes storage through a Lib-created managed store.
function internal.store.writePersisted(store, alias, value)
    return managedStore.writePersisted(store, alias, value)
end

-- Internal API: narrows a full staged session to the author-facing UI surface.
function internal.moduleState.createAuthorSession(session, opts)
    return sessionModule.createAuthorSession(session, opts)
end

--- Resets persistent storage roots to defaults in a staged session.
---@param storage StorageSchema Validated storage schema.
---@param session Session Staged session returned by `internal.moduleState.create`.
---@param opts table|nil Optional `{ exclude = { Alias = true } }` map.
---@return boolean changed True when at least one alias was reset.
---@return number count Number of aliases reset.
function public.resetStorageToDefaults(storage, session, opts)
    if type(storage) ~= "table" or type(session) ~= "table" then
        return false, 0
    end

    local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
    local count = 0

    for _, node in ipairs(internal.storage.getStageRoots(storage) or {}) do
        local alias = node.alias
        if node._persist and alias ~= nil and not exclude[alias] then
            local current = session.read(alias)
            if not internal.storage.valuesEqual(node, current, node.default) then
                session.reset(alias)
                count = count + 1
            end
        end
    end

    return count > 0, count
end
