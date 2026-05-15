local internal = AdamantModpackLib_Internal
internal.moduleHost = internal.moduleHost or {}

local storageInternal = internal.storage
local values = internal.values

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
    storage = true,
    hashGroupPlan = true,
}

local BuiltInStorageNodes = {
    { type = "bool", alias = "Enabled", default = false },
    { type = "bool", alias = "DebugMode", default = false, hash = false },
}

local BuiltInStorageAliases = {
    Enabled = true,
    DebugMode = true,
}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"


local KnownStructuralSurfaceKeys = {
    hasQuickContent = true,
}

local function IsStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local function NormalizeStructuralSurface(surface)
    if surface == nil then
        return nil
    end
    if type(surface) ~= "table" then
        internal.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
        )
    end

    local hasKnownKey = false
    for key in pairs(surface) do
        if KnownStructuralSurfaceKeys[key] then
            hasKnownKey = true
        end
    end

    if not hasKnownKey and next(surface) ~= nil then
        internal.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
        )
    end

    for key in pairs(surface) do
        if not KnownStructuralSurfaceKeys[key] then
            internal.violate("definition.invalid_args", "prepareDefinition: unknown option '%s'", tostring(key))
        end
    end

    if surface.hasQuickContent ~= nil and type(surface.hasQuickContent) ~= "boolean" then
        internal.violate("definition.invalid_args", "prepareDefinition: hasQuickContent must be boolean when provided")
    end

    return {
        hasQuickContent = surface.hasQuickContent == true,
    }
end

local function ValidateHashGroupPlan(definition, prefix)
    local hashGroupPlan = definition.hashGroupPlan
    if hashGroupPlan == nil then
        return
    end
    if type(hashGroupPlan) ~= "table" then
        return
    end

    for groupIndex, group in ipairs(hashGroupPlan) do
        if type(group) ~= "table" then
            internal.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d] must be table",
                prefix,
                groupIndex
            )
        end

        local keyPrefix = group.keyPrefix
        if type(keyPrefix) ~= "string" or keyPrefix == "" then
            internal.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d].keyPrefix is required",
                prefix,
                groupIndex
            )
        elseif not IsStableIdentifier(keyPrefix) then
            internal.violate(
                "definition.invalid_field_type",
                "%s: hashGroupPlan[%d].keyPrefix '%s' %s",
                prefix,
                groupIndex,
                keyPrefix,
                StableIdentifierDescription
            )
        end
    end
end

local function CompareKeys(a, b)
    local typeA = type(a)
    local typeB = type(b)
    if typeA ~= typeB then
        return typeA < typeB
    end
    if typeA == "number" or typeA == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

local function SerializeStructuralValue(value, seen)
    local valueType = type(value)
    if valueType == "nil" then
        return "nil"
    end
    if valueType == "boolean" then
        return value and "true" or "false"
    end
    if valueType == "number" then
        return string.format("%.17g", value)
    end
    if valueType == "string" then
        return string.format("%q", value)
    end
    if valueType == "function" then
        return "<function>"
    end
    if valueType ~= "table" then
        return "<" .. valueType .. ">"
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do
        if not (type(key) == "string" and string.sub(key, 1, 1) == "_") then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, CompareKeys)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "[" .. SerializeStructuralValue(key, seen) .. "]="
            .. SerializeStructuralValue(value[key], seen)
    end

    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function GetLabel(definition, fallback)
    if type(fallback) == "string" and fallback ~= "" then
        return fallback
    end
    if type(definition) == "table" then
        local label = definition.name or definition.id
        if type(label) == "string" and label ~= "" then
            return label
        end
    end
    return tostring(_PLUGIN.guid or "module")
end

local function IsLikelyDefinitionTable(definition)
    if type(definition) ~= "table" then
        return false
    end
    for key in pairs(definition) do
        if type(key) == "string" and KnownDefinitionKeys[key] then
            return true
        end
    end
    return false
end

