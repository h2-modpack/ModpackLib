local lu = require("luaunit")

TestHooks = {}

local savedModutil
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

    return counts
end

local function restorePathMock()
    for path, value in pairs(savedGlobals or {}) do
        _G[path] = value
    end
    savedGlobals = nil
    modutil = savedModutil
    savedModutil = nil
end

local function createHostWithHooks(owner, registerHooks)
    return lib.createModuleHost({
        definition = { id = "HookTest", name = "Hook Test", storage = {} },
        store = {
            read = function()
                return false
            end,
        },
        session = {
            view = {},
            read = function() end,
            write = function() end,
            reset = function() end,
            isDirty = function()
                return false
            end,
            _flushToConfig = function() end,
            _reloadFromConfig = function() end,
            auditMismatches = function()
                return {}
            end,
        },
        hookOwner = owner,
        registerHooks = registerHooks,
    })
end

function TestHooks:testRefreshIsNotPublicModuleApi()
    lu.assertNil(lib.hooks.Refresh)
end

function TestHooks:testWrapRegistersOnceAndUpdatesHandler()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestWrap = function(value)
        return "base:" .. value
    end

    lib.hooks.Wrap(owner, "AdamantHookTestWrap", function(base, value)
        return "first:" .. base(value)
    end)
    lib.hooks.Wrap(owner, "AdamantHookTestWrap", function(base, value)
        return "second:" .. base(value)
    end)

    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(_G.AdamantHookTestWrap("x"), "second:base:x")
    restorePathMock()
end

function TestHooks:testWrapRefreshOmissionFallsBackToBase()
    installPathMock()
    local owner = {}
    _G.AdamantHookTestWrapRefresh = function(value)
        return "base:" .. value
    end

    createHostWithHooks(owner, function()
        lib.hooks.Wrap(owner, "AdamantHookTestWrapRefresh", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestWrapRefresh("x"), "wrapped:base:x")

    createHostWithHooks(owner, function() end)

    lu.assertEquals(_G.AdamantHookTestWrapRefresh("x"), "base:x")
    restorePathMock()
end

function TestHooks:testOverrideFunctionRegistersOnceAndUpdatesReplacement()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestOverride = function()
        return "base"
    end

    lib.hooks.Override(owner, "AdamantHookTestOverride", function()
        return "first"
    end)
    lib.hooks.Override(owner, "AdamantHookTestOverride", function()
        return "second"
    end)

    lu.assertEquals(counts.override, 1)
    lu.assertEquals(_G.AdamantHookTestOverride(), "second")
    restorePathMock()
end

function TestHooks:testOverrideRefreshOmissionRestoresOriginal()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestOverrideRefresh = function()
        return "base"
    end

    createHostWithHooks(owner, function()
        lib.hooks.Override(owner, "AdamantHookTestOverrideRefresh", function()
            return "override"
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestOverrideRefresh(), "override")

    createHostWithHooks(owner, function() end)

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

    lib.hooks.Context.Wrap(owner, "AdamantHookTestContext", function()
        table.insert(observed, "first")
    end)
    lib.hooks.Context.Wrap(owner, "AdamantHookTestContext", function()
        table.insert(observed, "second")
    end)

    _G.AdamantHookTestContext()

    lu.assertEquals(counts.contextWrap, 1)
    lu.assertEquals(observed, { "second", "base" })
    restorePathMock()
end

function TestHooks:testContextWrapRefreshOmissionBecomesInert()
    installPathMock()
    local owner = {}
    local observed = {}

    _G.AdamantHookTestContextRefresh = function()
        table.insert(observed, "base")
    end

    createHostWithHooks(owner, function()
        lib.hooks.Context.Wrap(owner, "AdamantHookTestContextRefresh", function()
            table.insert(observed, "context")
        end)
    end)

    createHostWithHooks(owner, function() end)
    _G.AdamantHookTestContextRefresh()

    lu.assertEquals(observed, { "base" })
    restorePathMock()
end

function TestHooks:testCreateModuleHostIncrementsPackRegistryVersion()
    local packId = "hook-pack"
    local before = lib.getModuleRegistryVersion(packId)

    createHostWithHooks({}, function() end)

    lu.assertEquals(lib.getModuleRegistryVersion(packId), before)

    lib.createModuleHost({
        definition = { modpack = packId, id = "Alpha", name = "Alpha", storage = {} },
        store = {
            read = function()
                return false
            end,
        },
        session = {
            view = {},
            read = function() end,
            write = function() end,
            reset = function() end,
            isDirty = function()
                return false
            end,
            _flushToConfig = function() end,
            _reloadFromConfig = function() end,
            auditMismatches = function()
                return {}
            end,
        },
    })

    lu.assertEquals(lib.getModuleRegistryVersion(packId), before + 1)
end
