local lu = require('luaunit')

TestLogging = {}

function TestLogging:setUp()
    self.previousPrint = print
    self.lines = {}
    print = function(msg)
        table.insert(self.lines, msg)
    end
end

function TestLogging:tearDown()
    print = self.previousPrint
    AdamantModpackLib_Internal.violationPolicy["test.warn"] = nil
    AdamantModpackLib_Internal.violationPolicy["test.debug"] = nil
    AdamantModpackLib_Internal.violationPolicy["test.ignore"] = nil
    AdamantModpackLib_Internal.violationPolicy["test.error"] = nil
    AdamantModpackLib_Internal.violationPolicy["test.invalid"] = nil
    lib.config.DebugMode = false
end

function TestLogging:testViolationWarnUsesPolicyId()
    AdamantModpackLib_Internal.violationPolicy["test.warn"] = {
        severity = "warn",
        description = "Test warning policy.",
    }

    local severity, message = AdamantModpackLib_Internal.violate("test.warn", "hello %s", "world")

    lu.assertEquals(severity, "warn")
    lu.assertEquals(message, "[lib] test.warn: hello world")
    lu.assertEquals(self.lines, { "[lib] test.warn: hello world" })
end

function TestLogging:testViolationPolicyCarriesDescriptions()
    local policy = AdamantModpackLib_Internal.violationPolicy["storage.hash_requires_persist"]

    lu.assertEquals(policy.severity, "error")
    lu.assertStrContains(policy.description, "persisted")
end

function TestLogging:testViolationPolicyMatchesSourceCallSites()
    local files = {
        "src/core/module_bootstrap/definition.lua",
        "src/core/game_object/game_object.lua",
        "src/core/hooks/hooks.lua",
        "src/core/hooks/private_registry.lua",
        "src/core/module_bootstrap/host.lua",
        "src/core/module_bootstrap/private_host_lifecycle.lua",
        "src/core/integrations/integrations.lua",
        "src/core/integrations/private_registry.lua",
        "src/core/coordinator/coordinator.lua",
        "src/core/module_bootstrap/module.lua",
        "src/core/overlays/overlays.lua",
        "src/core/overlays/private_renderer.lua",
        "src/core/overlays/private_retained.lua",
        "src/core/overlays/private_state.lua",
        "src/core/standalone_host/standalone_host.lua",
        "src/core/module_state/module_state.lua",
        "src/core/logging/logging.lua",
        "src/core/helpers/values.lua",
        "src/core/module_state/private_session.lua",
        "src/core/storage/storage.lua",
        "src/core/storage/private_packed.lua",
        "src/core/storage/private_table.lua",
        "src/core/storage/private_types.lua",
        "src/core/module_state/private_store.lua",
        "src/core/widgets/widget_helpers.lua",
    }

    for _, path in ipairs(files) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "internal%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            lu.assertNotNil(AdamantModpackLib_Internal.violationPolicy[id], id)
        end
    end
end

function TestLogging:testViolationPolicyHasNoOrphanIds()
    local files = {
        "src/core/module_bootstrap/definition.lua",
        "src/core/game_object/game_object.lua",
        "src/core/hooks/hooks.lua",
        "src/core/hooks/private_registry.lua",
        "src/core/module_bootstrap/host.lua",
        "src/core/module_bootstrap/private_host_lifecycle.lua",
        "src/core/integrations/integrations.lua",
        "src/core/integrations/private_registry.lua",
        "src/core/coordinator/coordinator.lua",
        "src/core/module_bootstrap/module.lua",
        "src/core/overlays/overlays.lua",
        "src/core/overlays/private_renderer.lua",
        "src/core/overlays/private_retained.lua",
        "src/core/overlays/private_state.lua",
        "src/core/standalone_host/standalone_host.lua",
        "src/core/module_state/module_state.lua",
        "src/core/logging/logging.lua",
        "src/core/helpers/values.lua",
        "src/core/module_state/private_session.lua",
        "src/core/storage/storage.lua",
        "src/core/storage/private_packed.lua",
        "src/core/storage/private_table.lua",
        "src/core/storage/private_types.lua",
        "src/core/module_state/private_store.lua",
        "src/core/widgets/widget_helpers.lua",
    }
    local referenced = {}

    for _, path in ipairs(files) do
        local handle = assert(io.open(path, "r"))
        local source = handle:read("*a")
        handle:close()
        for id in string.gmatch(source, "internal%.violate%s*%(%s*[\"']([^\"']+)[\"']") do
            referenced[id] = true
        end
    end

    for id in pairs(AdamantModpackLib_Internal.violationPolicy) do
        if not string.match(id, "^test%.") then
            lu.assertTrue(referenced[id], id)
        end
    end
end

function TestLogging:testViolationDebugHonorsLibDebugMode()
    AdamantModpackLib_Internal.violationPolicy["test.debug"] = {
        severity = "debug",
        description = "Test debug policy.",
    }

    AdamantModpackLib_Internal.violate("test.debug", "hidden")
    lib.config.DebugMode = true
    AdamantModpackLib_Internal.violate("test.debug", "visible")

    lu.assertEquals(self.lines, { "[lib] test.debug: visible" })
end

function TestLogging:testViolationIgnoreReturnsWithoutPrinting()
    AdamantModpackLib_Internal.violationPolicy["test.ignore"] = {
        severity = "ignore",
        description = "Test ignored policy.",
    }

    local severity, message = AdamantModpackLib_Internal.violate("test.ignore", "ignored")

    lu.assertEquals(severity, "ignore")
    lu.assertEquals(message, "[lib] test.ignore: ignored")
    lu.assertEquals(self.lines, {})
end

function TestLogging:testViolationErrorRaises()
    AdamantModpackLib_Internal.violationPolicy["test.error"] = {
        severity = "error",
        description = "Test error policy.",
    }

    lu.assertErrorMsgContains("[lib] test.error: broken", function()
        AdamantModpackLib_Internal.violate("test.error", "broken")
    end)
end

function TestLogging:testViolationRejectsInvalidSeverity()
    AdamantModpackLib_Internal.violationPolicy["test.invalid"] = {
        severity = "trace",
        description = "Test invalid policy.",
    }

    lu.assertErrorMsgContains("violation.invalid_severity", function()
        AdamantModpackLib_Internal.violate("test.invalid", "broken")
    end)
end

function TestLogging:testViolationRejectsUnknownId()
    lu.assertErrorMsgContains("violation.unknown_id", function()
        AdamantModpackLib_Internal.violate("test.missing", "broken")
    end)
end
