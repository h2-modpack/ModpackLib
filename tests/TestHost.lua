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
    local pluginGuid = "test-standalone-commit"
    local definition = lib.prepareDefinition({}, {
        modpack = "standalone-pack",
        id = "StandaloneTest",
        name = "Standalone Test",
        storage = {},
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)

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

    local moduleHost = lib.createModuleHost({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    moduleHost.commitIfDirty = function()
        return false, "commit boom", false
    end

    local runtime = lib.standaloneHost(pluginGuid)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Standalone Test session commit failed")
    lu.assertStrContains(Warnings[1], "commit boom")
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), moduleHost)
end

function TestHost:testStandaloneHostCanResolveCurrentModuleHostFromLibRegistry()
    local pluginGuid = "test-standalone-registry"
    local definition = lib.prepareDefinition({}, {
        id = "StandaloneRegistryHost",
        name = "Standalone Registry Host",
        storage = {},
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = lib.createModuleHost({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local runtime = lib.standaloneHost(pluginGuid)

    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), host)
end

function TestHost:testHostFlushNotifiesSettingsObserver()
    local calls = 0
    local observedValue = nil
    local definition = lib.prepareDefinition({}, {
        id = "SettingsObserverHost",
        name = "Settings Observer Host",
        storage = {
            { type = "bool", alias = "Value", configKey = "Value", default = false },
        },
        onSettingsCommitted = function(store)
            calls = calls + 1
            observedValue = store.read("Value")
        end,
    })
    local store, session = lib.createStore({
        Value = false,
    }, definition)
    local host = lib.createModuleHost({
        pluginGuid = "test-settings-observer-host",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestHost:testHostAndAuthorSessionResetToDefaultsDelegateToLibHelper()
    local capturedAuthorSession = nil
    local definition = lib.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
            { type = "int", alias = "Count", configKey = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, session = lib.createStore({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    local host = lib.createModuleHost({
        pluginGuid = "test-reset-host",
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, authorSession)
            capturedAuthorSession = authorSession
        end,
    })

    host.drawTab({})

    local changed, count = host.resetToDefaults()
    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 2)

    session.write("EnabledFlag", true)
    session.write("Count", 6)
    local authorChanged, authorCount = capturedAuthorSession.resetToDefaults({
        exclude = { Count = true },
    })
    lu.assertTrue(authorChanged)
    lu.assertEquals(authorCount, 1)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 6)
end

function TestHost:testCreateModuleHostSkipsImmediateCoordinatedSyncWhenFrameworkRebuildIsPending()
    local applyCalls = 0
    local packId = "reload-pack"
    local rebuildReason = nil

    lib.lifecycle.registerCoordinator(packId, { ModEnabled = true })
    lib.lifecycle.registerCoordinatorRebuild(packId, function(reason)
        rebuildReason = reason
        return true
    end)
    local definition = lib.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    local host = lib.createModuleHost({
        pluginGuid = "reload-pack.ReloadHost",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local originalApplyOnLoad = lib.lifecycle.applyOnLoad
    lib.lifecycle.applyOnLoad = function(...)
        applyCalls = applyCalls + 1
        return originalApplyOnLoad(...)
    end

    local owner = {
        _definitionStructuralFingerprint = definition._structuralFingerprint,
    }
    local prepared = lib.prepareDefinition(owner, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", configKey = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadSession = lib.createStore({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local reloadedHost = lib.createModuleHost({
        pluginGuid = "reload-pack.ReloadHost",
        definition = prepared,
        store = reloadStore,
        session = reloadSession,
        drawTab = function() end,
    })

    lib.lifecycle.applyOnLoad = originalApplyOnLoad
    lib.lifecycle.registerCoordinator(packId, nil)
    lib.lifecycle.registerCoordinatorRebuild(packId, nil)
    lu.assertEquals(applyCalls, 0)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(lib.getLiveModuleHost("reload-pack.ReloadHost"), reloadedHost)
end
