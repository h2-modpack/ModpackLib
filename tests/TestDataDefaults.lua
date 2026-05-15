local lu = require('luaunit')

-- =============================================================================
-- getPackWidth
-- =============================================================================

TestGetPackWidth = {}

function TestGetPackWidth:testBoolAlwaysReturnsOne()
    lu.assertEquals(lib.hashing.getPackWidth({ type = "bool" }), 1)
end

function TestGetPackWidth:testIntDerivesFromMinMax()
    -- min=0, max=7 → range 7 → ceil(log2(8)) = 3
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 0, max = 7 }), 3)
    -- min=0, max=15 → range 15 → ceil(log2(16)) = 4
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 0, max = 15 }), 4)
    -- min=1, max=12 → range 11 → ceil(log2(12)) = 4
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 1, max = 12 }), 4)
end

function TestGetPackWidth:testIntUsesExplicitWidthOverMinMax()
    lu.assertEquals(lib.hashing.getPackWidth({ type = "int", min = 0, max = 7, width = 5 }), 5)
end

function TestGetPackWidth:testIntWithNoMaxReturnsNil()
    lu.assertNil(lib.hashing.getPackWidth({ type = "int", min = 0 }))
end

function TestGetPackWidth:testStringReturnsNil()
    lu.assertNil(lib.hashing.getPackWidth({ type = "string" }))
end

function TestGetPackWidth:testUnknownTypeReturnsNil()
    lu.assertNil(lib.hashing.getPackWidth({ type = "unknown" }))
end

-- =============================================================================
-- storage defaults
-- =============================================================================

TestDataDefaults = {}

local function makeStore(definition, config)
    config = config or {}
    definition.id = definition.id or "DataDefaults"
    definition.name = definition.name or "Data Defaults"
    if not (type(definition) == "table" and rawget(definition, "_preparedDefinition") == true) then
        definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, definition)
    end
    local store, session = CreateModuleState(config, definition)
    return store, session, config
end

local function makeChalkConfig()
    local raw = {
        entries = {},
        saved = 0,
    }

    function raw:bind(section, key, defaultValue, description)
        for descriptor in pairs(self.entries) do
            if descriptor.section == section and descriptor.key == key then
                error("duplicate config bind")
            end
        end

        local entry = {
            value = defaultValue,
            description = description or "",
        }
        function entry:get()
            return self.value
        end
        function entry:set(value)
            self.value = value
        end

        self.entries[{ section = section, key = key }] = entry
        return entry
    end

    function raw:save()
        self.saved = self.saved + 1
    end

    local wrapper = { __raw = raw }
    local chalk = rom.mods['SGG_Modding-Chalk']
    local previousOriginal = chalk.original
    chalk.original = function(config)
        return config.__raw
    end

    return wrapper, raw, function()
        chalk.original = previousOriginal
    end
end

function TestDataDefaults:testUsesBoolStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
        },
    }
    local store, session = makeStore(definition, {})

    lu.assertTrue(session.read("MyFlag"))
end

function TestDataDefaults:testUsesIntStorageDefault()
    local definition = {
        storage = {
            { type = "int", alias = "MyCount", default = 7, min = 0, max = 10 },
        },
    }
    local store, session = makeStore(definition, {})

    lu.assertEquals(session.read("MyCount"), 7)
end

function TestDataDefaults:testUsesStringStorageDefault()
    local definition = {
        storage = {
            { type = "string", alias = "MyChoice", default = "Forced" },
        },
    }
    local store, session = makeStore(definition, {})

    lu.assertEquals(session.read("MyChoice"), "Forced")
end

-- Live config value overrides the default when present
function TestDataDefaults:testLiveConfigValueOverridesDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
        },
    }
    local store, session = makeStore(definition, { MyFlag = false })

    lu.assertFalse(session.read("MyFlag"))
end

function TestDataDefaults:testMissingStorageDefaultFails()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag" },
        },
    }
    lu.assertErrorMsgContains("must declare an effective default", function()
        makeStore(definition, {})
    end)
end

function TestDataDefaults:testMissingTableRowDefaultFails()
    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Flag" },
                },
            },
        },
    }
    lu.assertErrorMsgContains("must declare an effective default", function()
        makeStore(definition, {})
    end)
end

function TestDataDefaults:testNestedTableStorageFails()
    local definition = {
        storage = {
            {
                type = "table",
                alias = "Rows",
                row = {
                    {
                        type = "table",
                        alias = "Nested",
                        row = {
                            { type = "bool", alias = "Flag", default = false },
                        },
                    },
                },
            },
        },
    }
    lu.assertErrorMsgContains("nested table storage is not supported", function()
        makeStore(definition, {})
    end)
end

function TestDataDefaults:testExplicitStorageDefaultsAreSafe()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
        },
    }
    local store, session = makeStore(definition, {})

    lu.assertTrue(session.read("MyFlag"))
end

