local internal = AdamantModpackLib_Internal

internal.store = internal.store or {}
local storeInternal = internal.store
local StoreState = setmetatable({}, { __mode = "k" })

storeInternal.ClonePersistedValue = internal.values.deepCopy

--- Registers internal callbacks for a managed store object.
---@param store ManagedStore
---@param state table
function storeInternal.bindManagedStore(store, state)
    StoreState[store] = state
end

--- Writes a declared storage alias through a managed store.
--- Internal plumbing only; ordinary state changes should go through session.
---@param store ManagedStore
---@param alias string Declared storage alias or built-in system field to write.
---@param value any Value to persist, normalized through the owning storage type when applicable.
function storeInternal.writePersisted(store, alias, value)
    local state = store and StoreState[store] or nil
    if not state or type(state.write) ~= "function" then
        error("internal.store.writePersisted expects a managed store", 2)
    end
    return state.write(alias, value)
end

---@param store ManagedStore
---@param alias string
---@return table[]
function storeInternal.getPackedAliases(store, alias)
    local state = store and StoreState[store] or nil
    if not state or type(state.getPackedAliases) ~= "function" then
        return {}
    end
    return state.getPackedAliases(alias)
end
