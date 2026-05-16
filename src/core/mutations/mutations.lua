local internal = AdamantModpackLib_Internal

public.mutation = public.mutation or {}
internal.mutation = internal.mutation or {}

AdamantModpackLib_MutationState = AdamantModpackLib_MutationState or {
    storeRuntime = setmetatable({}, { __mode = "k" }),
    moduleRuntime = {},
    planExecutors = setmetatable({}, { __mode = "k" }),
}
local mutationState = AdamantModpackLib_MutationState
mutationState.planExecutors = mutationState.planExecutors or setmetatable({}, { __mode = "k" })

local values = internal.values
public.mutation.createBackup = nil

---@class MutationPlan
---@field set fun(self: MutationPlan, tbl: table, key: any, value: any): MutationPlan
---@field setMany fun(self: MutationPlan, tbl: table, kv: table): MutationPlan
---@field transform fun(self: MutationPlan, tbl: table, key: any, fn: fun(current: any): any): MutationPlan
---@field append fun(self: MutationPlan, tbl: table, key: any, value: any): MutationPlan
---@field appendUnique fun(self: MutationPlan, tbl: table, key: any, value: any, eqFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field removeElement fun(self: MutationPlan, tbl: table, key: any, value: any, eqFn: fun(a: any, b: any): boolean|nil): MutationPlan
---@field setElement fun(self: MutationPlan, tbl: table, key: any, oldVal: any, newVal: any, eq: fun(any, any): boolean?): MutationPlan

local planExecutors = mutationState.planExecutors

---@return function backup, function restore
function internal.mutation.createBackup()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for i = 1, select("#", ...) do
            local key = select(i, ...)
            if saved[key] == nil then
                local value = tbl[key]
                saved[key] = (value == nil) and NIL or values.deepCopy(value)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, value in pairs(keys) do
                if value == NIL then
                    tbl[key] = nil
                elseif type(value) == "table" then
                    tbl[key] = values.deepCopy(value)
                else
                    tbl[key] = value
                end
            end
        end
        for tbl in pairs(savedValues) do
            savedValues[tbl] = nil
        end
    end

    return backup, restore
end

---@return MutationPlan
function public.mutation.createPlan()
    local backup, restore = internal.mutation.createBackup()
    local operations = {}
    local applied = false
    local plan = {}

    local function appendOperation(op)
        operations[#operations + 1] = op
        return plan
    end

    function plan.set(_, tbl, key, value)
        return appendOperation({
            kind = "set",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
        })
    end

    function plan.setMany(_, tbl, kv)
        return appendOperation({
            kind = "setMany",
            tbl = tbl,
            kv = kv,
        })
    end

    function plan.transform(_, tbl, key, fn)
        return appendOperation({
            kind = "transform",
            tbl = tbl,
            key = key,
            fn = fn,
        })
    end

    function plan.append(_, tbl, key, value)
        return appendOperation({
            kind = "append",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
        })
    end

    function plan.appendUnique(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "appendUnique",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    function plan.removeElement(_, tbl, key, value, equivalentFn)
        return appendOperation({
            kind = "removeElement",
            tbl = tbl,
            key = key,
            value = values.deepCopy(value),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    function plan.setElement(_, tbl, key, oldValue, newValue, equivalentFn)
        return appendOperation({
            kind = "setElement",
            tbl = tbl,
            key = key,
            oldValue = values.deepCopy(oldValue),
            newValue = values.deepCopy(newValue),
            equivalentFn = equivalentFn or values.deepEqual,
        })
    end

    local function applyOperations()
        for _, op in ipairs(operations) do
            local tbl = op.tbl
            local key = op.key

            if op.kind == "set" then
                if tbl[key] ~= op.value then
                    backup(tbl, key)
                    tbl[key] = values.deepCopy(op.value)
                end
            elseif op.kind == "setMany" then
                for mapKey, value in pairs(op.kv) do
                    if tbl[mapKey] ~= value then
                        backup(tbl, mapKey)
                        tbl[mapKey] = values.deepCopy(value)
                    end
                end
            elseif op.kind == "transform" then
                backup(tbl, key)
                tbl[key] = values.deepCopy(op.fn(values.deepCopy(tbl[key])))
            elseif op.kind == "append" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan append requires table at key '%s'"):format(tostring(key)), 0)
                else
                    backup(tbl, key)
                end
                list[#list + 1] = values.deepCopy(op.value)
            elseif op.kind == "appendUnique" then
                local list = tbl[key]
                if list == nil then
                    backup(tbl, key)
                    list = {}
                    tbl[key] = list
                elseif type(list) ~= "table" then
                    error(("mutation plan appendUnique requires table at key '%s'"):format(tostring(key)), 0)
                end

                local exists = false
                for _, entry in ipairs(list) do
                    if op.equivalentFn(entry, op.value) then
                        exists = true
                        break
                    end
                end
                if not exists then
                    backup(tbl, key)
                    list[#list + 1] = values.deepCopy(op.value)
                end
            elseif op.kind == "removeElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.value) then
                            backup(tbl, key)
                            table.remove(list, index)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan removeElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            elseif op.kind == "setElement" then
                local list = tbl[key]
                if type(list) == "table" then
                    for index, entry in ipairs(list) do
                        if op.equivalentFn(entry, op.oldValue) then
                            backup(tbl, key)
                            list[index] = values.deepCopy(op.newValue)
                            break
                        end
                    end
                elseif list ~= nil then
                    error(("mutation plan setElement requires table at key '%s'"):format(tostring(key)), 0)
                end
            end
        end
    end

    local function applyPlan()
        if applied then
            return false
        end

        local ok, err = pcall(applyOperations)
        if not ok then
            restore()
            error(err, 0)
        end

        applied = true
        return true
    end

    local function revertPlan()
        if not applied then
            return false
        end
        restore()
        applied = false
        return true
    end

    planExecutors[plan] = {
        apply = applyPlan,
        revert = revertPlan,
    }

    return plan --[[@as MutationPlan]]
end

local function GetPlanExecutor(plan, action)
    local executor = planExecutors[plan]
    if not executor then
        error("mutation plan is not executable", 0)
    end
    return executor[action]
end

function internal.mutation.applyPlan(plan)
    return GetPlanExecutor(plan, "apply")()
end

function internal.mutation.revertPlan(plan)
    return GetPlanExecutor(plan, "revert")()
end

---@alias MutationShape "patch"

---@class MutationInfo
---@field hasPatch boolean

local function GetRuntimeKey(def, store)
    if def and type(def.id) == "string" and def.id ~= "" then
        local packId = type(def.modpack) == "string" and def.modpack or ""
        return "module:" .. packId .. ":" .. def.id, mutationState.moduleRuntime
    end
    if store then
        return store, mutationState.storeRuntime
    end
    return nil, nil
end

local function GetRuntimeState(def, store)
    local key, bucket = GetRuntimeKey(def, store)
    if not bucket then
        return nil, nil, nil
    end
    return bucket[key], key, bucket
end

local function SetRuntimeState(def, store, state)
    local key, bucket = GetRuntimeKey(def, store)
    if not bucket then
        return
    end
    if state == nil or state.plan == nil then
        bucket[key] = nil
        return
    end
    bucket[key] = state
end

local function SetActiveMutationPlan(def, store, plan)
    local runtime = GetRuntimeState(def, store) or {}
    runtime.plan = plan
    SetRuntimeState(def, store, runtime)
end

local function CaptureActiveMutation(def, store)
    local runtime = GetRuntimeState(def, store)
    if not runtime then
        return nil
    end
    return {
        plan = runtime.plan,
    }
end

local function HasActiveMutationSnapshot(snapshot)
    return snapshot and snapshot.plan ~= nil
end

local function RestoreActiveMutation(def, store, snapshot)
    if not HasActiveMutationSnapshot(snapshot) then
        return true, nil
    end

    local okPlan, errPlan = pcall(internal.mutation.applyPlan, snapshot.plan)
    if not okPlan then
        return false, errPlan
    end

    SetActiveMutationPlan(def, store, snapshot.plan)
    return true, nil
end

local function BuildMutationPlan(mutationBundle, authorHost, store)
    local builder = mutationBundle and mutationBundle.patchMutation
    if builder == nil then
        return nil
    end

    local plan = public.mutation.createPlan()
    builder(plan, authorHost, store)
    return plan
end

local function RevertActivePlan(def, store)
    local runtime = GetRuntimeState(def, store)
    local activePlan = runtime and runtime.plan or nil
    if not activePlan then
        return true, nil, false
    end

    local okPlan, errPlan = pcall(internal.mutation.revertPlan, activePlan)
    runtime.plan = nil
    SetRuntimeState(def, store, runtime)
    if not okPlan then
        return false, errPlan, true
    end
    return true, nil, true
end

local function RevertActiveMutation(def, store)
    return RevertActivePlan(def, store)
end

local function InferMutation(mutationBundle)
    local hasPatch = mutationBundle and type(mutationBundle.patchMutation) == "function" or false

    local inferred = nil
    if hasPatch then
        inferred = "patch"
    end

    return inferred, {
        hasPatch = hasPatch,
    }
end

--- Returns whether a module declares that it affects live run data.
---@param mutationBundle table|nil Candidate mutation bundle.
---@return boolean affects True when the definition opts into run-data mutation behavior.
function internal.mutation.affectsRunData(mutationBundle)
    return mutationBundle
        and (mutationBundle.affectsRunData == true or type(mutationBundle.patchMutation) == "function")
        or false
end

--- Applies a module's current mutation lifecycle to live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function internal.mutation.apply(def, mutationBundle, authorHost, store)
    local inferred, info = InferMutation(mutationBundle)
    local previousMutation = CaptureActiveMutation(def, store)

    local okActive, errActive = RevertActiveMutation(def, store)
    if not okActive then
        return false, errActive
    end

    local function failApply(err)
        if HasActiveMutationSnapshot(previousMutation) then
            local okRestore, restoreErr = RestoreActiveMutation(def, store, previousMutation)
            if not okRestore then
                return false, tostring(err) .. " (previous mutation restore failed: " .. tostring(restoreErr) .. ")"
            end
        end
        return false, err
    end

    if not inferred then
        if not internal.mutation.affectsRunData(mutationBundle) then
            return true, nil
        end
        return failApply("no supported mutation lifecycle found")
    end

    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, mutationBundle, authorHost, store)
        if not okBuild then
            return failApply(result)
        end
        local builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(internal.mutation.applyPlan, builtPlan)
            if not okApply then
                return failApply(errApply)
            end
            SetActiveMutationPlan(def, store, builtPlan)
        end
    end

    return true, nil
end

--- Reverts any active tracked mutation state without invoking fallback lifecycle hooks.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when active mutation state was absent or reverted successfully.
---@return string|nil err Error message when active cleanup fails.
function internal.mutation.revertActive(def, _, store)
    local ok, err = RevertActiveMutation(def, store)
    return ok, err
end

--- Reverts a module's current mutation lifecycle from live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function internal.mutation.revert(def, mutationBundle, _, store)
    local inferred, info = InferMutation(mutationBundle)
    if not inferred then
        local okActive, errActive, didActive = RevertActiveMutation(def, store)
        if not okActive then
            return false, errActive
        end
        if didActive or not internal.mutation.affectsRunData(mutationBundle) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    if info.hasPatch then
        local okPlan, errPlan = RevertActivePlan(def, store)
        if not okPlan then
            return false, errPlan
        end
    end

    return true, nil
end

--- Reverts and reapplies a module's mutation lifecycle.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param mutationBundle table|nil Module mutation callbacks.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reapplied successfully.
---@return string|nil err Error message when the reapply step fails.
function internal.mutation.reapply(def, mutationBundle, authorHost, store)
    local okRevert, errRevert = internal.mutation.revert(def, mutationBundle, authorHost, store)
    if not okRevert then
        return false, errRevert
    end

    local okApply, errApply = internal.mutation.apply(def, mutationBundle, authorHost, store)
    if not okApply then
        return false, errApply
    end

    return true, nil
end
