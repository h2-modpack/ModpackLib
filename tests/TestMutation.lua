local lu = require('luaunit')

TestMutation = {}

local function ApplyPlan(plan)
    return AdamantModpackLib_Internal.mutation.applyPlan(plan)
end

local function RevertPlan(plan)
    return AdamantModpackLib_Internal.mutation.revertPlan(plan)
end

function TestMutation:testBackupRestoresChangedAndRemovedValues()
    local tbl = {
        Count = 1,
        Nested = { Value = "old" },
    }
    local backup, restore = AdamantModpackLib_Internal.mutation.createBackup()

    backup(tbl, "Count", "Nested", "Missing")
    tbl.Count = 7
    tbl.Nested.Value = "new"
    tbl.Missing = "created"
    restore()

    lu.assertEquals(tbl.Count, 1)
    lu.assertEquals(tbl.Nested, { Value = "old" })
    lu.assertNil(tbl.Missing)
end

function TestMutation:testPlanSetSetManyAndTransformApplyAndRevert()
    local tbl = {
        Count = 1,
        Name = "old",
        Flag = false,
    }
    local plan = lib.mutation.createPlan()
        :set(tbl, "Count", 2)
        :setMany(tbl, {
            Name = "new",
            Flag = true,
        })
        :transform(tbl, "Count", function(current)
            return current + 3
        end)

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl, {
        Count = 5,
        Name = "new",
        Flag = true,
    })
    lu.assertFalse(ApplyPlan(plan))
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl, {
        Count = 1,
        Name = "old",
        Flag = false,
    })
    lu.assertFalse(RevertPlan(plan))
end

function TestMutation:testPublicPlanDoesNotExposeExecutionMethods()
    local plan = lib.mutation.createPlan()

    lu.assertNil(plan.apply)
    lu.assertNil(plan.revert)
end

function TestMutation:testPlanExecutorSurvivesLibReload()
    local tbl = { Value = "base" }
    local plan = lib.mutation.createPlan()
        :set(tbl, "Value", "patched")

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.Value, "patched")

    dofile("src/main.lua")
    lib = public

    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.Value, "base")
end

function TestMutation:testPlanTransformReceivesCopiedCurrentValueOnly()
    local tbl = {
        Data = {
            Count = 1,
        },
    }
    local seenExtraArgCount = nil
    local plan = lib.mutation.createPlan()
        :transform(tbl, "Data", function(current, ...)
            seenExtraArgCount = select("#", ...)
            current.Count = current.Count + 1
            return current
        end)

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(seenExtraArgCount, 0)
    lu.assertEquals(tbl.Data, { Count = 2 })
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.Data, { Count = 1 })
end

function TestMutation:testPlanTransformErrorCannotMutateOriginalCurrentValue()
    local tbl = {
        Data = {
            Count = 1,
        },
    }
    local plan = lib.mutation.createPlan()
        :transform(tbl, "Data", function(current)
            current.Count = 999
            error("transform boom")
        end)

    lu.assertErrorMsgContains("transform boom", function()
        ApplyPlan(plan)
    end)
    lu.assertEquals(tbl.Data, { Count = 1 })
end

function TestMutation:testPlanTransformClonesReturnedTable()
    local tbl = {
        Data = {
            Count = 1,
        },
    }
    local replacement = { Count = 2 }
    local plan = lib.mutation.createPlan()
        :transform(tbl, "Data", function()
            return replacement
        end)

    lu.assertTrue(ApplyPlan(plan))
    replacement.Count = 999
    lu.assertEquals(tbl.Data, { Count = 2 })
end

function TestMutation:testPlanAppendAndAppendUniqueApplyAndRevert()
    local tbl = {
        Values = { "a" },
        Objects = {
            { id = 1 },
        },
    }
    local plan = lib.mutation.createPlan()
        :append(tbl, "Values", "b")
        :appendUnique(tbl, "Values", "a")
        :appendUnique(tbl, "Objects", { id = 1 })
        :appendUnique(tbl, "Objects", { id = 2 })

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.Values, { "a", "b" })
    lu.assertEquals(tbl.Objects, {
        { id = 1 },
        { id = 2 },
    })
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.Values, { "a" })
    lu.assertEquals(tbl.Objects, {
        { id = 1 },
    })
