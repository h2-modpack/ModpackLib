local lu = require("luaunit")

TestHooks = {}

local savedModutil
local savedRomModutil
local savedGlobals

local function installPathMock()
    local counts = {
        wrap = 0,
        override = 0,
        restore = 0,
        contextWrap = 0,
    }
    local originals = {}

    savedModutil = modutil
    savedGlobals = {}

    local function saveGlobal(path)
        if savedGlobals[path] == nil then
            savedGlobals[path] = _G[path]
        end
    end

    modutil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    counts.wrap = counts.wrap + 1
                    saveGlobal(path)
                    local base = _G[path]
                    _G[path] = function(...)
                        return handler(base, ...)
                    end
                end,

                Override = function(path, value)
                    counts.override = counts.override + 1
                    saveGlobal(path)
                    if originals[path] == nil then
                        originals[path] = _G[path]
                    end
                    _G[path] = value
                end,

                Restore = function(path)
                    counts.restore = counts.restore + 1
                    if originals[path] == nil then
                        error("object has no overrides")
                    end
                    _G[path] = originals[path]
                    originals[path] = nil
                end,

                Context = {
                    Wrap = function(path, context)
                        counts.contextWrap = counts.contextWrap + 1
                        saveGlobal(path)
                        local base = _G[path]
                        _G[path] = function(...)
                            context(...)
                            return base(...)
                        end
                    end,
                },
            },
        },
    }
    if rom and rom.mods then
        savedRomModutil = rom.mods["SGG_Modding-ModUtil"]
        rom.mods["SGG_Modding-ModUtil"] = modutil
    end

    return counts
end

local function restorePathMock()
    for path, value in pairs(savedGlobals or {}) do
        _G[path] = value
    end
    savedGlobals = nil
    modutil = savedModutil
    savedModutil = nil
    if rom and rom.mods then
        rom.mods["SGG_Modding-ModUtil"] = savedRomModutil
    end
    savedRomModutil = nil
end

local function createHostWithHooks(pluginGuid, registerHooks, activationOpts)
    activationOpts = activationOpts or {}
    local store = {
        read = function()
            return false
        end,
    }
    local session = {
        view = {},
        read = function() end,
        write = function() end,
        reset = function() end,
        getAliasSchema = function() end,
        isDirty = function()
            return false
        end,
        _flushToConfig = function() end,
        _reloadFromConfig = function() end,
        auditMismatches = function()
            return {}
        end,
    }
    local host = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        store = store,
        session = session,
        registerHooks = registerHooks,
        registerIntegrations = activationOpts.registerIntegrations,
        drawTab = function() end,
    })
    return AdamantModpackLib_Internal.moduleHost.activate(host)
end

function TestHooks:testWrapRegistersOnceAndUpdatesHandler()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestWrap = function(value)
        return "base:" .. value
    end

    lib.hooks.WrapOwned(owner, "AdamantHookTestWrap", function(base, value)
        return "first:" .. base(value)
    end)
    lib.hooks.WrapOwned(owner, "AdamantHookTestWrap", function(base, value)
        return "second:" .. base(value)
    end)

    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(_G.AdamantHookTestWrap("x"), "second:base:x")
    restorePathMock()
end

function TestHooks:testWrapResolvesModUtilFromRomModsWhenGlobalIsMissing()
    local counts = installPathMock()
    local owner = {}
    modutil = nil
    _G.AdamantHookTestWrapRomMods = function(value)
        return "base:" .. value
    end

    lib.hooks.WrapOwned(owner, "AdamantHookTestWrapRomMods", function(base, value)
        return "wrapped:" .. base(value)
    end)

    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(_G.AdamantHookTestWrapRomMods("x"), "wrapped:base:x")
    restorePathMock()
end

function TestHooks:testWrapRefreshOmissionFallsBackToBase()
    installPathMock()
    local pluginGuid = "hook-test-wrap-refresh"
    _G.AdamantHookTestWrapRefresh = function(value)
        return "base:" .. value
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Wrap("AdamantHookTestWrapRefresh", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestWrapRefresh("x"), "wrapped:base:x")

    createHostWithHooks(pluginGuid, function() end)

    lu.assertEquals(_G.AdamantHookTestWrapRefresh("x"), "base:x")
    restorePathMock()
end

function TestHooks:testMissingRegisterHooksRefreshRemovesPreviousHooks()
    installPathMock()
    local pluginGuid = "hook-test-missing-register-hooks"
    _G.AdamantHookTestMissingRegisterHooks = function(value)
        return "base:" .. value
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Wrap("AdamantHookTestMissingRegisterHooks", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestMissingRegisterHooks("x"), "wrapped:base:x")

    createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(_G.AdamantHookTestMissingRegisterHooks("x"), "base:x")
    restorePathMock()
