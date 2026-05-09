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

function TestLogging:testWarnAlwaysFormatsWithPackPrefix()
    lib.logging.warn("pack", "hello %s", "world")

    lu.assertEquals(self.lines, { "[pack] hello world" })
end

function TestLogging:testWarnIfHonorsEnabledFlag()
    lib.logging.warnIf("pack", false, "hidden")
    lib.logging.warnIf("pack", true, "visible %d", 7)

    lu.assertEquals(self.lines, { "[pack] visible 7" })
end

function TestLogging:testLogIfHonorsEnabledFlagAndHandlesPlainMessages()
    lib.logging.logIf("system", false, "hidden")
    lib.logging.logIf("system", true, "plain message")
    lib.logging.logIf("system", true, "formatted %s", "message")

    lu.assertEquals(self.lines, {
        "[system] plain message",
        "[system] formatted message",
    })
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
        "src/core/definition.lua",
        "src/core/game_object.lua",
        "src/core/hooks.lua",
        "src/core/host.lua",
        "src/core/integrations.lua",
        "src/core/lifecycle.lua",
        "src/core/module.lua",
        "src/core/overlays.lua",
        "src/core/store.lua",
        "src/core/internal/logging.lua",
        "src/core/internal/session.lua",
        "src/core/internal/storage.lua",
        "src/core/internal/storage_types.lua",
        "src/core/internal/store.lua",
        "src/widgets/widget_helpers.lua",
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
        "src/core/definition.lua",
        "src/core/game_object.lua",
        "src/core/hooks.lua",
        "src/core/host.lua",
        "src/core/integrations.lua",
        "src/core/lifecycle.lua",
        "src/core/module.lua",
        "src/core/overlays.lua",
        "src/core/store.lua",
        "src/core/internal/logging.lua",
        "src/core/internal/session.lua",
        "src/core/internal/storage.lua",
        "src/core/internal/storage_types.lua",
        "src/core/internal/store.lua",
        "src/widgets/widget_helpers.lua",
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
