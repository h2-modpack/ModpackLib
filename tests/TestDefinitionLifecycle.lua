local lu = require('luaunit')

TestDefinitionLifecycle = {}

local function ApplyPlan(plan)
    return AdamantModpackLib_Internal.mutation.applyPlan(plan)
end

local function RevertPlan(plan)
    return AdamantModpackLib_Internal.mutation.revertPlan(plan)
end

local function PatchMutation(fn)
    return {
        affectsRunData = true,
        patchMutation = fn,
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

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.HP, 250)
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.HP, 100)
end

function TestDefinitionLifecycle:testSetClonesTableValue()
    local plan = lib.mutation.createPlan()
    local replacement = { Damage = 100 }
    local tbl = { Data = { Damage = 10 } }

    plan:set(tbl, "Data", replacement)
    ApplyPlan(plan)
    replacement.Damage = 999

    lu.assertEquals(tbl.Data.Damage, 100)
    RevertPlan(plan)
    lu.assertEquals(tbl.Data.Damage, 10)
end

function TestDefinitionLifecycle:testSetManyApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { A = 1, B = 2, C = 3 }

    plan:setMany(tbl, { A = 10, B = 20 })
    ApplyPlan(plan)

    lu.assertEquals(tbl.A, 10)
    lu.assertEquals(tbl.B, 20)
    lu.assertEquals(tbl.C, 3)

    RevertPlan(plan)
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

    ApplyPlan(plan)
    lu.assertEquals(tbl.Requirements, { "A", "B" })

    RevertPlan(plan)
    lu.assertEquals(tbl.Requirements, { "A" })
end

function TestDefinitionLifecycle:testAppendCreatesMissingListAndRestoresNil()
    local plan = lib.mutation.createPlan()
    local tbl = {}

    plan:append(tbl, "Values", "A")
    ApplyPlan(plan)

    lu.assertEquals(tbl.Values, { "A" })

    RevertPlan(plan)
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
    ApplyPlan(plan)

    lu.assertEquals(#tbl.Requirements, 1)
    RevertPlan(plan)
    lu.assertEquals(#tbl.Requirements, 1)
end

function TestDefinitionLifecycle:testAppendUniqueCanUseCustomComparator()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 } } }

    plan:appendUnique(tbl, "Values", { Name = "A", Count = 2 }, function(a, b)
        return a.Name == b.Name
    end)
    ApplyPlan(plan)

    lu.assertEquals(#tbl.Values, 1)
end

function TestDefinitionLifecycle:testApplyAndRevertAreRepeatSafe()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = {} }

    plan:append(tbl, "Values", "A")
    lu.assertTrue(ApplyPlan(plan))
    lu.assertFalse(ApplyPlan(plan))
    lu.assertEquals(tbl.Values, { "A" })

    lu.assertTrue(RevertPlan(plan))
    lu.assertFalse(RevertPlan(plan))
    lu.assertEquals(tbl.Values, {})
end

function TestDefinitionLifecycle:testAppendErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:append(tbl, "Values", "A")
    lu.assertError(function()
        ApplyPlan(plan)
    end)
end

function TestDefinitionLifecycle:testAppendUniqueDoesNotAliasInsertedTable()
    local plan = lib.mutation.createPlan()
    local entry = { Name = "A", Meta = { Count = 1 } }
    local tbl = { Values = {} }

    plan:appendUnique(tbl, "Values", entry)
    ApplyPlan(plan)
    entry.Meta.Count = 999

    lu.assertEquals(tbl.Values[1].Meta.Count, 1)
end

