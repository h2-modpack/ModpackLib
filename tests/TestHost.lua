local lu = require('luaunit')

TestHost = {}

function TestHost:setUp()
    CaptureWarnings()
    self.previousImGui = rom.ImGui
    self.previousImGuiCond = rom.ImGuiCond
end

function TestHost:tearDown()
    rom.ImGui = self.previousImGui
    rom.ImGuiCond = self.previousImGuiCond
    RestoreWarnings()
end

function TestHost:testStandaloneHostWarnsWhenSessionCommitFails()
    local drawCalls = 0

    local function noop() end

    rom.ImGuiCond = { FirstUseEver = 1 }
    rom.ImGui = {
        BeginMenu = function() return true end,
        MenuItem = function() return true end,
        EndMenu = noop,
        SetNextWindowSize = noop,
        Begin = function() return true, true end,
        End = noop,
        Checkbox = function(_, current) return current, false end,
        Button = function() return false end,
        Separator = noop,
        Spacing = noop,
    }

    local moduleHost = {
        getDefinition = function()
            return { id = "StandaloneTest", name = "Standalone Test" }
        end,
        applyOnLoad = function()
            return true, nil
        end,
        read = function(alias)
            if alias == "Enabled" then
                return true
            end
            if alias == "DebugMode" then
                return false
            end
            return nil
        end,
        setEnabled = function()
            return true, nil
        end,
        setDebugMode = noop,
        hasDrawTab = function()
            return true
        end,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
        commitIfDirty = function()
            return false, "commit boom", false
        end,
    }

    local runtime = lib.standaloneHost(moduleHost)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Standalone Test session commit failed")
    lu.assertStrContains(Warnings[1], "commit boom")
end
