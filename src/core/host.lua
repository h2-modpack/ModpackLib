local internal = AdamantModpackLib_Internal
local moduleRegistry = internal.moduleRegistry

---@class StandaloneOpts
---@field windowTitle string|nil

---@class StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()

---@class AuthorSession
---@field view table<string, any>
---@field read fun(alias: string): any
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)

---@class ModuleHostOpts
---@field definition ModuleDefinition
---@field store ManagedStore
---@field session Session
---@field hookOwner table|nil
---@field registerHooks fun()|nil
---@field drawTab fun(imgui: table, session: AuthorSession)|nil
---@field drawQuickContent fun(imgui: table, session: AuthorSession)|nil

---@class ModuleHost
---@field getDefinition fun(): ModuleDefinition
---@field read fun(aliasOrKey: ConfigPath): any
---@field writeAndFlush fun(aliasOrKey: ConfigPath, value: any): boolean
---@field stage fun(aliasOrKey: ConfigPath, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
---@field commitIfDirty fun(): boolean, string|nil, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string|nil
---@field setDebugMode fun(enabled: boolean)
---@field applyOnLoad fun(): boolean, string|nil
---@field applyMutation fun(): boolean, string|nil
---@field revertMutation fun(): boolean, string|nil
---@field hasDrawTab fun(): boolean
---@field drawTab fun(imgui: table)
---@field hasQuickContent fun(): boolean
---@field drawQuickContent fun(imgui: table)

--- Creates a behavior-only host object for Framework and standalone hosting.
--- The host closes over store/session without exposing those state handles publicly.
---@param opts ModuleHostOpts
---@return ModuleHost host Module host behavior contract.
function public.createModuleHost(opts)
    assert(type(opts) == "table", "createModuleHost: opts must be a table")
    local def = opts.definition
    local store = opts.store
    local session = opts.session
    assert(type(def) == "table", "createModuleHost: definition is required")
    assert(store and type(store.read) == "function", "createModuleHost: store is required")
    assert(session and type(session.isDirty) == "function" and type(session.write) == "function",
        "createModuleHost: session is required")

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local registerHooks = opts.registerHooks
    local hookOwner = opts.hookOwner

    if registerHooks ~= nil then
        assert(type(registerHooks) == "function", "createModuleHost: registerHooks must be a function")
        assert(type(hookOwner) == "table", "createModuleHost: hookOwner is required when registerHooks is provided")
        internal.hooks.refresh(hookOwner, registerHooks)
    end

    ---@type AuthorSession
    local authorSession = {
        view = session.view,
        read = session.read,
        write = session.write,
        reset = session.reset,
    }

    ---@type ModuleHost
    local host = {}

    function host.getDefinition()
        return def
    end

    function host.read(aliasOrKey)
        return store.read(aliasOrKey)
    end

    function host.writeAndFlush(aliasOrKey, value)
        session.write(aliasOrKey, value)
        session._flushToConfig()
        return true
    end

    function host.stage(aliasOrKey, value)
        session.write(aliasOrKey, value)
        return true
    end

    function host.flush()
        session._flushToConfig()
        return true
    end

    function host.reloadFromConfig()
        session._reloadFromConfig()
    end

    function host.resync()
        return public.lifecycle.resyncSession(def, session)
    end

    function host.commitIfDirty()
        if not session.isDirty() then
            return true, nil, false
        end
        local ok, err = public.lifecycle.commitSession(def, store, session)
        return ok, err, ok == true
    end

    function host.isEnabled()
        return public.isModuleEnabled(store, def.modpack)
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

    function host.hasDrawTab()
        return type(drawTab) == "function"
    end

    function host.drawTab(imgui)
        if type(drawTab) == "function" then
            return drawTab(imgui, authorSession)
        end
    end

    function host.hasQuickContent()
        return type(drawQuickContent) == "function"
    end

    function host.drawQuickContent(imgui)
        if type(drawQuickContent) == "function" then
            return drawQuickContent(imgui, authorSession)
        end
    end

    local packId = def.modpack
    local moduleId = def.id
    if type(packId) == "string" and packId ~= "" and type(moduleId) == "string" and moduleId ~= "" then
        moduleRegistry.hosts[packId] = moduleRegistry.hosts[packId] or {}
        moduleRegistry.hosts[packId][moduleId] = {
            definition = def,
            host = host,
        }
        moduleRegistry.versions[packId] = (moduleRegistry.versions[packId] or 0) + 1
    end

    return host
end

--- Returns the current module-host registry version for a pack.
---@param packId string
---@return number version
function public.getModuleRegistryVersion(packId)
    return moduleRegistry.versions[packId] or 0
end

--- Initializes standalone module hosting and returns window/menu-bar renderers.
---@param moduleHost table Behavior host returned by `lib.createModuleHost`.
---@param opts StandaloneOpts|nil Optional standalone rendering hooks and window settings.
---@return StandaloneRuntime runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function public.standaloneHost(moduleHost, opts)
    assert(type(moduleHost) == "table", "standaloneHost: moduleHost is required")

    opts = opts or {}
    local def = moduleHost.getDefinition()
    assert(type(def) == "table", "standaloneHost: moduleHost definition is required")
    local DEFAULT_WINDOW_WIDTH = 960
    local DEFAULT_WINDOW_HEIGHT = 720

    if not (def.modpack and internal.coordinators[def.modpack]) then
        local ok, err = moduleHost.applyOnLoad()
        if not ok then
            internal.logging.warn("%s startup lifecycle failed: %s",
                tostring(def.name or def.id or "module"),
                tostring(err))
        end
    end

    local showWindow = false
    local didSeedWindowSize = false
    local runDataDirty = false

    local function markRunDataDirty()
        if public.lifecycle.mutatesRunData(def) then
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

    local function seedWindowSize(imgui)
        if didSeedWindowSize then
            return
        end
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        didSeedWindowSize = true
    end

    local function renderWindow()
        if def.modpack and internal.coordinators[def.modpack] then return end
        if not showWindow then return end

        local imgui = rom.ImGui
        local title = (opts.windowTitle or def.name) .. "###" .. tostring(def.id)
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
                    internal.logging.warn("%s %s failed: %s",
                        tostring(def.name or def.id or "module"),
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

            if moduleHost.hasDrawTab() then
                imgui.Separator()
                imgui.Spacing()
                moduleHost.drawTab(imgui)
                local ok, _, committed = moduleHost.commitIfDirty()
                if ok and committed and moduleHost.read("Enabled") == true then
                    markRunDataDirty()
                end
            end
        end
        imgui.End()
        if open == false then
            flushPendingRunData()
            showWindow = false
        end
    end

    local function addMenuBar()
        if def.modpack and internal.coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            if rom.ImGui.MenuItem(def.name) then
                if showWindow then
                    flushPendingRunData()
                end
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
