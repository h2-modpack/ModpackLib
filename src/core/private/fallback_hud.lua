local internal = AdamantModpackLib_Internal
internal.fallbackHud = internal.fallbackHud or {}
local fallbackHud = internal.fallbackHud

local MARKER_TEXT = "Modded"

local function isFrameworkInstalled()
    return rom
        and rom.mods
        and rom.mods["adamant-ModpackFramework"] ~= nil
end

local function shouldShowFallbackMarker()
    if isFrameworkInstalled() then
        return false
    end
    return true
end

function fallbackHud.createMarker()
    if fallbackHud._initialized then
        return
    end
    fallbackHud._initialized = true
    public.overlays.defineOwned("adamant-lib.fallback-hud", function(overlays)
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

return fallbackHud
