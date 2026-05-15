local internal = AdamantModpackLib_Internal
local HostState = setmetatable({}, { __mode = "k" })

---@class AuthorSession
---@field view table<string, any>
---@field read fun(alias: string): any
---@field write fun(alias: string, value: any)
---@field stageAction fun(actionKey: string, value: any)
---@field readAction fun(actionKey: string): any
---@field clearAction fun(actionKey: string)
---@field hasActions fun(): boolean
---@field reset fun(alias: string)
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil
---@field resetToDefaults fun(opts: table|nil): boolean, number

---@class AuthorHost
---@field isEnabled fun(): boolean
---@field getIdentity fun(): table
---@field getMeta fun(): table
---@field log fun(fmt: string, ...): nil
---@field logIf fun(fmt: string, ...): nil
---@field activate fun(): AuthorHost
---@field tryActivate fun(): boolean, string|nil

---@class ModuleHostOpts
---@field owner table|nil
---@field definition ModuleDefinition
---@field pluginGuid string
---@field store ManagedStore
---@field session Session
---@field registerHooks fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerPatchMutation fun(plan: table, host: AuthorHost, store: ManagedStore)|nil
---@field registerManualMutation table|nil
---@field onSettingsCommitted fun(host: AuthorHost, store: ManagedStore, commit: table)|nil
---@field registerIntegrations fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerOverlays fun(overlays: table, host: AuthorHost, store: ManagedStore)|nil
---@field drawTab fun(imgui: table, session: AuthorSession, host: AuthorHost)
---@field drawQuickContent fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil

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
---@field activate fun(): AuthorHost
---@field tryActivate fun(): boolean, string|nil
---@field drawTab fun(imgui: table)
---@field drawQuickContent fun(imgui: table)|nil

