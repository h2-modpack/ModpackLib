local mutationPlan = ...
local internal = AdamantModpackLib_Internal
internal.mutation = internal.mutation or {}
internal.mutationRuntime = internal.mutationRuntime or {}

local mutationInternal = internal.mutation
local mutationRuntime = internal.mutationRuntime
mutationRuntime.byKey = mutationRuntime.byKey or {}
mutationRuntime.byStore = mutationRuntime.byStore or setmetatable({}, { __mode = "k" })

---@alias MutationShape "patch"|"manual"|"hybrid"

---@class MutationInfo
---@field hasPatch boolean
---@field hasApply boolean
---@field hasRevert boolean
---@field hasManual boolean

local function GetRuntimeBucket(def, store)
    if def and type(def.id) == "string" and def.id ~= "" then
        local packId = (type(def.modpack) == "string" and def.modpack ~= "")
            and def.modpack
            or "_standalone"
        return mutationRuntime.byKey, packId .. "::" .. def.id
    end

    if store then
        return mutationRuntime.byStore, store
    end
end

local function GetRuntimeEntry(def, store, create)
    local bucket, key = GetRuntimeBucket(def, store)
    if not bucket then
        return nil, nil, nil
    end

    local entry = bucket[key]
    if not entry and create then
        entry = {}
        bucket[key] = entry
    end

    return entry, bucket, key
end

local function ClearRuntimeEntryIfEmpty(entry, bucket, key)
    if entry and not entry.plan and not entry.manualRevert then
        bucket[key] = nil
    end
end

local function GetActiveMutationPlan(def, store)
    local entry = GetRuntimeEntry(def, store, false)
    return entry and entry.plan or nil
end

local function SetActiveMutationPlan(def, store, plan)
    local entry, bucket, key = GetRuntimeEntry(def, store, plan ~= nil)
    if not entry then
        return
    end

    entry.plan = plan
    ClearRuntimeEntryIfEmpty(entry, bucket, key)
end

local function GetActiveManualRevert(def, store)
    local entry = GetRuntimeEntry(def, store, false)
    return entry and entry.manualRevert or nil
end

local function SetActiveManualRevert(def, store, revertFn)
    local entry, bucket, key = GetRuntimeEntry(def, store, revertFn ~= nil)
    if not entry then
        return
    end

    entry.manualRevert = revertFn
    ClearRuntimeEntryIfEmpty(entry, bucket, key)
end

local function RevertActiveManual(def, store)
    local revertFn = GetActiveManualRevert(def, store)
    if not revertFn then
        return true, nil, false
    end

    local ok, err = pcall(revertFn)
    if not ok then
        return false, err, true
    end

    SetActiveManualRevert(def, store, nil)
    return true, nil, true
end

local function RevertActivePlan(def, store)
    local activePlan = GetActiveMutationPlan(def, store)
    if not activePlan then
        return true, nil, false
    end

    local ok, err = pcall(activePlan.revert, activePlan)
    if not ok then
        return false, err, true
    end

    SetActiveMutationPlan(def, store, nil)
    return true, nil, true
end

local function RevertActiveMutation(def, store)
    local okManual, errManual, didManual = RevertActiveManual(def, store)
    if not okManual then
        return false, errManual
    end

    local okPlan, errPlan, didPlan = RevertActivePlan(def, store)
    if not okPlan then
        return false, errPlan
    end

    return true, nil, didManual or didPlan
end

local function BuildMutationPlan(def, store)
    local builder = def and def.patchPlan
    if type(builder) ~= "function" then
        return nil
    end

    local plan = mutationPlan.createPlan()
    builder(plan, store)
    return plan
end

--- Infers which mutation lifecycle a module definition exposes.
---@param def ModuleDefinition Candidate module definition table.
---@return MutationShape|nil shape Inferred lifecycle shape: `patch`, `manual`, `hybrid`, or nil.
---@return MutationInfo info Flags describing which lifecycle hooks are present on the definition.
function mutationInternal.inferMutation(def)
    local hasPatch = def and type(def.patchPlan) == "function" or false
    local hasApply = def and type(def.apply) == "function" or false
    local hasRevert = def and type(def.revert) == "function" or false
    local hasManual = hasApply and hasRevert

    local inferred = nil
    if hasPatch and hasManual then
        inferred = "hybrid"
    elseif hasPatch then
        inferred = "patch"
    elseif hasManual then
        inferred = "manual"
    end

    return inferred, {
        hasPatch = hasPatch,
        hasApply = hasApply,
        hasRevert = hasRevert,
        hasManual = hasManual,
    }
end

--- Returns whether a module definition declares that it mutates live run data.
---@param def ModuleDefinition|nil Candidate module definition table.
---@return boolean mutates True when the definition opts into run-data mutation behavior.
function mutationInternal.mutatesRunData(def)
    if not def then
        return false
    end
    return def.affectsRunData == true
end

--- Applies a module definition's current mutation lifecycle to live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function mutationInternal.apply(def, store)
    local inferred, info = mutationInternal.inferMutation(def)

    local okActive, errActive = RevertActiveMutation(def, store)
    if not okActive then
        return false, errActive
    end

    if not inferred then
        if not mutationInternal.mutatesRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local builtPlan = nil
    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, def, store)
        if not okBuild then
            return false, result
        end
        builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(builtPlan.apply, builtPlan)
            if not okApply then
                return false, errApply
            end
            SetActiveMutationPlan(def, store, builtPlan)
        end
    end

    if info.hasManual then
        local okManual, errManual = pcall(def.apply)
        if not okManual then
            if builtPlan then
                pcall(builtPlan.revert, builtPlan)
                SetActiveMutationPlan(def, store, nil)
            end
            return false, errManual
        end
        SetActiveManualRevert(def, store, def.revert)
    end

    return true, nil
end

--- Reverts any active tracked mutation state without invoking fallback lifecycle hooks.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when active mutation state was absent or reverted successfully.
---@return string|nil err Error message when active cleanup fails.
function mutationInternal.revertActive(def, store)
    local ok, err = RevertActiveMutation(def, store)
    return ok, err
end

--- Reverts a module definition's current mutation lifecycle from live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function mutationInternal.revert(def, store)
    local inferred, info = mutationInternal.inferMutation(def)
    if not inferred then
        local okActive, errActive, didActive = RevertActiveMutation(def, store)
        if not okActive then
            return false, errActive
        end
        if didActive or not mutationInternal.mutatesRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local firstErr = nil

    if info.hasManual then
        local okActiveManual, errActiveManual, didActiveManual = RevertActiveManual(def, store)
        if not okActiveManual and not firstErr then
            firstErr = errActiveManual
        elseif not didActiveManual then
            local okManual, errManual = pcall(def.revert)
            if not okManual and not firstErr then
                firstErr = errManual
            end
        end
    end

    local okPlan, errPlan = RevertActivePlan(def, store)
    if not okPlan and not firstErr then
        firstErr = errPlan
    end

    if firstErr then
        return false, firstErr
    end

    return true, nil
end

--- Reverts and reapplies a module definition's mutation lifecycle.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reapplied successfully.
---@return string|nil err Error message when the reapply step fails.
function mutationInternal.reapply(def, store)
    local okRevert, errRevert = mutationInternal.revert(def, store)
    if not okRevert then
        return false, errRevert
    end

    local okApply, errApply = mutationInternal.apply(def, store)
    if not okApply then
        return false, errApply
    end

    return true, nil
end
