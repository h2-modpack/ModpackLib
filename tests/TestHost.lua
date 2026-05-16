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

local function createActivatedHost(pluginGuid, opts, activationOpts)
    activationOpts = activationOpts or {}
    opts.pluginGuid = pluginGuid
    opts.owner = activationOpts.owner
    opts.registerHooks = activationOpts.registerHooks
    opts.registerIntegrations = activationOpts.registerIntegrations
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create(opts)
    authorHost.tryActivate()
    return host, authorHost
end

function TestHost:testStandaloneHostWarnsWhenSessionCommitFails()
    local drawCalls = 0
    local pluginGuid = "test-standalone-commit"
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = "standalone-pack",
        id = "StandaloneTest",
        name = "Standalone Test",
        storage = {},
    })
    local store, session = CreateModuleState({
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

    createActivatedHost(pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    local moduleHost = lib.getLiveModuleHost(pluginGuid)
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
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "StandaloneRegistryHost",
        name = "Standalone Registry Host",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local _, authorHost = createActivatedHost(pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })
    local host = lib.getLiveModuleHost(pluginGuid)

    local runtime = lib.standaloneHost(pluginGuid)

    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(authorHost.isEnabled), "function")
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), host)
end

function TestHost:testHostFlushNotifiesSettingsObserver()
    local calls = 0
    local observedValue = nil
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "SettingsObserverHost",
        name = "Settings Observer Host",
        storage = {
            { type = "bool", alias = "Value", default = false },
        },
    })
    local store, session = CreateModuleState({
        Value = false,
    }, definition)
    createActivatedHost("test-settings-observer-host", {
        definition = definition,
        store = store,
        session = session,
        onSettingsCommitted = function(_, activeStore)
            calls = calls + 1
            observedValue = activeStore.read("Value")
        end,
        drawTab = function() end,
    })
    local host = lib.getLiveModuleHost("test-settings-observer-host")

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestHost:testPatchMutationReceivesAuthorHost()
    local target = { Value = false }
    local patchHost = nil
    local patchStore = nil
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "PatchHostModule",
        name = "Patch Host Module",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = createActivatedHost("test-patch-host", {
        definition = definition,
        store = store,
        session = session,
        registerPatchMutation = function(plan, activeHost, activeStore)
            patchHost = activeHost
            patchStore = activeStore
            plan:set(target, "Value", true)
        end,
        drawTab = function() end,
    })
    local ok, err = host.applyMutation()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(patchHost, authorHost)
    lu.assertEquals(patchStore, store)
    lu.assertTrue(target.Value)
end

function TestHost:testSideEffectingHostMethodsRequireActivation()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "InactiveHost",
        name = "Inactive Host",
        storage = {},
    })
    local store, session = CreateModuleState({}, definition)
    local host = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "test-inactive-host",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)
end

function TestHost:testHostAndAuthorSessionResetToDefaultsDelegateToLibHelper()
    local capturedAuthorSession = nil
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, session = CreateModuleState({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedHost("test-reset-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, authorSession)
            capturedAuthorSession = authorSession
        end,
    })
    local host = lib.getLiveModuleHost("test-reset-host")

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

function TestHost:testCreateModuleHostPassesAuthorHostToCallbacks()
    local callbackHost = nil
    local drawHost = nil
    local quickHost = nil
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = "author-pack",
        id = "AuthorHostModule",
        name = "Author Host Module",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    local _, returnedHost = createActivatedHost("test-author-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, _, authorHost)
            drawHost = authorHost
        end,
        drawQuickContent = function(_, _, authorHost)
            quickHost = authorHost
        end,
    }, {
        registerIntegrations = function(authorHost)
            callbackHost = authorHost
        end,
    })

    local host = lib.getLiveModuleHost("test-author-host")
    host.drawTab({})
    host.drawQuickContent({})

    lu.assertEquals(returnedHost, callbackHost)
    lu.assertEquals(callbackHost, drawHost)
    lu.assertEquals(callbackHost, quickHost)
    lu.assertEquals(callbackHost.getIdentity().id, "AuthorHostModule")
    lu.assertEquals(callbackHost.getMeta().name, "Author Host Module")
    lu.assertTrue(callbackHost.isEnabled())
    lu.assertEquals(type(callbackHost.log), "function")
    lu.assertEquals(type(callbackHost.logIf), "function")
    lu.assertEquals(type(callbackHost.tryActivate), "function")
    lu.assertNil(callbackHost.read)
    lu.assertNil(callbackHost.setEnabled)

    local warningCount = #Warnings
    callbackHost.log("plain %s", "message")
    callbackHost.logIf("debug %d", 7)
    lu.assertEquals(Warnings[warningCount + 1], "[AuthorHostModule] plain message")
    lu.assertEquals(Warnings[warningCount + 2], "[AuthorHostModule] debug 7")
    lu.assertEquals(#Warnings, warningCount + 2)
end

function TestHost:testFullHostOwnsAuthorHostCapabilities()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "FullHostCapabilities",
        name = "Full Host Capabilities",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "test-full-host-capabilities",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getIdentity), "function")
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.log), "function")
    lu.assertEquals(type(host.logIf), "function")
    lu.assertEquals(type(host.tryActivate), "function")
    lu.assertEquals(authorHost.tryActivate, host.tryActivate)
end

