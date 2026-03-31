--- Create managed staging state for a special module.
--- @param modConfig table
--- @param schema table
--- @return table
function public.createSpecialState(modConfig, schema)
    public.validateSchema(schema, _PLUGIN.guid or "unknown module")

    local staging = {}
    local dirty = false
    local fieldByKey = {}

    local readPath = public.readPath
    local writePath = public.writePath
    for _, field in ipairs(schema) do
        if IsSchemaConfigField(field) then
            local schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
            fieldByKey[schemaKey] = field
        end
    end

    local function normalizeValue(key, value)
        local field = fieldByKey[SpecialFieldKey(key)]
        if not field then
            return value
        end

        local ft = FieldTypes[field.type]
        if not ft or not ft.toStaging then
            return value
        end
        return ft.toStaging(value, field)
    end

    local function copyConfigToStaging()
        for _, field in ipairs(schema) do
            if IsSchemaConfigField(field) then
                local val = readPath(modConfig, field.configKey)
                local ft = FieldTypes[field.type]
                if ft then
                    writePath(staging, field.configKey, ft.toStaging(val, field))
                end
            end
        end
    end

    local function copyStagingToConfig()
        for _, field in ipairs(schema) do
            if IsSchemaConfigField(field) then
                local val = readPath(staging, field.configKey)
                writePath(modConfig, field.configKey, val)
            end
        end
    end

    copyConfigToStaging()

    local readonlyCache = setmetatable({}, { __mode = "k" })

    local function makeReadonly(node)
        if type(node) ~= "table" then
            return node
        end
        if readonlyCache[node] then
            return readonlyCache[node]
        end

        local proxy = {}
        local mt = {
            __index = function(_, key)
                local value = node[key]
                if type(value) == "table" then
                    return makeReadonly(value)
                end
                return value
            end,
            __newindex = function()
                error("special state view is read-only; use state.set/update/toggle", 2)
            end,
            __pairs = function()
                return function(_, lastKey)
                    local nextKey, nextVal = next(node, lastKey)
                    if type(nextVal) == "table" then
                        nextVal = makeReadonly(nextVal)
                    end
                    return nextKey, nextVal
                end, proxy, nil
            end,
            __ipairs = function()
                local i = 0
                return function()
                    i = i + 1
                    local value = node[i]
                    if value ~= nil and type(value) == "table" then
                        value = makeReadonly(value)
                    end
                    if value ~= nil then
                        return i, value
                    end
                end, proxy, 0
            end,
        }

        setmetatable(proxy, mt)
        readonlyCache[node] = proxy
        return proxy
    end

    local function snapshot()
        copyConfigToStaging()
        dirty = false
    end

    local function sync()
        copyStagingToConfig()
        dirty = false
    end

    return {
        view = makeReadonly(staging),
        get = function(key)
            local value = readPath(staging, key)
            return value
        end,
        set = function(key, value)
            writePath(staging, key, normalizeValue(key, value))
            dirty = true
        end,
        update = function(key, updater)
            local current = readPath(staging, key)
            writePath(staging, key, normalizeValue(key, updater(current)))
            dirty = true
        end,
        toggle = function(key)
            local current = readPath(staging, key)
            writePath(staging, key, normalizeValue(key, not (current == true)))
            dirty = true
        end,
        reloadFromConfig = snapshot,
        flushToConfig = sync,
        isDirty = function()
            return dirty
        end,
    }
end

--- Capture the current config values for a special module's schema-backed fields.
--- @param modConfig table
--- @param schema table
--- @return table
function public.captureSpecialConfigSnapshot(modConfig, schema)
    local snapshot = {}
    for _, field in ipairs(schema or {}) do
        if IsSchemaConfigField(field) then
            snapshot[field._schemaKey or SpecialFieldKey(field.configKey)] = public.readPath(modConfig, field.configKey)
        end
    end
    return snapshot
end

--- Debug helper: warn if schema-backed config changed during draw without going through specialState.
--- @param name string
--- @param enabled boolean
--- @param specialState table
--- @param modConfig table
--- @param schema table
--- @param before table
function public.warnIfSpecialConfigBypassedState(name, enabled, specialState, modConfig, schema, before)
    if not enabled then return end
    for _, field in ipairs(schema or {}) do
        if IsSchemaConfigField(field) then
            local key = field._schemaKey or SpecialFieldKey(field.configKey)
            local current = public.readPath(modConfig, field.configKey)
            if current ~= before[key] then
                public.log(name, true,
                    "special UI modified config directly; use public.specialState for schema-backed state")
                return
            end
        end
    end
end

--- Run one special-module UI draw pass with optional direct-config-write detection
--- and managed-state flush.
--- @param opts table
--- @return boolean
function public.runSpecialUiPass(opts)
    local draw = opts and opts.draw
    if type(draw) ~= "function" then
        return false
    end

    local specialState = opts.specialState
    local validateEnabled = opts.validateEnabled
    if validateEnabled == nil then
        validateEnabled = public.isSpecialConfigWriteDebugEnabled()
    end

    local before = nil
    if validateEnabled then
        before = public.captureSpecialConfigSnapshot(opts.config, opts.schema)
    end

    draw(opts.imgui or rom.ImGui, specialState, opts.theme)

    if validateEnabled then
        public.warnIfSpecialConfigBypassedState(
            opts.name or "special",
            true,
            specialState,
            opts.config,
            opts.schema,
            before
        )
    end

    if specialState.isDirty() then
        specialState.flushToConfig()
        if type(opts.onFlushed) == "function" then
            opts.onFlushed()
        end
        return true
    end

    return false
end

--- Build standalone window + menu-bar callbacks for a special module.
--- @param def table
--- @param modConfig table
--- @param specialState table
--- @param apply function
--- @param revert function
--- @param opts table|nil
--- @return table
function public.standaloneSpecialUI(def, modConfig, specialState, apply, revert, opts)
    opts = opts or {}

    local function getDrawQuickContent()
        if type(opts.getDrawQuickContent) == "function" then
            return opts.getDrawQuickContent()
        end
        return opts.drawQuickContent
    end

    local function getDrawTab()
        if type(opts.getDrawTab) == "function" then
            return opts.getDrawTab()
        end
        return opts.drawTab
    end

    local function onStateFlushed()
        if def.dataMutation and modConfig.Enabled then
            revert()
            apply()
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
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", modConfig.Enabled)
            if enabledChanged then
                modConfig.Enabled = enabledValue
                if enabledValue then
                    apply()
                else
                    revert()
                end
                if def.dataMutation then
                    rom.game.SetupRunData()
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", modConfig.DebugMode == true)
            if debugChanged then
                modConfig.DebugMode = debugValue
            end

            public.drawSpecialConfigWriteDebugToggle(imgui)

            local drawQuickContent = getDrawQuickContent()
            local drawTab = getDrawTab()

            if drawQuickContent or drawTab then
                imgui.Separator()
                imgui.Spacing()
            end

            if drawQuickContent then
                public.runSpecialUiPass({
                    name = def.name,
                    imgui = imgui,
                    config = modConfig,
                    schema = def.stateSchema,
                    specialState = specialState,
                    theme = opts.theme,
                    draw = drawQuickContent,
                    onFlushed = onStateFlushed,
                })
            end

            if drawQuickContent and drawTab then
                imgui.Spacing()
                imgui.Separator()
            end

            if drawTab then
                public.runSpecialUiPass({
                    name = def.name,
                    imgui = imgui,
                    config = modConfig,
                    schema = def.stateSchema,
                    specialState = specialState,
                    theme = opts.theme,
                    draw = drawTab,
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
