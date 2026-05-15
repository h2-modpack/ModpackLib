local deps = ...
local internal = deps.internal
local mutation = deps.mutation
local clone = deps.clone
local isCoordinatorRegistered = deps.isCoordinatorRegistered
local setupRunData = deps.setupRunData

local function hasAction(actions, actionKey)
    return actions[actionKey] ~= nil
end

local function hasAnyAction(actions)
    return next(actions) ~= nil
end

local function makeCommitContext(actions, hadConfigChanges)
    actions = actions or {}
    return {
        readAction = function(actionKey)
            return clone(actions[actionKey])
        end,
        hasAction = function(actionKey)
            return hasAction(actions, actionKey)
        end,
        hasActions = function()
            return hasAnyAction(actions)
        end,
        hadConfigChanges = function()
            return hadConfigChanges == true
        end,
    }
end

local function notifySettingsCommitted(def, settingsObserver, authorHost, store, commitContext)
    if settingsObserver == nil then
        return true, nil
    end

    local ok, result = pcall(settingsObserver, authorHost, store, commitContext or makeCommitContext(nil, false))
    if not ok then
        internal.violate("lifecycle.on_settings_committed_failed", "%s: onSettingsCommitted failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(result))
        return true, nil
    end
    if result == false then
        internal.violate("lifecycle.on_settings_committed_false", "%s: onSettingsCommitted returned false",
            tostring(def.name or def.id or "module"))
    end
    return true, nil
end

local function isEnabled(store, packId)
    local coord = packId and internal.coordinators[packId]
    if coord and not coord.ModEnabled then
        return false
    end
    if not store then
        return false
    end
    return store.read("Enabled") == true
end

local function applyOnLoad(def, mutationBundle, authorHost, store)
    if isEnabled(store, def and def.modpack) then
        local ok, err = mutation.apply(def, mutationBundle, authorHost, store)
        if not ok then
            return false, err
        end
    else
        local ok, err = mutation.revertActive(def, authorHost, store)
        if not ok then
            return false, err
        end
    end

    -- Standalone only; Framework.init handles this centrally for coordinated packs.
    if mutation.affectsRunData(mutationBundle) and not isCoordinatorRegistered(def and def.modpack) then
        setupRunData()
    end

    return true, nil
end

local function resyncSession(def, session)
    local mismatches = session.auditMismatches()
    if #mismatches > 0 then
        local name = def and (def.name or def.id) or "module"
        internal.violate("lifecycle.session_drift_detected", "%s: session drift detected; reloading staged values for: %s",
            tostring(name),
            table.concat(mismatches, ", "))
        session._reloadFromConfig()
    end
    return mismatches
end

local function commitSession(def, mutationBundle, settingsObserver, authorHost, store, session)
    if not session.isDirty() then
        return true, nil
    end

    local hadConfigChanges = session._hasConfigChanges()
    local actions = session._captureActionSnapshot()
    local commitContext = makeCommitContext(actions, hadConfigChanges)
    local snapshot = hadConfigChanges and session._captureDirtyConfigSnapshot() or nil
    if hadConfigChanges then
        session._flushToConfig()
    end
    session._clearActions()

    local shouldReapply = mutation.affectsRunData(mutationBundle)
        and hadConfigChanges
        and store.read("Enabled") == true

    if not shouldReapply then
        return notifySettingsCommitted(def, settingsObserver, authorHost, store, commitContext)
    end

    local ok, err = mutation.reapply(def, mutationBundle, authorHost, store)
    if ok then
        return notifySettingsCommitted(def, settingsObserver, authorHost, store, commitContext)
    end

    session._restoreConfigSnapshot(snapshot)
    session._reloadFromConfig()

    local rollbackOk, rollbackErr = mutation.reapply(def, mutationBundle, authorHost, store)
    if not rollbackOk then
        internal.violate("lifecycle.session_rollback_reapply_failed", "%s: session rollback reapply failed: %s",
            tostring(def.name or def.id or "module"),
            tostring(rollbackErr))
        return false, tostring(err) .. " (rollback reapply failed: " .. tostring(rollbackErr) .. ")"
    end

    return false, err
end

local function setEnabled(def, mutationBundle, authorHost, store, enabled)
    local nextEnabled = enabled == true
    local current = store.read("Enabled") == true

    local ok, err
    if nextEnabled and current then
        ok, err = mutation.reapply(def, mutationBundle, authorHost, store)
    elseif nextEnabled then
        ok, err = mutation.apply(def, mutationBundle, authorHost, store)
    elseif current then
        ok, err = mutation.revert(def, mutationBundle, authorHost, store)
    else
        ok, err = true, nil
    end

    if not ok then
        return false, err
    end

    internal.store.writePersisted(store, "Enabled", nextEnabled)
    return true, nil
end

local function setDebugMode(store, enabled)
    internal.store.writePersisted(store, "DebugMode", enabled == true)
end

return {
    isEnabled = isEnabled,
    applyOnLoad = applyOnLoad,
    resyncSession = resyncSession,
    commitSession = commitSession,
    setEnabled = setEnabled,
    setDebugMode = setDebugMode,
}
