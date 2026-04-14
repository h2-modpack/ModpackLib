local internal = AdamantModpackLib_Internal
local shared = internal.shared
public.special = public.special or {}
local special = public.special

--- Runs a special-module UI pass with optional before/after hooks and transactional commit behavior.
---@param opts table Pass options containing draw hooks, uiState, commit handler, and render context.
---@return boolean changed True when the pass flushed dirty UI state or the draw callback reported a change.
---@return string|nil err Error message when the commit phase fails.
function special.runPass(opts)
    local draw = opts and opts.draw
    if type(draw) ~= "function" then
        return false
    end

    local uiState = opts.uiState
    if not uiState or type(uiState.isDirty) ~= "function" or type(uiState.flushToConfig) ~= "function" then
        if shared.logging and shared.logging.warnIf then
            shared.logging.warnIf("runUiStatePass: uiState is missing or malformed; pass skipped")
        end
        return false
    end
    local imgui = opts.imgui or rom.ImGui
    local beforeDraw = opts.beforeDraw
    if type(beforeDraw) == "function" then
        beforeDraw(imgui, uiState, opts.theme)
    end

    local drawChanged = draw(imgui, uiState, opts.theme) == true

    local afterDraw = opts.afterDraw
    if type(afterDraw) == "function" then
        afterDraw(imgui, uiState, opts.theme, drawChanged)
    end

    if uiState.isDirty() then
        if type(opts.commit) == "function" then
            local ok, err = opts.commit(uiState)
            if ok then
                if type(opts.onFlushed) == "function" then
                    opts.onFlushed()
                end
                return true, nil
            end
            if shared.logging and shared.logging.warn then
                shared.logging.warn("%s: uiState commit failed: %s",
                    tostring(opts.name or "uiState"),
                    tostring(err))
            end
            return false, err
        end

        uiState.flushToConfig()
        if type(opts.onFlushed) == "function" then
            opts.onFlushed()
        end
        return true
    end

    return false
end

--- Recomputes derived text aliases for a UI state and optionally caches computed signatures and values.
---@param uiState table UI state used to read view data and write derived aliases.
---@param entries table Ordered list of derived-text descriptors with `alias`, `compute`, and optional `signature`.
---@param cache table|nil Optional cache table keyed by alias.
---@return boolean changed True when any derived alias value changed.
function special.runDerivedText(uiState, entries, cache)
    if not uiState or type(uiState.set) ~= "function" or type(uiState.view) ~= "table" then
        if shared.logging and shared.logging.warnIf then
            shared.logging.warnIf("runDerivedText: uiState is missing or malformed; pass skipped")
        end
        return false
    end
    if type(entries) ~= "table" then
        return false
    end

    local changed = false
    local derivedCache = type(cache) == "table" and cache or nil

    for index, entry in ipairs(entries) do
        local alias = type(entry) == "table" and entry.alias or nil
        local compute = type(entry) == "table" and entry.compute or nil
        if type(alias) ~= "string" or alias == "" then
            if shared.logging and shared.logging.warnIf then
                shared.logging.warnIf("runDerivedText: entries[%d].alias must be a non-empty string", index)
            end
        elseif type(compute) ~= "function" then
            if shared.logging and shared.logging.warnIf then
                shared.logging.warnIf("runDerivedText: entries[%d].compute must be a function", index)
            end
        else
            local cached = derivedCache and derivedCache[alias] or nil
            local currentValue = uiState.view[alias]
            local signatureFn = entry.signature
            local signature = nil
            local useCachedValue = false

            if type(signatureFn) == "function" then
                signature = signatureFn(uiState)
                if cached and cached.signature == signature then
                    useCachedValue = true
                end
            end

            local nextValue
            if useCachedValue then
                nextValue = cached.value
            else
                nextValue = tostring(compute(uiState) or "")
            end

            if currentValue ~= nextValue then
                uiState.set(alias, nextValue)
                changed = true
            end

            if derivedCache then
                derivedCache[alias] = {
                    signature = signature,
                    value = nextValue,
                }
            end
        end
    end

    return changed
