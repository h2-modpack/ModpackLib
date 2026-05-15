local internal = AdamantModpackLib_Internal
internal.storage = internal.storage or {}

local typesModule = import('core/storage/private_types.lua', nil, {
    internal = internal,
    storage = internal.storage,
})
internal.storage.types = typesModule.types
internal.storage.NormalizeInteger = typesModule.NormalizeInteger

local packed = import('core/storage/private_packed.lua', nil, {
    internal = internal,
    storage = internal.storage,
    types = internal.storage.types,
})
internal.storage.packed = packed

local tableStorage = import('core/storage/private_table.lua', nil, {
    internal = internal,
    storage = internal.storage,
    types = internal.storage.types,
    values = internal.values,
})
internal.storage.table = tableStorage

local StorageTypes = internal.storage.types
local NormalizeInteger = internal.storage.NormalizeInteger
local values = internal.values

-- Storage schemas are prepared once by prepareDefinition, then treated as
-- runtime-stable metadata by store/session/Framework consumers. Validation is
-- fail-fast: the first structural contract violation stops preparation.
--
-- Supported root-axis combinations:
--   persist=true,  stage=true,  hash=true   -> config-backed UI/profile/hash state.
--   persist=true,  stage=true,  hash=false  -> config-backed UI state excluded from hashes.
--   persist=false, stage=true,  hash=false  -> transient staged UI state.
--   persist=true,  stage=false, hash=false  -> persistent runtime cache via store.writeUnstaged.
--   persist=false, stage=false, hash=false  -> in-memory runtime cache via store.writeUnstaged.
--
-- hash=true requires persist=true and stage=true. Table rows inherit their
-- table root axes. PackedInt roots currently require stage=true so root and
-- child aliases stay synchronized through the session surface.

---@alias StorageValueKind "'bool'"|"'int'"|"'string'"|"'table'"
---@alias StorageNodeType "'bool'"|"'int'"|"'string'"|"'packedInt'"|"'table'"

---@class PackedBitNode
---@field alias string
---@field label string|nil
---@field type "bool"|"int"
---@field default any
---@field min number|nil
---@field max number|nil
---@field offset number
---@field width number
---@field parent StorageNode|nil
---@field _isBitAlias boolean|nil
---@field _storageKey string|nil
---@field _valueKind StorageValueKind|nil

---@class StorageNode
---@field alias string
---@field label string|nil
---@field type StorageNodeType
---@field persist boolean|nil
---@field stage boolean|nil
---@field hash boolean|nil
---@field default any
---@field min number|nil
---@field max number|nil
---@field width number|nil
---@field maxLen number|nil
---@field bits PackedBitNode[]|nil
---@field row StorageSchema|nil
---@field minRows number|nil
---@field maxRows number|nil
---@field defaultRows number|nil
---@field _isRoot boolean|nil
---@field _persist boolean|nil
---@field _stage boolean|nil
---@field _hash boolean|nil
---@field _storageKey string|nil
---@field _valueKind StorageValueKind|nil
---@field _bitAliases PackedBitNode[]|nil

---@class StorageSchema: StorageNode[]
---@field _rootNodes StorageNode[]|nil Hash/profile root nodes.
---@field _persistRootNodes StorageNode[]|nil
---@field _stageRootNodes StorageNode[]|nil
---@field _runtimeCacheRootNodes StorageNode[]|nil
---@field _aliasNodes table<string, StorageNode|PackedBitNode>|nil

local CommonNodeFields = {
    alias = true,
    default = true,
    hash = true,
    label = true,
    persist = true,
    stage = true,
    tooltip = true,
    type = true,
    visibleIf = true,
}

local StableIdentifierPattern = "^[A-Za-z][A-Za-z0-9_]*$"
local StableIdentifierDescription = "must start with a letter and contain only letters, digits, and underscores"

local function IsStableIdentifier(value)
    return type(value) == "string" and string.match(value, StableIdentifierPattern) ~= nil
end

local RootNodeFieldsByType = {
    bool = {},
    int = {
        max = true,
        min = true,
        width = true,
    },
    string = {
        maxLen = true,
    },
    packedInt = {
        bits = true,
        width = true,
    },
    table = {
        defaultRows = true,
        maxRows = true,
        minRows = true,
        row = true,
    },
}

local function IsInternalField(key)
    return type(key) == "string" and string.sub(key, 1, 1) == "_"
end

local function ValidateKnownFields(node, allowedFields, prefix)
    for key in pairs(node) do
        if not IsInternalField(key) and not allowedFields[key] and not CommonNodeFields[key] then
            internal.violate("storage.unknown_field", "%s: unknown storage field '%s'", prefix, tostring(key))
        end
    end
end

local function PrepareRootNodeMetadata(node)
    node._storageKey = node.alias
end

local function ValidateAliasIdentifier(alias, prefix)
    if not IsStableIdentifier(alias) then
        internal.violate("storage.invalid_node", "%s: alias '%s' %s",
            prefix, tostring(alias), StableIdentifierDescription)
    end
end

