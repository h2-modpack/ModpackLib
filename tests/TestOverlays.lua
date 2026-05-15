local lu = require("luaunit")

TestOverlays = {}

function TestOverlays:setUp()
    self.previousScreenData = ScreenData
    self.previousHudScreen = HUDScreen
    self.previousModifyTextBox = ModifyTextBox
    self.previousSetAlpha = SetAlpha
    self.previousCreateComponentFromData = CreateComponentFromData
    self.previousDestroy = Destroy
    self.previousShowingCombatUI = ShowingCombatUI
    self.previousModUtil = modutil
    self.previousRomModUtil = rom.mods["SGG_Modding-ModUtil"]
    self.previousHooks = AdamantModpackLib_Internal.__adamantHooks
    self.overlayState = AdamantModpackLib_OverlayState
    self.rendererState = self.overlayState.renderer
    self.retainedState = self.overlayState.retained
    self.previousRendererTextElements = self.rendererState.textElements
    self.previousRendererStackRows = self.rendererState.stackRows
    self.previousRetainedTableRegistries = self.retainedState.tableRegistries
    self.previousRetainedExplicitRegistries = self.retainedState.explicitRegistries
    self.previousRetainedNextOwnerId = self.retainedState.nextOwnerId
    self.previousRetainedIntervalDriverRegistered = self.retainedState.intervalDriverRegistered
    self.previousUiSuppressors = self.overlayState.uiSuppressors
    self.previousNextUiSuppressorId = self.overlayState.nextUiSuppressorId

    AdamantModpackLib_Internal.__adamantHooks = nil
    self.rendererState.textElements = {}
    self.rendererState.stackRows = {}
    self.retainedState.tableRegistries = setmetatable({}, { __mode = "k" })
    self.retainedState.explicitRegistries = {}
    self.retainedState.nextOwnerId = 0
    self.retainedState.intervalDriverRegistered = true
    self.overlayState.uiSuppressors = {}
    self.overlayState.nextUiSuppressorId = 0
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

function TestOverlays:tearDown()
    ScreenData = self.previousScreenData
    HUDScreen = self.previousHudScreen
    ModifyTextBox = self.previousModifyTextBox
    SetAlpha = self.previousSetAlpha
    CreateComponentFromData = self.previousCreateComponentFromData
    Destroy = self.previousDestroy
    ShowingCombatUI = self.previousShowingCombatUI
    modutil = self.previousModUtil
    rom.mods["SGG_Modding-ModUtil"] = self.previousRomModUtil
    AdamantModpackLib_Internal.__adamantHooks = self.previousHooks
    self.rendererState.textElements = self.previousRendererTextElements
    self.rendererState.stackRows = self.previousRendererStackRows
    self.retainedState.tableRegistries = self.previousRetainedTableRegistries
    self.retainedState.explicitRegistries = self.previousRetainedExplicitRegistries
    self.retainedState.nextOwnerId = self.previousRetainedNextOwnerId
    self.retainedState.intervalDriverRegistered = self.previousRetainedIntervalDriverRegistered
    self.overlayState.uiSuppressors = self.previousUiSuppressors
    self.overlayState.nextUiSuppressorId = self.previousNextUiSuppressorId
end

local function dispatch(owner)
    AdamantModpackLib_Internal.overlays.dispatchCommit(owner, {})
end

