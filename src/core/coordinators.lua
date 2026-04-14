local internal = AdamantModpackLib_Internal
local shared = internal.shared
local libConfig = shared.libConfig
local _coordinators = shared.coordinators
public.coordinator = public.coordinator or {}
local coordinator = public.coordinator
public.logging = public.logging or {}
shared.logging = shared.logging or {}
local logging = public.logging
local sharedLogging = shared.logging

local function FormatWarning(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

local function libWarnIf(fmt, ...)
    if not libConfig.DebugMode then return end
    print(FormatWarning("[lib] ", fmt, ...))
end
sharedLogging.warnIf = libWarnIf

local function libWarn(fmt, ...)
    print(FormatWarning("[lib] ", fmt, ...))
end
sharedLogging.warn = libWarn

--- Registers coordinator metadata for a coordinated module pack.
---@param packId string Unique coordinator pack identifier.
---@param config table Coordinator configuration table.
function coordinator.register(packId, config)
    _coordinators[packId] = config
end

--- Returns whether a pack id has coordinator metadata registered.
---@param packId string Unique coordinator pack identifier.
---@return boolean coordinated True when the pack id is registered with the coordinator.
function coordinator.isCoordinated(packId)
    return _coordinators[packId] ~= nil
end

--- Returns whether a coordinated or standalone module should currently be treated as enabled.
---@param store table|nil Managed module store to read the Enabled flag from.
---@param packId string|nil Unique coordinator pack identifier.
---@return boolean enabled True when the module should be considered enabled.
function coordinator.isEnabled(store, packId)
    local coord = packId and _coordinators[packId]
    if coord and not coord.ModEnabled then return false end
    return store and type(store.read) == "function" and store.read("Enabled") == true or false
end

--- Emits a module-scoped warning when the supplied condition is enabled.
---@param packId string Module or pack identifier used as the log prefix.
---@param enabled boolean Whether the warning should be emitted.
---@param fmt string Message format string.
function logging.warnIf(packId, enabled, fmt, ...)
    if not enabled then return end
    print(FormatWarning("[" .. packId .. "] ", fmt, ...))
end

--- Emits a module-scoped warning unconditionally.
---@param packId string Module or pack identifier used as the log prefix.
---@param fmt string Message format string.
function logging.warn(packId, fmt, ...)
    print(FormatWarning("[" .. packId .. "] ", fmt, ...))
end

--- Emits a module-scoped log line when the supplied condition is enabled.
---@param name string Module or subsystem identifier used as the log prefix.
---@param enabled boolean Whether the log line should be emitted.
---@param fmt string Message format string.
function logging.logIf(name, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. name .. "] " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end
