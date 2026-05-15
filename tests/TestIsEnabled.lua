local lu = require('luaunit')

-- =============================================================================
-- isEnabled
-- =============================================================================

TestIsEnabled = {}

local function makeStore(enabled)
    return CreateModuleState({ Enabled = enabled }, AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "IsEnabledStore",
        name = "Is Enabled Store",
        storage = {},
    }))
end

-- Reset the "test-pack" coordinator slot before each test.
function TestIsEnabled:setUp()
    lib.coordinator.register("test-pack", nil)
end

-- no coordinator registered
function TestIsEnabled:testEnabledStandalone()
    lu.assertTrue(HostLifecycle.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledStandalone()
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(false), "test-pack"))
end

function TestIsEnabled:testEnabledNoPackId()
    lu.assertTrue(HostLifecycle.isEnabled(makeStore(true)))
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(false)))
end

-- coordinator registered with ModEnabled = true
function TestIsEnabled:testEnabledWithCoordEnabled()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertTrue(HostLifecycle.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordEnabled()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(false), "test-pack"))
end

-- coordinator registered with ModEnabled = false (pack-level off overrides module)
function TestIsEnabled:testEnabledWithCoordDisabled()
    lib.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordDisabled()
    lib.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(false), "test-pack"))
end

-- =============================================================================
-- isCoordinated
-- =============================================================================

TestIsCoordinated = {}

function TestIsCoordinated:setUp()
    lib.coordinator.register("test-pack", nil)
    lib.coordinator.register("other-pack", nil)
end

function TestIsCoordinated:testNotCoordinatedByDefault()
    lu.assertFalse(lib.coordinator.isRegistered("test-pack"))
end

function TestIsCoordinated:testCoordinatedAfterRegister()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.coordinator.isRegistered("test-pack"))
end

function TestIsCoordinated:testUnrelatedPackNotCoordinated()
    lib.coordinator.register("other-pack", { ModEnabled = true })
    lu.assertFalse(lib.coordinator.isRegistered("test-pack"))
end

function TestIsCoordinated:testClearedByNilRegister()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lib.coordinator.register("test-pack", nil)
    lu.assertFalse(lib.coordinator.isRegistered("test-pack"))
end

-- =============================================================================
-- registerCoordinator — multiple packs coexist
-- =============================================================================

TestRegisterCoordinator = {}

function TestRegisterCoordinator:setUp()
    lib.coordinator.register("pack-a", nil)
    lib.coordinator.register("pack-b", nil)
end

function TestRegisterCoordinator:testMultiplePacksIndependent()
    lib.coordinator.register("pack-a", { ModEnabled = true })
    lib.coordinator.register("pack-b", { ModEnabled = false })
    lu.assertTrue(lib.coordinator.isRegistered("pack-a"))
    lu.assertTrue(lib.coordinator.isRegistered("pack-b"))
    lu.assertTrue(HostLifecycle.isEnabled(makeStore(true), "pack-a"))
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(true), "pack-b"))
end

function TestRegisterCoordinator:testRegisterCoordinatorRejectsInvalidConfig()
    lu.assertErrorMsgContains("packId must be a non-empty string", function()
        lib.coordinator.register("", { ModEnabled = true })
    end)
    lu.assertErrorMsgContains("config.ModEnabled must be a boolean", function()
        lib.coordinator.register("bad-pack", {})
    end)
end

function TestRegisterCoordinator:testCoordinatorRegistrySurvivesLibReload()
    lib.coordinator.register("pack-a", { ModEnabled = false })
    lib.coordinator.registerRebuild("pack-a", function()
        return true
    end)

    dofile("src/main.lua")
    lib = public

    lu.assertTrue(lib.coordinator.isRegistered("pack-a"))
    lu.assertFalse(HostLifecycle.isEnabled(makeStore(true), "pack-a"))
    lu.assertTrue(lib.coordinator.requestRebuild("pack-a", {
        kind = "test",
    }))
end
