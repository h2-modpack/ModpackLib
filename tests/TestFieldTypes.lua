local lu = require('luaunit')

local function makeStore(definition, config)
    config = config or {}
    return lib.createStore(config, definition), config
end

local function makeBasicImgui()
    local state = { buttonResponses = {}, checkboxResponses = {}, selectables = {}, pushIds = {} }

    local imgui = {
        _state = state,
        Checkbox = function(_, _, current)
            local nextResponse = table.remove(state.checkboxResponses, 1)
            if nextResponse ~= nil then
                return nextResponse, nextResponse ~= current
            end
            return current, false
        end,
        BeginCombo = function()
            return false
        end,
        EndCombo = function() end,
        Selectable = function()
            local nextResponse = table.remove(state.selectables, 1)
            return nextResponse == true
        end,
        RadioButton = function()
            local nextResponse = table.remove(state.selectables, 1)
            return nextResponse == true
        end,
        Text = function() end,
        TextColored = function() end,
        SameLine = function() end,
        NewLine = function() end,
        IsItemHovered = function() return false end,
        SetTooltip = function() end,
        PushItemWidth = function() end,
        PopItemWidth = function() end,
        PushID = function(_, value)
            table.insert(state.pushIds, value)
        end,
        PopID = function() end,
        Indent = function() end,
        Unindent = function() end,
        Separator = function() end,
        CollapsingHeader = function()
            return true
        end,
        GetCursorPosX = function()
            return 0
        end,
        SetCursorPosX = function() end,
        Button = function()
            local nextResponse = table.remove(state.buttonResponses, 1)
            return nextResponse == true
        end,
    }

    return imgui
end

TestStorageTypes = {}

function TestStorageTypes:testBoolStorageRoundTripsHash()
    local node = { type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
    lib.validateStorage({ node }, "Test")

    lu.assertEquals(lib.StorageTypes.bool.toHash(node, true), "1")
    lu.assertEquals(lib.StorageTypes.bool.toHash(node, false), "0")
    lu.assertTrue(lib.StorageTypes.bool.fromHash(node, "1"))
    lu.assertFalse(lib.StorageTypes.bool.fromHash(node, "0"))
end

function TestStorageTypes:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            configKey = "Packed",
            bits = {
                { alias = "Flag", offset = 0, width = 1, type = "bool", default = true },
                { alias = "Mode", offset = 1, width = 2, type = "int", default = 2 },
            },
        },
    }

    lib.validateStorage(storage, "PackedTest")

    local aliases = lib.getStorageAliases(storage)
    lu.assertNotNil(aliases.Packed)
    lu.assertNotNil(aliases.Flag)
    lu.assertNotNil(aliases.Mode)
    lu.assertEquals(aliases.Packed.default, 5)
    lu.assertTrue(aliases.Flag.default)
    lu.assertEquals(aliases.Mode.default, 2)
    lu.assertEquals(aliases.Flag.parent.alias, "Packed")
end

TestUiNodes = {}

function TestUiNodes:testDrawCheckboxNodeWritesAliasBackIntoUiState()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfAlias()
    local definition = {
        storage = {
            { type = "bool", alias = "Gate", configKey = "Gate", default = false },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = "Gate" },
        },
    }
    local store = makeStore(definition, { Gate = false, Enabled = true })
    local imgui = makeBasicImgui()
    local checkboxCalls = 0
    imgui.Checkbox = function(_, _, current)
        checkboxCalls = checkboxCalls + 1
        return current, false
    end

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertFalse(changed)
    lu.assertEquals(checkboxCalls, 0)
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfValue()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", value = "Forced" } },
        },
    }
    local store = makeStore(definition, { Mode = "Forced", Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDrawUiNodeRespectsVisibleIfAnyOf()
    local definition = {
        storage = {
            { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla" },
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", visibleIf = { alias = "Mode", anyOf = { "Forced", "Charybdis" } } },
        },
    }
    local store = makeStore(definition, { Mode = "Charybdis", Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end

function TestUiNodes:testDrawSteppedRangeNodeWritesBothAliases()
    local definition = {
        storage = {
            { type = "int", alias = "MinDepth", configKey = "MinDepth", default = 2, min = 1, max = 10 },
            { type = "int", alias = "MaxDepth", configKey = "MaxDepth", default = 8, min = 1, max = 10 },
        },
        ui = {
            { type = "steppedRange", binds = { min = "MinDepth", max = "MaxDepth" }, label = "Depth", min = 1, max = 10, step = 1 },
        },
    }
    local store = makeStore(definition, { MinDepth = 2, MaxDepth = 8 })
    local imgui = makeBasicImgui()
    imgui._state.buttonResponses = {
        false, true,   -- min: "-" then "+"
        true, false,   -- max: "-" then "+"
    }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertEquals(store.uiState.get("MinDepth"), 3)
    lu.assertEquals(store.uiState.get("MaxDepth"), 7)
end

function TestUiNodes:testCollectQuickUiNodesRecursesThroughLayoutChildren()
    local nodes = {
        {
            type = "group",
            label = "Outer",
            children = {
                { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", quick = true },
                {
                    type = "group",
                    label = "Inner",
                    children = {
                        { type = "stepper", binds = { value = "Count" }, label = "Count", quick = true, min = 1, max = 9, step = 1 },
                    },
                },
            },
        },
    }

    local quick = lib.collectQuickUiNodes(nodes)

    lu.assertEquals(#quick, 2)
    lu.assertEquals(quick[1].binds and quick[1].binds.value, "Enabled")
    lu.assertEquals(quick[2].binds and quick[2].binds.value, "Count")
end

function TestUiNodes:testDrawUiNodeReturnsChangedWhenLayoutChildChanges()
    local definition = {
        storage = {
            { type = "bool", alias = "Enabled", configKey = "Enabled", default = true },
        },
        ui = {
            {
                type = "group",
                label = "Outer",
                children = {
                    { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
                },
            },
        },
    }
    local store = makeStore(definition, { Enabled = true })
    local imgui = makeBasicImgui()
    imgui._state.checkboxResponses = { false }

    local changed = lib.drawUiNode(imgui, definition.ui[1], store.uiState)

    lu.assertTrue(changed)
    lu.assertFalse(store.uiState.get("Enabled"))
end
