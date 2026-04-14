local internal = AdamantModpackLib_Internal
local shared = internal.shared
public.accessors = public.accessors or {}
local accessors = public.accessors

local function StorageKey(key)
    local helper = shared.StorageKey
    if type(helper) == "function" then
        return helper(key)
    end
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end
shared.StorageKey = StorageKey

--- Reads a value from a table using either a flat key or a nested key path.
---@param tbl table Source table to read from.
---@param key string|table Direct key or ordered nested key path.
---@return any value Resolved value, or nil when the path does not exist.
---@return table|nil owner Table that owns the resolved key when found.
---@return string|number|nil finalKey Final key used on the owner table.
function accessors.readNestedPath(tbl, key)
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

--- Writes a value into a table using either a flat key or a nested key path.
---@param tbl table Destination table to write into.
---@param key string|table Direct key or ordered nested key path.
---@param value any Value to store at the resolved location.
function accessors.writeNestedPath(tbl, key, value)
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

local function GetBitValueMask(width)
    local normalizedWidth = math.floor(tonumber(width) or 0)
    if normalizedWidth <= 0 then
        return 0
    end
    if normalizedWidth >= 32 then
        return 0xFFFFFFFF
    end
    return bit32.rshift(0xFFFFFFFF, 32 - normalizedWidth)
end

--- Reads a bitfield value from a packed integer using an offset and width.
---@param packed number Packed integer source value.
---@param offset number Zero-based starting bit offset.
---@param width number Number of bits to read.
---@return number value Decoded integer value for the requested bit range.
function accessors.readPackedBits(packed, offset, width)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then
        return 0
    end
    return bit32.band(bit32.rshift(normalizedPacked, normalizedOffset), mask)
end

--- Writes a bitfield value into a packed integer using an offset and width.
---@param packed number Packed integer source value.
---@param offset number Zero-based starting bit offset.
---@param width number Number of bits to write.
---@param value number Decoded integer value to encode into the requested bit range.
---@return number packed Packed integer with the requested bit range updated.
function accessors.writePackedBits(packed, offset, width, value)
    local normalizedPacked = math.floor(tonumber(packed) or 0)
    local normalizedOffset = math.max(0, math.floor(tonumber(offset) or 0))
    local mask = GetBitValueMask(width)
    if mask == 0 then
        return normalizedPacked
    end

    local normalizedValue = math.floor(tonumber(value) or 0)
    if normalizedValue < 0 then
        normalizedValue = 0
    elseif normalizedValue > mask then
        normalizedValue = mask
    end

    local shiftedMask = bit32.lshift(mask, normalizedOffset)
    local cleared = bit32.band(normalizedPacked, bit32.bnot(shiftedMask))
    return bit32.bor(cleared, bit32.lshift(normalizedValue, normalizedOffset))
end
