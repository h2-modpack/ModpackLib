local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry
local NormalizeInteger = registry.NormalizeInteger

StorageTypes.bool = {
    valueKind = "bool",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: bool default must be boolean, got %s", prefix, type(node.default))
        end
    end,
    normalize = function(_, value)
        return value == true
    end,
    toHash = function(_, value)
        return value and "1" or "0"
    end,
    fromHash = function(_, str)
        return str == "1"
    end,
    packWidth = function(_)
        return 1
    end,
}

StorageTypes.int = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            libWarn("%s: int default must be number, got %s", prefix, type(node.default))
        end
        if node.min ~= nil and type(node.min) ~= "number" then
            libWarn("%s: int min must be number, got %s", prefix, type(node.min))
        end
        if node.max ~= nil and type(node.max) ~= "number" then
            libWarn("%s: int max must be number, got %s", prefix, type(node.max))
        end
        if type(node.min) == "number" and type(node.max) == "number" and node.min > node.max then
            libWarn("%s: int min cannot exceed max", prefix)
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1) then
            libWarn("%s: int width must be a positive number", prefix)
        end
    end,
    normalize = function(node, value)
        return NormalizeInteger(node, value)
    end,
    toHash = function(node, value)
        return tostring(NormalizeInteger(node, value))
    end,
    fromHash = function(node, str)
        return NormalizeInteger(node, tonumber(str))
    end,
    packWidth = function(node)
        if type(node.width) == "number" and node.width >= 1 then
            return math.floor(node.width)
        end
        if type(node.min) == "number" and type(node.max) == "number" then
            local range = node.max - node.min
            if range <= 0 then return 1 end
            return math.ceil(math.log(range + 1) / math.log(2))
        end
        return nil
    end,
}

StorageTypes.string = {
    valueKind = "string",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "string" then
            libWarn("%s: string default must be string, got %s", prefix, type(node.default))
        end
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: string maxLen must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 256)
        if node._maxLen < 1 then node._maxLen = 256 end
    end,
    normalize = function(node, value)
        return value ~= nil and tostring(value) or (node.default or "")
    end,
    toHash = function(_, value)
        return tostring(value or "")
    end,
    fromHash = function(node, str)
        return str ~= nil and tostring(str) or (node.default or "")
    end,
}

StorageTypes.packedInt = {
    valueKind = "int",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "number" then
            libWarn("%s: packedInt default must be number, got %s", prefix, type(node.default))
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1 or node.width > 32) then
            libWarn("%s: packedInt width must be a positive number no greater than 32", prefix)
        end
        if type(node.bits) ~= "table" or #node.bits == 0 then
            libWarn("%s: packedInt bits must be a non-empty list", prefix)
            return
        end

        local seenAliases = {}
        local occupiedBits = {}
        for index, bitNode in ipairs(node.bits) do
            local bitPrefix = prefix .. " bits[" .. index .. "]"
            if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
                libWarn("%s: packed bit alias must be a non-empty string", bitPrefix)
            elseif seenAliases[bitNode.alias] then
                libWarn("%s: duplicate packed bit alias '%s'", bitPrefix, bitNode.alias)
            else
                seenAliases[bitNode.alias] = true
            end
            if type(bitNode.offset) ~= "number" or bitNode.offset < 0 then
                libWarn("%s: packed bit offset must be a non-negative number", bitPrefix)
            end
            if type(bitNode.width) ~= "number" or bitNode.width < 1 then
                libWarn("%s: packed bit width must be a positive number", bitPrefix)
            end

            if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
                local offset = math.floor(bitNode.offset)
                local width = math.floor(bitNode.width)
                if offset + width > 32 then
                    libWarn("%s: packed bit offset + width must stay within 32 bits", bitPrefix)
                end
                for bit = offset, offset + width - 1 do
                    if occupiedBits[bit] then
                        libWarn("%s: packed bit overlaps bit %d", bitPrefix, bit)
                    else
                        occupiedBits[bit] = true
                    end
                end
                bitNode.offset = offset
                bitNode.width = width
            end

            local valueType = bitNode.type or (bitNode.width == 1 and "bool" or "int")
            if valueType ~= "bool" and valueType ~= "int" then
                libWarn("%s: packed bit type must be 'bool' or 'int'", bitPrefix)
                valueType = bitNode.width == 1 and "bool" or "int"
            end
            bitNode.type = valueType
            local storageType = StorageTypes[valueType]
            if storageType then
                storageType.validate(bitNode, bitPrefix)
            end
        end
    end,
    normalize = function(node, value)
        return NormalizeInteger(node, value)
    end,
    toHash = function(node, value)
        return tostring(NormalizeInteger(node, value))
    end,
    fromHash = function(node, str)
        return NormalizeInteger(node, tonumber(str))
    end,
    packWidth = function(node)
        if type(node.width) == "number" and node.width >= 1 and node.width <= 32 then
            return math.floor(node.width)
        end
        if type(node.bits) ~= "table" then
            return nil
        end
        local maxUsedBit = 0
        for _, bitNode in ipairs(node.bits) do
            if type(bitNode.offset) == "number" and type(bitNode.width) == "number" then
                local used = math.floor(bitNode.offset) + math.floor(bitNode.width)
                if used > maxUsedBit then
                    maxUsedBit = used
                end
            end
        end
        if maxUsedBit > 0 and maxUsedBit <= 32 then
            return maxUsedBit
        end
        return nil
    end,
}

