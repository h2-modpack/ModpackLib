local lu = require('luaunit')

TestSpecialState = {}

function TestSpecialState:setUp()
    CaptureWarnings()
end

function TestSpecialState:tearDown()
    RestoreWarnings()
end

function TestSpecialState:testStagingMirrorsConfig()
    local config = { Mode = "Fast", Strict = true }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
        { type = "checkbox", configKey = "Strict" },
    }

    local specialState = lib.createSpecialState(config, schema)

    lu.assertEquals(specialState.view.Mode, "Fast")
    lu.assertEquals(specialState.view.Strict, true)
end

function TestSpecialState:testSnapshotReReadsConfig()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local specialState = lib.createSpecialState(config, schema)
    lu.assertEquals(specialState.view.Mode, "Fast")

    config.Mode = "Slow"
    specialState.reloadFromConfig()
    lu.assertEquals(specialState.view.Mode, "Slow")
end

function TestSpecialState:testSyncFlushesToConfig()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local specialState = lib.createSpecialState(config, schema)
    specialState.set("Mode", "Slow")

    lu.assertEquals(config.Mode, "Fast") -- not yet synced
    specialState.flushToConfig()
    lu.assertEquals(config.Mode, "Slow")
end

function TestSpecialState:testNestedConfigKey()
    local config = { Parent = { Child = "value" } }
    local schema = {
        { type = "dropdown", configKey = {"Parent", "Child"}, values = { "value", "other" }, default = "value" },
    }

    local specialState = lib.createSpecialState(config, schema)
    lu.assertEquals(specialState.view.Parent.Child, "value")

    specialState.set({"Parent", "Child"}, "other")
    specialState.flushToConfig()
    lu.assertEquals(config.Parent.Child, "other")

    config.Parent.Child = "value"
    specialState.reloadFromConfig()
    lu.assertEquals(specialState.view.Parent.Child, "value")
end

function TestSpecialState:testReadonlyViewRejectsWrites()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local specialState = lib.createSpecialState(config, schema)
    local ok = pcall(function()
        specialState.view.Mode = "Slow"
    end)

    lu.assertFalse(ok)
end

function TestSpecialState:testSetMarksDirtyAndSyncClearsDirty()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local specialState = lib.createSpecialState(config, schema)
    lu.assertFalse(specialState.isDirty())

    specialState.set("Strict", true)
    lu.assertTrue(specialState.isDirty())
    lu.assertEquals(specialState.view.Strict, true)

    specialState.flushToConfig()
    lu.assertFalse(specialState.isDirty())
    lu.assertTrue(config.Strict)
end

function TestSpecialState:testUpdateUsesCurrentValue()
    local config = { Count = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Count", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local specialState = lib.createSpecialState(config, schema)
    specialState.update("Count", function(current)
        if current == "Fast" then return "Slow" end
        return "Fast"
    end)

    lu.assertTrue(specialState.isDirty())
    lu.assertEquals(specialState.view.Count, "Slow")

    specialState.flushToConfig()
    lu.assertEquals(config.Count, "Slow")
end

function TestSpecialState:testToggleFlipsBooleanField()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local specialState = lib.createSpecialState(config, schema)
    specialState.toggle("Strict")
    lu.assertEquals(specialState.view.Strict, true)
    lu.assertTrue(specialState.isDirty())

    specialState.toggle("Strict")
    lu.assertEquals(specialState.view.Strict, false)
end

function TestSpecialState:testReloadFromConfigClearsUnsyncedViewChanges()
    local config = { Mode = "Fast" }
    local schema = {
        { type = "dropdown", configKey = "Mode", values = { "Fast", "Slow" }, default = "Fast" },
    }

    local specialState = lib.createSpecialState(config, schema)
    specialState.set("Mode", "Slow")
    lu.assertEquals(specialState.view.Mode, "Slow")
    lu.assertTrue(specialState.isDirty())

    specialState.reloadFromConfig()
    lu.assertEquals(specialState.view.Mode, "Fast")
    lu.assertFalse(specialState.isDirty())
end

TestSpecialConfigWarnings = {}

function TestSpecialConfigWarnings:setUp()
    CaptureWarnings()
end

function TestSpecialConfigWarnings:tearDown()
    RestoreWarnings()
end

function TestSpecialConfigWarnings:testCaptureSnapshotTracksSchemaKeys()
    local config = {
        Strict = false,
        Nested = { Mode = "Fast" },
    }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
        { type = "dropdown", configKey = { "Nested", "Mode" }, values = { "Fast", "Slow" }, default = "Fast" },
    }

    local snapshot = lib.captureSpecialConfigSnapshot(config, schema)
    lu.assertEquals(snapshot.Strict, false)
    lu.assertEquals(snapshot["Nested.Mode"], "Fast")
end

function TestSpecialConfigWarnings:testWarnsOnDirectConfigWriteWithoutDirtyState()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local specialState = lib.createSpecialState(config, schema)
    local before = lib.captureSpecialConfigSnapshot(config, schema)
    config.Strict = true

    lib.warnIfSpecialConfigBypassedState("TestSpecial", true, specialState, config, schema, before)

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "special UI modified config directly")
end

function TestSpecialConfigWarnings:testDoesNotWarnWhenSpecialStateIsDirty()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local specialState = lib.createSpecialState(config, schema)
    local before = lib.captureSpecialConfigSnapshot(config, schema)
    specialState.set("Strict", true)

    lib.warnIfSpecialConfigBypassedState("TestSpecial", true, specialState, config, schema, before)

    lu.assertEquals(#Warnings, 0)
end

function TestSpecialConfigWarnings:testDoesNotWarnWhenConfigDidNotChange()
    local config = { Strict = false }
    local schema = {
        { type = "checkbox", configKey = "Strict", default = false },
    }

    local specialState = lib.createSpecialState(config, schema)
    local before = lib.captureSpecialConfigSnapshot(config, schema)

    lib.warnIfSpecialConfigBypassedState("TestSpecial", true, specialState, config, schema, before)

    lu.assertEquals(#Warnings, 0)
end
