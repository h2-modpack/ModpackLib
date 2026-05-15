local lu = require('luaunit')

TestDefinitionLifecycle = {}

local function PatchMutation(fn)
    return {
        affectsRunData = true,
        patchMutation = fn,
    }
end

local function ManualMutation(apply, revert)
    return {
        affectsRunData = true,
        manualMutation = {
            apply = apply,
            revert = revert,
        },
    }
end

local function HybridMutation(patch, apply, revert)
    return {
        affectsRunData = true,
        patchMutation = patch,
        manualMutation = {
            apply = apply,
            revert = revert,
        },
    }
end

local function makeStore(enabled)
    return CreateModuleState({ Enabled = enabled }, AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "LifecycleStore",
        name = "Lifecycle Store",
        storage = {},
    }))
end

function TestDefinitionLifecycle:testSetApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { HP = 100 }

    plan:set(tbl, "HP", 250)

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl.HP, 250)
    lu.assertTrue(plan.revert())
    lu.assertEquals(tbl.HP, 100)
end

function TestDefinitionLifecycle:testSetClonesTableValue()
    local plan = lib.mutation.createPlan()
    local replacement = { Damage = 100 }
    local tbl = { Data = { Damage = 10 } }

    plan:set(tbl, "Data", replacement)
    plan:apply()
    replacement.Damage = 999

    lu.assertEquals(tbl.Data.Damage, 100)
    plan:revert()
    lu.assertEquals(tbl.Data.Damage, 10)
end

function TestDefinitionLifecycle:testSetManyApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { A = 1, B = 2, C = 3 }

    plan:setMany(tbl, { A = 10, B = 20 })
    plan:apply()

    lu.assertEquals(tbl.A, 10)
    lu.assertEquals(tbl.B, 20)
    lu.assertEquals(tbl.C, 3)

    plan:revert()
    lu.assertEquals(tbl.A, 1)
    lu.assertEquals(tbl.B, 2)
    lu.assertEquals(tbl.C, 3)
end

function TestDefinitionLifecycle:testTransformApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Requirements = { "A" } }

    plan:transform(tbl, "Requirements", function(current)
        local nextValue = rom.game.DeepCopyTable(current)
        table.insert(nextValue, "B")
        return nextValue
    end)

    plan:apply()
    lu.assertEquals(tbl.Requirements, { "A", "B" })

    plan:revert()
    lu.assertEquals(tbl.Requirements, { "A" })
end

function TestDefinitionLifecycle:testAppendCreatesMissingListAndRestoresNil()
    local plan = lib.mutation.createPlan()
    local tbl = {}

    plan:append(tbl, "Values", "A")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A" })

    plan:revert()
    lu.assertNil(tbl.Values)
end

