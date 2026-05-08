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
    AdamantModpackLib_Internal.violationSeverity["test.warn"] = nil
    AdamantModpackLib_Internal.violationSeverity["test.debug"] = nil
    AdamantModpackLib_Internal.violationSeverity["test.ignore"] = nil
    AdamantModpackLib_Internal.violationSeverity["test.error"] = nil
    AdamantModpackLib_Internal.violationSeverity["test.invalid"] = nil
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
    AdamantModpackLib_Internal.violationSeverity["test.warn"] = "warn"

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

function TestLogging:testViolationDebugHonorsLibDebugMode()
    AdamantModpackLib_Internal.violationSeverity["test.debug"] = "debug"

    AdamantModpackLib_Internal.violate("test.debug", "hidden")
    lib.config.DebugMode = true
    AdamantModpackLib_Internal.violate("test.debug", "visible")

    lu.assertEquals(self.lines, { "[lib] test.debug: visible" })
end

function TestLogging:testViolationIgnoreReturnsWithoutPrinting()
    AdamantModpackLib_Internal.violationSeverity["test.ignore"] = "ignore"

    local severity, message = AdamantModpackLib_Internal.violate("test.ignore", "ignored")

    lu.assertEquals(severity, "ignore")
    lu.assertEquals(message, "[lib] test.ignore: ignored")
    lu.assertEquals(self.lines, {})
end

function TestLogging:testViolationErrorRaises()
    AdamantModpackLib_Internal.violationSeverity["test.error"] = "error"

    lu.assertErrorMsgContains("[lib] test.error: broken", function()
        AdamantModpackLib_Internal.violate("test.error", "broken")
    end)
end

function TestLogging:testViolationRejectsInvalidSeverity()
    AdamantModpackLib_Internal.violationSeverity["test.invalid"] = "trace"

    lu.assertErrorMsgContains("violation.invalid_severity", function()
        AdamantModpackLib_Internal.violate("test.invalid", "broken")
    end)
end

function TestLogging:testViolationRejectsUnknownId()
    lu.assertErrorMsgContains("violation.unknown_id", function()
        AdamantModpackLib_Internal.violate("test.missing", "broken")
    end)
end
