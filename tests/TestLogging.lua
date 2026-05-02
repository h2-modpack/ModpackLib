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
