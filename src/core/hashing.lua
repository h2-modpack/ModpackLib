local internal = AdamantModpackLib_Internal
local storageInternal = internal.storage
local StorageTypes = storageInternal.types

public.hashing = public.hashing or {}
local hashingApi = public.hashing

---@param storage StorageSchema
---@return StorageNode[]
function hashingApi.getRoots(storage)
    return storageInternal.getRoots(storage)
end

---@param storage StorageSchema
---@return table<string, StorageNode|PackedBitNode>
function hashingApi.getAliases(storage)
    return storageInternal.getAliases(storage)
end

---@param node StorageNode|PackedBitNode|nil
---@param a any
---@param b any
---@return boolean
function hashingApi.valuesEqual(node, a, b)
    return storageInternal.valuesEqual(node, a, b)
end

--- Returns the packed bit width for a node type, or nil when the node is not packable.
---@param node StorageNode|PackedBitNode
---@return number|nil
function hashingApi.getPackWidth(node)
    if type(node) ~= "table" then return nil end
    local storageType = StorageTypes[node.type]
    if storageType and storageType.packWidth then
        return storageType.packWidth(node)
    end
    return nil
end

---@param node StorageNode|PackedBitNode
---@param value any
---@return string|nil
function hashingApi.toHash(node, value)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.toHash(node, value)
end

---@param node StorageNode|PackedBitNode
---@param str string
---@return any
function hashingApi.fromHash(node, str)
    local storageType = node and node.type and StorageTypes[node.type] or nil
    if not storageType then
        return nil
    end
    return storageType.fromHash(node, str)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@return number
function hashingApi.readPackedBits(packed, offset, width)
    return storageInternal.readPackedBits(packed, offset, width)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@param value number|nil
---@return number
function hashingApi.writePackedBits(packed, offset, width, value)
    return storageInternal.writePackedBits(packed, offset, width, value)
end
