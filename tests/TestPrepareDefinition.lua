local lu = require('luaunit')

TestPrepareDefinition = {}

function TestPrepareDefinition:setUp()
    lib.lifecycle.registerCoordinator("test-pack", nil)
    lib.lifecycle.registerCoordinatorRebuild("test-pack", nil)
    CaptureWarnings()
end

function TestPrepareDefinition:tearDown()
    lib.lifecycle.registerCoordinator("test-pack", nil)
    lib.lifecycle.registerCoordinatorRebuild("test-pack", nil)
    RestoreWarnings()
end

function TestPrepareDefinition:testPrepareDefinitionReturnsPreparedClone()
    local owner = {}
    local raw = {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "group",
                items = {
                    "EnabledFlag",
                },
            },
        },
    }

    local prepared = lib.prepareDefinition(owner, raw)
    raw.name = "Changed Name"
    raw.storage[1].alias = "ChangedAlias"
    raw.hashGroupPlan[1].keyPrefix = "changed_group"

    lu.assertNotIs(prepared, raw)
    lu.assertEquals(prepared.name, "Example")
    lu.assertEquals(prepared.storage[1].alias, "Enabled")
    lu.assertEquals(prepared.storage[2].alias, "DebugMode")
    lu.assertEquals(prepared.storage[3].alias, "EnabledFlag")
    lu.assertEquals(prepared.hashGroupPlan[1].keyPrefix, "group")
    lu.assertTrue(prepared._preparedDefinition)
    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testPrepareDefinitionMarksStructuralReloadMismatch()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
    lu.assertEquals(prepared.storage[3].alias, "OtherFlag")
end

function TestPrepareDefinition:testPrepareDefinitionInjectsBuiltInStorage()
    local prepared = lib.prepareDefinition({}, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 0, min = 0, max = 10 },
        },
    })

    lu.assertEquals(prepared.storage[1].alias, "Enabled")
    lu.assertFalse(prepared.storage[1].default)
    lu.assertEquals(prepared.storage[2].alias, "DebugMode")
    lu.assertFalse(prepared.storage[2].default)
    lu.assertFalse(prepared.storage[2].hash)
    lu.assertEquals(prepared.storage[3].alias, "Count")
end

function TestPrepareDefinition:testPrepareDefinitionRejectsReservedBuiltInStorageAliases()
    lu.assertErrorMsgContains("storage alias 'Enabled' is reserved by Lib", function()
        lib.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "Enabled", default = true },
            },
        })
    end)
end