local function PreparePackedChildAlias(bitNode, root, storage, seenAliases, seenRootKeys, prefix)
    if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
        return
    end
    ValidateAliasIdentifier(bitNode.alias, prefix)

    if seenAliases[bitNode.alias] then
        internal.violate("storage.duplicate_alias", "%s: duplicate alias '%s'", prefix, bitNode.alias)
    end
    local ownerKey = seenRootKeys[bitNode.alias]
    if ownerKey and ownerKey ~= root._storageKey then
        internal.violate("storage.duplicate_alias", "%s: alias '%s' conflicts with root alias '%s'", prefix, bitNode.alias, ownerKey)
    end

    local storageType = StorageTypes[bitNode.type]
    local child = {
        alias = bitNode.alias,
        label = bitNode.label or bitNode.alias,
        type = bitNode.type,
        default = bitNode.default,
        min = bitNode.min,
        max = bitNode.max,
        offset = bitNode.offset,
        width = bitNode.width,
        parent = root,
        _isBitAlias = true,
        _persist = root._persist,
        _stage = root._stage,
        _hash = root._hash,
        _storageKey = root._storageKey .. "." .. bitNode.alias,
        _valueKind = storageType and storageType.valueKind or bitNode.type,
    }
    if child.type == "bool" and child.default == nil then
        child.default = false
    end
    if child.type == "int" and child.default == nil then
        child.default = 0
    end

    seenAliases[child.alias] = true
    storage._aliasNodes[child.alias] = child
    root._bitAliases[#root._bitAliases + 1] = child
end

local function ValidatePersistedDefaults(storage, label)
    local prefix = label or "storage"
    for _, root in ipairs(rawget(storage, "_persistRootNodes") or {}) do
        if root.default == nil then
            internal.violate(
                "storage.missing_persisted_default",
                "%s: persisted storage alias '%s' must declare an effective default",
                prefix,
                tostring(root.alias or "<unknown>")
            )
        end
    end
end

--- Validates a storage schema and prepares its root, alias, and packed-bit metadata in place.
---@param storage StorageSchema Ordered list of storage root descriptors to validate.
---@param label string Validation label used to prefix warnings.
function internal.storage.validate(storage, label)
    if type(storage) ~= "table" then
        internal.violate("storage.invalid_schema", "%s: storage is not a table", label)
    end

    storage._rootNodes = {}
    storage._persistRootNodes = {}
    storage._stageRootNodes = {}
    storage._runtimeCacheRootNodes = {}
    storage._aliasNodes = {}

    local seenAliases = {}
    local seenRootKeys = {}

    for index, node in ipairs(storage) do
        local prefix = label .. " storage #" .. index
        if type(node) ~= "table" then
            internal.violate("storage.invalid_node", "%s: storage entry is not a table", prefix)
        elseif not node.type then
            internal.violate("storage.invalid_node", "%s: missing type", prefix)
        else
            local storageType = StorageTypes[node.type]
            local persist = node.persist ~= false
            local stage = node.stage ~= false
            local hash = node.hash ~= false
            if not storageType then
                internal.violate("storage.invalid_node", "%s: unknown storage type '%s'", prefix, tostring(node.type))
            elseif node.persist ~= nil and type(node.persist) ~= "boolean" then
                internal.violate("storage.invalid_axis_type", "%s: persist must be boolean when provided", prefix)
            elseif node.stage ~= nil and type(node.stage) ~= "boolean" then
                internal.violate("storage.invalid_axis_type", "%s: stage must be boolean when provided", prefix)
            elseif node.hash ~= nil and type(node.hash) ~= "boolean" then
                internal.violate("storage.invalid_axis_type", "%s: hash must be boolean when provided", prefix)
            elseif type(node.alias) ~= "string" or node.alias == "" then
                internal.violate("storage.invalid_node", "%s: missing alias", prefix)
            elseif hash and not persist then
                internal.violate("storage.hash_requires_persist", "%s: hash=true requires persist=true", prefix)
            elseif hash and not stage then
                internal.violate("storage.hash_requires_stage", "%s: hash=true requires stage=true", prefix)
            elseif not stage and node.type == "packedInt" then
                internal.violate("storage.packed_requires_stage", "%s: stage=false packedInt roots are not supported", prefix)
            else
                ValidateKnownFields(node, RootNodeFieldsByType[node.type] or {}, prefix)
                storageType.validate(node, prefix)
                ValidateAliasIdentifier(node.alias, prefix)
                PrepareRootNodeMetadata(node)
                node._isRoot = true
                node._persist = persist
                node._stage = stage
                node._hash = hash
                node._valueKind = storageType.valueKind
                node._bitAliases = {}

                if node._storageKey ~= nil then
                    if not seenRootKeys[node._storageKey] then
                        seenRootKeys[node._storageKey] = node._storageKey
                    end
                end

                local aliasValid = false
                if seenAliases[node.alias] then
                    internal.violate("storage.duplicate_alias", "%s: duplicate alias '%s'", prefix, node.alias)
                else
                    aliasValid = true
                    seenAliases[node.alias] = true
                    storage._aliasNodes[node.alias] = node
                end

                if node.type == "packedInt" then
                    packed.validatePackedBits(node, prefix)
                    for bitIndex, bitNode in ipairs(node.bits or {}) do
                        PreparePackedChildAlias(
                            bitNode,
                            node,
                            storage,
                            seenAliases,
                            seenRootKeys,
                            prefix .. " bits[" .. bitIndex .. "]"
                        )
                    end

                    if node.default == nil then
                        node.default = 0
                        for _, child in ipairs(node._bitAliases) do
                            local encoded = child.type == "bool"
                                and (child.default == true and 1 or 0)
                                or child.default
                            node.default = packed.writePackedBits(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = packed.readPackedBits(node.default, child.offset, child.width)
                            else
                                local expected = packed.readPackedBits(node.default, child.offset, child.width)
                                local normalized = StorageTypes[child.type].normalize(child, child.default)
                                local encoded = child.type == "bool"
                                    and (normalized == true and 1 or 0)
                                    or normalized
                                if expected ~= encoded then
                                    internal.violate(
                                        "storage.packed_child_default_mismatch",
                                        "%s: packed child default '%s' does not match packedInt default",
                                        prefix, child.alias)
                                end
                            end
                        end
                    end
                elseif node.type == "table" then
                    tableStorage.PrepareTableNode(node, prefix)
                end

                if node._persist then
                    table.insert(storage._persistRootNodes, node)
                end
                if node._stage then
                    table.insert(storage._stageRootNodes, node)
                else
                    table.insert(storage._runtimeCacheRootNodes, node)
                end
                if node._hash and aliasValid then
                    table.insert(storage._rootNodes, node)
                end
            end
        end
    end

    ValidatePersistedDefaults(storage, label)
end

--- Returns the prepared hash/profile root nodes for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of hash/profile root storage nodes.
function internal.storage.getRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_rootNodes") or {}
end

--- Returns prepared persisted root nodes for backing config hydration and access.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of persisted root storage nodes.
function internal.storage.getPersistRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_persistRootNodes") or {}
end

--- Returns prepared staged root nodes for session/UI state.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of staged root storage nodes.
function internal.storage.getStageRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_stageRootNodes") or {}
end

--- Returns prepared runtime-cache root nodes for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of stage=false root storage nodes.
function internal.storage.getRuntimeCacheRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_runtimeCacheRootNodes") or {}
end

--- Compares two values using storage-type equality when available, falling back to deep equality.
---@param node StorageNode|PackedBitNode|nil Storage node whose type-specific equality should be used.
---@param a any First value to compare.
---@param b any Second value to compare.
---@return boolean equal True when the two values are considered equivalent for the storage node.
function internal.storage.valuesEqual(node, a, b)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and storageType.equals ~= nil then
        return storageType.equals(node, a, b)
    end
    return values.deepEqual(a, b)
end

function internal.storage.NormalizeStorageValue(node, value)
    local storageType = node and node.type and internal.storage.types[node.type] or nil
    if storageType and storageType.normalize ~= nil then
        return storageType.normalize(node, value)
    end
    return value
end

--- Reads a declared alias through a backend that owns root-value storage.
---@param aliasNodes table<string, StorageNode|PackedBitNode>
---@param backend table
---@param alias string
---@return any
function internal.storage.readAlias(aliasNodes, backend, alias)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend and backend.onUnknownRead ~= nil then
            backend.onUnknownRead(alias)
        end
        return nil
    end

    if backend and backend.canRead ~= nil and backend.canRead(node, alias) == false then
        return nil
    end

    if node._isBitAlias then
        return packed.DecodePackedChild(node, backend.readRoot(node.parent))
    end
    return backend.readRoot(node)
end

--- Writes a declared alias through a backend that owns root-value storage.
---@param aliasNodes table<string, StorageNode|PackedBitNode>
---@param backend table
---@param alias string
---@param value any
---@return boolean changed
function internal.storage.writeAlias(aliasNodes, backend, alias, value)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend and backend.onUnknownWrite ~= nil then
            backend.onUnknownWrite(alias)
        end
        return false
    end

    if backend and backend.canWrite ~= nil and backend.canWrite(node, alias) == false then
        return false
    end

    if node._isBitAlias then
        local parent = node.parent
        local currentPacked = backend.readRoot(parent)
        local normalized = internal.storage.NormalizeStorageValue(node, value)
        local currentValue = packed.DecodePackedChild(node, currentPacked)
        if internal.storage.valuesEqual(node, currentValue, normalized) then
            return false
        end

        local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
        local nextPacked = packed.writePackedBits(currentPacked, node.offset, node.width, encoded)
        if internal.storage.valuesEqual(parent, currentPacked, nextPacked) then
            if backend.writeAliasValue ~= nil then
                backend.writeAliasValue(node, normalized)
            end
            return false
        end

        local changed = backend.writeRoot(parent, nextPacked)
        if backend.writeAliasValue ~= nil then
            backend.writeAliasValue(node, normalized)
        end
        return changed ~= false
    end

    return backend.writeRoot(node, value) ~= false
end

--- Returns the prepared alias map for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return table<string, StorageNode|PackedBitNode> aliases Map from storage alias to prepared storage node.
function internal.storage.getAliases(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_aliasNodes") or {}
end