local function PrepareRootNodeMetadata(node)
    node._storageKey = shared.StorageKey(node.configKey)
    if not node.alias then
        node.alias = node._storageKey
    end
end

local function ValidateChildAlias(bitNode, root, storage, seenAliases, seenRootKeys, prefix)
    if type(bitNode.alias) ~= "string" or bitNode.alias == "" then
        return
    end

    if seenAliases[bitNode.alias] then
        libWarn("%s: duplicate alias '%s'", prefix, bitNode.alias)
        return
    end
    local ownerKey = seenRootKeys[bitNode.alias]
    if ownerKey and ownerKey ~= root._storageKey then
        libWarn("%s: alias '%s' conflicts with root configKey '%s'", prefix, bitNode.alias, ownerKey)
        return
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

function public.validateStorage(storage, label)
    if type(storage) ~= "table" then
        libWarn("%s: storage is not a table", label)
        return
    end

    storage._rootNodes = {}
    storage._aliasNodes = {}
    storage._rootByKey = {}

    local seenAliases = {}
    local seenRootKeys = {}

    for index, node in ipairs(storage) do
        local prefix = label .. " storage #" .. index
        if type(node) ~= "table" then
            libWarn("%s: storage entry is not a table", prefix)
        elseif not node.type then
            libWarn("%s: missing type", prefix)
        else
            local storageType = StorageTypes[node.type]
            if not storageType then
                libWarn("%s: unknown storage type '%s'", prefix, tostring(node.type))
            elseif node.type == "packedInt" and node.configKey == nil then
                libWarn("%s: packedInt is missing configKey", prefix)
            elseif node.configKey == nil then
                libWarn("%s: missing configKey", prefix)
            else
                storageType.validate(node, prefix)
                PrepareRootNodeMetadata(node)
                node._isRoot = true
                node._valueKind = storageType.valueKind
                node._bitAliases = {}

                if seenRootKeys[node._storageKey] then
                    libWarn("%s: duplicate configKey '%s'", prefix, node._storageKey)
                else
                    seenRootKeys[node._storageKey] = node._storageKey
                    storage._rootByKey[node._storageKey] = node
                end

                if type(node.alias) ~= "string" or node.alias == "" then
                    libWarn("%s: missing alias", prefix)
                elseif seenAliases[node.alias] then
                    libWarn("%s: duplicate alias '%s'", prefix, node.alias)
                else
                    seenAliases[node.alias] = true
                    storage._aliasNodes[node.alias] = node
                end

                if node.type == "packedInt" then
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
                            node.default = public.writeBitsValue(node.default, child.offset, child.width, encoded)
                        end
                    else
                        node.default = NormalizeInteger(node, node.default)
                        for _, child in ipairs(node._bitAliases) do
                            if child.default == nil then
                                child.default = public.readBitsValue(node.default, child.offset, child.width)
                            else
                                local expected = public.readBitsValue(node.default, child.offset, child.width)
                                local normalized = StorageTypes[child.type].normalize(child, child.default)
                                if expected ~= normalized then
                                    libWarn("%s: packed child default '%s' does not match packedInt default",
                                        prefix, child.alias)
                                end
                            end
                        end
                    end
                end

                table.insert(storage._rootNodes, node)
            end
        end
    end
end

function public.getStorageRoots(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_rootNodes") or {}
end

function public.getPackWidth(node)
    if type(node) ~= "table" then return nil end
    local storageType = StorageTypes[node.type]
    if storageType and storageType.packWidth then
        return storageType.packWidth(node)
    end
    return nil
end

function public.getStorageAliases(storage)
    if type(storage) ~= "table" then return {} end
    return rawget(storage, "_aliasNodes") or {}
end

local function EnsurePreparedStorage(storage, label)
    if type(storage) ~= "table" then
        return {}
    end
    if rawget(storage, "_aliasNodes") ~= nil and rawget(storage, "_rootNodes") ~= nil then
        return storage._aliasNodes
    end
    public.validateStorage(storage, label or "storage")
    return public.getStorageAliases(storage)
end

registry.EnsurePreparedStorage = EnsurePreparedStorage