function TestDefinitionLifecycle:testRemoveElementApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:removeElement(tbl, "Values", "B")
    ApplyPlan(plan)

    lu.assertEquals(tbl.Values, { "A", "C" })

    RevertPlan(plan)
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestDefinitionLifecycle:testRemoveElementCanUseCustomComparator()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 }, { Name = "B", Count = 2 } } }

    plan:removeElement(tbl, "Values", { Name = "A", Count = 999 }, function(a, b)
        return a.Name == b.Name
    end)
    ApplyPlan(plan)

    lu.assertEquals(#tbl.Values, 1)
    lu.assertEquals(tbl.Values[1].Name, "B")
end

function TestDefinitionLifecycle:testSetElementApplyAndRevert()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:setElement(tbl, "Values", "B", "Z")
    ApplyPlan(plan)

    lu.assertEquals(tbl.Values, { "A", "Z", "C" })

    RevertPlan(plan)
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestDefinitionLifecycle:testSetElementClonesReplacementTable()
    local plan = lib.mutation.createPlan()
    local replacement = { Name = "Z", Meta = { Count = 10 } }
    local tbl = { Values = { { Name = "A" }, { Name = "B" } } }

    plan:setElement(tbl, "Values", { Name = "B" }, replacement, function(a, b)
        return a.Name == b.Name
    end)
    ApplyPlan(plan)
    replacement.Meta.Count = 999

    lu.assertEquals(tbl.Values[2].Name, "Z")
    lu.assertEquals(tbl.Values[2].Meta.Count, 10)
end

function TestDefinitionLifecycle:testRemoveElementErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:removeElement(tbl, "Values", "A")
    lu.assertError(function()
        ApplyPlan(plan)
    end)
end

function TestDefinitionLifecycle:testSetElementErrorsOnNonTableTarget()
    local plan = lib.mutation.createPlan()
    local tbl = { Values = 5 }

    plan:setElement(tbl, "Values", "A", "B")
    lu.assertError(function()
        ApplyPlan(plan)
    end)
end

function TestDefinitionLifecycle:testAffectsRunDataIgnoresDeprecatedFlag()
    lu.assertTrue(AdamantModpackLib_Internal.mutation.affectsRunData({ affectsRunData = true }))
    lu.assertTrue(AdamantModpackLib_Internal.mutation.affectsRunData({ patchMutation = function() end }))
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

function TestDefinitionLifecycle:testApplyDefinitionFailsWhenAffectedPatchLifecycleMissing()
    local store = makeStore(false)
    local def = { id = "MissingPatchLifecycle" }

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, { affectsRunData = true }, nil, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "no supported mutation lifecycle found")
end

function TestDefinitionLifecycle:testApplyFailureRestoresPreviousPatchRuntime()
    local target = { Value = "base" }
    local storeA = makeStore(true)
    local def = {
        modpack = "test-pack",
        id = "RestorePatchRuntimeOnApplyFailure",
    }
    local mutationA = PatchMutation(function(plan)
        plan:set(target, "Value", "first")
    end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "first")

    local storeB = makeStore(true)
    local mutationB = PatchMutation(function()
        error("replacement patch boom")
    end)

    ok, err = AdamantModpackLib_Internal.mutation.apply(def, mutationB, nil, storeB)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "replacement patch boom")
    lu.assertEquals(target.Value, "first")

    ok, err = AdamantModpackLib_Internal.mutation.revert(def, mutationA, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
end

function TestDefinitionLifecycle:testApplyOnLoadDisabledDoesNotBuildInactivePatch()
    local store = makeStore(false)
    local buildCalls = 0
    local def = {
        modpack = "test-pack",
        id = "InactivePatchRevert",
    }
    local mutation = PatchMutation(function()
        buildCalls = buildCalls + 1
    end)

    local ok, err = HostLifecycle.applyOnLoad(def, mutation, nil, store)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 0)
end

function TestDefinitionLifecycle:testSetDefinitionEnabledCommitsOnlyAfterSuccessfulEnable()
    local store = makeStore(false)
    local target = { Value = false }
    local def = { id = "SuccessfulEnable" }
    local mutation = PatchMutation(function(plan)
        plan:set(target, "Value", true)
    end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(target.Value)
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedEnable()
    local store = makeStore(false)
    local def = { id = "FailedEnable" }
    local mutation = PatchMutation(function()
        error("enable boom")
    end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, true)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "enable boom")
    lu.assertFalse(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledReappliesWhenAlreadyEnabled()
    local store = makeStore(true)
    local target = { Value = 0 }
    local buildCalls = 0
    local def = { id = "ReapplyEnabled" }
    local mutation = PatchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", buildCalls)
    end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)

    ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 2)
    lu.assertEquals(target.Value, 2)
    lu.assertTrue(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledDisablesActivePatch()
    local store = makeStore(true)
    local target = { Value = "base" }
    local def = { id = "DisableActivePatch" }
    local mutation = PatchMutation(function(plan)
        plan:set(target, "Value", "patched")
    end)

    local ok, err = AdamantModpackLib_Internal.mutation.apply(def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "patched")

    ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, false)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
    lu.assertFalse(store.read("Enabled"))
end

function TestDefinitionLifecycle:testSetDefinitionEnabledNoOpsWhenAlreadyDisabled()
    local store = makeStore(false)
    local buildCalls = 0
    local def = { id = "AlreadyDisabled" }
    local mutation = PatchMutation(function()
        buildCalls = buildCalls + 1
    end)

    local ok, err = HostLifecycle.setEnabled(def, mutation, nil, store, false)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 0)
    lu.assertFalse(store.read("Enabled"))
end


