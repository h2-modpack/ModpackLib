local internal = AdamantModpackLib_Internal

---@class ModuleCreateOpts
---@field owner table
---@field pluginGuid string
---@field config table
---@field definition ModuleDefinition
---@field registerHooks fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerPatchMutation fun(plan: table, host: AuthorHost, store: ManagedStore)|nil
---@field registerManualMutation table|nil
---@field onSettingsCommitted fun(host: AuthorHost, store: ManagedStore, commit: table)|nil
---@field registerIntegrations fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerOverlays fun(overlays: table, host: AuthorHost, store: ManagedStore)|nil
---@field drawTab fun(imgui: table, session: AuthorSession, host: AuthorHost)
---@field drawQuickContent fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil

local KnownModuleOpts = {
    owner = true,
    pluginGuid = true,
    config = true,
    definition = true,
    registerHooks = true,
    registerPatchMutation = true,
    registerManualMutation = true,
    onSettingsCommitted = true,
    registerIntegrations = true,
    registerOverlays = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts)
    for key in pairs(opts) do
        if not KnownModuleOpts[key] then
            internal.violate("host.unknown_opt", "createModule: unknown option '%s'", tostring(key))
        end
    end
end

--- Creates a module through the canonical prepare -> store -> host pipeline.
--- Call `host.activate()` after construction.
---@param opts ModuleCreateOpts
---@return AuthorHost host
---@return ManagedStore store
function public.createModule(opts)
    if type(opts) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModule: opts must be a table")
    end
    ValidateKnownOpts(opts)
    if type(opts.config) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModule: config is required")
    end
    if type(opts.owner) ~= "table" then
        internal.violate("host.invalid_create_opts", "createModule: owner is required")
    end

    local definition = internal.definition.prepare(opts.owner, opts.definition, {
        hasQuickContent = type(opts.drawQuickContent) == "function",
    })
    local store, session = public.createStore(opts.config, definition)
    local _, authorHost = public.createModuleHost({
        owner = opts.owner,
        definition = definition,
        pluginGuid = opts.pluginGuid,
        store = store,
        session = session,
        registerHooks = opts.registerHooks,
        registerPatchMutation = opts.registerPatchMutation,
        registerManualMutation = opts.registerManualMutation,
        onSettingsCommitted = opts.onSettingsCommitted,
        registerIntegrations = opts.registerIntegrations,
        registerOverlays = opts.registerOverlays,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    return authorHost, store
end

--- Safely creates a module through the canonical prepare -> store -> host pipeline.
--- Returns nils plus the construction error instead of throwing.
---@param opts ModuleCreateOpts
---@return AuthorHost|nil host
---@return ManagedStore|nil store
---@return string|nil err
function public.tryCreateModule(opts)
    local ok, host, store = pcall(public.createModule, opts)
    if ok then
        return host, store, nil
    end

    local err = tostring(host)
    internal.violate("host.create_failed", "createModule failed; skipping module: %s", err)
    return nil, nil, err
end
