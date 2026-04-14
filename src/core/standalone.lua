local internal = AdamantModpackLib_Internal
local shared = internal.shared

local libWarn = shared.logging.warn
local coordinator = public.coordinator

--- Creates a standalone menu renderer for a regular coordinated-capable module.
---@param def table Module definition declaring UI, storage, and mutation behavior.
---@param store table Managed module store associated with the definition.
---@return function render Menu render callback that draws the standalone module UI.
function coordinator.standaloneUI(def, store)
    local function TrySetEnabled(enabled)
        local ok, err = public.mutation.setEnabled(def, store, enabled)
        if ok then
            if public.mutation.mutatesRunData(def) then rom.game.SetupRunData() end
        else
            libWarn("%s %s failed: %s",
                tostring(def.name or def.id or "module"),
                enabled and "enable" or "disable",
                tostring(err))
        end
        return ok, err
    end

    local function onUiStateFlushed()
        if public.mutation.mutatesRunData(def) and store.read("Enabled") == true then
            rom.game.SetupRunData()
        end
    end

    return function()
        if def.modpack and shared.coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            local imgui = rom.ImGui
            local enabled = store.read("Enabled") == true
            local val, chg = imgui.Checkbox(def.name, enabled)
            if chg then
                TrySetEnabled(val)
            end
            if imgui.IsItemHovered() and (def.tooltip or "") ~= "" then
                imgui.SetTooltip(def.tooltip)
            end

            local dbgVal, dbgChg = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if dbgChg then
                store.write("DebugMode", dbgVal)
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Print diagnostic warnings to the console for this module.")
            end

            if store.uiState and imgui.Button("Audit + Resync UI State") then
                public.special.auditAndResyncState(def.name or def.id or "module", store.uiState)
            end

            if enabled and store.uiState and type(def.ui) == "table" and #def.ui > 0 then
                imgui.Separator()
                public.special.runPass({
                    name = def.name,
                    imgui = imgui,
                    uiState = store.uiState,
                    commit = function(state)
                        return public.special.commitState(def, store, state)
                    end,
                    draw = function()
                        public.ui.drawTree(imgui, def.ui, store.uiState, imgui.GetWindowWidth() * 0.45, def.customTypes)
                    end,
                    onFlushed = onUiStateFlushed,
                })
            end

            imgui.EndMenu()
        end
    end
end
