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

--- Check if a module should be active.
--- @param modConfig table
--- @param packId string
--- @return boolean
function public.isEnabled(modConfig, packId)
    local coord = packId and _coordinators[packId]
    if coord and not coord.ModEnabled then return false end
    return modConfig.Enabled == true
end

--- Lib-internal diagnostic — gated on lib's own DebugMode.
function libWarn(fmt, ...)
    if not libConfig.DebugMode then return end
    print("[lib] " .. (select('#', ...) > 0 and string.format(fmt, ...) or fmt))
end

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

--- Return true when direct-config-write detection for special-module UI should run.
--- @return boolean
function public.isSpecialConfigWriteDebugEnabled()
    return libConfig.DebugSpecialConfigWrites == true or libConfig.DebugStateValidation == true
end

--- Render the expensive direct-config-write detection toggle.
--- @param imgui table
--- @param label string|nil
--- @return boolean value, boolean changed
function public.drawSpecialConfigWriteDebugToggle(imgui, label)
    local value, changed = imgui.Checkbox(
        label or "Direct Config Write Detection",
        public.isSpecialConfigWriteDebugEnabled()
    )
    if changed then
        libConfig.DebugSpecialConfigWrites = value
        libConfig.DebugStateValidation = value
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(
            "Warn when special-module UI writes schema-backed config directly instead of using public.specialState."
        )
    end
    return value, changed
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

--- Build a menu-bar callback for a boolean mod.
--- @param def table
--- @param modConfig table
--- @param apply function
--- @param revert function
--- @return function
function public.standaloneUI(def, modConfig, apply, revert)
    local function onOptionChanged()
        if def.dataMutation then
            revert()
            apply()
            rom.game.SetupRunData()
        end
    end

    local function DrawOption(imgui, opt, index)
        if not public.isFieldVisible(opt, modConfig) then
            return
        end

        local pushId = opt._pushId or opt.configKey or (opt.type .. "_" .. tostring(index))
        imgui.PushID(pushId)
        if opt.indent then
            imgui.Indent()
        end

        local currentValue = nil
        if opt.configKey ~= nil then
            currentValue = modConfig[opt.configKey]
        end
        local newVal, newChg = public.drawField(imgui, opt, currentValue)
        if newChg and opt.configKey then
            modConfig[opt.configKey] = newVal
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
            local val, chg = imgui.Checkbox(def.name, modConfig.Enabled)
            if chg then
                modConfig.Enabled = val
                if val then apply() else revert() end
                if def.dataMutation then rom.game.SetupRunData() end
            end
            if imgui.IsItemHovered() and (def.tooltip or "") ~= "" then
                imgui.SetTooltip(def.tooltip)
            end

            local dbgVal, dbgChg = imgui.Checkbox("Debug Mode", modConfig.DebugMode == true)
            if dbgChg then
                modConfig.DebugMode = dbgVal
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("Print diagnostic warnings to the console for this module.")
            end

            if modConfig.Enabled and def.options then
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

function SpecialFieldKey(configKey)
    if type(configKey) == "table" then
        return table.concat(configKey, ".")
    end
    return tostring(configKey)
end

function IsSchemaConfigField(field)
    return field and field.type ~= "separator" and field.configKey ~= nil
end

function ChoiceDisplay(field, value)
    if field.displayValues and field.displayValues[value] ~= nil then
        return tostring(field.displayValues[value])
    end
    return tostring(value)
end
