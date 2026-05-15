local lu = require("luaunit")

TestRetainedOverlays = {}

function TestRetainedOverlays:setUp()
    self.previousScreenData = ScreenData
    self.previousHudScreen = HUDScreen
    self.previousModifyTextBox = ModifyTextBox
    self.previousSetAlpha = SetAlpha
    self.previousCreateComponentFromData = CreateComponentFromData
    self.previousDestroy = Destroy
    self.previousShowingCombatUI = ShowingCombatUI
    self.previousRetained = AdamantModpackLib_Internal.overlays.retained
    self.previousHudText = AdamantModpackLib_Internal.overlays.hudText
    self.previousStackedText = AdamantModpackLib_Internal.overlays.stackedText
    self.previousModUtil = modutil
    self.previousRomModUtil = rom.mods["SGG_Modding-ModUtil"]
    self.previousHooks = AdamantModpackLib_Internal.__adamantHooks

    AdamantModpackLib_Internal.__adamantHooks = nil
    AdamantModpackLib_Internal.overlays.hudText = {}
    AdamantModpackLib_Internal.overlays.stackedText = {}
    AdamantModpackLib_Internal.overlays.retained = {
        tableRegistries = setmetatable({}, { __mode = "k" }),
        explicitRegistries = {},
        nextOwnerId = 0,
        intervalDriverRegistered = true,
    }

    ShowingCombatUI = true
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    local nextId = 100
    CreateComponentFromData = function(_, data)
        nextId = nextId + 1
        return {
            Id = nextId,
            Name = data.Name,
        }
    end
    ModifyTextBox = function() end
    SetAlpha = function() end
    Destroy = function() end
end

function TestRetainedOverlays:tearDown()
    ScreenData = self.previousScreenData
    HUDScreen = self.previousHudScreen
    ModifyTextBox = self.previousModifyTextBox
    SetAlpha = self.previousSetAlpha
    CreateComponentFromData = self.previousCreateComponentFromData
    Destroy = self.previousDestroy
    ShowingCombatUI = self.previousShowingCombatUI
    AdamantModpackLib_Internal.overlays.retained = self.previousRetained
    AdamantModpackLib_Internal.overlays.hudText = self.previousHudText
    AdamantModpackLib_Internal.overlays.stackedText = self.previousStackedText
    AdamantModpackLib_Internal.__adamantHooks = self.previousHooks
    modutil = self.previousModUtil
    rom.mods["SGG_Modding-ModUtil"] = self.previousRomModUtil
end

