local internal = AdamantModpackLib_Internal
internal.storage = internal.storage or {}
local storageInternal = internal.storage
local StorageTypes = storageInternal.types
local NormalizeInteger = storageInternal.NormalizeInteger
local values = internal.values

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

local function PrepareRootNodeMetadata(node)
    node._storageKey = node.alias
end

local function ClampRowCount(node, count)
    count = math.floor(tonumber(count) or 0)
    if count < 0 then count = 0 end
    if node.minRows ~= nil and count < node.minRows then count = node.minRows end
    if node.maxRows ~= nil and count > node.maxRows then count = node.maxRows end
    return count
end

local function PrepareTableNode(node, prefix)
    if type(node.row) ~= "table" then
        return
    end

    for index, rowNode in ipairs(node.row) do
        local rowPrefix = prefix .. " row[" .. index .. "]"
        if type(rowNode) == "table" then
            if rowNode.type == "table" then
                internal.violate("storage.invalid_table_row", "%s: nested table storage is not supported", rowPrefix)
            end
            if rowNode.persist ~= nil then
                internal.violate(
                    "storage.invalid_table_row",
                    "%s: row storage cannot declare persist; table root owns persistence",
                    rowPrefix
                )
            end
            if rowNode.stage ~= nil then
                internal.violate("storage.invalid_table_row", "%s: row storage cannot declare stage; table root owns staging", rowPrefix)
            end
            if rowNode.hash ~= nil then
                internal.violate("storage.invalid_table_row", "%s: row storage cannot declare hash; table root owns hashing", rowPrefix)
            end
        end
    end

    storageInternal.validate(node.row, prefix .. " row")

    node.minRows = ClampRowCount({ minRows = 0 }, node.minRows or 0)
    node.maxRows = node.maxRows ~= nil and ClampRowCount({ minRows = 0 }, node.maxRows) or nil
    if node.maxRows ~= nil and node.minRows > node.maxRows then
        node.minRows = node.maxRows
    end
    node.defaultRows = ClampRowCount(node, node.defaultRows or node.minRows or 0)
    node.default = storageInternal.NormalizeTableValue(node, nil)
    node._tableDefaultPrepared = true
end

local function ValidateChildAlias(bitNode, root, storage, seenAliases, seenRootKeys, prefix)
    if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
        return
    end

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

local function ValidatePackedBits(node, prefix)
    local seenAliases = {}
    local occupiedBits = {}
    for index, bitNode in ipairs(node.bits or {}) do
        local bitPrefix = prefix .. " bits[" .. index .. "]"
        if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
            internal.violate("storage.invalid_packed_bit", "%s: packed bit alias must be a non-empty string", bitPrefix)
        elseif seenAliases[bitNode.alias] then
            internal.violate("storage.duplicate_alias", "%s: duplicate packed bit alias '%s'", bitPrefix, bitNode.alias)
        else
            seenAliases[bitNode.alias] = true
        end
        if type(bitNode.offset) ~= "number" or bitNode.offset < 0 then
            internal.violate("storage.invalid_packed_bit", "%s: packed bit offset must be a non-negative number", bitPrefix)
        end
        if type(bitNode.width) ~= "number" or bitNode.width < 1 then
            internal.violate("storage.invalid_packed_bit", "%s: packed bit width must be a positive number", bitPrefix)
        end

        if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
            local offset = math.floor(bitNode.offset)
            local width = math.floor(bitNode.width)
            if offset + width > 32 then
                internal.violate("storage.invalid_packed_bit", "%s: packed bit offset + width must stay within 32 bits", bitPrefix)
            end
            for bit = offset, offset + width - 1 do
                if occupiedBits[bit] then
                    internal.violate("storage.invalid_packed_bit", "%s: packed bit overlaps bit %d", bitPrefix, bit)
                else
                    occupiedBits[bit] = true
                end
            end
            bitNode.offset = offset
            bitNode.width = width
        end

        local valueType = bitNode.type or (bitNode.width == 1 and "bool" or "int")
        if valueType ~= "bool" and valueType ~= "int" then
            internal.violate("storage.invalid_packed_bit", "%s: packed bit type must be 'bool' or 'int'", bitPrefix)
        end
        bitNode.type = valueType
        local storageType = StorageTypes[valueType]
        if storageType then
            storageType.validate(bitNode, bitPrefix)
        end
    end
end

local function EnsurePreparedStorage(storage, label)
    if type(storage) ~= "table" then
        return {}
    end
    if rawget(storage, "_aliasNodes") ~= nil and rawget(storage, "_rootNodes") ~= nil then
        return storage._aliasNodes
    end
    storageInternal.validate(storage, label or "storage")
    return storageInternal.getAliases(storage)
end

storageInternal.EnsurePreparedStorage = EnsurePreparedStorage

