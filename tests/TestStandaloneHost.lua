local lu = require('luaunit')

TestStandaloneHost = {}

local PLUGIN_GUID = "test-standalone-module"
local FALLBACK_OWNER = "adamant-lib.fallback-hud"
local FALLBACK_ROW_KEY = "middleRightStack\0" .. FALLBACK_OWNER .. ":marker"

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

local function installHost(host, pluginGuid)
    pluginGuid = pluginGuid or PLUGIN_GUID
    local previousHost = AdamantModpackLib_Internal.liveModuleHosts[pluginGuid]
    AdamantModpackLib_Internal.liveModuleHosts[pluginGuid] = host
    return function()
        AdamantModpackLib_Internal.liveModuleHosts[pluginGuid] = previousHost
    end
end

local function getFallbackMarkerRow()
    AdamantModpackLib_Internal.fallbackHud.createMarker()
    return AdamantModpackLib_OverlayState.renderer.stackRows[FALLBACK_ROW_KEY]
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
    self.previousSuppressForUi = lib.overlays.suppressForUi
    self.previousCoordinator = AdamantModpackLib_Internal.coordinators["standalone-pack"]
    self.previousOtherCoordinator = AdamantModpackLib_Internal.coordinators["other-pack"]
    self.previousStandaloneRuntimes = AdamantModpackLib_Internal.standaloneRuntimes
    self.previousFallbackInitialized = AdamantModpackLib_Internal.fallbackHud._initialized
    self.previousScreenData = ScreenData
    self.previousHudScreen = HUDScreen
    self.previousModifyTextBox = ModifyTextBox
    self.previousSetAlpha = SetAlpha
    self.previousCreateComponentFromData = CreateComponentFromData
    self.previousDestroy = Destroy
    self.previousShowingCombatUI = ShowingCombatUI
    self.overlayState = AdamantModpackLib_OverlayState
    self.rendererState = self.overlayState.renderer
    self.retainedState = self.overlayState.retained
    self.previousRendererTextElements = self.rendererState.textElements
    self.previousRendererStackRows = self.rendererState.stackRows
    self.previousRetainedTableRegistries = self.retainedState.tableRegistries
    self.previousRetainedExplicitRegistries = self.retainedState.explicitRegistries
    self.previousRetainedNextOwnerId = self.retainedState.nextOwnerId
    self.previousRetainedIntervalDriverRegistered = self.retainedState.intervalDriverRegistered

    rom.ImGuiCond = { FirstUseEver = 1 }
    AdamantModpackLib_Internal.standaloneRuntimes = {}
    AdamantModpackLib_Internal.fallbackHud._initialized = nil
    self.rendererState.textElements = {}
    self.rendererState.stackRows = {}
    self.retainedState.tableRegistries = setmetatable({}, { __mode = "k" })
    self.retainedState.explicitRegistries = {}
    self.retainedState.nextOwnerId = 0
    self.retainedState.intervalDriverRegistered = true
    ShowingCombatUI = true
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end
    SetAlpha = function() end
    CreateComponentFromData = function(_, data)
        return {
            Id = data.Name,
        }
    end
    Destroy = function() end
end

function TestStandaloneHost:tearDown()
    rom.ImGui = self.previousImGui
    rom.ImGuiCond = self.previousImGuiCond
    rom.game.SetupRunData = self.previousSetupRunData
    lib.overlays.suppressForUi = self.previousSuppressForUi
    lib.coordinator.register("standalone-pack", self.previousCoordinator)
    lib.coordinator.register("other-pack", self.previousOtherCoordinator)
    AdamantModpackLib_Internal.standaloneRuntimes = self.previousStandaloneRuntimes
    AdamantModpackLib_Internal.fallbackHud._initialized = self.previousFallbackInitialized
    ScreenData = self.previousScreenData
    HUDScreen = self.previousHudScreen
    ModifyTextBox = self.previousModifyTextBox
    SetAlpha = self.previousSetAlpha
    CreateComponentFromData = self.previousCreateComponentFromData
    Destroy = self.previousDestroy
    ShowingCombatUI = self.previousShowingCombatUI
    self.rendererState.textElements = self.previousRendererTextElements
    self.rendererState.stackRows = self.previousRendererStackRows
    self.retainedState.tableRegistries = self.previousRetainedTableRegistries
    self.retainedState.explicitRegistries = self.previousRetainedExplicitRegistries
    self.retainedState.nextOwnerId = self.previousRetainedNextOwnerId
    self.retainedState.intervalDriverRegistered = self.previousRetainedIntervalDriverRegistered
    RestoreWarnings()
end

function TestStandaloneHost:testErrorsWhenPluginGuidMissing()
    lu.assertErrorMsgContains("pluginGuid is required", function()
        lib.standaloneHost()
    end)
end

function TestStandaloneHost:testBridgeErrorsWhenPluginGuidMissing()
    lu.assertErrorMsgContains("pluginGuid is required", function()
        lib.standaloneUiBridge()
    end)
end

function TestStandaloneHost:testErrorsWhenModuleHasNoLiveHost()
    local restoreHost = installHost(nil)

    lu.assertErrorMsgContains("no live module host is registered", function()
        lib.standaloneHost(PLUGIN_GUID)
    end)

    restoreHost()
end

