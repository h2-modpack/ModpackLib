local lu = require('luaunit')

TestIntegrations = {}

function TestIntegrations:setUp()
    lib.integrations.unregisterProvider("ProviderA")
    lib.integrations.unregisterProvider("ProviderB")
    lib.integrations.unregisterProvider("ProviderC")
    lib.integrations.unregisterProvider("LifecycleProvider")
end

function TestIntegrations:tearDown()
    lib.integrations.unregisterProvider("ProviderA")
    lib.integrations.unregisterProvider("ProviderB")
    lib.integrations.unregisterProvider("ProviderC")
    lib.integrations.unregisterProvider("RefreshProvider")
    lib.integrations.unregisterProvider("LifecycleProvider")
end

function TestIntegrations:testRegisterAndGetIntegration()
    local api = {
        isActive = function() return true end,
    }

    local registered = lib.integrations.register("test.example", "ProviderA", api)
    local found, providerId = lib.integrations.get("test.example")

    lu.assertEquals(registered, api)
    lu.assertEquals(found, api)
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testRegisterReplacesSameProviderWithoutDuplicatingListEntry()
    local first = { value = 1 }
    local second = { value = 2 }

    lib.integrations.register("test.example", "ProviderA", first)
    lib.integrations.register("test.example", "ProviderA", second)

    local found, providerId = lib.integrations.get("test.example")
    local providers = lib.integrations.list("test.example")

    lu.assertEquals(found, second)
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#providers, 1)
    lu.assertEquals(providers[1].api, second)
end

function TestIntegrations:testGetReturnsMostRecentlyRegisteredProvider()
    local first = { value = 1 }
    local second = { value = 2 }

    lib.integrations.register("test.example", "ProviderA", first)
    lib.integrations.register("test.example", "ProviderB", second)

    local found, providerId = lib.integrations.get("test.example")

    lu.assertEquals(found, second)
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testInvokeCallsMostRecentProviderMethod()
    lib.integrations.register("test.example", "ProviderA", {
        value = function()
            return "first"
        end,
    })
    lib.integrations.register("test.example", "ProviderB", {
        value = function(suffix)
            return "second:" .. suffix
        end,
    })

    local result, providerId = lib.integrations.invoke("test.example", "value", "fallback", "x")

    lu.assertEquals(result, "second:x")
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testInvokeUsesCurrentProviderAfterReregister()
    lib.integrations.register("test.example", "ProviderA", {
        value = function()
            return "first"
        end,
    })

    lu.assertEquals(lib.integrations.invoke("test.example", "value", "fallback"), "first")

    lib.integrations.register("test.example", "ProviderA", {
        value = function()
            return "second"
        end,
    })

    lu.assertEquals(lib.integrations.invoke("test.example", "value", "fallback"), "second")
end

