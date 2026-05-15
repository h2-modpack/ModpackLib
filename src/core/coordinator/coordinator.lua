local internal = AdamantModpackLib_Internal
public.coordinator = public.coordinator or {}

---@class CoordinatorConfig
---@field ModEnabled boolean

--- Returns whether a pack id has coordinator metadata registered.
---@param packId string Unique coordinator pack identifier.
---@return boolean coordinated True when the pack id is registered with the coordinator.
function public.coordinator.isRegistered(packId)
    return internal.coordinators[packId] ~= nil
end

--- Registers coordinator metadata for a coordinated module pack.
--- Framework-facing API; feature modules should query through top-level module helpers.
---@param packId string Unique coordinator pack identifier.
---@param config CoordinatorConfig Coordinator configuration table.
function public.coordinator.register(packId, config)
    if type(packId) ~= "string" or packId == "" then
        internal.violate(
            "coordinator.invalid_registration",
            "coordinator.register: packId must be a non-empty string"
        )
    end
    if config ~= nil and type(config) ~= "table" then
        internal.violate(
            "coordinator.invalid_registration",
            "coordinator.register: config must be a table when provided"
        )
    end
    if config ~= nil and type(config.ModEnabled) ~= "boolean" then
        internal.violate(
            "coordinator.invalid_registration",
            "coordinator.register: config.ModEnabled must be a boolean"
        )
    end
    internal.coordinators[packId] = config
end

--- Registers a pack-level rebuild callback used when coordinated module structure changes.
---@param packId string Unique coordinator pack identifier.
---@param callback fun(reason: table)|nil Callback invoked when Lib requests a framework rebuild.
function public.coordinator.registerRebuild(packId, callback)
    if callback == nil then
        internal.coordinatorRebuilds[packId] = nil
        return
    end

    if type(callback) ~= "function" then
        internal.violate(
            "coordinator.invalid_rebuild_callback",
            "coordinator.registerRebuild: callback must be a function when provided"
        )
    end
    internal.coordinatorRebuilds[packId] = callback
end

--- Requests a coordinated pack-level rebuild after a structural module change.
---@param packId string Unique coordinator pack identifier.
---@param reason table Reason metadata describing the rebuild request.
---@return boolean requested True when a rebuild callback was registered and accepted the request.
function public.coordinator.requestRebuild(packId, reason)
    local callback = packId and internal.coordinatorRebuilds[packId] or nil
    if callback == nil then
        return false
    end

    return callback(reason or {}) == true
end
