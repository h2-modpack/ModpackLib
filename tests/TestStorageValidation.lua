local lu = require('luaunit')

TestStorageValidation = {}

function TestStorageValidation:setUp()
    CaptureWarnings()
end

function TestStorageValidation:tearDown()
    RestoreWarnings()
end

function TestStorageValidation:testDuplicateAliasFails()
    lu.assertErrorMsgContains("duplicate alias 'Flag'", function()
        AdamantModpackLib_Internal.storage.validate({
            { type = "bool", alias = "Flag", default = false },
            { type = "bool", alias = "Flag", default = false },
        }, "DuplicateAlias")
    end)
end

function TestStorageValidation:testInvalidRootAliasFails()
    lu.assertErrorMsgContains("alias 'Bad-Alias' must start with a letter", function()
        AdamantModpackLib_Internal.storage.validate({
            { type = "bool", alias = "Bad-Alias", default = false },
        }, "InvalidRootAlias")
    end)
end

function TestStorageValidation:testInvalidPackedChildAliasFails()
    lu.assertErrorMsgContains("alias 'Bad.Child' must start with a letter", function()
        AdamantModpackLib_Internal.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "Bad.Child", offset = 0, width = 1, type = "bool", default = false },
                },
            },
        }, "InvalidPackedChildAlias")
    end)
end

function TestStorageValidation:testInvalidTableRowAliasFails()
    lu.assertErrorMsgContains("alias 'Bad=Row' must start with a letter", function()
        AdamantModpackLib_Internal.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Bad=Row", default = false },
                },
            },
        }, "InvalidTableRowAlias")
    end)
end

function TestStorageValidation:testTransientRootRegistersAliasButNotPersistedRoots()
    local storage = {
        { type = "bool", alias = "Enabled", default = false },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
    }

    AdamantModpackLib_Internal.storage.validate(storage, "TransientRoot")

    lu.assertEquals(#lib.hashing.getRoots(storage), 1)
    lu.assertEquals(lib.hashing.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(lib.hashing.getAliases(storage).FilterText)
    lu.assertEquals(#Warnings, 0)
end

function TestStorageValidation:testRuntimeCacheRootRegistersAliasButNotHashRoot()
    local storage = {
        { type = "bool", alias = "Enabled", default = false },
        { type = "bool", alias = "RecordingArmed", default = false, stage = false, hash = false },
    }

    AdamantModpackLib_Internal.storage.validate(storage, "RuntimeCacheRoot")

    lu.assertEquals(#lib.hashing.getRoots(storage), 1)
    lu.assertEquals(lib.hashing.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(lib.hashing.getAliases(storage).RecordingArmed)
    lu.assertEquals(#AdamantModpackLib_Internal.storage.getRuntimeCacheRoots(storage), 1)
    lu.assertEquals(#Warnings, 0)
end

function TestStorageValidation:testRuntimePackedIntFails()
    lu.assertErrorMsgContains("stage=false packedInt roots are not supported", function()
        AdamantModpackLib_Internal.storage.validate({
            {
                type = "packedInt",
                alias = "RuntimePacked",
                stage = false,
                hash = false,
                bits = {
                    { alias = "Bit", offset = 0, width = 1, type = "bool", default = false },
                },
            },
        }, "RuntimePacked")
    end)
end

function TestStorageValidation:testUnknownRootStorageFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        AdamantModpackLib_Internal.storage.validate({
            { type = "int", alias = "Count", default = 0, min = 0, max = 10, defalt = 1 },
        }, "UnknownRootField")
    end)
end

function TestStorageValidation:testUnknownFieldForStorageTypeFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        AdamantModpackLib_Internal.storage.validate({
            { type = "bool", alias = "Flag", default = false, width = 1 },
        }, "UnknownTypeField")
    end)
end

function TestStorageValidation:testUnknownPackedBitFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        AdamantModpackLib_Internal.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "Bit", offset = 0, width = 1, type = "bool", default = false, defalt = true },
                },
            },
        }, "UnknownPackedBitField")
    end)
end

function TestStorageValidation:testUnknownTableRowFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        AdamantModpackLib_Internal.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Count", default = 0, min = 0, max = 10, with = 4 },
                },
            },
        }, "UnknownTableRowField")
    end)
end

function TestStorageValidation:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2 },
            },
        },
    }

    AdamantModpackLib_Internal.storage.validate(storage, "PackedTest")

    lu.assertEquals(storage[1].default, 5)
    lu.assertNotNil(lib.hashing.getAliases(storage).EnabledBit)
    lu.assertNotNil(lib.hashing.getAliases(storage).ModeBits)
    lu.assertEquals(#Warnings, 0)
end

function TestStorageValidation:testBoolStorageRoundTripsHash()
    local node = { type = "bool", alias = "Enabled", default = false }
    local storage = { node }
    AdamantModpackLib_Internal.storage.validate(storage, "BoolHash")

    lu.assertEquals(lib.hashing.toHash(node, true), "1")
    lu.assertTrue(lib.hashing.fromHash(node, "1"))
    lu.assertFalse(lib.hashing.fromHash(node, "0"))
end

function TestStorageValidation:testResetSessionToDefaultsResetsChangedPersistentRoots()
    local config = { Flag = true, Count = 3, Filter = "ignored" }
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ResetPersistentRoots",
        name = "Reset Persistent Roots",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            { type = "int", alias = "Count", default = 1, min = 0, max = 5 },
            { type = "string", alias = "Filter", persist = false, hash = false, default = "", maxLen = 32 },
        },
    })
    local _, session = CreateModuleState(config, definition)

    session.write("Filter", "live")
    local changed, count = lib.resetStorageToDefaults(definition.storage, session)

    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertFalse(session.read("Flag"))
    lu.assertEquals(session.read("Count"), 1)
    lu.assertEquals(session.read("Filter"), "live")
end

function TestStorageValidation:testResetSessionToDefaultsCanExcludeAliases()
    local config = { Flag = true, ViewRegion = "Surface" }
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ResetExcludeAliases",
        name = "Reset Exclude Aliases",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            { type = "string", alias = "ViewRegion", default = "Underworld" },
        },
    })
    local _, session = CreateModuleState(config, definition)

    local changed, count = lib.resetStorageToDefaults(definition.storage, session, {
        exclude = { ViewRegion = true },
    })

    lu.assertTrue(changed)
    lu.assertEquals(count, 1)
    lu.assertFalse(session.read("Flag"))
    lu.assertEquals(session.read("ViewRegion"), "Surface")
end