--- Validates a storage schema and prepares its root, alias, and packed-bit metadata in place.
---@param storage StorageSchema Ordered list of storage root descriptors to validate.
---@param label string Validation label used to prefix warnings.
function storageInternal.validate(storage, label)
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
                storageType.validate(node, prefix)
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
                    ValidatePackedBits(node, prefix)
                    for bitIndex, bitNode in ipairs(node.bits or {}) do
                        ValidateChildAlias(
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
                            node.default = storageInternal.writePackedBits(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = storageInternal.readPackedBits(node.default, child.offset, child.width)
                            else
                                local expected = storageInternal.readPackedBits(node.default, child.offset, child.width)
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
                    PrepareTableNode(node, prefix)
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

    storageInternal.validatePersistedDefaults(storage, label)
end

--- Validates that every persisted root has an effective storage-declared default.
---@param storage StorageSchema
---@param label string
function storageInternal.validatePersistedDefaults(storage, label)
    local prefix = label or "storage"
    for _, root in ipairs(storageInternal.getPersistRoots(storage) or {}) do
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

--- Returns the prepared hash/profile root nodes for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of hash/profile root storage nodes.
function storageInternal.getRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_rootNodes") or {}
end

--- Returns prepared persisted root nodes for backing config hydration and access.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of persisted root storage nodes.
function storageInternal.getPersistRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_persistRootNodes") or {}
end

--- Returns prepared staged root nodes for session/UI state.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of staged root storage nodes.
function storageInternal.getStageRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_stageRootNodes") or {}
end

--- Returns prepared runtime-cache root nodes for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return StorageNode[] roots Prepared list of stage=false root storage nodes.
function storageInternal.getRuntimeCacheRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_runtimeCacheRootNodes") or {}
end

--- Compares two values using storage-type equality when available, falling back to deep equality.
---@param node StorageNode|PackedBitNode|nil Storage node whose type-specific equality should be used.
---@param a any First value to compare.
---@param b any Second value to compare.
---@return boolean equal True when the two values are considered equivalent for the storage node.
function storageInternal.valuesEqual(node, a, b)
    local storageType = node and StorageTypes and node.type and StorageTypes[node.type] or nil
    if storageType and type(storageType.equals) == "function" then
        return storageType.equals(node, a, b)
    end
    return values.deepEqual(a, b)
end

function storageInternal.NormalizeStorageValue(node, value)
    local storageType = node and node.type and storageInternal.types[node.type] or nil
    if storageType and type(storageType.normalize) == "function" then
        return storageType.normalize(node, value)
    end
    return value
end

local function GetRowAliasNodes(node)
    return node and node.row and storageInternal.getAliases(node.row) or {}
end

local function GetRowRootNodes(node)
    return node and node.row and storageInternal.getRoots(node.row) or {}
end

local function CreateDefaultTableRow(node)
    local row = {}
    for _, root in ipairs(GetRowRootNodes(node)) do
        row[root.alias] = values.deepCopy(root.default)
    end
    return row
end

function storageInternal.NormalizeTableRow(node, rowValue)
    local row = CreateDefaultTableRow(node)
    if type(rowValue) ~= "table" then
        return row
    end
    local aliasNodes = GetRowAliasNodes(node)

    for _, root in ipairs(GetRowRootNodes(node)) do
        if rowValue[root.alias] ~= nil then
            row[root.alias] = storageInternal.NormalizeStorageValue(root, rowValue[root.alias])
        end
    end

    local rowBackend = {
        readRoot = function(root)
            local value = row[root.alias]
            if value == nil then
                value = values.deepCopy(root.default)
            end
            return storageInternal.NormalizeStorageValue(root, value)
        end,
        writeRoot = function(root, value)
            row[root.alias] = storageInternal.NormalizeStorageValue(root, value)
            return true
        end,
    }

    for alias, value in pairs(rowValue) do
        if aliasNodes[alias] ~= nil then
            storageInternal.writeAlias(aliasNodes, rowBackend, alias, value)
        end
    end

    return row
end

function storageInternal.NormalizeTableValue(node, value)
    local rows = {}
    local source = type(value) == "table" and value or nil
    local count = source and #source or node.defaultRows or 0
    count = ClampRowCount(node, count)

    for index = 1, count do
        rows[index] = storageInternal.NormalizeTableRow(node, source and source[index] or nil)
    end
    return rows
end

local function EncodeLengthPrefixed(value)
    value = tostring(value or "")
    return tostring(#value) .. ":" .. value
end

local function DecodeLengthPrefixed(str, pos)
    local lenText, nextPos = string.match(str, "^(%d+):()", pos)
    if not lenText then
        return nil, nil
    end
    local len = tonumber(lenText) or 0
    local valueStart = nextPos
    local valueEnd = valueStart + len - 1
    if valueEnd > #str then
        return nil, nil
    end
    return string.sub(str, valueStart, valueEnd), valueEnd + 1
end

function storageInternal.SerializeTableValue(node, value)
    local rows = storageInternal.NormalizeTableValue(node, value)
    local parts = { tostring(#rows) .. ":" }
    for _, row in ipairs(rows) do
        for _, root in ipairs(GetRowRootNodes(node)) do
            local storageType = StorageTypes[root.type]
            local encoded = storageType.toHash(root, row[root.alias])
            parts[#parts + 1] = EncodeLengthPrefixed(encoded)
        end
    end
    return table.concat(parts)
end

function storageInternal.DeserializeTableValue(node, str)
    if type(str) ~= "string" then
        return storageInternal.NormalizeTableValue(node, nil)
    end

    local countText, pos = string.match(str, "^(%d+):()")
    if not countText then
        return storageInternal.NormalizeTableValue(node, nil)
    end

    local rows = {}
    local count = ClampRowCount(node, tonumber(countText) or 0)
    local roots = GetRowRootNodes(node)
    for rowIndex = 1, count do
        local row = {}
        for _, root in ipairs(roots) do
            local encoded
            encoded, pos = DecodeLengthPrefixed(str, pos)
            if encoded == nil then
                return storageInternal.NormalizeTableValue(node, nil)
            end
            local storageType = StorageTypes[root.type]
            row[root.alias] = storageType.fromHash(root, encoded)
        end
        rows[rowIndex] = storageInternal.NormalizeTableRow(node, row)
    end
    return storageInternal.NormalizeTableValue(node, rows)
end

function storageInternal.CreateTableHandle(node, opts)
    opts = opts or {}
    local aliasNodes = GetRowAliasNodes(node)

    local function readRows()
        local rows = opts.readRoot(node)
        if opts.normalizedRoot == true then
            return type(rows) == "table" and rows or node.default
        end
        return storageInternal.NormalizeTableValue(node, rows)
    end

    local function copyRows()
        if opts.normalizedRoot == true then
            return values.deepCopy(readRows())
        end
        return readRows()
    end

    local function writeRows(rows)
        if type(opts.writeRoot) ~= "function" then
            internal.violate("storage.readonly_table_handle", "table storage handle is read-only")
        end
        return opts.writeRoot(node, storageInternal.NormalizeTableValue(node, rows))
    end

    local function readRow(rows, rowIndex)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        return rows[rowIndex], rowIndex
    end

    local function readRowAlias(row, alias)
        local rowBackend = {
            readRoot = function(root)
                local value = row[root.alias]
                if value == nil then
                    value = values.deepCopy(root.default)
                end
                return storageInternal.NormalizeStorageValue(root, value)
            end,
        }
        return storageInternal.readAlias(aliasNodes, rowBackend, alias)
    end

    local function writeRowAlias(row, alias, value)
        local rowBackend = {
            readRoot = function(root)
                local raw = row[root.alias]
                if raw == nil then
                    raw = values.deepCopy(root.default)
                end
                return storageInternal.NormalizeStorageValue(root, raw)
            end,
            writeRoot = function(root, rootValue)
                row[root.alias] = storageInternal.NormalizeStorageValue(root, rootValue)
                return true
            end,
        }
        return storageInternal.writeAlias(aliasNodes, rowBackend, alias, value)
    end

    local handle = {}

    local function ShiftMethodArgs(first, second, third, fourth)
        if first == handle then
            return second, third, fourth
        end
        return first, second, third
    end

    function handle.count()
        return #readRows()
    end

    function handle.read(first, second, third)
        local rowIndex, alias = ShiftMethodArgs(first, second, third)
        local row = readRow(readRows(), rowIndex)
        if not row then
            return nil
        end
        return readRowAlias(row, alias)
    end

    function handle.row(first, second)
        local rowIndex = ShiftMethodArgs(first, second)
        local row = readRow(readRows(), rowIndex)
        return row and values.deepCopy(row) or nil
    end

    function handle.rows()
        return values.deepCopy(readRows())
    end

    if type(opts.writeRoot) == "function" then
        function handle.write(first, second, third, fourth)
            local rowIndex, alias, value = ShiftMethodArgs(first, second, third, fourth)
            local rows = copyRows()
            local row = readRow(rows, rowIndex)
            if not row then
                return false
            end
            local changed = writeRowAlias(row, alias, value)
            if changed then
                writeRows(rows)
            end
            return changed
        end

        function handle.reset(first, second, third)
            local rowIndex, alias = ShiftMethodArgs(first, second, third)
            local rows = copyRows()
            local row = readRow(rows, rowIndex)
            if not row then
                return false
            end
            local aliasNode = aliasNodes[alias]
            if not aliasNode then
                return false
            end
            local changed = writeRowAlias(row, alias, values.deepCopy(aliasNode.default))
            if changed then
                writeRows(rows)
            end
            return changed
        end

        function handle.resetRow(first, second)
            local rowIndex = ShiftMethodArgs(first, second)
            local rows = copyRows()
            local _, normalizedIndex = readRow(rows, rowIndex)
            if normalizedIndex < 1 or normalizedIndex > #rows then
                return false
            end
            rows[normalizedIndex] = CreateDefaultTableRow(node)
            writeRows(rows)
            return true
        end

        function handle.append(first, second)
            local rowValues = ShiftMethodArgs(first, second)
            local rows = copyRows()
            if node.maxRows ~= nil and #rows >= node.maxRows then
                return false
            end
            rows[#rows + 1] = storageInternal.NormalizeTableRow(node, rowValues)
            writeRows(rows)
            return true
        end

        function handle.insert(first, second, third)
            local rowIndex, rowValues = ShiftMethodArgs(first, second, third)
            local rows = copyRows()
            if node.maxRows ~= nil and #rows >= node.maxRows then
                return false
            end
            rowIndex = math.floor(tonumber(rowIndex) or (#rows + 1))
            if rowIndex < 1 then rowIndex = 1 end
            if rowIndex > #rows + 1 then rowIndex = #rows + 1 end
            table.insert(rows, rowIndex, storageInternal.NormalizeTableRow(node, rowValues))
            writeRows(rows)
            return true
        end

        function handle.remove(first, second)
            local rowIndex = ShiftMethodArgs(first, second)
            local rows = copyRows()
            rowIndex = math.floor(tonumber(rowIndex) or 0)
            if rowIndex < 1 or rowIndex > #rows then
                return false
            end
            table.remove(rows, rowIndex)
            writeRows(rows)
            return true
        end

        function handle.clear()
            writeRows({})
            return true
        end
    end

    return handle
end

local function DecodePackedChild(node, packedValue)
    local rawValue = storageInternal.readPackedBits(packedValue, node.offset, node.width)
    if node.type == "bool" then
        rawValue = rawValue ~= 0
    end
    return storageInternal.NormalizeStorageValue(node, rawValue)
end

storageInternal.DecodePackedChild = DecodePackedChild

--- Reads a declared alias through a backend that owns root-value storage.
---@param aliasNodes table<string, StorageNode|PackedBitNode>
---@param backend table
---@param alias string
---@return any
function storageInternal.readAlias(aliasNodes, backend, alias)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend and type(backend.onUnknownRead) == "function" then
            backend.onUnknownRead(alias)
        end
        return nil
    end

    if backend and type(backend.canRead) == "function" and backend.canRead(node, alias) == false then
        return nil
    end

    if node._isBitAlias then
        return DecodePackedChild(node, backend.readRoot(node.parent))
    end
    return backend.readRoot(node)
end

--- Writes a declared alias through a backend that owns root-value storage.
---@param aliasNodes table<string, StorageNode|PackedBitNode>
---@param backend table
---@param alias string
---@param value any
---@return boolean changed
function storageInternal.writeAlias(aliasNodes, backend, alias, value)
    local node = type(alias) == "string" and aliasNodes[alias] or nil
    if not node then
        if backend and type(backend.onUnknownWrite) == "function" then
            backend.onUnknownWrite(alias)
        end
        return false
    end

    if backend and type(backend.canWrite) == "function" and backend.canWrite(node, alias) == false then
        return false
    end

    if node._isBitAlias then
        local parent = node.parent
        local currentPacked = backend.readRoot(parent)
        local normalized = storageInternal.NormalizeStorageValue(node, value)
        local currentValue = DecodePackedChild(node, currentPacked)
        if storageInternal.valuesEqual(node, currentValue, normalized) then
            return false
        end

        local encoded = node.type == "bool" and (normalized and 1 or 0) or normalized
        local nextPacked = storageInternal.writePackedBits(currentPacked, node.offset, node.width, encoded)
        if storageInternal.valuesEqual(parent, currentPacked, nextPacked) then
            if type(backend.writeAliasValue) == "function" then
                backend.writeAliasValue(node, normalized)
            end
            return false
        end

        local changed = backend.writeRoot(parent, nextPacked)
        if type(backend.writeAliasValue) == "function" then
            backend.writeAliasValue(node, normalized)
        end
        return changed ~= false
    end

    return backend.writeRoot(node, value) ~= false
end

--- Returns the prepared alias map for a validated storage schema.
---@param storage StorageSchema Validated storage schema.
---@return table<string, StorageNode|PackedBitNode> aliases Map from storage alias to prepared storage node.
function storageInternal.getAliases(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_aliasNodes") or {}
end
