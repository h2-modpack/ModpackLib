local internal = AdamantModpackLib_Internal
internal.values = internal.values or {}

function internal.values.readPath(tbl, key)
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

function internal.values.writePath(tbl, key, value)
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

function internal.values.deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[internal.values.deepCopy(key, seen)] = internal.values.deepCopy(child, seen)
    end
    return copy
end

function internal.values.deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    seen = seen or {}
    local seenForA = seen[a]
    if seenForA and seenForA[b] then
        return true
    end
    if not seenForA then
        seenForA = {}
        seen[a] = seenForA
    end
    seenForA[b] = true

    for key, value in pairs(a) do
        if not internal.values.deepEqual(value, b[key], seen) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end
