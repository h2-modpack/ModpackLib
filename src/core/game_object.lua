public.gameObject = public.gameObject or {}
local gameObject = public.gameObject

local ROOT_KEY = "_AdamantModpackLibGameObject"

local function assertNonEmptyString(value, name)
    if type(value) ~= "string" or value == "" then
        error(string.format("lib.gameObject %s must be a non-empty string", name), 3)
    end
end

local function assertObject(object)
    if type(object) ~= "table" then
        error("lib.gameObject object must be a table", 3)
    end
end

local function tableIsEmpty(value)
    return next(value) == nil
end

local function getModuleBucket(object, packId, moduleId, key, create)
    assertObject(object)
    assertNonEmptyString(packId, "packId")
    assertNonEmptyString(moduleId, "moduleId")
    assertNonEmptyString(key, "key")

    local root = rawget(object, ROOT_KEY)
    if root == nil and create then
        root = {}
        rawset(object, ROOT_KEY, root)
    end
    if type(root) ~= "table" then
        if create then
            error("lib.gameObject root bucket is not a table", 3)
        end
        return nil
    end

    local packBucket = root[packId]
    if packBucket == nil and create then
        packBucket = {}
        root[packId] = packBucket
    end
    if type(packBucket) ~= "table" then
        if create then
            error("lib.gameObject pack bucket is not a table", 3)
        end
        return nil
    end

    local moduleBucket = packBucket[moduleId]
    if moduleBucket == nil and create then
        moduleBucket = {}
        packBucket[moduleId] = moduleBucket
    end
    if type(moduleBucket) ~= "table" then
        if create then
            error("lib.gameObject module bucket is not a table", 3)
        end
        return nil
    end

    return moduleBucket, packBucket, root
end

--- Gets or creates a module-owned state table scoped to a live game object.
---@param object table Live game object table such as `CurrentRun`, room data, or loot data.
---@param packId string Pack namespace.
---@param moduleId string Module namespace inside the pack.
---@param key string State bucket key inside the module namespace.
---@param factory fun(): table|nil Optional initializer. Defaults to `{}`.
---@return table state Namespaced object state table.
function gameObject.get(object, packId, moduleId, key, factory)
    local moduleBucket = getModuleBucket(object, packId, moduleId, key, true)
    local state = moduleBucket[key]
    if state == nil then
        if factory ~= nil then
            if type(factory) ~= "function" then
                error("lib.gameObject.get factory must be a function", 2)
            end
            state = factory()
        end
        if state == nil then
            state = {}
        end
        if type(state) ~= "table" then
            error("lib.gameObject.get factory must return a table", 2)
        end
        moduleBucket[key] = state
    end
    if type(state) ~= "table" then
        error("lib.gameObject state bucket is not a table", 2)
    end
    return state
end

--- Returns an existing module-owned state table without creating it.
---@param object table Live game object table.
---@param packId string Pack namespace.
---@param moduleId string Module namespace inside the pack.
---@param key string State bucket key inside the module namespace.
---@return table|nil state Existing state table, when present.
function gameObject.peek(object, packId, moduleId, key)
    local moduleBucket = getModuleBucket(object, packId, moduleId, key, false)
    local state = moduleBucket and moduleBucket[key] or nil
    if type(state) == "table" then
        return state
    end
    return nil
end

--- Clears one module-owned state table from a live game object.
---@param object table Live game object table.
---@param packId string Pack namespace.
---@param moduleId string Module namespace inside the pack.
---@param key string State bucket key inside the module namespace.
---@return boolean cleared True when a bucket existed and was removed.
function gameObject.clear(object, packId, moduleId, key)
    local moduleBucket, packBucket, root = getModuleBucket(object, packId, moduleId, key, false)
    if not moduleBucket or moduleBucket[key] == nil then
        return false
    end
    moduleBucket[key] = nil
    if tableIsEmpty(moduleBucket) then
        packBucket[moduleId] = nil
        if tableIsEmpty(packBucket) then
            root[packId] = nil
            if tableIsEmpty(root) then
                rawset(object, ROOT_KEY, nil)
            end
        end
    end
    return true
end
