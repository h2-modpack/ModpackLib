local lu = require('luaunit')

TestPrepareDefinition = {}

function TestPrepareDefinition:setUp()
    lib.coordinator.register("test-pack", nil)
    lib.coordinator.registerRebuild("test-pack", nil)
    CaptureWarnings()
end

function TestPrepareDefinition:tearDown()
    lib.coordinator.register("test-pack", nil)
    lib.coordinator.registerRebuild("test-pack", nil)
    RestoreWarnings()
end

local function createAndActivate(pluginGuid, definition, store, session)
    local _, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })
    return authorHost.tryActivate()
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

    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, raw)
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

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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
    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
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
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "Enabled", default = true },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsInvalidMetadataFieldTypes()
    lu.assertErrorMsgContains("definition.invalid_field_type", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            modpack = "test-pack",
            id = "Example",
            name = 7,
            storage = {},
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsDefinitionWithoutId()
    lu.assertErrorMsgContains("definition.missing_id", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            name = "Missing ID",
            storage = {},
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsInvalidDefinitionId()
    lu.assertErrorMsgContains("definition.id 'Bad.Id' must start with a letter", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "Bad.Id",
            name = "Bad ID",
            storage = {},
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsDefinitionWithoutName()
    lu.assertErrorMsgContains("definition.missing_name", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "MissingName",
            storage = {},
        })
    end)
end

function TestPrepareDefinition:testCreateModuleHostRequestsCoordinatorRebuildOnStructuralMismatch()
    local owner = {}
    local rebuildReason = nil

    lib.coordinator.register("test-pack", { ModEnabled = true })
    lib.coordinator.registerRebuild("test-pack", function(reason)
        rebuildReason = reason
        return true
    end)

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, session = CreateModuleState({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createAndActivate("test-module", prepared, store, session)

    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(lib.getLiveModuleHost("test-module"))
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(rebuildReason.kind, "structural_definition_changed")
    lu.assertEquals(rebuildReason.moduleId, "Example")
    lu.assertEquals(rebuildReason.modpack, "test-pack")
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateModuleHostErrorsWhenCoordinatedRebuildCallbackIsMissing()
    local owner = {}

    lib.coordinator.register("test-pack", { ModEnabled = true })

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, session = CreateModuleState({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local ok, err = createAndActivate("test-module", prepared, store, session)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "host.structural_rebuild_unavailable")
    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(AdamantModpackLib_Internal.pendingCoordinatorRebuilds[prepared])
end

function TestPrepareDefinition:testCreateModuleHostErrorsAndKeepsPendingReasonWhenRebuildRequestIsRejected()
    local owner = {}

    lib.coordinator.register("test-pack", { ModEnabled = true })
    lib.coordinator.registerRebuild("test-pack", function()
        return false
    end)

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })

    local store, session = CreateModuleState({
        Enabled = false,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local ok, err = createAndActivate("test-module", prepared, store, session)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "host.structural_rebuild_unavailable")
    lu.assertTrue(owner.requiresFullReload)
    lu.assertNotNil(AdamantModpackLib_Internal.pendingCoordinatorRebuilds[prepared])
end

function TestPrepareDefinition:testPrepareDefinitionKeepsStableStructuralFingerprint()
    local owner = {}

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    lu.assertEquals(owner.requiresFullReload, nil)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateStoreAcceptsPreparedDefinition()
    local owner = {}
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    local store, session = CreateModuleState({
        EnabledFlag = true,
    }, definition)

    lu.assertEquals(store.read("EnabledFlag"), true)
    lu.assertEquals(session.read("EnabledFlag"), true)
    lu.assertEquals(#Warnings, 0)
end

function TestPrepareDefinition:testCreateStoreRejectsRawDefinition()
    lu.assertErrorMsgContains(
        "createModuleState expects a prepared definition",
        function()
            CreateModuleState({}, {
                storage = {
                    { type = "bool", alias = "EnabledFlag", default = false },
                },
            })
        end)
end

function TestPrepareDefinition:testCreateStoreRejectsNonTableConfig()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "RejectNonTableConfig",
        name = "Reject Non Table Config",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })

    lu.assertErrorMsgContains("store.invalid_config", function()
        CreateModuleState(nil, definition)
    end)
end

function TestPrepareDefinition:testCreateModuleHostRejectsRawDefinition()
    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "RejectRawDefinition",
        name = "Reject Raw Definition",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, session = CreateModuleState({}, prepared)

    lu.assertErrorMsgContains("prepared definition is required", function()
        AdamantModpackLib_Internal.moduleHost.create({
            pluginGuid = "test-raw-host",
            definition = {
                storage = {
                    { type = "bool", alias = "EnabledFlag", default = false },
                },
            },
            store = store,
            session = session,
            drawTab = function() end,
        })
    end)
end

function TestPrepareDefinition:testCreateStoreRequiresStorage()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "NoStorage",
        name = "No Storage",
    })

    local store, session = CreateModuleState({}, definition)

    lu.assertFalse(store.read("Enabled"))
    lu.assertFalse(session.read("DebugMode"))
