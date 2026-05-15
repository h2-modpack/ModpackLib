local lu = require('luaunit')

local function prepareDefinition(definition)
    definition.id = definition.id or "SessionTest"
    definition.name = definition.name or "Session Test"
    return AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, definition)
end

local function makeScalarDefinition()
    return prepareDefinition({
        storage = {
            { type = "int", alias = "MaxGods", default = 3, min = 1, max = 9 },
        },
    })
end

local function makePackedDefinition()
    return prepareDefinition({
        storage = {
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 0 },
                },
            },
        },
    })
end

local function makeTransientDefinition()
    return prepareDefinition({
        storage = {
            { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
            { type = "string", alias = "FilterMode", persist = false, hash = false, default = "all", maxLen = 16 },
            { type = "string", alias = "SummaryText", persist = false, hash = false, default = "", maxLen = 128 },
        },
    })
end

local function makeRuntimeDefinition()
    return prepareDefinition({
        storage = {
            { type = "bool", alias = "RecordingArmed", default = false, stage = false, hash = false },
            { type = "int", alias = "RunMarker", default = 0, min = 0, max = 99, stage = false, hash = false },
        },
    })
end

local function makeTableDefinition()
    return prepareDefinition({
        storage = {
            {
                type = "table",
                alias = "Tiers",
                minRows = 0,
                maxRows = 3,
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Enabled", default = true },
                    { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
                    { type = "string", alias = "Note", default = "", maxLen = 64 },
                    {
                        type = "packedInt",
                        alias = "PackedChoices",
                        bits = {
                            { alias = "ChoiceA", offset = 0, width = 1, type = "bool", default = false },
                            { alias = "ChoiceMode", offset = 1, width = 2, type = "int", default = 0 },
                        },
                    },
                },
            },
        },
    })
end

local function makeMinRowsTableDefinition()
    return prepareDefinition({
        storage = {
            {
                type = "table",
                alias = "Rows",
                minRows = 1,
                maxRows = 2,
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Count", default = 0, min = 0, max = 5 },
                },
            },
        },
    })
end

TestStore = {}

function TestStore:testCreateStoreReadsAndWritesScalarAliases()
    local config = { Enabled = false, MaxGods = 4 }
    local store, session = CreateModuleState(config, makeScalarDefinition())

    lu.assertFalse(store.read("Enabled"))
    lu.assertEquals(store.read("MaxGods"), 4)
    lu.assertErrorMsgContains("store.unknown_read_alias", function()
        store.read("MaxGodsPerRun")
    end)

    session.write("Enabled", true)
    session.write("MaxGods", 12)
    session._flushToConfig()

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.MaxGods, 9)
    lu.assertEquals(store.read("MaxGods"), 9)
end

function TestStore:testPackedAliasReadWriteUpdatesOwningRoot()
    local config = { Packed = 0 }
    local store, session = CreateModuleState(config, makePackedDefinition())

    lu.assertFalse(store.read("EnabledBit"))
    lu.assertEquals(store.read("ModeBits"), 0)
    lu.assertEquals(store.read("Packed"), 0)

    session.write("EnabledBit", true)
    session._flushToConfig()
    lu.assertEquals(config.Packed, 1)
    lu.assertTrue(store.read("EnabledBit"))

    session.write("ModeBits", 3)
    session._flushToConfig()
    lu.assertEquals(config.Packed, 7)
    lu.assertEquals(store.read("ModeBits"), 3)
end

function TestStore:testTransientAliasesAreNotReadableThroughStore()
    local config = { Enabled = false }
    local store, session = CreateModuleState(config, makeTransientDefinition())

    lu.assertErrorMsgContains("store.invalid_read_surface", function()
        store.read("FilterText")
    end)
    lu.assertEquals(session.view.FilterText, "")
end

function TestStore:testRuntimeAliasesUseNarrowStoreAccessor()
    local config = { Enabled = true, RecordingArmed = false, RunMarker = 2 }
    local store, session = CreateModuleState(config, makeRuntimeDefinition())

    lu.assertTrue(store.read("Enabled"))
    lu.assertFalse(store.read("RecordingArmed"))
    lu.assertEquals(store.read("RunMarker"), 2)
    lu.assertErrorMsgContains("session.invalid_read_surface", function()
        session.read("RecordingArmed")
    end)

    store.writeUnstaged("RecordingArmed", true)
    store.writeUnstaged("RunMarker", 120)

    lu.assertTrue(config.RecordingArmed)
    lu.assertEquals(config.RunMarker, 99)
    lu.assertFalse(session.isDirty())

    local ok, err = pcall(function()
        store.writeUnstaged("Enabled", false)
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "stage = false")
end

