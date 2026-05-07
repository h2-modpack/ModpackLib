local lu = require('luaunit')

local function prepareDefinition(definition)
    return lib.prepareDefinition({}, definition)
end

local function makeScalarDefinition()
    return prepareDefinition({
        storage = {
            { type = "int", alias = "MaxGods", default = 3, min = 1, max = 9 },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
            { type = "stepper", binds = { value = "MaxGods" }, label = "Max Gods", min = 1, max = 9, step = 1 },
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
        ui = {
            { type = "checkbox", binds = { value = "EnabledBit" }, label = "Enabled" },
            { type = "dropdown", binds = { value = "ModeBits" }, label = "Mode", values = { 0, 1, 2, 3 } },
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
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
            { type = "text", text = "Filter" },
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

TestStore = {}

function TestStore:testCreateStoreReadsAndWritesScalarAliases()
    local config = { Enabled = false, MaxGods = 4 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    lu.assertFalse(store.read("Enabled"))
    lu.assertEquals(store.read("MaxGods"), 4)
    CaptureWarnings()
    lu.assertNil(store.read("MaxGodsPerRun"))
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "unknown storage alias 'MaxGodsPerRun'")
    RestoreWarnings()

    session.write("Enabled", true)
    session.write("MaxGods", 12)
    session._flushToConfig()

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.MaxGods, 9)
    lu.assertEquals(store.read("MaxGods"), 9)
end

function TestStore:testPackedAliasReadWriteUpdatesOwningRoot()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

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
    CaptureWarnings()
    local config = { Enabled = false }
    local store, session = lib.createStore(config, makeTransientDefinition())

    lu.assertNil(store.read("FilterText"))
    lu.assertEquals(session.view.FilterText, "")

    local sawReadWarning = false
    for _, warning in ipairs(Warnings) do
        if string.find(warning, "store.read: alias 'FilterText' is staged-only", 1, true) then
            sawReadWarning = true
        end
    end
    RestoreWarnings()

    lu.assertTrue(sawReadWarning)
end

function TestStore:testRuntimeAliasesUseNarrowStoreAccessor()
    local config = { Enabled = true, RecordingArmed = false, RunMarker = 2 }
    local store, session = lib.createStore(config, makeRuntimeDefinition())

    lu.assertTrue(store.read("Enabled"))
    lu.assertFalse(store.read("RecordingArmed"))
    lu.assertEquals(store.read("RunMarker"), 2)
    lu.assertNil(session.read("RecordingArmed"))

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

function TestStore:testSessionRejectsRuntimeWrites()
    local config = { Enabled = true, RecordingArmed = false }
    local _, session = lib.createStore(config, makeRuntimeDefinition())

    local ok, err = pcall(function()
        session.write("RecordingArmed", true)
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "not staged")
    lu.assertFalse(config.RecordingArmed)
end

TestSession = {}

function TestSession:testSessionStagesScalarAliases()
    local config = { Enabled = true, MaxGods = 5 }
    local store, session = lib.createStore(config, makeScalarDefinition())

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
    local store, session = lib.createStore(config, makePackedDefinition())

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
    local store, session = lib.createStore(config, makePackedDefinition())

    config.Packed = 5
    session._reloadFromConfig()

    lu.assertEquals(session.view.Packed, 5)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
end

function TestSession:testResyncSessionDetectsPackedDrift()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    config.Packed = 5
    local mismatches = lib.lifecycle.resyncSession({ name = "PackedSession" }, session)

    table.sort(mismatches)
    lu.assertEquals(mismatches, { "EnabledBit", "ModeBits", "Packed" })
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 5)
end

function TestSession:testReadonlyViewRejectsWrites()
    local config = { Enabled = true, MaxGods = 5 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    local ok, err = pcall(function()
        session.view.Enabled = false
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "read-only")
end

function TestSession:testTransientAliasesLiveOnlyInSession()
    local config = { Enabled = false }
    local store, session = lib.createStore(config, makeTransientDefinition())

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
    local store, session = lib.createStore(config, makeTransientDefinition())

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
    local store, session = lib.createStore(config, makeTransientDefinition())

    session.write("FilterText", "Hermes")
    session.reset("FilterText")

    lu.assertEquals(session.view.FilterText, "")
    lu.assertFalse(session.isDirty())
end

function TestSession:testResetRestoresPersistedAliasDefaultAndMarksDirty()
    local config = { Enabled = true, MaxGods = 5 }
    local store, session = lib.createStore(config, makeScalarDefinition())

    session.reset("Enabled")

    lu.assertFalse(session.view.Enabled)
    lu.assertTrue(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(config.Enabled)
end

function TestSession:testResetRestoresPackedChildDefault()
    local config = { Packed = 0 }
    local store, session = lib.createStore(config, makePackedDefinition())

    session.write("EnabledBit", true)
    session.write("ModeBits", 3)
    session.reset("ModeBits")

    lu.assertEquals(session.view.ModeBits, 0)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.Packed, 1)
end

function TestSession:testTableStorageHydratesDefaultRows()
    local config = {}
    local store, session = lib.createStore(config, makeTableDefinition())

    lu.assertEquals(session.table("Tiers"):count(), 1)
    lu.assertTrue(session.table("Tiers"):read(1, "Enabled"))
    lu.assertEquals(session.table("Tiers"):read(1, "Limit"), 2)
    lu.assertEquals(session.table("Tiers"):read(1, "PackedChoices"), 0)
    lu.assertEquals(#config.Tiers, 1)
end

function TestSession:testTableStorageStagesRowWritesAndFlushesRoot()
    local config = {}
    local store, session = lib.createStore(config, makeTableDefinition())
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

function TestSession:testTableStorageMutatesRowsAsCompactList()
    local config = {}
    local _, session = lib.createStore(config, makeTableDefinition())
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

    tiers:clear()
    lu.assertEquals(tiers:count(), 0)
end

function TestSession:testTableStorageDoesNotLeakRowAliasesGlobally()
    local _, session = lib.createStore({}, makeTableDefinition())

    CaptureWarnings()
    lu.assertNil(session.read("Limit"))
    lu.assertNil(session.read("ChoiceA"))
    RestoreWarnings()
end

function TestSession:testReadonlyViewDoesNotExposeMutableTableRoot()
    local _, session = lib.createStore({}, makeTableDefinition())

    local snapshot = session.view.Tiers
    snapshot[1].Limit = 5

    lu.assertEquals(session.table("Tiers"):read(1, "Limit"), 2)
end

function TestSession:testTableStorageHashRoundTripsRows()
    local definition = makeTableDefinition()
    local tableNode = definition.storage[3]
    local value = {
        { Enabled = false, Limit = 4, PackedChoices = 5 },
        { Enabled = true, Limit = 1, ChoiceMode = 2 },
    }

    local encoded = lib.hashing.toHash(tableNode, value)
    local decoded = lib.hashing.fromHash(tableNode, encoded)

    lu.assertEquals(#decoded, 2)
    lu.assertFalse(decoded[1].Enabled)
    lu.assertEquals(decoded[1].Limit, 4)
    lu.assertEquals(decoded[1].PackedChoices, 5)
    lu.assertTrue(decoded[2].Enabled)
    lu.assertEquals(decoded[2].Limit, 1)
    lu.assertEquals(decoded[2].PackedChoices, 4)
end

