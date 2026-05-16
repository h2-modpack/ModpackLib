local internal = AdamantModpackLib_Internal

internal.moduleRuntime = internal.moduleRuntime or {}

local moduleRuntime = internal.moduleRuntime
moduleRuntime.slots = moduleRuntime.slots or {}

local function ensureSlotShape(slot, pluginGuid)
    slot.pluginGuid = pluginGuid
    slot.hookOwner = slot.hookOwner or {}
    slot.overlayOwner = slot.overlayOwner or ("module:" .. pluginGuid)
    slot.definitionState = slot.definitionState or {}
    slot.integrationRefreshOwnerId = slot.integrationRefreshOwnerId or pluginGuid
    slot.mutationKey = slot.mutationKey or pluginGuid
    return slot
end

function moduleRuntime.get(pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("host.invalid_create_opts", "moduleRuntime.get: pluginGuid is required")
    end

    local slot = moduleRuntime.slots[pluginGuid]
    if not slot then
        slot = {}
        moduleRuntime.slots[pluginGuid] = slot
    end

    return ensureSlotShape(slot, pluginGuid)
end