end

function TestHooks:testRegisterHooksCanUseOwnerlessHookApi()
    installPathMock()
    local pluginGuid = "hook-test-ownerless-wrap"
    _G.AdamantHookTestOwnerlessWrap = function(value)
        return "base:" .. value
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Wrap("AdamantHookTestOwnerlessWrap", function(base, value)
            return "scoped:" .. base(value)
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestOwnerlessWrap("x"), "scoped:base:x")
    restorePathMock()
end

function TestHooks:testOwnerlessHookApiRequiresActiveRegistrationContext()
    local ok = pcall(function()
        lib.hooks.Wrap("AdamantHookTestNoContext", function(base)
            return base()
        end)
    end)

    lu.assertFalse(ok)
end

function TestHooks:testOverrideFunctionRegistersOnceAndUpdatesReplacement()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestOverride = function()
        return "base"
    end

    lib.hooks.OverrideOwned(owner, "AdamantHookTestOverride", function()
        return "first"
    end)
    lib.hooks.OverrideOwned(owner, "AdamantHookTestOverride", function()
        return "second"
    end)

    lu.assertEquals(counts.override, 1)
    lu.assertEquals(_G.AdamantHookTestOverride(), "second")
    restorePathMock()
end

function TestHooks:testOverrideRefreshOmissionRestoresOriginal()
    local counts = installPathMock()
    local pluginGuid = "hook-test-override-refresh"
    _G.AdamantHookTestOverrideRefresh = function()
        return "base"
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Override("AdamantHookTestOverrideRefresh", function()
            return "override"
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestOverrideRefresh(), "override")

    createHostWithHooks(pluginGuid, function() end)

    lu.assertEquals(counts.restore, 1)
    lu.assertEquals(_G.AdamantHookTestOverrideRefresh(), "base")
    restorePathMock()
end

function TestHooks:testContextWrapRegistersOnceAndUpdatesContext()
    local counts = installPathMock()
    local owner = {}
    local observed = {}

    _G.AdamantHookTestContext = function()
        table.insert(observed, "base")
    end

    lib.hooks.Context.WrapOwned(owner, "AdamantHookTestContext", function()
        table.insert(observed, "first")
    end)
    lib.hooks.Context.WrapOwned(owner, "AdamantHookTestContext", function()
        table.insert(observed, "second")
    end)

    _G.AdamantHookTestContext()

    lu.assertEquals(counts.contextWrap, 1)
    lu.assertEquals(observed, { "second", "base" })
    restorePathMock()
end

function TestHooks:testContextWrapRefreshOmissionBecomesInert()
    installPathMock()
    local pluginGuid = "hook-test-context-refresh"
    local observed = {}

    _G.AdamantHookTestContextRefresh = function()
        table.insert(observed, "base")
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Context.Wrap("AdamantHookTestContextRefresh", function()
            table.insert(observed, "context")
        end)
    end)

    createHostWithHooks(pluginGuid, function() end)
    _G.AdamantHookTestContextRefresh()

    lu.assertEquals(observed, { "base" })
    restorePathMock()
end

function TestHooks:testRefreshFailureKeepsPreviousLiveHookState()
    local counts = installPathMock()
    local pluginGuid = "hook-test-refresh-failure"
    local observed = {}

    _G.AdamantHookTestFailureWrap = function(value)
        return "base:" .. value
    end
    _G.AdamantHookTestFailureOverride = function()
        return "base-override"
    end
    _G.AdamantHookTestFailureContext = function()
        table.insert(observed, "base")
    end
    _G.AdamantHookTestFailureNew = function(value)
        return "new-base:" .. value
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Wrap("AdamantHookTestFailureWrap", function(base, value)
            return "first:" .. base(value)
        end)
        lib.hooks.Override("AdamantHookTestFailureOverride", function()
            return "first-override"
        end)
        lib.hooks.Context.Wrap("AdamantHookTestFailureContext", function()
            table.insert(observed, "first-context")
        end)
    end)

    local ok = pcall(function()
        createHostWithHooks(pluginGuid, function()
            lib.hooks.Wrap("AdamantHookTestFailureWrap", function(base, value)
                return "second:" .. base(value)
            end)
            lib.hooks.Override("AdamantHookTestFailureOverride", function()
                return "second-override"
            end)
            lib.hooks.Context.Wrap("AdamantHookTestFailureContext", function()
                table.insert(observed, "second-context")
            end)
            lib.hooks.Wrap("AdamantHookTestFailureNew", function(base, value)
                return "new:" .. base(value)
            end)
            error("boom")
        end)
    end)

    observed = {}
    _G.AdamantHookTestFailureContext()

    lu.assertFalse(ok)
    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(counts.override, 1)
    lu.assertEquals(counts.contextWrap, 1)
    lu.assertEquals(_G.AdamantHookTestFailureWrap("x"), "first:base:x")
    lu.assertEquals(_G.AdamantHookTestFailureOverride(), "first-override")
    lu.assertEquals(observed, { "first-context", "base" })
    lu.assertEquals(_G.AdamantHookTestFailureNew("x"), "new-base:x")
    lu.assertFalse(pcall(function()
        lib.hooks.Wrap("AdamantHookTestFailureNew", function(base, value)
            return "leaked:" .. base(value)
        end)
    end))
    restorePathMock()
