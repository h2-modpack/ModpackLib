local internal = AdamantModpackLib_Internal

---@class StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()

---@class AuthorSession
---@field view table<string, any>
---@field read fun(alias: string): any
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field resetToDefaults fun(opts: table|nil): boolean, number

---@class ModuleHostOpts
---@field definition ModuleDefinition
---@field pluginGuid string
---@field store ManagedStore
---@field session Session
---@field hookOwner table|nil
---@field registerHooks fun()|nil
---@field drawTab fun(imgui: table, session: AuthorSession)
---@field drawQuickContent fun(imgui: table, session: AuthorSession)|nil

---@class ModuleHost
---@field getIdentity fun(): table
---@field getMeta fun(): table
---@field affectsRunData fun(): boolean
---@field getHashHints fun(): table|nil
---@field getStorage fun(): StorageSchema|nil
---@field read fun(alias: string): any
---@field writeAndFlush fun(alias: string, value: any): boolean
---@field stage fun(alias: string, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
---@field resetToDefaults fun(opts: table|nil): boolean, number
---@field commitIfDirty fun(): boolean, string|nil, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string|nil
---@field setDebugMode fun(enabled: boolean)
---@field applyOnLoad fun(): boolean, string|nil
---@field applyMutation fun(): boolean, string|nil
---@field revertMutation fun(): boolean, string|nil
---@field drawTab fun(imgui: table)
---@field drawQuickContent fun(imgui: table)|nil

function public.getLiveModuleHost(pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        return nil
    end
    return internal.liveModuleHosts[pluginGuid]
end

--- Creates a behavior-only host object for Framework and standalone hosting.
--- Registers the created host into Lib's live-host registry under `opts.pluginGuid`
--- so coordinated discovery can resolve it immediately.
--- The host closes over store/session without exposing those state handles publicly.
---@param opts ModuleHostOpts
---@return ModuleHost host Module host behavior contract.
function public.createModuleHost(opts)
    if type(opts) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModuleHost: opts must be a table")
    end
    local def = opts.definition
    local store = opts.store
    local session = opts.session
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        internal.violate("host.invalid_create_opts", "createModuleHost: prepared definition is required")
    end
    if not (store and type(store.read) == "function") then
        internal.violate("host.invalid_create_opts", "createModuleHost: store is required")
    end
    if not (session and type(session.isDirty) == "function" and type(session.write) == "function") then
        internal.violate("host.invalid_create_opts", "createModuleHost: session is required")
    end

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local registerHooks = opts.registerHooks
    local hookOwner = opts.hookOwner
    local pluginGuid = opts.pluginGuid

    if type(drawTab) ~= "function" then
        internal.violate("host.invalid_create_opts", "createModuleHost: drawTab is required")
    end
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("host.invalid_create_opts", "createModuleHost: pluginGuid is required")
    end

    if registerHooks ~= nil then
        if type(registerHooks) ~= "function" then
            internal.violate("host.invalid_create_opts", "createModuleHost: registerHooks must be a function")
        end
        if type(hookOwner) ~= "table" then
            internal.violate("host.invalid_create_opts", "createModuleHost: hookOwner is required when registerHooks is provided")
        end
        internal.hooks.refresh(hookOwner, registerHooks)
    end

    ---@type AuthorSession
    local authorSession = {
        view = session.view,
        read = session.read,
        write = session.write,
        reset = session.reset,
        resetToDefaults = function(resetOpts)
            return public.resetStorageToDefaults(def.storage, session, resetOpts)
        end,
    }

    ---@type ModuleHost
    local host = {}

    function host.getIdentity()
        return {
            id = def.id,
            modpack = def.modpack,
        }
    end

    function host.getMeta()
        return {
            name = def.name,
            shortName = def.shortName,
            tooltip = def.tooltip,
        }
    end

    function host.affectsRunData()
        return public.lifecycle.affectsRunData(def)
    end

    function host.getHashHints()
        return def.hashGroupPlan
    end

    function host.getStorage()
        return def.storage
    end

    function host.read(alias)
        return store.read(alias)
    end

    function host.writeAndFlush(alias, value)
        session.write(alias, value)
        session._flushToConfig()
        return public.lifecycle.notifySettingsCommitted(def, store)
    end

    function host.stage(alias, value)
        session.write(alias, value)
        return true
    end

    function host.flush()
        if not session.isDirty() then
            return true
        end
        session._flushToConfig()
        return public.lifecycle.notifySettingsCommitted(def, store)
    end

    function host.reloadFromConfig()
        session._reloadFromConfig()
    end

    function host.resync()
        return public.lifecycle.resyncSession(def, session)
    end

    function host.resetToDefaults(resetOpts)
        return public.resetStorageToDefaults(def.storage, session, resetOpts)
    end

    function host.commitIfDirty()
        if not session.isDirty() then
            return true, nil, false
        end
        local ok, err = public.lifecycle.commitSession(def, store, session)
        return ok, err, ok == true
    end

    function host.isEnabled()
        return public.isModuleEnabled(store, host.getIdentity().modpack)
    end

    function host.setEnabled(enabled)
        return public.lifecycle.setEnabled(def, store, enabled)
    end

    function host.setDebugMode(enabled)
        return public.lifecycle.setDebugMode(store, enabled)
    end

    function host.applyOnLoad()
        return public.lifecycle.applyOnLoad(def, store)
    end

    function host.applyMutation()
        return public.lifecycle.applyMutation(def, store)
    end

    function host.revertMutation()
        return public.lifecycle.revertMutation(def, store)
    end

    function host.drawTab(imgui)
        return drawTab(imgui, authorSession)
    end

    if type(drawQuickContent) == "function" then
        function host.drawQuickContent(imgui)
            return drawQuickContent(imgui, authorSession)
        end
    end

    local identity = host.getIdentity()
    local meta = host.getMeta()
    local packId = identity.modpack
    local pendingCoordinatorRebuild = internal.pendingCoordinatorRebuilds[def]
    local hasPendingCoordinatorRebuild = type(pendingCoordinatorRebuild) == "table"
    internal.liveModuleHosts[pluginGuid] = host
    if not hasPendingCoordinatorRebuild
        and type(packId) == "string"
        and packId ~= ""
        and public.isModuleCoordinated(packId) then
        local ok, err = host.applyOnLoad()
        if not ok then
            internal.violate("host.coordinated_runtime_sync_failed", "%s coordinated runtime sync failed: %s",
                tostring(meta.name or identity.id or "module"),
                tostring(err))
        end
    elseif hasPendingCoordinatorRebuild then
        local requested = public.lifecycle.requestCoordinatorRebuild(packId, pendingCoordinatorRebuild)
        if requested then
            internal.pendingCoordinatorRebuilds[def] = nil
        else
            internal.violate(
                "host.structural_rebuild_unavailable",
                "%s structural definition changed during hot reload; full reload required",
                tostring(meta.name or identity.id or "module"))
        end
    end

    return host
end

--- Initializes standalone module hosting and returns window/menu-bar renderers.
---@param pluginGuid string Plugin guid used when creating the module host.
---@return StandaloneRuntime runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function public.standaloneHost(pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("host.invalid_standalone_binding", "standaloneHost: pluginGuid is required")
    end
    local moduleHost = public.getLiveModuleHost(pluginGuid)
    if type(moduleHost) ~= "table" then
        internal.violate(
            "host.invalid_standalone_binding",
            "standaloneHost: no live module host is registered for current module '%s'",
            tostring(pluginGuid)
        )
    end

    if type(moduleHost.getIdentity) ~= "function" or type(moduleHost.getMeta) ~= "function" then
        internal.violate(
            "host.invalid_standalone_binding",
            "standaloneHost: moduleHost metadata accessors are required"
        )
    end
    local DEFAULT_WINDOW_WIDTH = 960
    local DEFAULT_WINDOW_HEIGHT = 720

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

    local function setWindowOpen(open)
        open = open == true
        if showWindow == open then
            return
        end

        if open then
            showWindow = true
            uiSuppressionToken = public.overlays.suppressForUi()
            return
        end

        flushPendingRunData()
        showWindow = false
        if uiSuppressionToken then
            uiSuppressionToken.release()
            uiSuppressionToken = nil
        end
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
                internal.violate("host.session_commit_failed", "%s session commit failed; restored previous config where possible: %s",
                    tostring(meta.name or identity.id or "module"),
                    tostring(err))
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

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
    }
end
