local internal = AdamantModpackLib_Internal
internal.storage = internal.storage or {}

local storage = internal.storage
local StorageTypes = {}

storage.types = StorageTypes

local function NormalizeInteger(node, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(node.default) or 0
    end
    num = math.floor(num)
    if node.min ~= nil and num < node.min then num = node.min end
    if node.max ~= nil and num > node.max then num = node.max end
    return num
end

storage.NormalizeInteger = NormalizeInteger

local function GetBitValueMask(width)
    local normalizedWidth = math.floor(tonumber(width) or 0)
    if normalizedWidth <= 0 then return 0 end
    if normalizedWidth >= 32 then return 0xFFFFFFFF end
    return bit32.rshift(0xFFFFFFFF, 32 - normalizedWidth)
end

storage.GetBitValueMask = GetBitValueMask

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@return number
function storage.readPackedBits(packed, offset, width)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then return 0 end
    return bit32.band(bit32.rshift(normalizedPacked, normalizedOffset), mask)
end

---@param packed number|nil
---@param offset number|nil
---@param width number|nil
---@param value number|nil
---@return number
function storage.writePackedBits(packed, offset, width, value)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then return normalizedPacked end
    local normalizedValue = math.floor(tonumber(value) or 0)
    if normalizedValue < 0 then normalizedValue = 0
    elseif normalizedValue > mask then normalizedValue = mask end
    local shiftedMask = bit32.lshift(mask, normalizedOffset)
    local cleared = bit32.band(normalizedPacked, bit32.bnot(shiftedMask))
    return bit32.bor(cleared, bit32.lshift(normalizedValue, normalizedOffset))
end

StorageTypes.bool = {
    valueKind = "bool",
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            internal.libWarnIf("%s: bool default must be boolean, got %s", prefix, type(node.default))
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
            internal.libWarnIf("%s: int default must be number, got %s", prefix, type(node.default))
        end
        if node.min ~= nil and type(node.min) ~= "number" then
            internal.libWarnIf("%s: int min must be number, got %s", prefix, type(node.min))
        end
        if node.max ~= nil and type(node.max) ~= "number" then
            internal.libWarnIf("%s: int max must be number, got %s", prefix, type(node.max))
        end
        if type(node.min) == "number" and type(node.max) == "number" and node.min > node.max then
            internal.libWarnIf("%s: int min cannot exceed max", prefix)
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1) then
            internal.libWarnIf("%s: int width must be a positive number", prefix)
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
            internal.libWarnIf("%s: string default must be string, got %s", prefix, type(node.default))
        end
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            internal.libWarnIf("%s: string maxLen must be a positive number", prefix)
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
            internal.libWarnIf("%s: packedInt default must be number, got %s", prefix, type(node.default))
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width < 1 or node.width > 32) then
            internal.libWarnIf("%s: packedInt width must be a positive number no greater than 32", prefix)
        end
        if type(node.bits) ~= "table" or #node.bits == 0 then
            internal.libWarnIf("%s: packedInt bits must be a non-empty list", prefix)
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
