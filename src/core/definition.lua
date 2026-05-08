local internal = AdamantModpackLib_Internal
internal.definition = internal.definition or {}
local definitionInternal = internal.definition
local storageInternal = internal.storage
local mutationInternal = internal.mutation
local values = internal.values

local KnownDefinitionKeys = {
    modpack = true,
    id = true,
    name = true,
    shortName = true,
    tooltip = true,
    affectsRunData = true,
    storage = true,
    hashGroupPlan = true,
    patchPlan = true,
    apply = true,
    revert = true,
    onSettingsCommitted = true,
}

definitionInternal.KnownKeys = KnownDefinitionKeys

local BuiltInStorageNodes = {
    { type = "bool", alias = "Enabled", default = false },
    { type = "bool", alias = "DebugMode", default = false, hash = false },
}

local BuiltInStorageAliases = {
    Enabled = true,
    DebugMode = true,
}

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

function definitionInternal.getLabel(definition, fallback)
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

function definitionInternal.isPrepared(definition)
    return type(definition) == "table" and rawget(definition, "_preparedDefinition") == true
end

function definitionInternal.isLikelyDefinitionTable(definition)
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

function definitionInternal.validate(definition, label)
    if not definitionInternal.isLikelyDefinitionTable(definition) then
        return
    end

    local prefix = definitionInternal.getLabel(definition, label)

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

    for _, key in ipairs({ "modpack", "id", "name", "shortName", "tooltip" }) do
        checkType(key, "string")
    end
    checkType("affectsRunData", "boolean")
    checkType("storage", "table")
    checkType("hashGroupPlan", "table")
    for _, key in ipairs({ "patchPlan", "apply", "revert", "onSettingsCommitted" }) do
        checkType(key, "function")
    end

    if definition.modpack ~= nil and definition.id == nil then
        internal.violate("definition.missing_coordinated_id", "%s: coordinated modules should declare definition.id", prefix)
    end

    local inferredMutationShape, mutationInfo = mutationInternal.inferMutation(definition)
    if definition.affectsRunData == true and not inferredMutationShape then
        internal.violate(
            "definition.missing_mutation",
            "%s: affectsRunData=true requires patchPlan or apply/revert",
            prefix
        )
    end
    if mutationInfo.hasApply ~= mutationInfo.hasRevert then
        internal.violate(
            "definition.incomplete_manual_lifecycle",
            "%s: manual lifecycle requires both definition.apply and definition.revert",
            prefix
        )
    end
end

function definitionInternal.getStructuralFingerprint(definition)
    local structuralState = {
        modpack = definition and definition.modpack or nil,
        id = definition and definition.id or nil,
        name = definition and definition.name or nil,
        shortName = definition and definition.shortName or nil,
        affectsRunData = definition and definition.affectsRunData or nil,
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

function definitionInternal.prepare(owner, definition, ...)
    if select("#", ...) ~= 0 then
        internal.violate(
            "definition.invalid_args",
            "prepareDefinition: pass storage defaults on definition.storage nodes, not as a separate argument"
        )
    end
    if owner ~= nil and type(owner) ~= "table" then
        internal.violate("definition.invalid_args", "prepareDefinition: owner must be a table when provided")
    end
    if type(definition) ~= "table" then
        internal.violate("definition.invalid_args", "prepareDefinition: definition must be a table")
    end

    local prepared = values.deepCopy(definition)
    local label = definitionInternal.getLabel(prepared)
    InjectBuiltInStorage(prepared, label)

    definitionInternal.validate(prepared, label)
    storageInternal.validate(prepared.storage, label)

    local fingerprint = definitionInternal.getStructuralFingerprint(prepared)
    prepared._preparedDefinition = true
    prepared._structuralFingerprint = fingerprint

    if owner then
        local previousFingerprint = rawget(owner, "_definitionStructuralFingerprint")
        if previousFingerprint ~= nil and previousFingerprint ~= fingerprint then
            owner.requiresFullReload = true
            if type(prepared.modpack) == "string" and public.isModuleCoordinated(prepared.modpack) then
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

function public.prepareDefinition(owner, definition, ...)
    return definitionInternal.prepare(owner, definition, ...)
end