function TestStore:testDowngradedUnstagedWriteRejectionDoesNotWrite()
    local policy = AdamantModpackLib_Internal.violationPolicy["store.invalid_unstaged_write"]
    local previous = policy.severity
    policy.severity = "warn"
    CaptureWarnings()

    local config = { Enabled = true, RecordingArmed = false }
    local store = CreateModuleState(config, makeRuntimeDefinition())

    lu.assertFalse(store.writeUnstaged("Enabled", false))

    lu.assertTrue(config.Enabled)
    lu.assertEquals(#Warnings, 1)

    RestoreWarnings()
    policy.severity = previous
end

function TestStore:testSessionRejectsRuntimeWrites()
    local config = { Enabled = true, RecordingArmed = false }
    local _, session = CreateModuleState(config, makeRuntimeDefinition())

    local ok, err = pcall(function()
        session.write("RecordingArmed", true)
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "not staged")
    lu.assertFalse(config.RecordingArmed)
end

function TestStore:testDowngradedSessionRuntimeWriteStillDoesNotStage()
    local policy = AdamantModpackLib_Internal.violationPolicy["session.invalid_write_surface"]
    local previous = policy.severity
    policy.severity = "warn"
    CaptureWarnings()

    local config = { Enabled = true, RecordingArmed = false }
    local _, session = CreateModuleState(config, makeRuntimeDefinition())

    session.write("RecordingArmed", true)

    lu.assertFalse(config.RecordingArmed)
    lu.assertFalse(session.isDirty())
    lu.assertEquals(#Warnings, 1)

    RestoreWarnings()
    policy.severity = previous
end

TestSession = {}

function TestSession:testSessionStagesScalarAliases()
    local config = { Enabled = true, MaxGods = 5 }
    local store, session = CreateModuleState(config, makeScalarDefinition())

    lu.assertTrue(session.view.Enabled)
    lu.assertEquals(session.view.MaxGods, 5)
    lu.assertFalse(session.isDirty())

    session.write("Enabled", false)
    lu.assertTrue(session.isDirty())
    lu.assertFalse(session.view.Enabled)

    session._flushToConfig()
    lu.assertFalse(session.isDirty())
    lu.assertFalse(config.Enabled)
end

function TestSession:testPackedAliasEditReencodesPackedRootOnFlush()
    local config = { Packed = 0 }
    local store, session = CreateModuleState(config, makePackedDefinition())

    session.write("ModeBits", 2)

    lu.assertTrue(session.isDirty())
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 4)
    lu.assertEquals(config.Packed, 0)

    session._flushToConfig()

    lu.assertEquals(config.Packed, 4)
    lu.assertFalse(session.isDirty())
end

function TestSession:testInternalReloadFromConfigRebuildsPackedChildren()
    local config = { Packed = 0 }
    local store, session = CreateModuleState(config, makePackedDefinition())

    config.Packed = 5
    session._reloadFromConfig()

    lu.assertEquals(session.view.Packed, 5)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
end

function TestSession:testResyncSessionDetectsPackedDrift()
    local config = { Packed = 0 }
    local store, session = CreateModuleState(config, makePackedDefinition())

    config.Packed = 5
    local mismatches = HostLifecycle.resyncSession({ name = "PackedSession" }, session)

    table.sort(mismatches)
    lu.assertEquals(mismatches, { "EnabledBit", "ModeBits", "Packed" })
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 5)
end

function TestSession:testReadonlyViewRejectsWrites()
    local config = { Enabled = true, MaxGods = 5 }
    local store, session = CreateModuleState(config, makeScalarDefinition())

    local ok, err = pcall(function()
        session.view.Enabled = false
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "read-only")
end