function TestHost:testCreateModuleHostSkipsImmediateCoordinatedSyncWhenFrameworkRebuildIsPending()
    local packId = "reload-pack"
    local rebuildReason = nil

    lib.coordinator.register(packId, { ModEnabled = true })
    lib.coordinator.registerRebuild(packId, function(reason)
        rebuildReason = reason
        return true
    end)
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    createActivatedHost("reload-pack.ReloadHost", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local applyCalls = 0

    local owner = {
        _definitionStructuralFingerprint = definition._structuralFingerprint,
    }
    local prepared = AdamantModpackLib_Internal.moduleHost.prepareDefinition(owner, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createActivatedHost("reload-pack.ReloadHost", {
        definition = prepared,
        store = reloadStore,
        session = reloadSession,
        registerPatchMutation = function(plan)
            applyCalls = applyCalls + 1
            plan:set({}, "unused", true)
        end,
        drawTab = function() end,
    })
    local reloadedHost = lib.getLiveModuleHost("reload-pack.ReloadHost")

    lib.coordinator.register(packId, nil)
    lib.coordinator.registerRebuild(packId, nil)
    lu.assertEquals(applyCalls, 0)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(lib.getLiveModuleHost("reload-pack.ReloadHost"), reloadedHost)
end

function TestHost:testActivationFailureRestoresLiveHostAndIntegrations()
    local pluginGuid = "test-activation-rollback"
    local integrationId = "test.activation.rollback"
    local providerId = "RollbackProvider"
    local previousApi = { value = "previous" }

    local firstDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local firstStore, firstSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        drawTab = function() end,
    })
    lib.integrations.register(integrationId, providerId, previousApi)

    local secondDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local secondStore, secondSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        registerIntegrations = function()
            lib.integrations.register(integrationId, providerId, { value = "replacement" })
            error("integration boom")
        end,
        drawTab = function() end,
    })

    local ok, err = secondAuthorHost.tryActivate()
    local api = lib.integrations.get(integrationId)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "integration boom")
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), firstHost)
    lu.assertEquals(api, previousApi)
    lu.assertErrorMsgContains("host.not_activated", function()
        secondHost.flush()
    end)

    lib.integrations.unregisterProvider(providerId)
end

function TestHost:testRuntimeSyncFailureRestoresPreviousPatchMutation()
    local packId = "activation-runtime-rollback-pack"
    local pluginGuid = "test-activation-runtime-rollback"
    local target = { Value = "base" }
    local previousCoordinator = AdamantModpackLib_Internal.coordinators[packId]
    local previousLiveHost = lib.getLiveModuleHost(pluginGuid)

    lib.coordinator.register(packId, { ModEnabled = true })

    local firstDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local firstStore, firstSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        registerPatchMutation = function(plan)
            plan:set(target, "Value", "first")
        end,
        drawTab = function() end,
    })

    local secondDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local secondStore, secondSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        registerPatchMutation = function()
            error("replacement boom")
        end,
        drawTab = function() end,
    })

    local ok, err = secondAuthorHost.tryActivate()
    local liveHost = lib.getLiveModuleHost(pluginGuid)
    local targetValue = target.Value

    lib.coordinator.register(packId, previousCoordinator)
    AdamantModpackLib_Internal.liveModuleHosts[pluginGuid] = previousLiveHost

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(liveHost, secondHost)
    lu.assertNotEquals(liveHost, firstHost)
    lu.assertEquals(targetValue, "first")
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "host.coordinated_runtime_sync_failed")
    lu.assertStrContains(Warnings[1], "replacement boom")
end

function TestHost:testTryActivateModuleReturnsErrorAndDoesNotPublishBrokenHost()
    local pluginGuid = "test-try-activate-failure"
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "TryActivateFailure",
        name = "Try Activate Failure",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        registerIntegrations = function()
            error("try activate boom")
        end,
        drawTab = function() end,
    })

    local ok, err = authorHost.tryActivate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "try activate boom")
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "host.activate_failed")
    lu.assertStrContains(Warnings[1], "try activate boom")
    lu.assertNil(lib.getLiveModuleHost(pluginGuid))
    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)
end

function TestHost:testTryActivateModuleSucceedsThroughFullHost()
    local pluginGuid = "test-try-activate-success"
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "TryActivateSuccess",
        name = "Try Activate Success",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local ok, err = host.tryActivate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), host)
end

function TestHost:testActivationRefreshRemovesOmittedIntegrations()
    local pluginGuid = "test-activation-integration-refresh"
    local integrationId = "test.activation.refresh"
    local providerId = "ActivationRefresh"

    local firstDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = providerId,
        name = "Activation Refresh",
        storage = {},
    })
    local firstStore, firstSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    createActivatedHost(pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        drawTab = function() end,
    }, {
        registerIntegrations = function()
            lib.integrations.register(integrationId, providerId, { value = "first" })
        end,
    })

    lu.assertNotNil(lib.integrations.get(integrationId))

    local secondDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = providerId,
        name = "Activation Refresh",
        storage = {},
    })
    local secondStore, secondSession = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    createActivatedHost(pluginGuid, {
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        drawTab = function() end,
    })

    lu.assertNil(lib.integrations.get(integrationId))
    lib.integrations.unregisterProvider(providerId)
end

function TestHost:testActivationRejectsReentrantActivateCalls()
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ReentrantActivate",
        name = "Reentrant Activate",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost
    host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        store = store,
        session = session,
        registerIntegrations = function()
            authorHost.tryActivate()
        end,
        drawTab = function() end,
    })

    local ok, err = authorHost.tryActivate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(lib.getLiveModuleHost("test-reentrant-activate"), host)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "host.activation_in_progress")
end
