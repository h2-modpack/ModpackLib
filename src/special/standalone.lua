local internal = AdamantModpackLib_Internal
local shared = internal.shared
local _coordinators = shared.coordinators
public.special = public.special or {}
local special = public.special

--- Creates standalone window and menu-bar renderers for a special module.
---@param def table Special module definition declaring UI and mutation behavior.
---@param store table Managed module store associated with the definition.
---@param uiState table|nil Optional UI state override; defaults to `store.uiState`.
---@param opts table|nil Optional standalone rendering hooks and window settings.
---@return table runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function special.standaloneUI(def, store, uiState, opts)
    opts = opts or {}
    uiState = uiState or (store and store.uiState) or nil

    local function getDrawQuickContent()
        if type(opts.getDrawQuickContent) == "function" then
            return opts.getDrawQuickContent()
        end
        return opts.drawQuickContent
    end

    local function getBeforeDrawQuickContent()
        if type(opts.getBeforeDrawQuickContent) == "function" then
            return opts.getBeforeDrawQuickContent()
        end
        return opts.beforeDrawQuickContent
    end

    local function getAfterDrawQuickContent()
        if type(opts.getAfterDrawQuickContent) == "function" then
            return opts.getAfterDrawQuickContent()
        end
        return opts.afterDrawQuickContent
    end

    local function getDrawTab()
        if type(opts.getDrawTab) == "function" then
            return opts.getDrawTab()
        end
        return opts.drawTab
    end

    local function getBeforeDrawTab()
        if type(opts.getBeforeDrawTab) == "function" then
            return opts.getBeforeDrawTab()
        end
        return opts.beforeDrawTab
    end

    local function getAfterDrawTab()
        if type(opts.getAfterDrawTab) == "function" then
            return opts.getAfterDrawTab()
        end
        return opts.afterDrawTab
    end

    local function onStateFlushed()
        if public.mutation.mutatesRunData(def) and store.read("Enabled") == true then
            rom.game.SetupRunData()
        end
    end

    local showWindow = false

    local function renderWindow()
        if def.modpack and _coordinators[def.modpack] then return end
        if not showWindow then return end

        local imgui = rom.ImGui
        local title = (opts.windowTitle or def.name) .. "###" .. tostring(def.id)
        if imgui.Begin(title) then
            local enabled = store.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = public.mutation.setEnabled(def, store, enabledValue)
                if ok then
                    if public.mutation.mutatesRunData(def) then
                        rom.game.SetupRunData()
                    end
                else
                    if shared.logging and shared.logging.warn then
                        shared.logging.warn("%s %s failed: %s",
                            tostring(def.name or def.id or "module"),
                            enabledValue and "enable" or "disable",
                            tostring(err))
                    end
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", store.read("DebugMode") == true)
            if debugChanged then
                store.write("DebugMode", debugValue)
            end

            if uiState and imgui.Button("Audit + Resync UI State") then
                special.auditAndResyncState(def.name or def.id or "module", uiState)
            end

            local drawQuickContent = getDrawQuickContent()
            local beforeDrawQuickContent = getBeforeDrawQuickContent()
            local afterDrawQuickContent = getAfterDrawQuickContent()
            local drawTab = getDrawTab()
            local beforeDrawTab = getBeforeDrawTab()
            local afterDrawTab = getAfterDrawTab()
            if not drawTab and type(def.ui) == "table" and #def.ui > 0 then
                drawTab = function(ui)
                    public.ui.drawTree(ui, def.ui, uiState, ui.GetWindowWidth() * 0.4, def.customTypes)
                end
            end

            if drawQuickContent or drawTab then
                imgui.Separator()
                imgui.Spacing()
            end

            if drawQuickContent then
                special.runPass({
                    name = def.name,
                    imgui = imgui,
                    uiState = uiState,
                    theme = opts.theme,
                    commit = function(state)
                        return special.commitState(def, store, state)
                    end,
                    beforeDraw = beforeDrawQuickContent,
                    draw = drawQuickContent,
                    afterDraw = afterDrawQuickContent,
                    onFlushed = onStateFlushed,
                })
            end

            if drawQuickContent and drawTab then
                imgui.Spacing()
                imgui.Separator()
            end

            if drawTab then
                special.runPass({
                    name = def.name,
                    imgui = imgui,
                    uiState = uiState,
                    theme = opts.theme,
                    commit = function(state)
                        return special.commitState(def, store, state)
                    end,
                    beforeDraw = beforeDrawTab,
                    draw = drawTab,
                    afterDraw = afterDrawTab,
                    onFlushed = onStateFlushed,
                })
            end

            imgui.End()
        else
            showWindow = false
        end
    end

    local function addMenuBar()
        if def.modpack and _coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            if rom.ImGui.MenuItem(def.name) then
                showWindow = not showWindow
            end
            rom.ImGui.EndMenu()
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
    }
end