function public.getLiveModuleHost(pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        return nil
    end
    return internal.liveModuleHosts[pluginGuid]
end

local KnownHostOpts = {
    owner = true,
    definition = true,
    pluginGuid = true,
    store = true,
    session = true,
    registerHooks = true,
    registerPatchMutation = true,
    registerManualMutation = true,
    onSettingsCommitted = true,
    registerIntegrations = true,
    registerOverlays = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts, context)
    for key in pairs(opts) do
        if not KnownHostOpts[key] then
            internal.violate("host.unknown_opt", "%s: unknown option '%s'", context, tostring(key))
        end
    end
end

local function BuildMutationBundle(opts)
    local patchMutation = opts.registerPatchMutation
    local manualMutation = opts.registerManualMutation

    if patchMutation ~= nil and type(patchMutation) ~= "function" then
        internal.violate("host.invalid_create_opts", "createModuleHost: registerPatchMutation must be a function")
    end
    if manualMutation ~= nil then
        if type(manualMutation) ~= "table" then
            internal.violate("host.invalid_create_opts", "createModuleHost: registerManualMutation must be a table")
        end
        if type(manualMutation.apply) ~= "function" or type(manualMutation.revert) ~= "function" then
            internal.violate(
                "host.invalid_create_opts",
                "createModuleHost: registerManualMutation requires apply and revert functions"
            )
        end
    end
    if opts.onSettingsCommitted ~= nil and type(opts.onSettingsCommitted) ~= "function" then
        internal.violate("host.invalid_create_opts", "createModuleHost: onSettingsCommitted must be a function")
    end

    return {
        affectsRunData = patchMutation ~= nil or manualMutation ~= nil,
        patchMutation = patchMutation,
        manualMutation = manualMutation,
    }, opts.onSettingsCommitted
end

--- Creates full and author-facing host objects for Framework and standalone hosting.
--- Activation is explicit through the returned author host.
---@param opts ModuleHostOpts
---@return ModuleHost host Full module host.
---@return AuthorHost authorHost Module author host view.
function public.createModuleHost(opts)
    if type(opts) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModuleHost: opts must be a table")
    end
    ValidateKnownOpts(opts, "createModuleHost")
    local owner = opts.owner
    local def = opts.definition
    local pluginGuid = opts.pluginGuid
    local store = opts.store
    local session = opts.session
    local registerHooks = opts.registerHooks
    local registerIntegrations = opts.registerIntegrations
    local registerOverlays = opts.registerOverlays
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        internal.violate("host.invalid_create_opts", "createModuleHost: prepared definition is required")
    end
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        internal.violate("host.invalid_create_opts", "createModuleHost: pluginGuid is required")
    end
    if not (store and type(store.read) == "function") then
        internal.violate("host.invalid_create_opts", "createModuleHost: store is required")
    end
    if not (session and type(session.isDirty) == "function" and type(session.write) == "function"
        and type(session.getAliasSchema) == "function") then
        internal.violate("host.invalid_create_opts", "createModuleHost: session is required")
    end

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local mutationBundle, settingsObserver = BuildMutationBundle(opts)

    if type(drawTab) ~= "function" then
        internal.violate("host.invalid_create_opts", "createModuleHost: drawTab is required")
    end
    if registerHooks ~= nil then
        if type(registerHooks) ~= "function" then
            internal.violate("host.invalid_create_opts", "createModuleHost: registerHooks must be a function")
        end
        if type(owner) ~= "table" then
            internal.violate("host.invalid_create_opts", "createModuleHost: owner is required when registerHooks is provided")
        end
    end
    if registerIntegrations ~= nil and type(registerIntegrations) ~= "function" then
        internal.violate("host.invalid_create_opts", "createModuleHost: registerIntegrations must be a function")
    end
    if registerOverlays ~= nil then
        if type(registerOverlays) ~= "function" then
            internal.violate("host.invalid_create_opts", "createModuleHost: registerOverlays must be a function")
        end
        if type(owner) ~= "table" then
            internal.violate("host.invalid_create_opts", "createModuleHost: owner is required when registerOverlays is provided")
        end
    end
    local hookOwner = owner or {}

    local function notifySettingsCommitted(activeHost, activeStore, commit)
        if settingsObserver ~= nil then
            settingsObserver(activeHost, activeStore, commit)
        end
        internal.overlays.dispatchCommit(hookOwner, commit)
    end

    ---@type AuthorSession
    local authorSession = {
        view = session.view,
        read = session.read,
        table = session.table,
        write = session.write,
        stageAction = session.stageAction,
        readAction = session.readAction,
        clearAction = session.clearAction,
        hasActions = session.hasActions,
        reset = session.reset,
        getAliasSchema = session.getAliasSchema,
        resetToDefaults = function(resetOpts)
            return public.resetStorageToDefaults(def.storage, session, resetOpts)
        end,
    }

    ---@type ModuleHost
    local host = {}
    ---@type AuthorHost
    local authorHost

    local function requireActivated(methodName)
        local state = HostState[host]
        if not state or state.activated ~= true then
            internal.violate("host.not_activated", "host.%s requires host.activate() before it can run", methodName)
        end
    end

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
        return public.lifecycle.affectsRunData(mutationBundle)
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
        requireActivated("writeAndFlush")
        session.write(alias, value)
        local ok, err = public.lifecycle.commitSession(def, mutationBundle, notifySettingsCommitted, authorHost, store, session)
        return ok, err
    end

    function host.stage(alias, value)
        session.write(alias, value)
        return true
    end

    function host.flush()
        requireActivated("flush")
        if not session.isDirty() then
            return true
        end
        return public.lifecycle.commitSession(def, mutationBundle, notifySettingsCommitted, authorHost, store, session)
    end

    function host.reloadFromConfig()
        requireActivated("reloadFromConfig")
        session._reloadFromConfig()
    end

    function host.resync()
        requireActivated("resync")
        return public.lifecycle.resyncSession(def, session)
    end

    function host.resetToDefaults(resetOpts)
        requireActivated("resetToDefaults")
        return public.resetStorageToDefaults(def.storage, session, resetOpts)
    end

    function host.commitIfDirty()
        requireActivated("commitIfDirty")
        if not session.isDirty() then
            return true, nil, false
        end
        local ok, err = public.lifecycle.commitSession(def, mutationBundle, notifySettingsCommitted, authorHost, store, session)
        return ok, err, ok == true
    end

    function host.isEnabled()
        return public.isModuleEnabled(store, def.modpack)
    end

    function host.setEnabled(enabled)
        requireActivated("setEnabled")
        return public.lifecycle.setEnabled(def, mutationBundle, authorHost, store, enabled)
    end

    function host.setDebugMode(enabled)
        requireActivated("setDebugMode")
        return public.lifecycle.setDebugMode(store, enabled)
    end

    local logPrefix = "[" .. tostring(def.id or pluginGuid) .. "] "

    function host.log(fmt, ...)
        print(internal.formatLogMessage(logPrefix, fmt, ...))
    end

    function host.logIf(fmt, ...)
        if store.read("DebugMode") == true then
            host.log(fmt, ...)
        end
    end

    function host.applyOnLoad()
        requireActivated("applyOnLoad")
        return public.lifecycle.applyOnLoad(def, mutationBundle, authorHost, store)
    end

    function host.applyMutation()
        requireActivated("applyMutation")
        return public.lifecycle.applyMutation(def, mutationBundle, authorHost, store)
    end

    function host.revertMutation()
        requireActivated("revertMutation")
        return public.lifecycle.revertMutation(def, mutationBundle, authorHost, store)
    end

    function host.activate()
        return public.activateModuleHost(host)
    end

    function host.tryActivate()
        return public.tryActivateModule(host)
    end

    authorHost = {
        isEnabled = host.isEnabled,
        getIdentity = host.getIdentity,
        getMeta = host.getMeta,
        activate = host.activate,
        tryActivate = host.tryActivate,
    }

    function authorHost.log(fmt, ...)
        return host.log(fmt, ...)
    end

    function authorHost.logIf(fmt, ...)
        return host.logIf(fmt, ...)
    end

    function host.drawTab(imgui)
        requireActivated("drawTab")
        return drawTab(imgui, authorSession, authorHost)
    end

    if type(drawQuickContent) == "function" then
        function host.drawQuickContent(imgui)
            requireActivated("drawQuickContent")
            return drawQuickContent(imgui, authorSession, authorHost)
        end
    end

    HostState[host] = {
        definition = def,
        mutationBundle = mutationBundle,
        pluginGuid = pluginGuid,
        store = store,
        owner = hookOwner,
        registerHooks = registerHooks,
        registerIntegrations = registerIntegrations,
        registerOverlays = registerOverlays,
        authorSession = authorSession,
        authorHost = authorHost,
        activated = false,
    }

    return host, authorHost
end

--- Activates a constructed module host by registering external side effects.
---@param host ModuleHost
---@return AuthorHost host Module author host view.
function public.activateModuleHost(host)
    local state = type(host) == "table" and HostState[host] or nil
    if not state then
        internal.violate("host.invalid_activate_opts", "activateModuleHost: host is required")
    end

    local pluginGuid = state.pluginGuid
    local owner = state.owner
    local registerHooks = state.registerHooks
    local registerIntegrations = state.registerIntegrations
    local registerOverlays = state.registerOverlays
    local store = state.store
    local authorHost = state.authorHost
    local def = state.definition

    if state.activated == true then
        internal.violate("host.already_activated", "activateModuleHost: host is already activated")
    end
    if state.activating == true then
        internal.violate("host.activation_in_progress", "activateModuleHost: host activation is already in progress")
    end
    local identity = host.getIdentity()
    local meta = host.getMeta()
    local packId = identity.modpack
    local pendingCoordinatorRebuild = internal.pendingCoordinatorRebuilds[def]
    local hasPendingCoordinatorRebuild = pendingCoordinatorRebuild ~= nil
    local previousHost = internal.liveModuleHosts[pluginGuid]
    local hadPreviousHost = previousHost ~= nil
    local hookTransaction = internal.hooks.beginTransaction(owner)
    local integrationTransaction = internal.integrations.beginTransaction()
    local overlayTransaction = internal.overlays.beginTransaction(owner)
    state.activating = true

    internal.liveModuleHosts[pluginGuid] = host
    local ok, err = pcall(function()
        internal.hooks.refresh(owner, function()
            if registerHooks ~= nil then
                return registerHooks(authorHost, store)
            end
        end)
        internal.integrations.refresh(def.id, function()
            if registerIntegrations then
                return registerIntegrations(authorHost, store)
            end
        end)
        internal.overlays.refresh(owner, pluginGuid, authorHost, store, function(overlays)
            if registerOverlays then
                return registerOverlays(overlays, authorHost, store)
            end
        end)

        if not hasPendingCoordinatorRebuild
            and type(packId) == "string"
            and packId ~= ""
            and public.isModuleCoordinated(packId) then
            local syncOk, syncErr = public.lifecycle.applyOnLoad(def, state.mutationBundle, authorHost, store)
            if not syncOk then
                internal.violate("host.coordinated_runtime_sync_failed", "%s coordinated runtime sync failed: %s",
                    tostring(meta.name or identity.id or "module"),
                    tostring(syncErr))
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
    end)

    if not ok then
        state.activating = false
        hookTransaction.rollback()
        integrationTransaction.rollback()
        overlayTransaction.rollback()
        if hadPreviousHost then
            internal.liveModuleHosts[pluginGuid] = previousHost
        else
            internal.liveModuleHosts[pluginGuid] = nil
        end
        error(err, 0)
    end

    hookTransaction.commit()
    integrationTransaction.commit()
    overlayTransaction.commit()
    state.activating = false
    state.activated = true
    return authorHost
end

--- Safely activates a constructed module host by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param host ModuleHost
---@return boolean ok
---@return string|nil err
function public.tryActivateModule(host)
    local ok, err = pcall(public.activateModuleHost, host)
    if ok then
        return true, nil
    end

    err = tostring(err)
    internal.violate("host.activate_failed", "activateModuleHost failed; skipping module: %s", err)
    return false, err
end
