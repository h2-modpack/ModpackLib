local lu = require('luaunit')

TestStandaloneHost = {}

local function makeHost(opts)
    opts = opts or {}
    local calls = {
        applyOnLoad = 0,
        setEnabled = {},
        setDebugMode = {},
        resync = 0,
        drawTab = 0,
        commitIfDirty = 0,
    }
    local enabled = opts.enabled ~= false
    local debugMode = opts.debugMode == true
    local host = {
        calls = calls,
        getIdentity = function()
            return {
                id = opts.id or "StandaloneTest",
                modpack = opts.modpack,
            }
        end,
        getMeta = function()
            return {
                name = opts.name or "Standalone Test",
            }
        end,
        affectsRunData = function()
            return opts.affectsRunData == true
        end,
        read = function(alias)
            if alias == "Enabled" then
                return enabled
            elseif alias == "DebugMode" then
                return debugMode
            end
            return nil
        end,
        setEnabled = function(value)
            table.insert(calls.setEnabled, value)
            if opts.setEnabledFails then
                return false, "enable boom"
            end
            enabled = value == true
            return true, nil
        end,
        setDebugMode = function(value)
            table.insert(calls.setDebugMode, value)
            debugMode = value == true
        end,
        applyOnLoad = function()
            calls.applyOnLoad = calls.applyOnLoad + 1
            if opts.applyFails then
                return false, "apply boom"
            end
            return true, nil
        end,
        resync = function()
            calls.resync = calls.resync + 1
        end,
        drawTab = function()
            calls.drawTab = calls.drawTab + 1
        end,
        commitIfDirty = function()
            calls.commitIfDirty = calls.commitIfDirty + 1
            return true, nil, opts.committed == true
        end,
    }
    return host
end

local function installHost(host)
    local moduleName = _PLUGIN.guid
    local previousHost = AdamantModpackLib_Internal.liveModuleHosts[moduleName]
    AdamantModpackLib_Internal.liveModuleHosts[moduleName] = host
    return function()
        AdamantModpackLib_Internal.liveModuleHosts[moduleName] = previousHost
    end
end

local function makeImgui(opts)
    opts = opts or {}
    local calls = {
        setNextWindowSize = 0,
        begin = 0,
        endWindow = 0,
        beginMenu = 0,
        endMenu = 0,
        separator = 0,
        spacing = 0,
        checkboxLabels = {},
        buttons = {},
    }
    local checkboxValues = opts.checkboxValues or {}
    local buttonClicks = opts.buttonClicks or {}
    local imgui = {
        calls = calls,
        SetNextWindowSize = function(width, height, cond)
            calls.setNextWindowSize = calls.setNextWindowSize + 1
            calls.windowSize = { width = width, height = height, cond = cond }
        end,
        Begin = function(title, showWindow)
            calls.begin = calls.begin + 1
            calls.title = title
            calls.showWindow = showWindow
            return opts.open ~= false, opts.shouldDraw ~= false
        end,
        End = function()
            calls.endWindow = calls.endWindow + 1
        end,
        Checkbox = function(label, current)
            table.insert(calls.checkboxLabels, label)
            local nextValue = checkboxValues[label]
            if nextValue == nil then
                return current, false
            end
            return nextValue, true
        end,
        Button = function(label)
            table.insert(calls.buttons, label)
            return buttonClicks[label] == true
        end,
        Separator = function()
            calls.separator = calls.separator + 1
        end,
        Spacing = function()
            calls.spacing = calls.spacing + 1
        end,
        BeginMenu = function(label)
            calls.beginMenu = calls.beginMenu + 1
            calls.menuLabel = label
            return opts.menuOpen ~= false
        end,
        MenuItem = function(label)
            calls.menuItem = label
            return opts.menuClicked == true
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
    }
    return imgui, calls
end

function TestStandaloneHost:setUp()
    CaptureWarnings()
    self.previousImGui = rom.ImGui
    self.previousImGuiCond = rom.ImGuiCond
    self.previousSetupRunData = rom.game.SetupRunData
    self.previousCoordinator = AdamantModpackLib_Internal.coordinators["standalone-pack"]
    rom.ImGuiCond = { FirstUseEver = 1 }
end

function TestStandaloneHost:tearDown()
    rom.ImGui = self.previousImGui
    rom.ImGuiCond = self.previousImGuiCond
    rom.game.SetupRunData = self.previousSetupRunData
    lib.lifecycle.registerCoordinator("standalone-pack", self.previousCoordinator)
    RestoreWarnings()
end

function TestStandaloneHost:testErrorsWhenCurrentModuleHasNoLiveHost()
    local restoreHost = installHost(nil)

    lu.assertErrorMsgContains("no live module host is registered", function()
        lib.standaloneHost()
    end)

    restoreHost()
end

function TestStandaloneHost:testAppliesOnLoadWhenModuleIsNotCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.lifecycle.registerCoordinator("standalone-pack", nil)

    local runtime = lib.standaloneHost()

    restoreHost()
    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(host.calls.applyOnLoad, 1)
end

function TestStandaloneHost:testSkipsStandaloneLifecycleAndUiWhenCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.lifecycle.registerCoordinator("standalone-pack", { ModEnabled = true })
    local imgui, calls = makeImgui({ menuClicked = true })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost()
    runtime.addMenuBar()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(host.calls.applyOnLoad, 0)
    lu.assertEquals(calls.beginMenu, 0)
    lu.assertEquals(calls.begin, 0)
end

function TestStandaloneHost:testMenuTogglesWindowAndRenderDrawsControls()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.lifecycle.registerCoordinator("standalone-pack", nil)
    local imgui, calls = makeImgui({
        menuClicked = true,
        buttonClicks = {
            ["Resync Session"] = true,
        },
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost()
    runtime.addMenuBar()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(calls.beginMenu, 1)
    lu.assertEquals(calls.menuLabel, "Standalone Test")
    lu.assertEquals(calls.menuItem, "Standalone Test")
    lu.assertEquals(calls.setNextWindowSize, 1)
    lu.assertEquals(calls.title, "Standalone Test###StandaloneTest")
    lu.assertEquals(calls.checkboxLabels, { "Enabled", "Debug Mode" })
    lu.assertEquals(host.calls.resync, 1)
    lu.assertEquals(host.calls.drawTab, 1)
    lu.assertEquals(host.calls.commitIfDirty, 1)
end

function TestStandaloneHost:testCloseFlushesRunDataAfterAffectingEnabledToggle()
    local setupCalls = 0
    rom.game.SetupRunData = function()
        setupCalls = setupCalls + 1
    end
    local host = makeHost({
        modpack = "standalone-pack",
        affectsRunData = true,
    })
    local restoreHost = installHost(host)
    lib.lifecycle.registerCoordinator("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            Enabled = false,
        },
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost()
    runtime.addMenuBar()
    runtime.renderWindow()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(host.calls.setEnabled, { false })
    lu.assertEquals(setupCalls, 1)
end

function TestStandaloneHost:testDebugToggleDoesNotMarkRunDataDirty()
    local setupCalls = 0
    rom.game.SetupRunData = function()
        setupCalls = setupCalls + 1
    end
    local host = makeHost({
        modpack = "standalone-pack",
        affectsRunData = true,
    })
    local restoreHost = installHost(host)
    lib.lifecycle.registerCoordinator("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            ["Debug Mode"] = true,
        },
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost()
    runtime.addMenuBar()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(host.calls.setDebugMode, { true })
    lu.assertEquals(setupCalls, 0)
end
