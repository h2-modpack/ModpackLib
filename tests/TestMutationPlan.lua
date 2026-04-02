local lu = require('luaunit')

TestMutationPlan = {}

function TestMutationPlan:testSetApplyAndRevert()
    local plan = lib.createMutationPlan()
    local tbl = { HP = 100 }

    plan:set(tbl, "HP", 250)

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl.HP, 250)
    lu.assertTrue(plan.revert())
    lu.assertEquals(tbl.HP, 100)
end

function TestMutationPlan:testSetClonesTableValue()
    local plan = lib.createMutationPlan()
    local replacement = { Damage = 100 }
    local tbl = { Data = { Damage = 10 } }

    plan:set(tbl, "Data", replacement)
    plan:apply()
    replacement.Damage = 999

    lu.assertEquals(tbl.Data.Damage, 100)
    plan:revert()
    lu.assertEquals(tbl.Data.Damage, 10)
end

function TestMutationPlan:testSetManyApplyAndRevert()
    local plan = lib.createMutationPlan()
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

function TestMutationPlan:testTransformApplyAndRevert()
    local plan = lib.createMutationPlan()
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

function TestMutationPlan:testAppendCreatesMissingListAndRestoresNil()
    local plan = lib.createMutationPlan()
    local tbl = {}

    plan:append(tbl, "Values", "A")
    plan:apply()

    lu.assertEquals(tbl.Values, { "A" })

    plan:revert()
    lu.assertNil(tbl.Values)
end

function TestMutationPlan:testAppendUniqueUsesDeepEquivalenceByDefault()
    local plan = lib.createMutationPlan()
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