end

function TestHooks:testActivationFailureAfterHookRefreshRestoresPreviousLiveHookState()
    installPathMock()
    local pluginGuid = "hook-test-activation-rollback"
    _G.AdamantHookTestActivationRollback = function(value)
        return "base:" .. value
    end

    createHostWithHooks(pluginGuid, function()
        lib.hooks.Wrap("AdamantHookTestActivationRollback", function(base, value)
            return "first:" .. base(value)
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestActivationRollback("x"), "first:base:x")

    local ok = pcall(function()
        createHostWithHooks(pluginGuid, function()
            lib.hooks.Wrap("AdamantHookTestActivationRollback", function(base, value)
                return "second:" .. base(value)
            end)
        end, {
            registerIntegrations = function()
                error("late activation boom")
            end,
        })
    end)

    lu.assertFalse(ok)
    lu.assertEquals(_G.AdamantHookTestActivationRollback("x"), "first:base:x")
    restorePathMock()
end

function TestHooks:testCreateModuleHostSyncsCoordinatedRuntimeImmediately()
    local packId = "hook-pack"
    local buildCalls = 0
    local target = { Value = "base" }
    lib.coordinator.register(packId, { ModEnabled = true })

    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
        })
    local store = {
        read = function(key)
            if key == "Enabled" then
                return true
            end
            return false
        end,
    }
    local session = {
        view = {},
        read = function() end,
        write = function() end,
        reset = function() end,
        getAliasSchema = function() end,
        isDirty = function()
            return false
        end,
        _flushToConfig = function() end,
        _reloadFromConfig = function() end,
        auditMismatches = function()
            return {}
        end,
    }
    local host = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "hook-pack.Alpha",
        definition = definition,
        registerPatchMutation = function(plan)
            buildCalls = buildCalls + 1
            plan:set(target, "Value", "patched")
        end,
        store = store,
        session = session,
        drawTab = function() end,
    })
    AdamantModpackLib_Internal.moduleHost.activate(host)

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
    lib.coordinator.register(packId, nil)
end

function TestHooks:testCreateModuleHostHotReloadReplacesCoordinatedRuntimeState()
    local packId = "hook-reload-pack"
    local firstBuildCalls = 0
    local secondBuildCalls = 0
    local target = { Value = "base" }
    lib.coordinator.register(packId, { ModEnabled = true })

    local function createSession()
        return {
            view = {},
            read = function() end,
            write = function() end,
            reset = function() end,
            getAliasSchema = function() end,
            isDirty = function()
                return false
            end,
            _flushToConfig = function() end,
            _reloadFromConfig = function() end,
            auditMismatches = function()
                return {}
            end,
        }
    end

    local store = {
        read = function(key)
            if key == "Enabled" then
                return true
            end
            return false
        end,
    }

    local firstDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
        })
    local firstSession = createSession()
    local firstHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = firstDefinition,
        registerPatchMutation = function(plan)
            firstBuildCalls = firstBuildCalls + 1
            plan:set(target, "Value", "first")
        end,
        store = store,
        session = firstSession,
        drawTab = function() end,
    })
    AdamantModpackLib_Internal.moduleHost.activate(firstHost)

    local secondDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
        })
    local secondSession = createSession()
    local secondHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = secondDefinition,
        registerPatchMutation = function(plan)
            secondBuildCalls = secondBuildCalls + 1
            plan:set(target, "Value", "second")
        end,
        store = store,
        session = secondSession,
        drawTab = function() end,
    })
    AdamantModpackLib_Internal.moduleHost.activate(secondHost)

    lu.assertEquals(firstBuildCalls, 1)
    lu.assertEquals(secondBuildCalls, 1)
    lu.assertEquals(target.Value, "second")

    lib.coordinator.register(packId, nil)
    AdamantModpackLib_Internal.mutation.revertForPlugin("hook-reload-pack.Alpha", {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    }, {
        affectsRunData = true,
        patchMutation = function(plan)
            plan:set(target, "Value", "second")
        end,
    }, nil, store)
    lu.assertEquals(target.Value, "base")
end