local function createHostWithOverlays(owner, registerOverlays, opts)
    opts = opts or {}
    local definition = lib.prepareDefinition({}, {
        id = opts.id or "RetainedOverlayHost",
        name = opts.name or "Retained Overlay Host",
        storage = opts.storage or {},
    })
    local store, session = lib.createStore(opts.config or {
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = lib.createModuleHost({
        owner = owner,
        pluginGuid = opts.pluginGuid or "test-retained-overlay-host",
        definition = definition,
        store = store,
        session = session,
        registerOverlays = registerOverlays,
        onSettingsCommitted = opts.onSettingsCommitted,
        registerIntegrations = opts.registerIntegrations,
        drawTab = function() end,
    })
    return host, authorHost, store, session
end

function TestRetainedOverlays:testDefineOwnedLineProjectsThroughCommitContext()
    local modified = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end

    lib.overlays.defineOwned("test.retained.line", function(overlays)
        overlays.createLine("summary.igt", {
            region = "middleRightStack",
            columns = {
                { key = "label", minWidth = 40 },
                { key = "time", minWidth = 80 },
            },
        })
        overlays.onCommit(function(ctx)
            ctx.setLine("summary.igt", { label = "IGT:", time = "01:23.45" })
            ctx.refresh("summary.igt")
        end)
    end)

    AdamantModpackLib_Internal.overlays.dispatchCommit("test.retained.line", {})

    lu.assertEquals(modified[#modified - 1].Text, "IGT:")
    lu.assertEquals(modified[#modified].Text, "01:23.45")
end

function TestRetainedOverlays:testDefineOwnedRemovesOmittedDeclarations()
    local destroyed = {}
    Destroy = function(args)
        destroyed[#destroyed + 1] = args.Id
    end

    lib.overlays.defineOwned("test.retained.omit", function(overlays)
        overlays.createLine("transient", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end)
    lu.assertNotNil(next(AdamantModpackLib_Internal.overlays.hudText))

    lib.overlays.defineOwned("test.retained.omit", function() end)

    lu.assertNil(next(AdamantModpackLib_Internal.overlays.stackedText))
    lu.assertNil(next(AdamantModpackLib_Internal.overlays.hudText))
    lu.assertTrue(#destroyed > 0)
end

function TestRetainedOverlays:testRetainedTableCapsRowsAndHidesUnusedRows()
    local modified = {}
    local alphas = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    lib.overlays.defineOwned("test.retained.table", function(overlays)
        overlays.createTable("runs", {
            region = "middleRightStack",
            maxRows = 2,
            columns = {
                { key = "label", minWidth = 40 },
                { key = "time", minWidth = 80 },
            },
        })
        overlays.onCommit(function(ctx)
            ctx.setTable("runs", {
                { key = "one", label = "Run 1", time = "00:01.00" },
                { key = "two", label = "Run 2", time = "00:02.00" },
                { key = "three", label = "Run 3", time = "00:03.00" },
            })
            ctx.refresh("runs")
        end)
    end)

    AdamantModpackLib_Internal.overlays.dispatchCommit("test.retained.table", {})

    local text = {}
    for _, call in ipairs(modified) do
        text[call.Text] = true
    end
    lu.assertTrue(text["Run 1"])
    lu.assertTrue(text["00:01.00"])
    lu.assertTrue(text["Run 2"])
    lu.assertTrue(text["00:02.00"])
    lu.assertNil(text["Run 3"])
    lu.assertNil(text["00:03.00"])
    lu.assertTrue(#alphas > 0)
end

function TestRetainedOverlays:testHostCommitDispatchesOverlaysAfterSettingsObserver()
    local owner = {}
    local order = {}
    local host, authorHost, _, session = createHostWithOverlays(owner, function(overlays)
        overlays.onCommit(function()
            order[#order + 1] = "overlay"
        end)
    end, {
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        config = {
            Enabled = true,
            DebugMode = false,
            Flag = false,
        },
        onSettingsCommitted = function()
            order[#order + 1] = "settings"
        end,
    })
    authorHost.activate()

    session.write("Flag", true)
    local ok, err = host.flush()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(order, { "settings", "overlay" })
end

function TestRetainedOverlays:testRetainedIntervalDispatchesWhenDue()
    local calls = 0
    lib.overlays.defineOwned("test.retained.interval", function(overlays)
        overlays.onInterval("tick", 1.0, function()
            calls = calls + 1
        end)
    end)

    AdamantModpackLib_Internal.overlays.dispatchIntervals(0)
    AdamantModpackLib_Internal.overlays.dispatchIntervals(0.5)
    AdamantModpackLib_Internal.overlays.dispatchIntervals(1.1)

    lu.assertEquals(calls, 2)
end

function TestRetainedOverlays:testAfterHookObservesResultsWithoutChangingReturn()
    local wrapped = nil
    local observed = nil
    modutil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    lu.assertEquals(path, "StartNewRun")
                    wrapped = handler
                end,
            },
        },
    }
    rom.mods["SGG_Modding-ModUtil"] = modutil

    local owner = {}
    local _, authorHost = createHostWithOverlays(owner, function(overlays)
        overlays.afterHook("StartNewRun", function(_, event)
            observed = {
                arg = event.args[1],
                result = event.result,
            }
        end)
    end)
    authorHost.activate()

    local result = wrapped(function(value)
        return value .. ":base"
    end, "run")

    lu.assertEquals(result, "run:base")
    lu.assertEquals(observed, {
        arg = "run",
        result = "run:base",
    })
end

function TestRetainedOverlays:testActivationFailureRollsBackOverlayDeclarations()
    local owner = {}
    local pluginGuid = "test-retained-rollback"
    local firstHost, firstAuthorHost = createHostWithOverlays(owner, function(overlays)
        overlays.createLine("stable", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        pluginGuid = pluginGuid,
        id = "RetainedRollback",
    })
    firstAuthorHost.activate()

    local _, secondAuthorHost = createHostWithOverlays(owner, function(overlays)
        overlays.createLine("replacement", {
            region = "middleRightStack",
            columns = {
                { key = "text", minWidth = 40 },
            },
        })
    end, {
        pluginGuid = pluginGuid,
        id = "RetainedRollback",
        registerIntegrations = function()
            error("rollback after overlays")
        end,
    })

    lu.assertErrorMsgContains("rollback after overlays", function()
        secondAuthorHost.activate()
    end)

    local retained = AdamantModpackLib_Internal.overlays.retained.tableRegistries[owner]
    lu.assertNotNil(retained.elements.stable)
    lu.assertNil(retained.elements.replacement)
    lu.assertEquals(lib.getLiveModuleHost(pluginGuid), firstHost)
end
