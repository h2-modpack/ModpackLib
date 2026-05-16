-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-ModpackLib']

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

modutil = mods['SGG_Modding-ModUtil']
local chalk = mods['SGG_Modding-Chalk']
local libConfig = chalk.auto('config.lua')
public.config = libConfig

local _liveModuleHosts = {}
AdamantModpackLib_Internal = AdamantModpackLib_Internal or {}
local internal = AdamantModpackLib_Internal
internal.libConfig = libConfig
internal.coordinators = internal.coordinators or {}
internal.coordinatorRebuilds = internal.coordinatorRebuilds or {}
internal.liveModuleHosts = internal.liveModuleHosts or _liveModuleHosts
internal.pendingCoordinatorRebuilds = internal.pendingCoordinatorRebuilds
    or setmetatable({}, { __mode = "k" })

---@class AdamantModpackLib
---@field config table
---@field resetStorageToDefaults fun(storage: StorageSchema, session: Session, opts: table|nil)
---@field createModule fun(opts: ModuleCreateOpts): AuthorHost, ManagedStore
---@field tryCreateModule fun(opts: ModuleCreateOpts): AuthorHost|nil, ManagedStore|nil, string|nil
---@field standaloneHost fun(pluginGuid: string): StandaloneRuntime
---@field standaloneUiBridge fun(pluginGuid: string): StandaloneRuntime
---@field getLiveModuleHost fun(pluginGuid: string|nil): ModuleHost|nil
---@field coordinator table
---@field mutation table
---@field gameObject table
---@field hashing table
---@field imguiHelpers table
---@field overlays table
---@field widgets table
---@field nav table

import 'core/init.lua'

-- Standalone framework debug toggle - hidden when Core/Framework registers coordinators.
rom.gui.add_to_menu_bar(function()
    if next(internal.coordinators) ~= nil then return end
    if rom.ImGui.BeginMenu("adamant-lib") then
        local val, chg = rom.ImGui.Checkbox("Lib Debug", libConfig.DebugMode == true)
        if chg then libConfig.DebugMode = val end
        if rom.ImGui.IsItemHovered() then
            rom.ImGui.SetTooltip("Print lib-internal diagnostic warnings. Structural schema errors always fail.")
        end
        rom.ImGui.EndMenu()
    end
end)

if type(rom.gui.add_always_draw_imgui) == "function" and type(rom.gui.is_open) == "function" then
    local wasGuiOpen = rom.gui.is_open() == true
    rom.gui.add_always_draw_imgui(function()
        local isGuiOpen = rom.gui.is_open() == true
        if wasGuiOpen and not isGuiOpen then
            for _, runtime in pairs(internal.standaloneRuntimes or {}) do
                if runtime.handleHostGuiClosed then
                    runtime.handleHostGuiClosed()
                end
            end
        end
        wasGuiOpen = isGuiOpen
    end)
end
