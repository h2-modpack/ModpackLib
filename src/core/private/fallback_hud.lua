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
    fallbackHud._handle = public.overlays.registerStackedText({
        id = "lib:fallbackHud",
        componentName = "ModpackMark_StandaloneLib",
        region = "middleRightStack",
        order = 0,
        text = function()
            return MARKER_TEXT
        end,
        visible = shouldShowFallbackMarker,
    })
end

return fallbackHud
