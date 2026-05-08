public.gameObject = public.gameObject or {}
local internal = AdamantModpackLib_Internal
local gameObject = public.gameObject

local ROOT_KEY = "_AdamantModpackLibGameObject"

local function tableIsEmpty(value)
    return next(value) == nil
end

local function getModuleBucket(object, packId, moduleId, key, create)
    if type(object) ~= "table" then
        internal.violate("game_object.invalid_args", "lib.gameObject object must be a table")
    end
    if type(packId) ~= "string" or packId == "" then
        internal.violate("game_object.invalid_args", "lib.gameObject packId must be a non-empty string")
    end
    if type(moduleId) ~= "string" or moduleId == "" then
        internal.violate("game_object.invalid_args", "lib.gameObject moduleId must be a non-empty string")
    end
    if type(key) ~= "string" or key == "" then
        internal.violate("game_object.invalid_args", "lib.gameObject key must be a non-empty string")
    end

    local root = rawget(object, ROOT_KEY)
    if root == nil and create then
        root = {}
        rawset(object, ROOT_KEY, root)
    end
    if type(root) ~= "table" then
        if create then
            internal.violate("game_object.invalid_bucket", "lib.gameObject root bucket is not a table")
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
            internal.violate("game_object.invalid_bucket", "lib.gameObject pack bucket is not a table")
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
            internal.violate("game_object.invalid_bucket", "lib.gameObject module bucket is not a table")
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
                internal.violate("game_object.invalid_factory", "lib.gameObject.get factory must be a function")
            end
            state = factory()
        end
        if state == nil then
            state = {}
        end
        if type(state) ~= "table" then
            internal.violate("game_object.invalid_factory", "lib.gameObject.get factory must return a table")
        end
        moduleBucket[key] = state
    end
    if type(state) ~= "table" then
        internal.violate("game_object.invalid_bucket", "lib.gameObject state bucket is not a table")
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