function TestDataDefaults:testCreateStoreHydratesMissingConfigFromStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "MyCount", default = 4, min = 0, max = 10 },
            { type = "string", alias = "MyMode", default = "Auto" },
            {
                type = "packedInt",
                alias = "PackedChoices",
                default = 2,
                bits = {
                    { alias = "PackedChoiceA", offset = 0, width = 1, type = "bool", default = false },
                    { alias = "PackedChoiceB", offset = 1, width = 1, type = "bool", default = true },
                },
            },
        },
    }
    local store, session, config = makeStore(definition, {})

    lu.assertTrue(session.read("MyFlag"))
    lu.assertEquals(session.read("MyCount"), 4)
    lu.assertEquals(session.read("MyMode"), "Auto")
    lu.assertEquals(session.read("PackedChoices"), 2)
    lu.assertEquals(config.MyFlag, true)
    lu.assertEquals(config.MyCount, 4)
    lu.assertEquals(config.MyMode, "Auto")
    lu.assertEquals(config.PackedChoices, 2)
end

function TestDataDefaults:testCreateStoreHydratesMissingRuntimeConfigFromStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "RecordingArmed", default = false, stage = false, hash = false },
            { type = "int", alias = "RunMarker", default = 3, min = 0, max = 10, stage = false, hash = false },
        },
    }
    local store, session, config = makeStore(definition, {})

    lu.assertFalse(session.read("Enabled"))
    lu.assertFalse(store.read("RecordingArmed"))
    lu.assertEquals(store.read("RunMarker"), 3)
    lu.assertEquals(config.Enabled, false)
    lu.assertEquals(config.RecordingArmed, false)
    lu.assertEquals(config.RunMarker, 3)
end

function TestDataDefaults:testCreateStorePreservesExistingConfigValues()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "MyCount", default = 4, min = 0, max = 10 },
        },
    }
    local store, session, config = makeStore(definition, { MyFlag = false, MyCount = 9 })

    lu.assertFalse(session.read("MyFlag"))
    lu.assertEquals(session.read("MyCount"), 9)
    lu.assertEquals(config.MyFlag, false)
    lu.assertEquals(config.MyCount, 9)
end

function TestDataDefaults:testCreateStoreHydratesAliasBackedConfig()
    local definition = {
        storage = {
            { type = "bool", alias = "GodModeEnabled", default = true },
            { type = "int", alias = "FixedValue", default = 3, min = 0, max = 10 },
        },
    }
    local store, session, config = makeStore(definition, {})

    lu.assertTrue(session.read("GodModeEnabled"))
    lu.assertEquals(session.read("FixedValue"), 3)
    lu.assertEquals(config.GodModeEnabled, true)
    lu.assertEquals(config.FixedValue, 3)
end

function TestDataDefaults:testCreateStoreHydratesMissingChalkEntryFromStorageDefault()
    local config, raw, restoreChalk = makeChalkConfig()
    local definition = {
        storage = {
            { type = "bool", alias = "MyFlag", default = true },
            { type = "int", alias = "FixedValue", default = 3, min = 0, max = 10 },
        },
    }

    local ok, _, session = pcall(function()
        return makeStore(definition, config)
    end)
    restoreChalk()

    lu.assertTrue(ok)
    lu.assertTrue(session.read("MyFlag"))
    lu.assertEquals(session.read("FixedValue"), 3)
    lu.assertEquals(raw.saved, 4)

    local valuesByPath = {}
    for descriptor, entry in pairs(raw.entries) do
        valuesByPath[descriptor.section .. "." .. descriptor.key] = entry:get()
    end
    lu.assertEquals(valuesByPath["config.Enabled"], false)
    lu.assertEquals(valuesByPath["config.DebugMode"], false)
    lu.assertEquals(valuesByPath["config.MyFlag"], true)
    lu.assertEquals(valuesByPath["config.FixedValue"], 3)
end

function TestDataDefaults:testLookupUsesAliasAsBackingKey()
    local definition = {
        storage = {
            { type = "int", alias = "MyAlias", default = 0, min = 0, max = 10 },
        },
    }
    local _, session = makeStore(definition, { MyAlias = 1, OldBackingKey = 9 })

    lu.assertEquals(session.read("MyAlias"), 1)
end

function TestDataDefaults:testMissingAliasUsesStorageDefault()
    local definition = {
        storage = {
            { type = "bool", alias = "GodModeEnabled", default = true },
            { type = "int",  alias = "FixedValue", default = 3, min = 0, max = 10 },
        },
    }
    local _, session = makeStore(definition, {})

    lu.assertTrue(session.read("GodModeEnabled"))
    lu.assertEquals(session.read("FixedValue"), 3)
end

function TestDataDefaults:testPreparedStorageDefaultsAreStableAcrossCreateStoreCalls()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "StablePreparedDefaults",
        name = "Stable Prepared Defaults",
        storage = {
            { type = "int", alias = "MyCount", default = 5, min = 0, max = 10 },
        },
    })

    lu.assertEquals(definition.storage[3].default, 5)

    makeStore(definition, {})
    lu.assertEquals(definition.storage[3].default, 5)
end

-- Multiple nodes all receive their storage defaults.
function TestDataDefaults:testMultipleNodesAllFilled()
    local definition = {
        storage = {
            { type = "bool",   alias = "FlagA", default = true },
            { type = "int",    alias = "Count", default = 5, min = 0, max = 20 },
            { type = "string", alias = "Mode", default = "Vanilla" },
        },
    }
    local store, session = makeStore(definition, {})

    lu.assertTrue(session.read("FlagA"))
    lu.assertEquals(session.read("Count"), 5)
    lu.assertEquals(session.read("Mode"), "Vanilla")
end

