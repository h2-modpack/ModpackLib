local internal = AdamantModpackLib_Internal
internal.fallbackHud = internal.fallbackHud or {}

local FALLBACK_OWNER = "adamant-lib.fallback-hud"
local MARKER_TEXT = "Modded"

local function isRuntimeUncoordinated(pluginGuid)
    local moduleHost = public.getLiveModuleHost(pluginGuid)
    if type(moduleHost) ~= "table" or type(moduleHost.getIdentity) ~= "function" then
        return false
    end

    local identity = moduleHost.getIdentity() or {}
    return not (identity.modpack and internal.coordinators[identity.modpack])
end

local function shouldShowFallbackMarker()
    for pluginGuid in pairs(internal.standaloneRuntimes or {}) do
        if isRuntimeUncoordinated(pluginGuid) then
            return true
        end
    end
    return false
end

function internal.fallbackHud.refreshMarker()
    internal.overlays.dispatchCommit(FALLBACK_OWNER, {})
end

function internal.fallbackHud.createMarker()
    if internal.fallbackHud._initialized then
        return
    end
    internal.fallbackHud._initialized = true
    public.overlays.defineOwned(FALLBACK_OWNER, function(overlays)
        overlays.createLine("marker", {
            componentName = "ModpackMark_StandaloneLib",
            region = "middleRightStack",
            order = 0,
            visible = shouldShowFallbackMarker,
            minWidth = 80,
        })
        overlays.onCommit(function(ctx)
            ctx.setLine("marker", MARKER_TEXT)
            ctx.refresh("marker")
        end)
    end)
end

return internal.fallbackHud