function TestPrepareDefinition:testCreateModuleHostRequestsCoordinatorRebuildOnStructuralMismatch()
    local owner = {}
    local rebuildReason = nil

    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lib.lifecycle.registerCoordinatorRebuild("test-pack", function(reason)
        rebuildReason = reason
        return true
    end)

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local host = lib.createModuleHost({
        pluginGuid = "test-module",
        definition = prepared,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(lib.getLiveModuleHost("test-module"), host)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(rebuildReason.kind, "structural_definition_changed")
    lu.assertEquals(rebuildReason.moduleId, "Example")
    lu.assertEquals(rebuildReason.modpack, "test-pack")
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateModuleHostWarnsWhenCoordinatedRebuildCallbackIsMissing()
    local owner = {}

    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    lib.createModuleHost({
        pluginGuid = "test-module",
        definition = prepared,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
    lu.assertNotNil(AdamantModpackLib_Internal.pendingCoordinatorRebuilds[prepared])
end

function TestPrepareDefinition:testCreateModuleHostKeepsPendingReasonWhenRebuildRequestIsRejected()
    local owner = {}

    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lib.lifecycle.registerCoordinatorRebuild("test-pack", function()
        return false
    end)

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    lib.createModuleHost({
        pluginGuid = "test-module",
        definition = prepared,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(AdamantModpackLib_Internal.pendingCoordinatorRebuilds[prepared])
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end

function TestPrepareDefinition:testPrepareDefinitionIgnoresBehaviorOnlyChanges()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        affectsRunData = true,
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
        patchPlan = function() end,
    })

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        affectsRunData = true,
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
        patchPlan = function()
            return "changed"
        end,
    })

    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateStoreAcceptsPreparedDefinition()
    local owner = {}
    local definition = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local store, session = lib.createStore({
        EnabledFlag = true,
    }, definition)

    lu.assertEquals(store.read("EnabledFlag"), true)
    lu.assertEquals(session.read("EnabledFlag"), true)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateStoreRejectsRawDefinition()
    lu.assertErrorMsgContains(
        "createStore expects a prepared definition",
        function()
            lib.createStore({}, {
                storage = {
                    { type = "bool", alias = "EnabledFlag", default = false },
                },
            })
        end)
end

function TestPrepareDefinition:testCreateStoreRequiresStorage()
    local definition = lib.prepareDefinition({}, {
        id = "NoStorage",
        name = "No Storage",
    })

    local store, session = lib.createStore({}, definition)

    lu.assertFalse(store.read("Enabled"))
    lu.assertFalse(session.read("DebugMode"))
end

function TestPrepareDefinition:testPrepareDefinitionPreservesHashGroupPlan()
    local owner = {}
    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Tier", default = 0, min = 0, max = 3 },
            { type = "bool", alias = "DebugFlag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "main",
                items = {
                    { "EnabledFlag", "Tier" },
                    "DebugFlag",
                },
            },
        },
    })

    lu.assertEquals(prepared.hashGroupPlan[1].keyPrefix, "main")
    lu.assertEquals(prepared.hashGroupPlan[1].items[1][1], "EnabledFlag")
    lu.assertEquals(prepared.hashGroupPlan[1].items[1][2], "Tier")
    lu.assertEquals(prepared.hashGroupPlan[1].items[2], "DebugFlag")
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testPrepareDefinitionUsesStorageDefaultsInFingerprint()
    local owner = {}
    local prepared = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = true },
            { type = "int", alias = "Count", default = 7, min = 0, max = 10 },
        },
    })

    lu.assertFalse(prepared.storage[1].default)
    lu.assertFalse(prepared.storage[2].default)
    lu.assertTrue(prepared.storage[3].default)
    lu.assertEquals(prepared.storage[4].default, 7)
    lu.assertStrContains(prepared._structuralFingerprint, "EnabledFlag")
    lu.assertStrContains(prepared._structuralFingerprint, "Count")
end

function TestPrepareDefinition:testPrepareDefinitionTreatsStorageDefaultChangesAsStructural()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 4, min = 0, max = 10 },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end

function TestPrepareDefinition:testPrepareDefinitionRejectsLegacyDataDefaultsArgument()
    lu.assertErrorMsgContains("storage defaults on definition.storage nodes", function()
        lib.prepareDefinition({}, { Count = 1 }, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionFingerprintIgnoresExternalTables()
    local owner = {}

    local first = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })
    local second = lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })

    lu.assertEquals(first._structuralFingerprint, second._structuralFingerprint)
    lu.assertNil(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testPrepareDefinitionFingerprintTracksHashGroupPlanChanges()
    local owner = {}

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "LargeA", default = 0, min = 0, max = 65535 },
            { type = "int", alias = "LargeB", default = 0, min = 0, max = 65535 },
            { type = "bool", alias = "Flag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "split",
                items = {
                    { "LargeA", "LargeB" },
                    "Flag",
                },
            },
        },
    })

    lib.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "LargeA", default = 0, min = 0, max = 65535 },
            { type = "int", alias = "LargeB", default = 0, min = 0, max = 65535 },
            { type = "bool", alias = "Flag", default = false },
        },
        hashGroupPlan = {
            {
                keyPrefix = "split",
                items = {
                    { "LargeA" },
                    { "LargeB", "Flag" },
                },
            },
        },
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end
