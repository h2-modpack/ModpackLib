local lu = require('luaunit')

TestMutation = {}

function TestMutation:testBackupRestoresChangedAndRemovedValues()
    local tbl = {
        Count = 1,
        Nested = { Value = "old" },
    }
    local backup, restore = lib.mutation.createBackup()

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

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl, {
        Count = 5,
        Name = "new",
        Flag = true,
    })
    lu.assertFalse(plan:apply())
    lu.assertTrue(plan:revert())
    lu.assertEquals(tbl, {
        Count = 1,
        Name = "old",
        Flag = false,
    })
    lu.assertFalse(plan:revert())
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

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl.Values, { "a", "b" })
    lu.assertEquals(tbl.Objects, {
        { id = 1 },
        { id = 2 },
    })
    lu.assertTrue(plan:revert())
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

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl.Values, { "a", "c" })
    lu.assertEquals(tbl.Objects, {
        { id = 1, value = "new" },
        { id = 2, value = "keep" },
    })
    lu.assertTrue(plan:revert())
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

    lu.assertTrue(plan:apply())
    lu.assertEquals(tbl.Values, { "a" })
    lu.assertEquals(tbl.Objects, { { id = 1 } })
    lu.assertTrue(plan:revert())
    lu.assertNil(tbl.Values)
    lu.assertNil(tbl.Objects)
end

function TestMutation:testPlanListOperationsRejectNonTableTargets()
    local tbl = {
        Values = "not-list",
    }

    lu.assertErrorMsgContains("append requires table", function()
        lib.mutation.createPlan()
            :append(tbl, "Values", "a")
            :apply()
    end)

    lu.assertErrorMsgContains("removeElement requires table", function()
        lib.mutation.createPlan()
            :removeElement(tbl, "Values", "a")
            :apply()
    end)

    lu.assertErrorMsgContains("setElement requires table", function()
        lib.mutation.createPlan()
            :setElement(tbl, "Values", "a", "b")
            :apply()
    end)
end

function TestMutation:testManualLifecycleHooksReceiveStore()
    local reads = {}
    local store = {
        read = function(alias)
            table.insert(reads, alias)
            if alias == "Mode" then
                return "manual"
            end
            return nil
        end,
    }
    local def = {
        affectsRunData = true,
        apply = function(receivedStore)
            lu.assertEquals(receivedStore, store)
            lu.assertEquals(receivedStore.read("Mode"), "manual")
        end,
        revert = function(receivedStore)
            lu.assertEquals(receivedStore, store)
            lu.assertEquals(receivedStore.read("Mode"), "manual")
        end,
    }

    lu.assertTrue(lib.lifecycle.applyMutation(def, store))
    lu.assertTrue(lib.lifecycle.revertMutation(def, store))
    lu.assertEquals(reads, { "Mode", "Mode" })
end

function TestMutation:testManualLifecycleFallbackRevertReceivesStore()
    local reverted = false
    local store = {
        read = function(alias)
            return alias == "Enabled" and true or nil
        end,
    }
    local def = {
        affectsRunData = true,
        apply = function() end,
        revert = function(receivedStore)
            lu.assertEquals(receivedStore, store)
            reverted = true
        end,
    }

    lu.assertTrue(lib.lifecycle.revertMutation(def, store))
    lu.assertTrue(reverted)
end