function TestStandaloneHost:testBridgeCallbacksNoOpBeforeRuntimeExists()
    local bridge = lib.standaloneUiBridge(PLUGIN_GUID)

    local okMenu, errMenu = pcall(bridge.addMenuBar)
    local okRender, errRender = pcall(bridge.renderWindow)
    local okClosed, errClosed = pcall(bridge.handleHostGuiClosed)

    lu.assertTrue(okMenu, errMenu)
    lu.assertTrue(okRender, errRender)
    lu.assertTrue(okClosed, errClosed)
end

function TestStandaloneHost:testAppliesOnLoadWhenModuleIsNotCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", nil)

    local runtime = lib.standaloneHost(PLUGIN_GUID)

    restoreHost()
    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(runtime.handleHostGuiClosed), "function")
    lu.assertEquals(host.calls.applyOnLoad, 1)
end

function TestStandaloneHost:testBridgeDispatchesInstalledRuntime()
    local bridge = lib.standaloneUiBridge(PLUGIN_GUID)
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({ menuClicked = true })
    rom.ImGui = imgui

    lib.standaloneHost(PLUGIN_GUID)
    bridge.addMenuBar()
    bridge.renderWindow()

    restoreHost()
    lu.assertEquals(host.calls.drawTab, 1)
end

function TestStandaloneHost:testBridgeDispatchesReplacementRuntime()
    local bridge = lib.standaloneUiBridge(PLUGIN_GUID)
    local firstHost = makeHost({ modpack = "standalone-pack", name = "First Standalone" })
    local restoreFirstHost = installHost(firstHost)
    lib.coordinator.register("standalone-pack", nil)
    rom.ImGui = makeImgui({ menuClicked = true })
    lib.standaloneHost(PLUGIN_GUID)
    bridge.addMenuBar()
    bridge.renderWindow()

    local secondHost = makeHost({ modpack = "standalone-pack", name = "Second Standalone" })
    local restoreSecondHost = installHost(secondHost)
    rom.ImGui = makeImgui({ menuClicked = true })
    lib.standaloneHost(PLUGIN_GUID)
    bridge.addMenuBar()
    bridge.renderWindow()

    restoreSecondHost()
    restoreFirstHost()
    lu.assertEquals(firstHost.calls.drawTab, 1)
    lu.assertEquals(secondHost.calls.drawTab, 1)
end

function TestStandaloneHost:testSkipsStandaloneLifecycleAndUiWhenCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", { ModEnabled = true })
    local imgui, calls = makeImgui({ menuClicked = true })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(host.calls.applyOnLoad, 0)
    lu.assertEquals(calls.beginMenu, 0)
    lu.assertEquals(calls.begin, 0)
end

function TestStandaloneHost:testFallbackMarkerHidesWhenOnlyStandaloneRuntimeIsCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", { ModEnabled = true })

    lib.standaloneHost(PLUGIN_GUID)
    local row = getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertFalse(row.visible())
    restoreHost()
end

function TestStandaloneHost:testFallbackMarkerShowsWhenStandaloneRuntimeIsUncoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", nil)

    lib.standaloneHost(PLUGIN_GUID)
    local row = getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertTrue(row.visible())
    restoreHost()
end

function TestStandaloneHost:testFallbackMarkerShowsWhenAnyStandaloneRuntimeIsUncoordinated()
    local coordinatedHost = makeHost({ modpack = "standalone-pack" })
    local uncoordinatedHost = makeHost({ modpack = "other-pack" })
    local restoreCoordinatedHost = installHost(coordinatedHost)
    local restoreUncoordinatedHost = installHost(uncoordinatedHost, "other-plugin")
    lib.coordinator.register("standalone-pack", { ModEnabled = true })
    lib.coordinator.register("other-pack", nil)

    lib.standaloneHost(PLUGIN_GUID)
    lib.standaloneHost("other-plugin")
    local row = getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertTrue(row.visible())
    restoreUncoordinatedHost()
    restoreCoordinatedHost()
end

function TestStandaloneHost:testMenuTogglesWindowAndRenderDrawsControls()
    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", nil)
    local imgui, calls = makeImgui({
        menuClicked = true,
        buttonClicks = {
            ["Resync Session"] = true,
        },
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost(PLUGIN_GUID)
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
    lib.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            Enabled = false,
        },
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost(PLUGIN_GUID)
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
    lib.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            ["Debug Mode"] = true,
        },
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(host.calls.setDebugMode, { true })
    lu.assertEquals(setupCalls, 0)
end

function TestStandaloneHost:testStandaloneWindowSuppressesOverlaysUntilClose()
    local suppressCalls = 0
    local releaseCalls = 0
    lib.overlays.suppressForUi = function()
        suppressCalls = suppressCalls + 1
        return {
            release = function()
                releaseCalls = releaseCalls + 1
            end,
        }
    end

    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
    })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(suppressCalls, 1)
    lu.assertEquals(releaseCalls, 1)
end

function TestStandaloneHost:testHostGuiClosedReleasesSuppressionWithoutClosingWindow()
    local suppressCalls = 0
    local releaseCalls = 0
    lib.overlays.suppressForUi = function()
        suppressCalls = suppressCalls + 1
        return {
            release = function()
                releaseCalls = releaseCalls + 1
            end,
        }
    end

    local host = makeHost({ modpack = "standalone-pack" })
    local restoreHost = installHost(host)
    lib.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({ menuClicked = true })
    rom.ImGui = imgui

    local runtime = lib.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.handleHostGuiClosed()
    runtime.renderWindow()

    restoreHost()
    lu.assertEquals(suppressCalls, 2)
    lu.assertEquals(releaseCalls, 1)
    lu.assertEquals(host.calls.drawTab, 1)
end