function TestOverlays:testRetainedLineUsesHudComponentAndVisibilityHooks()
    local modified = {}
    local alphas = {}
    local wrappedStartRoomPresentation = nil
    local text = "Ready"
    local visible = true

    local testModUtil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    if path == "StartRoomPresentation" then
                        wrappedStartRoomPresentation = handler
                    end
                end,
            },
        },
    }
    modutil = testModUtil
    rom.mods["SGG_Modding-ModUtil"] = testModUtil

    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    lib.overlays.defineOwned("test.overlay.line", function(overlays)
        overlays.createLine("message", {
            componentName = "TestOverlay",
            region = "middleRightStack",
            visible = function()
                return visible
            end,
            minWidth = 80,
            textArgs = {
                Color = { 0.5, 0.5, 0.5, 1 },
            },
        })
        overlays.onCommit(function(ctx)
            ctx.setLine("message", text)
            ctx.refresh("message")
        end)
    end)

    local componentData = ScreenData.HUD.ComponentData.AdamantOverlay_TestOverlay_text
    lu.assertNotNil(wrappedStartRoomPresentation)
    lu.assertEquals(componentData.TextArgs.Text, "")
    lu.assertEquals(componentData.TextArgs.Color, { 0.5, 0.5, 0.5, 1 })
    lu.assertEquals(modified[#modified].Text, "Ready")

    text = "Updated"
    dispatch("test.overlay.line")

    lu.assertEquals(modified[#modified].Text, "Updated")

    visible = false
    dispatch("test.overlay.line")

    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    visible = true
    wrappedStartRoomPresentation(function() end, {}, {})

    lu.assertEquals(alphas[#alphas].Fraction, 1.0)
end

function TestOverlays:testRetainedLinesUseStableMiddleRightOrderingAndBands()
    lib.overlays.defineOwned("test.overlay.order", function(overlays)
        overlays.createLine("module", {
            componentName = "ModuleOverlay",
            region = "middleRightStack",
            minWidth = 80,
        })
        overlays.createLine("framework", {
            componentName = "FrameworkOverlay",
            region = "middleRightStack",
            order = lib.overlays.order.framework + 1,
            minWidth = 80,
        })
        overlays.createLine("debug", {
            componentName = "DebugOverlay",
            region = "middleRightStack",
            order = lib.overlays.order.debug,
            minWidth = 80,
        })
        overlays.onCommit(function(ctx)
            ctx.setLine("module", "Module")
            ctx.setLine("framework", "Framework")
            ctx.setLine("debug", "Debug")
            ctx.refreshRegion("middleRightStack")
        end)
    end)

    lu.assertEquals(ScreenData.HUD.ComponentData.AdamantOverlay_FrameworkOverlay_text.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.AdamantOverlay_ModuleOverlay_text.Y, 240)
    lu.assertEquals(ScreenData.HUD.ComponentData.AdamantOverlay_DebugOverlay_text.Y, 280)
end

function TestOverlays:testRetainedTableUsesStableColumnSpacing()
    lib.overlays.defineOwned("test.overlay.table", function(overlays)
        overlays.createTable("timer", {
            componentName = "TimerTable",
            region = "middleRightStack",
            maxRows = 1,
            columnGap = 6,
            columns = {
                {
                    key = "label",
                    minWidth = 42,
                    justify = "Right",
                    textArgs = {
                        Font = "P22UndergroundSCMedium",
                    },
                },
                {
                    key = "time",
                    minWidth = 96,
                    justify = "Right",
                    textArgs = {
                        Font = "MonospaceTypewriterBold",
                    },
                },
            },
        })
        overlays.onCommit(function(ctx)
            ctx.setTable("timer", {
                { key = "row", label = "IGT:", time = "00:00.00" },
            })
            ctx.refresh("timer")
        end)
    end)

    local label = ScreenData.HUD.ComponentData.AdamantOverlay_TimerTable_1_label
    local time = ScreenData.HUD.ComponentData.AdamantOverlay_TimerTable_1_time
    lu.assertEquals(label.RightOffset, 112)
    lu.assertEquals(time.RightOffset, 10)
    lu.assertEquals(label.Y, 200)
    lu.assertEquals(time.Y, 200)
    lu.assertEquals(label.TextArgs.Font, "P22UndergroundSCMedium")
    lu.assertEquals(time.TextArgs.Font, "MonospaceTypewriterBold")
end

function TestOverlays:testUiSuppressionTokenGloballyHidesAndRestoresRetainedOverlays()
    local alphas = {}
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    lib.overlays.defineOwned("test.overlay.suppression", function(overlays)
        overlays.createLine("line", {
            componentName = "SuppressedOverlay",
            region = "middleRightStack",
            minWidth = 80,
        })
        overlays.onCommit(function(ctx)
            ctx.setLine("line", "Visible")
            ctx.refresh("line")
        end)
    end)

    lu.assertFalse(lib.overlays.isUiSuppressed())

    local firstToken = lib.overlays.suppressForUi()
    lu.assertTrue(lib.overlays.isUiSuppressed())
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    local secondToken = lib.overlays.suppressForUi()
    firstToken.release()
    lu.assertTrue(lib.overlays.isUiSuppressed())
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    secondToken.release()
    lu.assertFalse(lib.overlays.isUiSuppressed())
    lu.assertEquals(alphas[#alphas].Fraction, 1.0)

    secondToken.release()
    lu.assertFalse(lib.overlays.isUiSuppressed())
end
