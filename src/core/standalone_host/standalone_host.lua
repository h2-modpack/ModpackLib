local internal = AdamantModpackLib_Internal

---@class StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()
---@field handleHostGuiClosed fun()

local DEFAULT_WINDOW_WIDTH = 960
local DEFAULT_WINDOW_HEIGHT = 720
local fallbackHud = import 'core/standalone_host/private_fallback_hud.lua'

local function validatePluginGuid(apiName, pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("host.invalid_standalone_binding", "%s: pluginGuid is required", apiName)
    end
end

local function getStandaloneRuntime(pluginGuid)
    local runtimes = internal.standaloneRuntimes
    if type(runtimes) ~= "table" then
        return nil
    end
    local runtime = runtimes[pluginGuid]
    if type(runtime) ~= "table" then
        return nil
    end
    return runtime
end

--- Creates stable callbacks that late-read the current standalone runtime.
---@param pluginGuid string Plugin guid used when creating the module host.
---@return StandaloneRuntime bridge Standalone bridge with `renderWindow` and `addMenuBar` callbacks.
function public.standaloneUiBridge(pluginGuid)
    validatePluginGuid("standaloneUiBridge", pluginGuid)

    local function callRuntime(method)
        local runtime = getStandaloneRuntime(pluginGuid)
        local callback = runtime and runtime[method] or nil
        if type(callback) == "function" then
            return callback()
        end
    end

    return {
        renderWindow = function()
            return callRuntime("renderWindow")
        end,
        addMenuBar = function()
            return callRuntime("addMenuBar")
        end,
        handleHostGuiClosed = function()
            return callRuntime("handleHostGuiClosed")
        end,
    }
end

--- Initializes standalone module hosting and returns window/menu-bar renderers.
---@param pluginGuid string Plugin guid used when creating the module host.
---@return StandaloneRuntime runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function public.standaloneHost(pluginGuid)
    validatePluginGuid("standaloneHost", pluginGuid)
    local moduleHost = public.getLiveModuleHost(pluginGuid)
    if type(moduleHost) ~= "table" then
        internal.violate(
            "host.invalid_standalone_binding",
            "standaloneHost: no live module host is registered for current module '%s'",
            tostring(pluginGuid)
        )
    end

    local function getIdentity()
        return moduleHost.getIdentity() or {}
    end

    local function getMeta()
        return moduleHost.getMeta() or {}
    end

    if not (getIdentity().modpack and internal.coordinators[getIdentity().modpack]) then
        local ok, err = moduleHost.applyOnLoad()
        if not ok then
            internal.violate("host.standalone_startup_lifecycle_failed", "%s startup lifecycle failed: %s",
                tostring(getMeta().name or getIdentity().id or "module"),
                tostring(err))
        end
    end

    local showWindow = false
    local didSeedWindowSize = false
    local runDataDirty = false
    local uiSuppressionToken = nil

    local function markRunDataDirty()
        if moduleHost.affectsRunData() then
            runDataDirty = true
        end
    end

    local function flushPendingRunData()
        if not runDataDirty then
            return
        end
        rom.game.SetupRunData()
        runDataDirty = false
    end

    local function suppressOverlays()
        if not uiSuppressionToken then
            uiSuppressionToken = public.overlays.suppressForUi()
        end
    end

    local function releaseOverlaySuppression()
        if uiSuppressionToken then
            uiSuppressionToken.release()
            uiSuppressionToken = nil
        end
    end

    local function handleHostGuiClosed()
        flushPendingRunData()
        releaseOverlaySuppression()
    end

    local function setWindowOpen(open)
        open = open == true
        if showWindow == open then
            return
        end

        if open then
            showWindow = true
            suppressOverlays()
            return
        end

        flushPendingRunData()
        showWindow = false
        releaseOverlaySuppression()
    end

    local function seedWindowSize(imgui)
        if didSeedWindowSize then
            return
        end
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        didSeedWindowSize = true
    end

    local function renderWindow()
        local identity = getIdentity()
        local meta = getMeta()
        if identity.modpack and internal.coordinators[identity.modpack] then
            return
        end
        if not showWindow then
            return
        end

        suppressOverlays()

        local imgui = rom.ImGui
        local title = tostring(meta.name or identity.id or "Module") .. "###" .. tostring(identity.id)
        seedWindowSize(imgui)
        local open, shouldDraw = imgui.Begin(title, showWindow)
        if shouldDraw then
            local enabled = moduleHost.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = moduleHost.setEnabled(enabledValue)
                if ok then
                    markRunDataDirty()
                else
                    internal.violate("host.enable_transition_failed", "%s %s failed: %s",
                        tostring(meta.name or identity.id or "module"),
                        enabledValue and "enable" or "disable",
                        tostring(err))
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", moduleHost.read("DebugMode") == true)
            if debugChanged then
                moduleHost.setDebugMode(debugValue)
            end

            if imgui.Button("Resync Session") then
                moduleHost.resync()
            end

            imgui.Separator()
            imgui.Spacing()
            moduleHost.drawTab(imgui)
            local ok, err, committed = moduleHost.commitIfDirty()
            if ok and committed and moduleHost.read("Enabled") == true then
                markRunDataDirty()
            elseif ok == false then
                internal.violate(
                    "host.session_commit_failed",
                    "%s session commit failed; restored previous config where possible: %s",
                    tostring(meta.name or identity.id or "module"),
                    tostring(err)
                )
            end
        end
        imgui.End()
        if open == false then
            setWindowOpen(false)
        end
    end

    local function addMenuBar()
        local identity = getIdentity()
        local meta = getMeta()
        if identity.modpack and internal.coordinators[identity.modpack] then return end
        if rom.ImGui.BeginMenu(meta.name) then
            if rom.ImGui.MenuItem(meta.name) then
                setWindowOpen(not showWindow)
            end
            rom.ImGui.EndMenu()
        end
    end

    local runtime = {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        handleHostGuiClosed = handleHostGuiClosed,
    }
    internal.standaloneRuntimes = internal.standaloneRuntimes or {}
    internal.standaloneRuntimes[pluginGuid] = runtime
    fallbackHud.refreshMarker()
    return runtime
end

modutil.once_loaded.game(function()
    fallbackHud.createMarker()
end)