function TestSession:testTransientAliasesLiveOnlyInSession()
    local config = { Enabled = false }
    local store, session = CreateModuleState(config, makeTransientDefinition())

    lu.assertEquals(session.view.FilterText, "")
    lu.assertEquals(session.view.FilterMode, "all")
    lu.assertFalse(session.isDirty())

    session.write("FilterText", "Poseidon")
    session.write("FilterMode", "allowed")

    lu.assertEquals(session.view.FilterText, "Poseidon")
    lu.assertEquals(session.view.FilterMode, "allowed")
    lu.assertFalse(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(session.isDirty())
    lu.assertNil(config.FilterText)
end

function TestSession:testInternalReloadFromConfigResetsTransientAliasesToDefaults()
    local config = { Enabled = true }
    local store, session = CreateModuleState(config, makeTransientDefinition())

    session.write("FilterText", "Hera")
    session.write("FilterMode", "banned")
    config.Enabled = false

    session._reloadFromConfig()

    lu.assertFalse(session.view.Enabled)
    lu.assertEquals(session.view.FilterText, "")
    lu.assertEquals(session.view.FilterMode, "all")
end

function TestSession:testResetRestoresTransientAliasDefault()
    local config = { Enabled = true }
    local store, session = CreateModuleState(config, makeTransientDefinition())

    session.write("FilterText", "Hermes")
    session.reset("FilterText")

    lu.assertEquals(session.view.FilterText, "")
    lu.assertFalse(session.isDirty())
end

function TestSession:testResetRestoresPersistedAliasDefaultAndMarksDirty()
    local config = { Enabled = true, MaxGods = 5 }
    local store, session = CreateModuleState(config, makeScalarDefinition())

    session.reset("Enabled")

    lu.assertFalse(session.view.Enabled)
    lu.assertTrue(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(config.Enabled)
end

function TestSession:testResetRestoresPackedChildDefault()
    local config = { Packed = 0 }
    local store, session = CreateModuleState(config, makePackedDefinition())

    session.write("EnabledBit", true)
    session.write("ModeBits", 3)
    session.reset("ModeBits")

    lu.assertEquals(session.view.ModeBits, 0)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.Packed, 1)
end

function TestSession:testTableStorageHydratesDefaultRows()
    local config = {}
    local store, session = CreateModuleState(config, makeTableDefinition())

    lu.assertEquals(session.table("Tiers"):count(), 1)
    lu.assertTrue(session.table("Tiers"):read(1, "Enabled"))
    lu.assertEquals(session.table("Tiers"):read(1, "Limit"), 2)
    lu.assertEquals(session.table("Tiers"):read(1, "PackedChoices"), 0)
    lu.assertEquals(#config.Tiers, 1)
end

function TestSession:testTableStorageStagesRowWritesAndFlushesRoot()
    local config = {}
    local store, session = CreateModuleState(config, makeTableDefinition())
    local tiers = session.table("Tiers")

    lu.assertTrue(tiers:append({ Enabled = false, Limit = 4, ChoiceA = true }))
    lu.assertTrue(tiers:write(2, "ChoiceMode", 3))
    lu.assertTrue(tiers:write(2, "Limit", 9))

    lu.assertEquals(tiers:count(), 2)
    lu.assertFalse(tiers:read(2, "Enabled"))
    lu.assertTrue(tiers:read(2, "ChoiceA"))
    lu.assertEquals(tiers:read(2, "ChoiceMode"), 3)
    lu.assertEquals(tiers:read(2, "PackedChoices"), 7)
    lu.assertEquals(tiers:read(2, "Limit"), 5)
    lu.assertEquals(#config.Tiers, 1)

    session._flushToConfig()

    lu.assertEquals(#config.Tiers, 2)
    lu.assertEquals(config.Tiers[2].PackedChoices, 7)
    lu.assertEquals(config.Tiers[2].Limit, 5)
    lu.assertEquals(store.table("Tiers"):read(2, "ChoiceMode"), 3)
end

function TestSession:testTableRowHandleReadsAndWritesThroughParentTable()
    local config = {}
    local store, session = CreateModuleState(config, makeTableDefinition())
    local tiers = session.table("Tiers")

    tiers:append({ Limit = 3, ChoiceA = true })
    local row = tiers:rowHandle(2)

    lu.assertEquals(row.read("Limit"), 3)
    lu.assertTrue(row.read("ChoiceA"))
    lu.assertEquals(row.getAliasSchema("PackedChoices").alias, "PackedChoices")

    lu.assertTrue(row.write("ChoiceMode", 2))
    lu.assertEquals(row.read("PackedChoices"), 5)
    lu.assertTrue(row.reset("ChoiceA"))
    lu.assertFalse(row.read("ChoiceA"))

    session._flushToConfig()
    local storeRow = store.table("Tiers"):rowHandle(2)

    lu.assertEquals(storeRow.read("ChoiceMode"), 2)
    lu.assertEquals(storeRow.getAliasSchema("ChoiceMode").alias, "ChoiceMode")
    lu.assertNil(storeRow.write)
    lu.assertNil(storeRow.reset)
end

function TestSession:testStoreTableReadOnlyHandleClampsRawPersistedRows()
    local config = {
        Tiers = {
            { Limit = 1 },
            { Limit = 2 },
            { Limit = 3 },
            { Limit = 4 },
        },
    }
    local store = CreateModuleState(config, makeTableDefinition())
    local tiers = store.table("Tiers")

    lu.assertEquals(#config.Tiers, 3)
    lu.assertNil(config.Tiers[4])
    lu.assertEquals(tiers:count(), 3)
    lu.assertEquals(tiers:rowHandle(3).read("Limit"), 3)
    lu.assertNil(tiers:rowHandle(4).read("Limit"))
end

function TestSession:testTableRowHandleIsPositionalAndMissingRowsAreNil()
    local _, session = CreateModuleState({}, makeTableDefinition())
    local tiers = session.table("Tiers")
    local row = tiers:rowHandle(2)

    lu.assertNil(row.read("Limit"))
    lu.assertFalse(row.write("Limit", 4))

    tiers:append({ Limit = 4 })
    lu.assertEquals(row.read("Limit"), 4)
end

function TestSession:testTableStorageMutatesRowsAsCompactList()
    local config = {}
    local _, session = CreateModuleState(config, makeTableDefinition())
    local tiers = session.table("Tiers")

    tiers:append({ Limit = 1 })
    tiers:insert(2, { Limit = 3 })
    lu.assertEquals(tiers:count(), 3)
    lu.assertEquals(tiers:read(2, "Limit"), 3)

    tiers:remove(2)
    lu.assertEquals(tiers:count(), 2)
    lu.assertEquals(tiers:read(2, "Limit"), 1)

    tiers:resetRow(2)
    lu.assertEquals(tiers:read(2, "Limit"), 2)

    lu.assertTrue(tiers:clear())
    lu.assertEquals(tiers:count(), 0)
end

function TestSession:testTableStorageClearReportsNoChangeWhenAlreadyDefault()
    local _, session = CreateModuleState({}, makeMinRowsTableDefinition())
    local rows = session.table("Rows")

    lu.assertEquals(rows:count(), 1)
    lu.assertFalse(rows:clear())
    lu.assertEquals(rows:count(), 1)
    lu.assertFalse(session.isDirty())
end

function TestSession:testTableStorageUnknownRowAliasFails()
    local _, session = CreateModuleState({}, makeTableDefinition())
    local tiers = session.table("Tiers")

    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:read(1, "MissingRowAlias")
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:write(1, "MissingRowAlias", true)
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:reset(1, "MissingRowAlias")
    end)
end

function TestSession:testTableStorageHandleRequiresColonSyntax()
    local _, session = CreateModuleState({}, makeTableDefinition())
    local tiers = session.table("Tiers")

    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.read(1, "Enabled")
    end)
    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.count()
    end)
end

function TestSession:testTableStorageAppendRespectsMaxRows()
    local _, session = CreateModuleState({}, makeTableDefinition())
    local tiers = session.table("Tiers")

    lu.assertTrue(tiers:append())
    lu.assertTrue(tiers:append())
    lu.assertFalse(tiers:append())
    lu.assertEquals(tiers:count(), 3)
end

function TestSession:testTableStorageDoesNotLeakRowAliasesGlobally()
    local _, session = CreateModuleState({}, makeTableDefinition())

    lu.assertErrorMsgContains("session.unknown_read_alias", function()
        session.read("Limit")
    end)
    lu.assertErrorMsgContains("session.unknown_read_alias", function()
        session.read("ChoiceA")
    end)
end

function TestSession:testSessionWriteUnknownAliasFails()
    local _, session = CreateModuleState({}, makeRuntimeDefinition())

    lu.assertErrorMsgContains("unknown alias 'Nope'", function()
        session.write("Nope", true)
    end)
end

function TestSession:testSessionReadUnknownAliasFails()
    local _, session = CreateModuleState({}, makeRuntimeDefinition())

    lu.assertErrorMsgContains("session.unknown_read_alias", function()
        session.read("Nope")
    end)
end

function TestSession:testSessionResetUnknownAliasFails()
    local _, session = CreateModuleState({}, makeScalarDefinition())

    lu.assertErrorMsgContains("unknown alias 'Nope'", function()
        session.reset("Nope")
    end)
end

function TestSession:testDowngradedSessionResetUnknownAliasReturnsSafely()
    local policy = AdamantModpackLib_Internal.violationPolicy["session.unknown_reset_alias"]
    local previous = policy.severity
    policy.severity = "warn"
    CaptureWarnings()

    local _, session = CreateModuleState({}, makeRuntimeDefinition())

    session.reset("Nope")

    lu.assertFalse(session.isDirty())
    lu.assertEquals(#Warnings, 1)

    RestoreWarnings()
    policy.severity = previous
end

function TestSession:testSessionTableWrongAliasFails()
    local _, session = CreateModuleState({}, makeScalarDefinition())

    lu.assertErrorMsgContains("is not table storage", function()
        session.table("Enabled")
    end)
end

function TestSession:testDowngradedSessionTableErrorsReturnNilSafely()
    local unknownPolicy = AdamantModpackLib_Internal.violationPolicy["session.unknown_table_alias"]
    local invalidPolicy = AdamantModpackLib_Internal.violationPolicy["session.invalid_table_alias"]
    local previousUnknown = unknownPolicy.severity
    local previousInvalid = invalidPolicy.severity
    local previousPrint = print
    local lines = {}
    unknownPolicy.severity = "warn"
    invalidPolicy.severity = "warn"
    print = function(msg)
        table.insert(lines, msg)
    end

    local _, session = CreateModuleState({ Enabled = true, MaxGods = 5 }, makeScalarDefinition())
    local missing = session.table("Missing")
    local wrongType = session.table("MaxGods")

    print = previousPrint
    unknownPolicy.severity = previousUnknown
    invalidPolicy.severity = previousInvalid

    lu.assertNil(missing)
    lu.assertNil(wrongType)
    lu.assertEquals(#lines, 2)
end

function TestSession:testDowngradedStoreTableErrorsReturnNilSafely()
    local unknownPolicy = AdamantModpackLib_Internal.violationPolicy["store.unknown_table_alias"]
    local invalidPolicy = AdamantModpackLib_Internal.violationPolicy["store.invalid_table_alias"]
    local previousUnknown = unknownPolicy.severity
    local previousInvalid = invalidPolicy.severity
    local previousPrint = print
    local lines = {}
    unknownPolicy.severity = "warn"
    invalidPolicy.severity = "warn"
    print = function(msg)
        table.insert(lines, msg)
    end

    local store = CreateModuleState({ Enabled = true, MaxGods = 5 }, makeScalarDefinition())
    local missing = store.table("Missing")
    local wrongType = store.table("MaxGods")

    print = previousPrint
    unknownPolicy.severity = previousUnknown
    invalidPolicy.severity = previousInvalid

    lu.assertNil(missing)
    lu.assertNil(wrongType)
    lu.assertEquals(#lines, 2)
end

function TestSession:testReadonlyViewDoesNotExposeMutableTableRoot()
    local _, session = CreateModuleState({}, makeTableDefinition())

    local snapshot = session.view.Tiers
    snapshot[1].Limit = 5

    lu.assertEquals(session.table("Tiers"):read(1, "Limit"), 2)
end

function TestSession:testTableStorageHashRoundTripsRows()
    local definition = makeTableDefinition()
    local tableNode = definition.storage[3]
    local value = {
        { Enabled = false, Limit = 4, PackedChoices = 5 },
        { Enabled = true, Limit = 1, ChoiceMode = 2, Note = "a|b=%c" },
    }

    local encoded = lib.hashing.toHash(tableNode, value)
    local decoded = lib.hashing.fromHash(tableNode, encoded)

    lu.assertEquals(#decoded, 2)
    lu.assertFalse(decoded[1].Enabled)
    lu.assertEquals(decoded[1].Limit, 4)
    lu.assertEquals(decoded[1].PackedChoices, 5)
    lu.assertTrue(decoded[2].Enabled)
    lu.assertEquals(decoded[2].Limit, 1)
    lu.assertEquals(decoded[2].Note, "a|b=%c")
    lu.assertEquals(decoded[2].PackedChoices, 4)
end

function TestSession:testSessionActionsAreDirtyAndLastWriteWins()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "SessionActionTest",
        name = "Session Action Test",
        storage = {},
    })
    local _, session = CreateModuleState({}, definition)

    lu.assertFalse(session.hasActions())
    lu.assertFalse(session.isDirty())

    session.stageAction("recording", { kind = "start" })
    session.stageAction("recording", { kind = "stop" })

    lu.assertTrue(session.hasActions())
    lu.assertTrue(session.isDirty())
    lu.assertEquals(session.readAction("recording"), { kind = "stop" })

    session.clearAction("recording")

    lu.assertFalse(session.hasActions())
    lu.assertFalse(session.isDirty())
end