function TestDefinitionLifecycle:testAppendUniqueUsesDeepEquivalenceByDefault()
    local plan = lib.mutation.createPlan()
    local tbl = {
        Requirements = {
            { Path = { "CurrentRun", "Hero" }, Value = 1 },
        },
    }

    plan:appendUnique(tbl, "Requirements", { Path = { "CurrentRun", "Hero" }, Value = 1 })
    plan:apply()

    lu.assertEquals(#tbl.Requirements, 1)
    plan:revert()
    lu.assertEquals(#tbl.Requirements, 1)
end

function TestDefinitionLifecycle:testAppendUniqueCanUseCustomComparator()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 } } }

    plan:appendUnique(tbl, "Values", { Name = "A", Count = 2 }, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()

    lu.assertEquals(#tbl.Values, 1)
end

function TestDefinitionLifecycle:testApplyAndRevertAreRepeatSafe()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = {} }

    plan:append(tbl, "Values", "A")
    lu.assertTrue(plan:apply())
    lu.assertFalse(plan:apply())
    lu.assertEquals(tbl.Values, { "A" })

    lu.assertTrue(plan:revert())
    lu.assertFalse(plan:revert())
    lu.assertEquals(tbl.Values, {})
end

function TestDefinitionLifecycle:testAppendErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:append(tbl, "Values", "A")
    lu.assertError(plan.apply)
end

function TestDefinitionLifecycle:testAppendUniqueDoesNotAliasInsertedTable()
    local plan = lib.mutation.createPlan()
    local entry = { Name = "A", Meta = { Count = 1 } }
    local tbl = { Values = {} }

    plan:appendUnique(tbl, "Values", entry)
    plan:apply()
    entry.Meta.Count = 999

    lu.assertEquals(tbl.Values[1].Meta.Count, 1)
end

function TestDefinitionLifecycle:testRemoveElementApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:removeElement(tbl, "Values", "B")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A", "C" })

    plan:revert()
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestDefinitionLifecycle:testRemoveElementCanUseCustomComparator()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 }, { Name = "B", Count = 2 } } }

    plan:removeElement(tbl, "Values", { Name = "A", Count = 999 }, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()

    lu.assertEquals(#tbl.Values, 1)
    lu.assertEquals(tbl.Values[1].Name, "B")
end

function TestDefinitionLifecycle:testSetElementApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:setElement(tbl, "Values", "B", "Z")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A", "Z", "C" })

    plan:revert()
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestDefinitionLifecycle:testSetElementClonesReplacementTable()
    local plan = lib.mutation.createPlan()
    local replacement = { Name = "Z", Meta = { Count = 10 } }
    local tbl = { Values = { { Name = "A" }, { Name = "B" } } }

    plan:setElement(tbl, "Values", { Name = "B" }, replacement, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()
    replacement.Meta.Count = 999

    lu.assertEquals(tbl.Values[2].Name, "Z")
    lu.assertEquals(tbl.Values[2].Meta.Count, 10)
end

function TestDefinitionLifecycle:testRemoveElementErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:removeElement(tbl, "Values", "A")
    lu.assertError(plan.apply)
end

function TestDefinitionLifecycle:testSetElementErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:setElement(tbl, "Values", "A", "B")
    lu.assertError(plan.apply)
end

function TestDefinitionLifecycle:testAffectsRunDataIgnoresDeprecatedFlag()
    lu.assertTrue(AdamantModpackLib_Internal.mutation.affectsRunData({ affectsRunData = true }))
    lu.assertFalse(AdamantModpackLib_Internal.mutation.affectsRunData({ affectsRunData = false }))
    lu.assertFalse(AdamantModpackLib_Internal.mutation.affectsRunData({ dataMutation = true }))
    lu.assertFalse(AdamantModpackLib_Internal.mutation.affectsRunData({}))
end

function TestDefinitionLifecycle:testCommitSessionCallsSettingsObserverAfterFlush()
    local calls = 0
    local observedValue = nil
    local config = {
        Enabled = true,
        Value = false,
    }
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "CommitSessionObserver",
        name = "Commit Session Observer",
        storage = {
            {
                type = "bool",
                alias = "Value",
                default = false,
            },
        },
    })
    local store, session = CreateModuleState(config, definition)
    local settingsObserver = function(_, activeStore)
        calls = calls + 1
        observedValue = activeStore.read("Value")
    end

    session.write("Value", true)
    local ok, err = HostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
    lu.assertTrue(config.Value)

    ok, err = HostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
end

function TestDefinitionLifecycle:testCommitSessionCallsSettingsObserverForActions()
    local calls = 0
    local observedAction = nil
    local observedConfigChange = nil
    local config = {
        Enabled = true,
    }
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "CommitSessionActionObserver",
        name = "Commit Session Action Observer",
        storage = {},
    })
    local store, session = CreateModuleState(config, definition)
    local settingsObserver = function(_, _, commit)
        calls = calls + 1
        observedAction = commit.readAction("recording")
        observedConfigChange = commit.hadConfigChanges()
    end

    session.stageAction("recording", { kind = "start" })
    local ok, err = HostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertEquals(observedAction, { kind = "start" })
    lu.assertFalse(observedConfigChange)
    lu.assertFalse(session.hasActions())
    lu.assertFalse(session.isDirty())

    ok, err = HostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
end

