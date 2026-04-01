local internal = AdamantModpackLib_Internal
local shared = internal.shared
local libConfig = shared.libConfig
local _coordinators = shared.coordinators
local chalk = shared.chalk
local _mutationRuntime = shared.mutationRuntime or setmetatable({}, { __mode = "k" })
shared.mutationRuntime = _mutationRuntime
local SpecialFieldKey
local PrepareSchemaFieldRuntimeMetadata
local IsSchemaConfigField
local ChoiceDisplay

--- Register a coordinator's config under its packId.
--- Called by Framework.init on behalf of the coordinator.
--- Pass nil to deregister (used in tests and hot-reload).
--- @param packId string
--- @param config table|nil
function public.registerCoordinator(packId, config)
    _coordinators[packId] = config
end

--- Return true if a coordinator has registered for this packId.
--- @param packId string
--- @return boolean
function public.isCoordinated(packId)
    return _coordinators[packId] ~= nil
end

--- Check if a store-backed module should be active.
--- @param store table
--- @param packId string
--- @return boolean
function public.isEnabled(store, packId)
    local coord = packId and _coordinators[packId]
    if coord and not coord.ModEnabled then return false end
    return store and type(store.read) == "function" and store.read("Enabled") == true or false
end

--- Lib-internal diagnostic — gated on lib's own DebugMode.
local function libWarn(fmt, ...)
    if not libConfig.DebugMode then return end
    print("[lib] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end
shared.libWarn = libWarn

--- Print a framework diagnostic warning, gated on the caller's enabled flag.
--- @param packId string
--- @param enabled boolean
--- @param fmt string
function public.warn(packId, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. packId .. "] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end

--- Print a module-level diagnostic trace when the module's own DebugMode is enabled.
--- @param name string
--- @param enabled boolean
--- @param fmt string
function public.log(name, enabled, fmt, ...)
    if not enabled then return end
    print("[" .. name .. "] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end

public.MutationMode = {
    Patch = "patch",
    Manual = "manual",
    Hybrid = "hybrid",
}

local function CloneMutationValue(value)
    if type(value) == "table" then
        return rom.game.DeepCopyTable(value)
    end
    return value
end

local function MutationDeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    for key, value in pairs(a) do
        if not MutationDeepEqual(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

--- Create an isolated backup/restore pair.
--- @return function backup
--- @return function restore
function public.createBackupSystem()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select('#', ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local v = tbl[key]
                saved[key] = (v == nil) and NIL or (type(v) == "table" and rom.game.DeepCopyTable(v) or v)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, v in pairs(keys) do
                if v == NIL then
                    tbl[key] = nil
                elseif type(v) == "table" then
                    tbl[key] = rom.game.DeepCopyTable(v)
                else
                    tbl[key] = v
                end
            end
        end
    end

    return backup, restore
end

--- Create a reversible declarative mutation plan.
--- @return table
function public.createMutationPlan()
    local backup, restore = public.createBackupSystem()
    local operations = {}
    local applied = false
    local plan = {}

    local function appendOperation(op)
        operations[#operations + 1] = op
        return plan
    end

    function plan.set(_, tbl, key, value)
        return appendOperation({
            kind = "set",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    function plan.setMany(_, tbl, kv)
        return appendOperation({
            kind = "setMany",
            tbl = tbl,
            kv = kv,
        })
    end

    function plan.transform(_, tbl, key, fn)
        return appendOperation({
            kind = "transform",
            tbl = tbl,
            key = key,
            fn = fn,
        })
    end

    function plan.append(_, tbl, key, value)
        return appendOperation({
            kind = "append",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
        })
    end

    function plan.appendUnique(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "appendUnique",
            tbl = tbl,
            key = key,
            value = CloneMutationValue(value),
            equivalentFn = equivalentFn or MutationDeepEqual,
        })
    end

    function plan.apply()
        if applied then
            return false
        end

        for _, op in ipairs(operations) do
            local tbl = op.tbl
            local key = op.key

            if op.kind == "set" then
                if tbl[key] ~= op.value then
                    backup(tbl, key)
                    tbl[key] = CloneMutationValue(op.value)
                end
            elseif op.kind == "setMany" then
                for mapKey, value in pairs(op.kv) do
                    if tbl[mapKey] ~= value then
                        backup(tbl, mapKey)
                        tbl[mapKey] = CloneMutationValue(value)
                    end
                end
            elseif op.kind == "transform" then
                backup(tbl, key)
                tbl[key] = op.fn(tbl[key], key, tbl)
            elseif op.kind == "append" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan append requires table at key '%s'"):format(tostring(key)), 0)
                else
                    backup(tbl, key)
                end
                list[#list + 1] = CloneMutationValue(op.value)
            elseif op.kind == "appendUnique" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan appendUnique requires table at key '%s'"):format(tostring(key)), 0)
                end

                local exists = false
                for _, entry in ipairs(list) do
                    if op.equivalentFn(entry, op.value) then
                        exists = true
                        break
                    end
                end
                if not exists then
                    if tbl[key] == list then
                        backup(tbl, key)
                    end
                    list[#list + 1] = CloneMutationValue(op.value)
                end
            end
        end

        applied = true
        return true
    end

    function plan.revert()
        if not applied then
            return false
        end
        restore()
        applied = false
        return true
    end

    return plan
end

--- Infer a module's mutation authoring shape from its exports.
--- @param def table
--- @return string|nil, table
function public.inferMutationMode(def)
    local hasPatch = def and type(def.patchPlan) == "function" or false
    local hasApply = def and type(def.apply) == "function" or false
    local hasRevert = def and type(def.revert) == "function" or false
    local hasManual = hasApply and hasRevert

    local inferred = nil
    if hasPatch and hasManual then
        inferred = public.MutationMode.Hybrid
    elseif hasPatch then
        inferred = public.MutationMode.Patch
    elseif hasManual then
        inferred = public.MutationMode.Manual
    end

    return inferred, {
        hasPatch = hasPatch,
        hasApply = hasApply,
        hasRevert = hasRevert,
        hasManual = hasManual,
    }
end

local function GetActiveMutationPlan(store)
    local runtime = store and _mutationRuntime[store]
    return runtime and runtime.plan or nil
end

local function SetActiveMutationPlan(store, plan)
    if not store then
        return
    end
    if plan == nil then
        _mutationRuntime[store] = nil
        return
    end
    _mutationRuntime[store] = { plan = plan }
end

local function BuildMutationPlan(def, store)
    local builder = def and def.patchPlan
    if type(builder) ~= "function" then
        return nil
    end

    local plan = public.createMutationPlan()
    builder(plan, store)
    return plan
end

--- Activate a module definition using inferred patch/manual/hybrid mutation behavior.
--- @param def table
--- @param store table|nil
--- @return boolean, string|nil
function public.applyDefinition(def, store)
    local inferred, info = public.inferMutationMode(def)
    if not inferred then
        return false, "no supported mutation lifecycle found"
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        activePlan:revert()
        SetActiveMutationPlan(store, nil)
    end

    local builtPlan = nil
    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, def, store)
        if not okBuild then
            return false, result
        end
        builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(builtPlan.apply, builtPlan)
            if not okApply then
                return false, errApply
            end
            SetActiveMutationPlan(store, builtPlan)
        end
    end

    if info.hasManual then
        local okManual, errManual = pcall(def.apply)
        if not okManual then
            if builtPlan then
                pcall(builtPlan.revert, builtPlan)
                SetActiveMutationPlan(store, nil)
            end
            return false, errManual
        end
    end

    return true, nil
end

--- Deactivate a module definition using inferred patch/manual/hybrid mutation behavior.
--- @param def table
--- @param store table|nil
--- @return boolean, string|nil
function public.revertDefinition(def, store)
    local inferred, info = public.inferMutationMode(def)
    if not inferred then
        return false, "no supported mutation lifecycle found"
    end

    local firstErr = nil

    if info.hasManual then
        local okManual, errManual = pcall(def.revert)
        if not okManual and not firstErr then
            firstErr = errManual
        end
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okPlan, errPlan = pcall(activePlan.revert, activePlan)
        SetActiveMutationPlan(store, nil)
        if not okPlan and not firstErr then
            firstErr = errPlan
        end
    end

    if firstErr then
        return false, firstErr
    end

    return true, nil
end

--- Build a menu-bar callback for a boolean mod.
--- @param def table
--- @param store table
--- @return function
function public.standaloneUI(def, store)
    local function onOptionChanged()
        if def.dataMutation then
            public.revertDefinition(def, store)
            public.applyDefinition(def, store)
            rom.game.SetupRunData()
        end
    end

    local function IsOptionVisible(opt)
        if not opt.visibleIf then
            return true
        end
        return store.read(opt.visibleIf) == true
    end

    local function DrawOption(imgui, opt, index)
        if not IsOptionVisible(opt) then
            return
        end

        local pushId = opt._pushId or opt.configKey or (opt.type .. "_" .. tostring(index))
        imgui.PushID(pushId)
        if opt.indent then
            imgui.Indent()
        end

        local currentValue = nil
        if opt.configKey ~= nil then
            currentValue = store.read(opt.configKey)
        end
        local newVal, newChg = public.drawField(imgui, opt, currentValue)
        if newChg and opt.configKey then
            store.write(opt.configKey, newVal)
            onOptionChanged()
        end

        if opt.indent then
            imgui.Unindent()
        end
        imgui.PopID()
    end

    return function()
        if def.modpack and _coordinators[def.modpack] then return end
        if rom.ImGui.BeginMenu(def.name) then
            local imgui = rom.ImGui
            local enabled = store.read("Enabled") == true
            local val, chg = imgui.Checkbox(def.name, enabled)
            if chg then
                store.write("Enabled", val)
                if val then
                    public.applyDefinition(def, store)
                else
                    public.revertDefinition(def, store)
                end
                if def.dataMutation then rom.game.SetupRunData() end
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

            if enabled and def.options then
                imgui.Separator()
                for index, opt in ipairs(def.options) do
                    DrawOption(imgui, opt, index)
                end
            end

            imgui.EndMenu()
        end
    end
end

--- Read a value from a table using a configKey (string or table path).
--- @param tbl table
--- @param key string|table
--- @return any, table|nil, string|nil
function public.readPath(tbl, key)
    if type(key) == "table" then
        if #key == 0 then return nil, nil, nil end
        for i = 1, #key - 1 do
            tbl = tbl[key[i]]
            if not tbl then return nil, nil, nil end
        end
        return tbl[key[#key]], tbl, key[#key]
    end
    return tbl[key], tbl, key
end

--- Write a value to a table using a configKey (string or table path).
--- @param tbl table
--- @param key string|table
--- @param value any
function public.writePath(tbl, key, value)
    if type(key) == "table" then
        for i = 1, #key - 1 do
            tbl[key[i]] = tbl[key[i]] or {}
            tbl = tbl[key[i]]
        end
        tbl[key[#key]] = value
        return
    end
    tbl[key] = value
end

--- Create the module-owned store facade around persisted Chalk-backed config.
--- Regular modules call createStore(config); special modules pass stateSchema too.
--- @param modConfig table
--- @param schema table|nil
--- @return table
function public.createStore(modConfig, schema)
    local backend = GetConfigBackend(modConfig)
    local store = {
        _config = modConfig,
        _backend = backend,
    }

    function store.read(key)
        if backend then
            local value = backend.readValue(key)
            if value ~= nil then
                return value
            end
        end
        return public.readPath(modConfig, key)
    end

    function store.write(key, value)
        if backend and backend.writeValue(key, value) then
            return
        end
        public.writePath(modConfig, key, value)
    end

    if schema then
        store.specialState = shared.CreateSpecialState(store, schema)
    end

    return store
end

PrepareSchemaFieldRuntimeMetadata = function(field)
    if not field or field.configKey == nil then
        return
    end
    field._schemaKey = field._schemaKey or SpecialFieldKey(field.configKey)
    if not field._readValue or not field._writeValue then
        local configKey = field.configKey
        if type(configKey) ~= "table" then
            local key = configKey
            field._readValue = function(tbl)
                return tbl[key]
            end
            field._writeValue = function(tbl, value)
                tbl[key] = value
            end
            return
        end

        local len = #configKey
        if len == 0 then
            field._readValue = function()
                return nil
            end
            field._writeValue = function()
            end
            return
        end

        if len == 1 then
            local key = configKey[1]
            field._readValue = function(tbl)
                return tbl[key]
            end
            field._writeValue = function(tbl, value)
                tbl[key] = value
            end
            return
        end

        if len == 2 then
            local key1, key2 = configKey[1], configKey[2]
            field._readValue = function(tbl)
                local child = tbl[key1]
                return child and child[key2] or nil
            end
            field._writeValue = function(tbl, value)
                local child = tbl[key1]
                if not child then
                    child = {}
                    tbl[key1] = child
                end
                child[key2] = value
            end
            return
        end

        if len == 3 then
            local key1, key2, key3 = configKey[1], configKey[2], configKey[3]
            field._readValue = function(tbl)
                local child1 = tbl[key1]
                if not child1 then return nil end
                local child2 = child1[key2]
                return child2 and child2[key3] or nil
            end
            field._writeValue = function(tbl, value)
                local child1 = tbl[key1]
                if not child1 then
                    child1 = {}
                    tbl[key1] = child1
                end
                local child2 = child1[key2]
                if not child2 then
                    child2 = {}
                    child1[key2] = child2
                end
                child2[key3] = value
            end
            return
        end

        field._readValue = function(tbl)
            return public.readPath(tbl, configKey)
        end
        field._writeValue = function(tbl, value)
            public.writePath(tbl, configKey, value)
        end
    end
end
shared.PrepareSchemaFieldRuntimeMetadata = PrepareSchemaFieldRuntimeMetadata

local ConfigBackendCache = setmetatable({}, { __mode = "k" })

local function GetChalkSectionAndKey(configKey)
    if type(configKey) == "table" then
        local len = #configKey
        if len == 0 then
            return nil, nil
        end
        if len == 1 then
            return "config", tostring(configKey[1])
        end
        return "config." .. table.concat(configKey, ".", 1, len - 1), tostring(configKey[len])
    end
    return "config", tostring(configKey)
end

function GetConfigBackend(config)
    if not chalk or type(chalk.original) ~= "function" then
        return nil
    end

    local ok, rawConfig = pcall(chalk.original, config)
    if not ok or type(rawConfig) ~= "table" or type(rawConfig.entries) ~= "table" then
        return nil
    end

    local backend = ConfigBackendCache[rawConfig]
    if backend then
        return backend
    end

    local entryIndex = {}
    for descriptor, entry in pairs(rawConfig.entries) do
        local section = descriptor.section
        local key = descriptor.key
        if section ~= nil and key ~= nil then
            local sectionEntries = entryIndex[section]
            if not sectionEntries then
                sectionEntries = {}
                entryIndex[section] = sectionEntries
            end
            sectionEntries[key] = entry
        end
    end

    local pathEntryCache = {}
    backend = {}

    function backend.getEntry(configKey)
        local pathKey = SpecialFieldKey(configKey)
        local cached = pathEntryCache[pathKey]
        if cached ~= nil then
            return cached or nil
        end

        local section, key = GetChalkSectionAndKey(configKey)
        local entry = section and entryIndex[section] and entryIndex[section][key] or nil
        if entry and type(entry.get) == "function" and type(entry.set) == "function" then
            pathEntryCache[pathKey] = entry
            return entry
        end

        pathEntryCache[pathKey] = false
        return nil
    end

    function backend.readValue(configKey)
        local entry = backend.getEntry(configKey)
        if entry then
            return entry:get()
        end
        return nil
    end

    function backend.writeValue(configKey, value)
        local entry = backend.getEntry(configKey)
        if entry then
            entry:set(value)
            return true
        end
        return false
    end

    backend.rawConfig = rawConfig
    ConfigBackendCache[rawConfig] = backend
    return backend
end
shared.GetConfigBackend = GetConfigBackend

SpecialFieldKey = function(configKey)
    if type(configKey) == "table" then
        return table.concat(configKey, ".")
    end
    return tostring(configKey)
end
shared.SpecialFieldKey = SpecialFieldKey

IsSchemaConfigField = function(field)
    return field and field.type ~= "separator" and field.configKey ~= nil
end
shared.IsSchemaConfigField = IsSchemaConfigField

ChoiceDisplay = function(field, value)
    if field.displayValues and field.displayValues[value] ~= nil then
        return tostring(field.displayValues[value])
    end
    return tostring(value)
end
shared.ChoiceDisplay = ChoiceDisplay
