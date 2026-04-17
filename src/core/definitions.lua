local internal = AdamantModpackLib_Internal
public.definition = public.definition or {}
public.mutation = public.mutation or {}
local definition = public.definition
local mutation = public.mutation

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    category = true,
    subgroup = true,
    placement = true,
    tooltip = true,
    default = true,
    affectsRunData = true,
    storage = true,
    ui = true,
    customTypes = true,
    patchPlan = true,
    apply = true,
    revert = true,
    selectQuickUi = true,
    hashGroups = true,
}

local function IsLikelyDefinitionTable(def)
    if type(def) ~= "table" then
        return false
    end

    if def.stateSchema ~= nil or def.options ~= nil then
        return true
    end

    for key in pairs(def) do
        if type(key) == "string" and KnownDefinitionKeys[key] then
            return true
        end
    end

    return false
end

--- Validates a module definition table and emits warnings for unsupported or inconsistent keys.
---@param def table Candidate module definition table.
---@param label string|nil Optional label used to prefix validation warnings.
---@return table def The original definition table for call-site chaining.
function definition.validate(def, label)
    if not IsLikelyDefinitionTable(def) then
        return def
    end

    local prefix = tostring(label or def.name or def.id or _PLUGIN.guid or "module")

    for key in pairs(def) do
        if type(key) == "string"
            and key ~= "stateSchema"
            and key ~= "options"
            and not KnownDefinitionKeys[key] then
            internal.logging.warn("%s: unknown definition key '%s'", prefix, tostring(key))
        end
    end

    local function warnType(key, expected)
        if def[key] ~= nil and type(def[key]) ~= expected then
            internal.logging.warn("%s: definition.%s should be %s, got %s",
                prefix, key, expected, type(def[key]))
        end
    end

    for _, key in ipairs({ "modpack", "id", "name", "shortName", "placement", "category", "subgroup", "tooltip" }) do
        warnType(key, "string")
    end
    for _, key in ipairs({ "affectsRunData" }) do
        warnType(key, "boolean")
    end
    for _, key in ipairs({ "storage", "ui", "customTypes", "hashGroups" }) do
        warnType(key, "table")
    end
    for _, key in ipairs({ "patchPlan", "apply", "revert", "selectQuickUi" }) do
        warnType(key, "function")
    end

    if def.modpack ~= nil and def.id == nil then
        internal.logging.warn("%s: coordinated modules should declare definition.id", prefix)
    end
    if def.category ~= nil then
        internal.logging.warn("%s: definition.category is ignored under the one-tab-per-module framework contract",
            prefix)
    end
    if def.subgroup ~= nil then
        internal.logging.warn("%s: definition.subgroup is ignored under the one-tab-per-module framework contract",
            prefix)
    end
    if def.placement ~= nil then
        internal.logging.warn("%s: definition.placement is ignored under the one-tab-per-module framework contract",
            prefix)
    end
    if def.ui ~= nil then
        internal.logging.warn("%s: definition.ui is ignored under the lean DrawTab contract", prefix)
    end
    if def.customTypes ~= nil then
        internal.logging.warn("%s: definition.customTypes is ignored under the lean DrawTab contract", prefix)
    end
    if def.selectQuickUi ~= nil then
        internal.logging.warn("%s: definition.selectQuickUi is ignored; quick setup uses DrawQuickContent",
            prefix)
    end

    local inferred, info = mutation.inferShape(def)
    if info.hasApply ~= info.hasRevert then
        internal.logging.warn("%s: manual lifecycle requires both definition.apply and definition.revert", prefix)
    end
    if mutation.mutatesRunData(def) and not inferred then
        internal.logging.warn("%s: affectsRunData=true but module exposes neither patchPlan nor apply/revert", prefix)
    end

    return def
end