end

function TestMutation:testPlanRemoveElementAndSetElementApplyAndRevert()
    local tbl = {
        Values = { "a", "b", "c" },
        Objects = {
            { id = 1, value = "old" },
            { id = 2, value = "keep" },
        },
    }
    local sameId = function(a, b)
        return a.id == b.id
    end
    local plan = lib.mutation.createPlan()
        :removeElement(tbl, "Values", "b")
        :setElement(tbl, "Objects", { id = 1 }, { id = 1, value = "new" }, sameId)

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.Values, { "a", "c" })
    lu.assertEquals(tbl.Objects, {
        { id = 1, value = "new" },
        { id = 2, value = "keep" },
    })
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.Values, { "a", "b", "c" })
    lu.assertEquals(tbl.Objects, {
        { id = 1, value = "old" },
        { id = 2, value = "keep" },
    })
end

function TestMutation:testPlanListOperationsCreateMissingLists()
    local tbl = {}
    local plan = lib.mutation.createPlan()
        :append(tbl, "Values", "a")
        :appendUnique(tbl, "Objects", { id = 1 })

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.Values, { "a" })
    lu.assertEquals(tbl.Objects, { { id = 1 } })
    lu.assertTrue(RevertPlan(plan))
    lu.assertNil(tbl.Values)
    lu.assertNil(tbl.Objects)
end

function TestMutation:testPlanListOperationsRejectNonTableTargets()
    local tbl = {
        Values = "not-list",
    }

    lu.assertErrorMsgContains("append requires table", function()
        local plan = lib.mutation.createPlan()
            :append(tbl, "Values", "a")
        ApplyPlan(plan)
    end)

    lu.assertErrorMsgContains("removeElement requires table", function()
        local plan = lib.mutation.createPlan()
            :removeElement(tbl, "Values", "a")
        ApplyPlan(plan)
    end)

    lu.assertErrorMsgContains("setElement requires table", function()
        local plan = lib.mutation.createPlan()
            :setElement(tbl, "Values", "a", "b")
        ApplyPlan(plan)
    end)
end

function TestMutation:testPlanApplyRestoresEarlierMutationsWhenLaterOperationFails()
    local tbl = {
        Count = 1,
        Values = "not-list",
    }
    local plan = lib.mutation.createPlan()
        :set(tbl, "Count", 2)
        :append(tbl, "Values", "a")

    lu.assertErrorMsgContains("append requires table", function()
        ApplyPlan(plan)
    end)

    lu.assertEquals(tbl, {
        Count = 1,
        Values = "not-list",
    })
    lu.assertFalse(RevertPlan(plan))
end

function TestMutation:testPlanReapplyAfterRevertCapturesFreshSnapshot()
    local tbl = {
        Count = 1,
    }
    local plan = lib.mutation.createPlan()
        :set(tbl, "Count", 2)

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.Count, 2)
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.Count, 1)

    tbl.Count = 5

    lu.assertTrue(ApplyPlan(plan))
    lu.assertEquals(tbl.Count, 2)
    lu.assertTrue(RevertPlan(plan))
    lu.assertEquals(tbl.Count, 5)
end

function TestMutation:testFailedPlanRetryRestoresToLatestSnapshot()
    local tbl = {
        Count = 1,
        Values = "not-list",
    }
    local plan = lib.mutation.createPlan()
        :set(tbl, "Count", 2)
        :append(tbl, "Values", "a")

    lu.assertErrorMsgContains("append requires table", function()
        ApplyPlan(plan)
    end)
    lu.assertEquals(tbl.Count, 1)

    tbl.Count = 4

    lu.assertErrorMsgContains("append requires table", function()
        ApplyPlan(plan)
    end)
    lu.assertEquals(tbl, {
        Count = 4,
        Values = "not-list",
    })
end