function TestMutationPlan:testAppendUniqueCanUseCustomComparator()
    local plan = lib.createMutationPlan()
    local tbl = { Values = { { Name = "A", Count = 1 } } }

    plan:appendUnique(tbl, "Values", { Name = "A", Count = 2 }, function(a, b)
        return a.Name == b.Name
    end)
    plan:apply()

    lu.assertEquals(#tbl.Values, 1)
end

function TestMutationPlan:testApplyAndRevertAreRepeatSafe()
    local plan = lib.createMutationPlan()
    local tbl = { Values = {} }

    plan:append(tbl, "Values", "A")
    lu.assertTrue(plan:apply())
    lu.assertFalse(plan:apply())
    lu.assertEquals(tbl.Values, { "A" })

    lu.assertTrue(plan:revert())
    lu.assertFalse(plan:revert())
    lu.assertEquals(tbl.Values, {})
end

function TestMutationPlan:testAppendErrorsOnNonTableTarget()
    local plan = lib.createMutationPlan()
    local tbl = { Values = 5 }

    plan:append(tbl, "Values", "A")
    lu.assertError(plan.apply)
end

function TestMutationPlan:testAppendUniqueDoesNotAliasInsertedTable()
    local plan = lib.createMutationPlan()
    local entry = { Name = "A", Meta = { Count = 1 } }
    local tbl = { Values = {} }

    plan:appendUnique(tbl, "Values", entry)
    plan:apply()
    entry.Meta.Count = 999

    lu.assertEquals(tbl.Values[1].Meta.Count, 1)
end

function TestMutationPlan:testInferMutationShapeManual()
    local mode, info = lib.inferMutationShape({
        apply = function() end,
        revert = function() end,
    })

    lu.assertEquals(mode, "manual")
    lu.assertTrue(info.hasManual)
    lu.assertFalse(info.hasPatch)
end

function TestMutationPlan:testInferMutationShapePatch()
    local mode, info = lib.inferMutationShape({
        patchPlan = function() end,
    })

    lu.assertEquals(mode, "patch")
    lu.assertTrue(info.hasPatch)
    lu.assertFalse(info.hasManual)
end

function TestMutationPlan:testInferMutationShapeHybrid()
    local mode, info = lib.inferMutationShape({
        patchPlan = function() end,
        apply = function() end,
        revert = function() end,
    })

    lu.assertEquals(mode, "hybrid")
    lu.assertTrue(info.hasPatch)
    lu.assertTrue(info.hasManual)
end

function TestMutationPlan:testAffectsRunDataIgnoresDeprecatedFlag()
    lu.assertTrue(lib.affectsRunData({ affectsRunData = true }))
    lu.assertFalse(lib.affectsRunData({ affectsRunData = false }))
    lu.assertFalse(lib.affectsRunData({ dataMutation = true }))
    lu.assertFalse(lib.affectsRunData({}))
end

function TestMutationPlan:testApplyDefinitionSupportsPatchOnly()
    local store = lib.createStore({ Enabled = false })
    local target = { Value = 1 }
    local def = {
        patchPlan = function(plan)
            plan:set(target, "Value", 7)
        end,
    }

    local ok, err = lib.applyDefinition(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    ok, err = lib.revertDefinition(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestMutationPlan:testApplyDefinitionNoOpsWhenLifecycleMissingAndRunDataUnaffected()
    local store = lib.createStore({ Enabled = false })
    local def = {
        affectsRunData = false,
    }

    local ok, err = lib.applyDefinition(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)

    ok, err = lib.revertDefinition(def, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

function TestMutationPlan:testSetDefinitionEnabledCommitsOnlyAfterSuccessfulEnable()
    local store = lib.createStore({ Enabled = false })
    local applied = false
    local def = {
        apply = function()
            applied = true
        end,
        revert = function() end,
    }

    local ok, err = lib.setDefinitionEnabled(def, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(applied)
    lu.assertTrue(store.read("Enabled"))
end

function TestMutationPlan:testSetDefinitionEnabledDoesNotCommitFailedEnable()
    local store = lib.createStore({ Enabled = false })
    local def = {
        apply = function()
            error("enable boom")
        end,
        revert = function() end,
    }

    local ok, err = lib.setDefinitionEnabled(def, store, true)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "enable boom")
    lu.assertFalse(store.read("Enabled"))
end

function TestMutationPlan:testSetDefinitionEnabledDoesNotCommitFailedDisable()
    local store = lib.createStore({ Enabled = true })
    local def = {
        apply = function() end,
        revert = function()
            error("disable boom")
        end,
    }

    local ok, err = lib.setDefinitionEnabled(def, store, false)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "disable boom")
    lu.assertTrue(store.read("Enabled"))
end

function TestMutationPlan:testSetDefinitionEnabledReappliesWhenAlreadyEnabled()
    local store = lib.createStore({ Enabled = true })
    local calls = {}
    local def = {
        apply = function()
            table.insert(calls, "apply")
        end,
        revert = function()
            table.insert(calls, "revert")
        end,
    }

    local ok, err = lib.setDefinitionEnabled(def, store, true)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, { "revert", "apply" })
    lu.assertTrue(store.read("Enabled"))
end

function TestMutationPlan:testSetDefinitionEnabledNoOpsWhenAlreadyDisabled()
    local store = lib.createStore({ Enabled = false })
    local revertCalls = 0
    local def = {
        apply = function() end,
        revert = function()
            revertCalls = revertCalls + 1
        end,
    }

    local ok, err = lib.setDefinitionEnabled(def, store, false)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(revertCalls, 0)
    lu.assertFalse(store.read("Enabled"))
end

function TestMutationPlan:testReapplyDefinitionStopsWhenRevertFails()
    local store = lib.createStore({ Enabled = true })
    local applyCalls = 0
    local def = {
        apply = function()
            applyCalls = applyCalls + 1
        end,
        revert = function()
            error("revert boom")
        end,
    }

    local ok, err = lib.reapplyDefinition(def, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "revert boom")
    lu.assertEquals(applyCalls, 0)
end

function TestMutationPlan:testHybridOrderingIsPatchThenManualOnApplyAndManualThenPatchOnRevert()
    local store = lib.createStore({ Enabled = false })
    local target = { Value = 0 }
    local order = {}
    local def = {
        patchPlan = function(plan)
            table.insert(order, "build")
            plan:set(target, "Value", 10)
        end,
        apply = function()
            table.insert(order, "manual-apply")
            target.Value = target.Value + 5
        end,
        revert = function()
            table.insert(order, "manual-revert")
            target.Value = -1
        end,
    }

    local ok = lib.applyDefinition(def, store)
    lu.assertTrue(ok)
    lu.assertEquals(order, { "build", "manual-apply" })
    lu.assertEquals(target.Value, 15)

    ok = lib.revertDefinition(def, store)
    lu.assertTrue(ok)
    lu.assertEquals(order, { "build", "manual-apply", "manual-revert" })
    lu.assertEquals(target.Value, 0)
end