end

function TestPrepareDefinition:testPrepareDefinitionPreservesHashGroupPlan()
    local owner = {}
    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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

function TestPrepareDefinition:testPrepareDefinitionRejectsInvalidHashGroupPrefix()
    lu.assertErrorMsgContains("hashGroupPlan[1].keyPrefix 'bad-prefix' must start with a letter", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "bad-prefix",
                    items = {
                        "EnabledFlag",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsUnknownHashGroupField()
    lu.assertErrorMsgContains("unknown hashGroupPlan[1] field 'itemz'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    itemz = {
                        "EnabledFlag",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsDuplicateHashGroupPrefix()
    lu.assertErrorMsgContains("duplicate hashGroupPlan keyPrefix 'main'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "bool", alias = "OtherFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "EnabledFlag",
                    },
                },
                {
                    keyPrefix = "main",
                    items = {
                        "OtherFlag",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsDuplicateHashGroupAlias()
    lu.assertErrorMsgContains("duplicate hashGroupPlan alias 'EnabledFlag'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "bool", alias = "OtherFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        { "EnabledFlag", "OtherFlag" },
                    },
                },
                {
                    keyPrefix = "extra",
                    items = {
                        "EnabledFlag",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsInvalidHashGroupItemShape()
    lu.assertErrorMsgContains("hashGroupPlan[1].items[1] must be an alias string or alias list", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        7,
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsUnknownHashGroupAlias()
    lu.assertErrorMsgContains("references unknown storage alias 'MissingAlias'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "MissingAlias",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsHashGroupEnabledAlias()
    lu.assertErrorMsgContains("alias 'Enabled' is encoded as module enable state", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "Enabled",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsHashGroupPackedChildAlias()
    lu.assertErrorMsgContains("is a packed child alias; only root storage aliases are supported", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                {
                    type = "packedInt",
                    alias = "PackedRoot",
                    bits = {
                        { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = false },
                    },
                },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "EnabledBit",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsHashGroupNonHashAlias()
    lu.assertErrorMsgContains("is excluded from hashes; only hash root aliases are supported", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "string", alias = "FilterMode", persist = false, hash = false, default = "all", maxLen = 16 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "FilterMode",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsHashGroupUnpackableAlias()
    lu.assertErrorMsgContains("alias 'FilterMode' cannot be packed", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "string", alias = "FilterMode", default = "all", maxLen = 16 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        "FilterMode",
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionRejectsHashGroupItemOver32Bits()
    lu.assertErrorMsgContains("hashGroupPlan[1].items[1] exceeds 32 packed bits", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "BadHashGroup",
            name = "Bad Hash Group",
            storage = {
                { type = "int", alias = "WideA", default = 0, min = 0, max = 1, width = 20 },
                { type = "int", alias = "WideB", default = 0, min = 0, max = 1, width = 20 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "main",
                    items = {
                        { "WideA", "WideB" },
                    },
                },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionUsesStorageDefaultsInFingerprint()
    local owner = {}
    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, { Count = 1 }, {
            modpack = "test-pack",
            id = "Example",
            name = "Example",
            storage = {
                { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
            },
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionTracksQuickContentForLowerLevelHosts()
    local owner = {}

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "QuickSurface",
        name = "Quick Surface",
    }, {
        hasQuickContent = false,
    })

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "QuickSurface",
        name = "Quick Surface",
    }, {
        hasQuickContent = true,
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end

function TestPrepareDefinition:testPrepareDefinitionRejectsUnknownStructuralSurfaceOption()
    lu.assertErrorMsgContains("unknown option 'quickContent'", function()
        AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            id = "UnknownSurface",
            name = "Unknown Surface",
        }, {
            hasQuickContent = true,
            quickContent = true,
        })
    end)
end

function TestPrepareDefinition:testPrepareDefinitionFingerprintIgnoresExternalTables()
    local owner = {}

    local first = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        storage = {
            { type = "int", alias = "Count", default = 3, min = 0, max = 10 },
        },
    })
    local second = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
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

function TestPrepareDefinition:testPrepareDefinitionFingerprintTracksTooltipChanges()
    local owner = {}

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        tooltip = "old",
        storage = {},
    })

    AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = "test-pack",
        id = "Example",
        name = "Example",
        tooltip = "new",
        storage = {},
    })

    lu.assertTrue(owner.requiresFullReload)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "structural definition changed during hot reload")
end