function TestDefinitionLifecycle:testApplyDefinitionSupportsPatchOnly()
    local store = makeStore(false)
    local target = { Value = 1 }
    local def = { id = "PatchOnly" }
    local mutation = PatchMutation(function(plan)
            plan:set(target, "Value", 7)
        end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    ok, err = AdamantModpackLib_Internal.mutation.revert(def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestDefinitionLifecycle:testPatchRuntimeSurvivesRecreatedStoreByModuleId()
    local target = { Value = 1 }
    local storeA = makeStore(true)
    local defA = {
        modpack = "test-pack",
        id = "StablePatchRuntime",
    }
    local mutationA = PatchMutation(function(plan)
            plan:set(target, "Value", 7)
        end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(defA, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    local storeB = makeStore(true)
    local defB = {
        modpack = "test-pack",
        id = "StablePatchRuntime",
    }
    local mutationB = PatchMutation(function(plan)
            plan:set(target, "Value", 9)
        end)

    ok, err = AdamantModpackLib_Internal.mutation.apply(defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 9)

    ok, err = AdamantModpackLib_Internal.mutation.revert(defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestDefinitionLifecycle:testApplyOnLoadRevertsStablePatchWhenReloadedDisabled()
    local target = { Value = 1 }
    local storeA = makeStore(true)
    local def = {
        modpack = "test-pack",
        id = "DisabledReloadPatchRuntime",
    }
    local mutation = PatchMutation(function(plan)
            plan:set(target, "Value", 7)
        end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, mutation, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    local storeB = makeStore(false)

    ok, err = HostLifecycle.applyOnLoad(def, mutation, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestDefinitionLifecycle:testManualRuntimeSurvivesRecreatedStoreByModuleId()
    local target = { Value = 0 }
    local storeA = makeStore(true)
    local defA = {
        modpack = "test-pack",
        id = "StableManualRuntime",
    }
    local mutationA = ManualMutation(function()
        target.Value = target.Value + 1
    end, function()
        target.Value = target.Value - 1
    end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(defA, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)

    local storeB = makeStore(true)
    local defB = {
        modpack = "test-pack",
        id = "StableManualRuntime",
    }
    local mutationB = ManualMutation(function()
        target.Value = target.Value + 10
    end, function()
        target.Value = target.Value - 10
    end)

    ok, err = AdamantModpackLib_Internal.mutation.apply(defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 10)

    ok, err = AdamantModpackLib_Internal.mutation.revert(defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 0)
end

function TestDefinitionLifecycle:testApplyOnLoadDisabledDoesNotCallInactiveManualRevert()
    local store = makeStore(false)
    local revertCalls = 0
    local def = {
        modpack = "test-pack",
        id = "InactiveManualRevert",
    }
    local mutation = ManualMutation(function() end, function()
        revertCalls = revertCalls + 1
    end)

    local ok, err = HostLifecycle.applyOnLoad(def, mutation, nil, store)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(revertCalls, 0)
end

function TestDefinitionLifecycle:testApplyDefinitionNoOpsWhenLifecycleMissingAndRunDataUnaffected()
    local store = makeStore(false)
    local def = { id = "NoLifecycle" }

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, nil, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)

    ok, err = AdamantModpackLib_Internal.mutation.revert(def, nil, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

function TestDefinitionLifecycle:testSetDefinitionEnabledCommitsOnlyAfterSuccessfulEnable()
    local store = makeStore(false)
    local applied = false
    local def = { id = "SuccessfulEnable" }
    local mutation = ManualMutation(function()
        applied = true
    end, function() end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(applied)
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedEnable()
    local store = makeStore(false)
    local def = { id = "FailedEnable" }
    local mutation = ManualMutation(function()
        error("enable boom")
    end, function() end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, true)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "enable boom")
    lu.assertFalse(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedDisable()
    local store = makeStore(true)
    local def = { id = "FailedDisable" }
    local mutation = ManualMutation(function() end, function()
        error("disable boom")
    end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, false)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "disable boom")
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledReappliesWhenAlreadyEnabled()
    local store = makeStore(true)
    local calls = {}
    local def = { id = "ReapplyEnabled" }
    local mutation = ManualMutation(function()
        table.insert(calls, "apply")
    end, function()
        table.insert(calls, "revert")
    end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, { "revert", "apply" })
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledNoOpsWhenAlreadyDisabled()
    local store = makeStore(false)
    local revertCalls = 0
    local def = { id = "AlreadyDisabled" }
    local mutation = ManualMutation(function() end, function()
        revertCalls = revertCalls + 1
    end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, false)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(revertCalls, 0)
    lu.assertFalse(store.read("Enabled"))
end

function TestDefinitionLifecycle:testReapplyDefinitionStopsWhenRevertFails()
    local store = makeStore(true)
    local applyCalls = 0
    local def = { id = "RevertFails" }
    local mutation = ManualMutation(function()
        applyCalls = applyCalls + 1
    end, function()
        error("revert boom")
    end)

    local ok, err = AdamantModpackLib_Internal.mutation.reapply(def, mutation, nil, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "revert boom")
    lu.assertEquals(applyCalls, 0)
end

function TestDefinitionLifecycle:testHybridOrderingIsPatchThenManualOnApplyAndManualThenPatchOnRevert()
    local store = makeStore(false)
    local target = { Value = 0 }
    local order = {}
    local def = { id = "HybridOrdering" }
    local mutation = HybridMutation(function(plan)
            table.insert(order, "build")
            plan:set(target, "Value", 10)
        end, function()
            table.insert(order, "manual-apply")
            target.Value = target.Value + 5
        end, function()
            table.insert(order, "manual-revert")
            target.Value = -1
        end)

    local ok = AdamantModpackLib_Internal.mutation.apply(def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertEquals(order, { "build", "manual-apply" })
    lu.assertEquals(target.Value, 15)

    ok = AdamantModpackLib_Internal.mutation.revert(def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertEquals(order, { "build", "manual-apply", "manual-revert" })
    lu.assertEquals(target.Value, 0)
end