local function ValidateDefinition(definition, label)
    if not IsLikelyDefinitionTable(definition) then
        return
    end

    local prefix = GetLabel(definition, label)

    for key in pairs(definition) do
        if type(key) == "string" and not KnownDefinitionKeys[key] then
            internal.violate("definition.unknown_key", "%s: unknown definition key '%s'", prefix, tostring(key))
        end
    end

    local function checkType(key, expected)
        if definition[key] ~= nil and type(definition[key]) ~= expected then
            internal.violate("definition.invalid_field_type", "%s: definition.%s should be %s, got %s",
                prefix, key, expected, type(definition[key]))
        end
    end

    if definition.id == nil or definition.id == "" then
        internal.violate("definition.missing_id", "%s: definition.id is required", prefix)
    elseif type(definition.id) ~= "string" then
        internal.violate("definition.invalid_field_type", "%s: definition.id should be string, got %s",
            prefix, type(definition.id))
    elseif not IsStableIdentifier(definition.id) then
        internal.violate("definition.invalid_field_type", "%s: definition.id '%s' %s",
            prefix, definition.id, StableIdentifierDescription)
    end

    if definition.name == nil or definition.name == "" then
        internal.violate("definition.missing_name", "%s: definition.name is required", prefix)
    elseif type(definition.name) ~= "string" then
        internal.violate("definition.invalid_field_type", "%s: definition.name should be string, got %s",
            prefix, type(definition.name))
    end

    for _, key in ipairs({ "modpack", "shortName", "tooltip" }) do
        checkType(key, "string")
    end
    checkType("storage", "table")
    checkType("hashGroupPlan", "table")
    ValidateHashGroupPlan(definition, prefix)
end

local function GetStructuralFingerprint(definition, structuralSurface)
    local structuralState = {
        modpack = definition and definition.modpack or nil,
        id = definition and definition.id or nil,
        name = definition and definition.name or nil,
        shortName = definition and definition.shortName or nil,
        tooltip = definition and definition.tooltip or nil,
        hasQuickContent = structuralSurface and structuralSurface.hasQuickContent == true or false,
        storage = definition and definition.storage or nil,
        hashGroupPlan = definition and definition.hashGroupPlan or nil,
    }
    return SerializeStructuralValue(structuralState)
end

local function InjectBuiltInStorage(definition, label)
    if definition.storage == nil then
        definition.storage = {}
    end
    if type(definition.storage) ~= "table" then
        internal.violate("definition.invalid_args", "%s: definition.storage must be a table", label)
    end

    for _, node in ipairs(definition.storage) do
        if type(node) == "table" and BuiltInStorageAliases[node.alias] then
            internal.violate(
                "definition.reserved_storage_alias",
                "%s: storage alias '%s' is reserved by Lib",
                label,
                tostring(node.alias)
            )
        end
    end

    for index = #BuiltInStorageNodes, 1, -1 do
        table.insert(definition.storage, 1, values.deepCopy(BuiltInStorageNodes[index]))
    end
end

function internal.moduleHost.prepareDefinition(owner, definition, structuralSurface, ...)
    if select("#", ...) ~= 0 then
        internal.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
        )
    end
    structuralSurface = NormalizeStructuralSurface(structuralSurface)
    if owner ~= nil and type(owner) ~= "table" then
        internal.violate("definition.invalid_args", "prepareDefinition: owner must be a table when provided")
    end
    if type(definition) ~= "table" then
        internal.violate("definition.invalid_args", "prepareDefinition: definition must be a table")
    end

    local prepared = values.deepCopy(definition)
    local label = GetLabel(prepared)
    InjectBuiltInStorage(prepared, label)

    ValidateDefinition(prepared, label)
    storageInternal.validate(prepared.storage, label)

    local fingerprint = GetStructuralFingerprint(prepared, structuralSurface)
    prepared._preparedDefinition = true
    prepared._structuralFingerprint = fingerprint

    if owner then
        local previousFingerprint = rawget(owner, "_definitionStructuralFingerprint")
        if previousFingerprint ~= nil and previousFingerprint ~= fingerprint then
            owner.requiresFullReload = true
            if type(prepared.modpack) == "string" and public.coordinator.isRegistered(prepared.modpack) then
                internal.pendingCoordinatorRebuilds[prepared] = {
                    kind = "structural_definition_changed",
                    moduleId = prepared.id,
                    displayName = prepared.name,
                    modpack = prepared.modpack,
                }
            else
                internal.violate("definition.structural_reload_required", "%s: %s", label,
                    "structural definition changed during hot reload; full reload required")
            end
        end
        owner._definitionStructuralFingerprint = fingerprint
    end

    return prepared
end