end

--- Reuses or rebuilds a prepared UI node based on a caller-provided cache entry and signature.
---@param cacheEntry table|nil Previous cache entry containing `signature` and `node`.
---@param signature any Signature describing the current build inputs.
---@param buildFn function Builder that receives the previous node and returns the next node.
---@param opts table|nil Optional cache behavior hooks such as `reuseState`.
---@return table|nil cacheEntry Next cache entry when a node exists.
---@return table|nil node Prepared node returned by the builder or cache.
---@return boolean rebuilt True when the node was rebuilt instead of reused.
---@return table|nil previousNode Previously cached node, if one existed.
function special.getCachedPreparedNode(cacheEntry, signature, buildFn, opts)
    if type(buildFn) ~= "function" then
        if shared.logging and shared.logging.warnIf then
            shared.logging.warnIf("getCachedPreparedNode: buildFn must be a function")
        end
        return nil, nil, false, nil
    end

    local cached = type(cacheEntry) == "table" and cacheEntry or nil
    local previousNode = cached and cached.node or nil
    if cached and previousNode ~= nil and cached.signature == signature then
        return cached, previousNode, false, previousNode
    end

    local node = buildFn(previousNode)
    if node == nil then
        return nil, nil, true, previousNode
    end

    if previousNode ~= nil and type(opts) == "table" and type(opts.reuseState) == "function" then
        opts.reuseState(node, previousNode)
    end

    return {
        signature = signature,
        node = node,
    }, node, true, previousNode
end

--- Audits staged UI state against persisted config values and reloads staged values from config.
---@param name string Label used when printing mismatch diagnostics.
---@param uiState table UI state exposing config mismatch and reload helpers.
---@return table mismatches List of alias names whose staged values drifted from persisted config.
function special.auditAndResyncState(name, uiState)
    if not uiState or type(uiState.collectConfigMismatches) ~= "function" or type(uiState.reloadFromConfig) ~= "function" then
        return {}
    end

    local mismatches = uiState.collectConfigMismatches()
    if #mismatches > 0 then
        print("[" .. tostring(name) .. "] UI state drift detected; reloading staged values for: " .. table.concat(mismatches, ", "))
    end
    uiState.reloadFromConfig()
    return mismatches
end

--- Commits staged UI state back to config and reapplies live mutations when required.
---@param def table Module definition declaring mutation behavior.
---@param store table Managed module store associated with the definition.
---@param uiState table UI state exposing transactional flush and reload helpers.
---@return boolean ok True when the commit completed successfully.
---@return string|nil err Error message when the commit or rollback path fails.
function special.commitState(def, store, uiState)
    if not uiState or type(uiState.isDirty) ~= "function" or type(uiState.flushToConfig) ~= "function"
        or type(uiState.reloadFromConfig) ~= "function"
        or type(uiState._captureDirtyConfigSnapshot) ~= "function"
        or type(uiState._restoreConfigSnapshot) ~= "function" then
        return false, "uiState is missing transactional commit helpers"
    end

    if not uiState.isDirty() then
        return true, nil
    end

    local snapshot = uiState._captureDirtyConfigSnapshot()
    uiState.flushToConfig()

    local shouldReapply = public.mutation.mutatesRunData(def)
        and store
        and type(store.read) == "function"
        and store.read("Enabled") == true

    if not shouldReapply then
        return true, nil
    end

    local ok, err = public.mutation.reapply(def, store)
    if ok then
        return true, nil
    end

    uiState._restoreConfigSnapshot(snapshot)
    uiState.reloadFromConfig()

    local rollbackOk, rollbackErr = public.mutation.reapply(def, store)
    if not rollbackOk then
        if shared.logging and shared.logging.warn then
            shared.logging.warn("%s: uiState rollback reapply failed: %s",
                tostring(def.name or def.id or "module"),
                tostring(rollbackErr))
        end
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end