function TestIntegrations:testInvokeReturnsFallbackForMissingProviderOrMethod()
    lu.assertEquals(lib.integrations.invoke("test.missing", "value", "fallback"), "fallback")

    lib.integrations.register("test.example", "ProviderA", {})

    local result, providerId = lib.integrations.invoke("test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testInvokeReturnsFallbackWhenProviderMethodFails()
    CaptureWarnings()
    lib.integrations.register("test.example", "ProviderA", {
        value = function()
            error("boom")
        end,
    })

    local result, providerId = lib.integrations.invoke("test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "test.example.value provider 'ProviderA' failed")
    RestoreWarnings()
end

function TestIntegrations:testListReturnsRegistrationOrder()
    lib.integrations.register("test.example", "ProviderA", { value = 1 })
    lib.integrations.register("test.example", "ProviderB", { value = 2 })

    local providers = lib.integrations.list("test.example")

    lu.assertEquals(#providers, 2)
    lu.assertEquals(providers[1].providerId, "ProviderA")
    lu.assertEquals(providers[2].providerId, "ProviderB")
end

function TestIntegrations:testUnregisterRemovesOneProvider()
    local first = { value = 1 }
    local second = { value = 2 }

    lib.integrations.register("test.example", "ProviderA", first)
    lib.integrations.register("test.example", "ProviderB", second)

    lu.assertTrue(lib.integrations.unregister("test.example", "ProviderB"))

    local found, providerId = lib.integrations.get("test.example")
    local providers = lib.integrations.list("test.example")

    lu.assertEquals(found, first)
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#providers, 1)
end

function TestIntegrations:testUnregisterProviderRemovesProviderAcrossIntegrationIds()
    lib.integrations.register("test.one", "ProviderA", { value = 1 })
    lib.integrations.register("test.two", "ProviderA", { value = 2 })
    lib.integrations.register("test.two", "ProviderB", { value = 3 })

    local removed = lib.integrations.unregisterProvider("ProviderA")

    lu.assertEquals(removed, 2)
    lu.assertNil(lib.integrations.get("test.one"))

    local found, providerId = lib.integrations.get("test.two")
    lu.assertEquals(found.value, 3)
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testRefreshRemovesOmittedProviderRegistrations()
    lib.integrations.unregisterProvider("RefreshProvider")

    AdamantModpackLib_Internal.integrations.refresh("RefreshProvider", function()
        lib.integrations.register("test.refresh.one", "RefreshProvider", { value = 1 })
        lib.integrations.register("test.refresh.two", "RefreshProvider", { value = 2 })
    end)

    lu.assertNotNil(lib.integrations.get("test.refresh.one"))
    lu.assertNotNil(lib.integrations.get("test.refresh.two"))

    AdamantModpackLib_Internal.integrations.refresh("RefreshProvider", function()
        lib.integrations.register("test.refresh.two", "RefreshProvider", { value = 3 })
    end)

    lu.assertNil(lib.integrations.get("test.refresh.one"))
    local found, providerId = lib.integrations.get("test.refresh.two")
    lu.assertEquals(found.value, 3)
    lu.assertEquals(providerId, "RefreshProvider")

    lib.integrations.unregisterProvider("RefreshProvider")
end

function TestIntegrations:testRefreshOwnerCanDifferFromProviderId()
    local refreshOwnerId = "plugin-guid.integration-owner"

    AdamantModpackLib_Internal.integrations.refresh(refreshOwnerId, function()
        lib.integrations.register("test.refresh.lifecycle-owner", "LifecycleProvider", { value = 1 })
    end)

    local found, providerId = lib.integrations.get("test.refresh.lifecycle-owner")
    lu.assertEquals(found.value, 1)
    lu.assertEquals(providerId, "LifecycleProvider")

    AdamantModpackLib_Internal.integrations.refresh(refreshOwnerId, function() end)

    lu.assertNil(lib.integrations.get("test.refresh.lifecycle-owner"))
end

function TestIntegrations:testFailedRefreshKeepsPreviousProviderRegistrations()
    lib.integrations.unregisterProvider("RefreshProvider")

    AdamantModpackLib_Internal.integrations.refresh("RefreshProvider", function()
        lib.integrations.register("test.refresh.one", "RefreshProvider", { value = 1 })
    end)

    local transaction = AdamantModpackLib_Internal.integrations.beginTransaction()
    lu.assertErrorMsgContains("refresh boom", function()
        AdamantModpackLib_Internal.integrations.refresh("RefreshProvider", function()
            lib.integrations.register("test.refresh.two", "RefreshProvider", { value = 2 })
            error("refresh boom")
        end)
    end)
    transaction.rollback()

    local foundOne, providerOne = lib.integrations.get("test.refresh.one")
    lu.assertEquals(foundOne.value, 1)
    lu.assertEquals(providerOne, "RefreshProvider")
    lu.assertNil(lib.integrations.get("test.refresh.two"))

    lib.integrations.unregisterProvider("RefreshProvider")
end

function TestIntegrations:testMissingIntegrationReturnsNilAndEmptyList()
    local found, providerId = lib.integrations.get("test.missing")
    local providers = lib.integrations.list("test.missing")

    lu.assertNil(found)
    lu.assertNil(providerId)
    lu.assertEquals(providers, {})
end
