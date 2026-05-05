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
    self.overlayState = AdamantModpackLib_Internal.overlays
    self.previousOverlayHudText = self.overlayState.hudText
    self.previousOverlayStackedText = self.overlayState.stackedText
    self.previousOverlaySuppressedOwners = self.overlayState.suppressedOwners

    AdamantModpackLib_Internal.__adamantHooks = nil
    self.overlayState.hudText = {}
    self.overlayState.stackedText = {}
    self.overlayState.suppressedOwners = {}
    ShowingCombatUI = true
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
    self.overlayState.hudText = self.previousOverlayHudText
    self.overlayState.stackedText = self.previousOverlayStackedText
    self.overlayState.suppressedOwners = self.previousOverlaySuppressedOwners
end

function TestOverlays:testHudTextOverlayUsesRetainedHudComponent()
    local modified = {}
    local alphas = {}
    local wrappedStartRoomPresentation = nil
    local wrappedShowCombatUI = nil
    local wrappedHideCombatUI = nil
    local text = "Ready"
    local visible = true

    local testModUtil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    if path == "StartRoomPresentation" then
                        wrappedStartRoomPresentation = handler
                    elseif path == "ShowCombatUI" then
                        wrappedShowCombatUI = handler
                    elseif path == "HideCombatUI" then
                        wrappedHideCombatUI = handler
                    else
                        error("unexpected overlay hook: " .. tostring(path))
                    end
                end,
            },
        },
    }
    modutil = testModUtil
    rom.mods["SGG_Modding-ModUtil"] = testModUtil

    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            TestOverlay = {
                Id = 42,
            },
        },
    }
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end
    CreateComponentFromData = function(_, data)
        return {
            Id = data.Name == "OwnedOverlay" and 501 or 502,
        }
    end

    local handle = lib.overlays.registerHudText({
        id = "test:overlay",
        componentName = "TestOverlay",
        layout = {
            RightOffset = 80,
            Y = 420,
        },
        textArgs = {
            Color = { 0.5, 0.5, 0.5, 1 },
        },
        text = function()
            return text
        end,
        visible = function()
            return visible
        end,
    })

    lu.assertNotNil(wrappedStartRoomPresentation)
    lu.assertNotNil(wrappedShowCombatUI)
    lu.assertNotNil(wrappedHideCombatUI)
    lu.assertEquals(ScreenData.HUD.ComponentData.TestOverlay.RightOffset, 80)
    lu.assertEquals(ScreenData.HUD.ComponentData.TestOverlay.Y, 420)
    lu.assertEquals(ScreenData.HUD.ComponentData.TestOverlay.TextArgs.Text, "")
    lu.assertEquals(ScreenData.HUD.ComponentData.TestOverlay.TextArgs.Color, { 0.5, 0.5, 0.5, 1 })
    lu.assertEquals(modified[#modified].Text, "Ready")

    modified = {}
    text = "Updated"
    handle.refresh()

    lu.assertEquals(modified[#modified].Text, "Updated")

    modified = {}
    alphas = {}
    visible = false
    handle.refresh()

    lu.assertEquals(#modified, 0)
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    alphas = {}
    visible = true
    wrappedStartRoomPresentation(function() end, {}, {})

    lu.assertEquals(alphas[#alphas].Fraction, 1.0)
end

function TestOverlays:testStackedTextUsesStableMiddleRightOrdering()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedText({
        id = "timer",
        componentName = "TimerOverlay",
        region = "middleRightStack",
        order = 20,
        text = "Timer",
    })
    lib.overlays.registerStackedText({
        id = "hash",
        componentName = "HashOverlay",
        region = "middleRightStack",
        order = 10,
        text = "Hash",
    })

    lu.assertEquals(ScreenData.HUD.ComponentData.HashOverlay.RightOffset, 10)
    lu.assertEquals(ScreenData.HUD.ComponentData.HashOverlay.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.HashOverlay.TextArgs.FontSize, 18)
    lu.assertEquals(ScreenData.HUD.ComponentData.HashOverlay.TextArgs.Justification, "Right")
    lu.assertEquals(ScreenData.HUD.ComponentData.TimerOverlay.RightOffset, 10)
    lu.assertEquals(ScreenData.HUD.ComponentData.TimerOverlay.Y, 232)
end

function TestOverlays:testFrameworkOrderBandSortsAboveModuleDefaults()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedText({
        id = "module",
        componentName = "ModuleOverlay",
        region = "middleRightStack",
        text = "Module",
    })
    lib.overlays.registerStackedText({
        id = "framework",
        componentName = "FrameworkOverlay",
        region = "middleRightStack",
        order = lib.overlays.order.framework + 1,
        text = "Framework",
    })

    lu.assertEquals(ScreenData.HUD.ComponentData.FrameworkOverlay.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.ModuleOverlay.Y, 240)
end

function TestOverlays:testHiddenStackedTextDoesNotReserveSpace()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    local hiddenHandle = lib.overlays.registerStackedText({
        id = "hidden",
        componentName = "HiddenOverlay",
        region = "middleRightStack",
        order = 10,
        text = "Hidden",
        visible = false,
    })
    lib.overlays.registerStackedText({
        id = "visible",
        componentName = "VisibleOverlay",
        region = "middleRightStack",
        order = 20,
        text = "Visible",
    })

    lu.assertEquals(ScreenData.HUD.ComponentData.VisibleOverlay.Y, 200)

    hiddenHandle.setVisible(true)

    lu.assertEquals(ScreenData.HUD.ComponentData.HiddenOverlay.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.VisibleOverlay.Y, 232)
end

function TestOverlays:testStackedTextRecreatesStaleComponentAfterLayout()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            StaleOverlay = {
                Id = 10,
            },
        },
    }
    local destroyed = {}
    local created = {}
    Destroy = function(args)
        destroyed[#destroyed + 1] = args.Id
    end
    CreateComponentFromData = function(_, data)
        created[#created + 1] = data
        return {
            Id = 11,
        }
    end
    ModifyTextBox = function() end

    lib.overlays.registerStackedText({
        id = "stale",
        componentName = "StaleOverlay",
        region = "middleRightStack",
        text = "Stale",
    })

    lu.assertEquals(destroyed[1], 10)
    lu.assertEquals(created[1].RightOffset, 10)
    lu.assertEquals(created[1].Y, 200)
    lu.assertEquals(HUDScreen.Components.StaleOverlay.Id, 11)
end

function TestOverlays:testUnregisterStackedTextRehydratesRemainingStack()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    local nextId = 20
    local destroyed = {}
    local modified = {}
    CreateComponentFromData = function()
        nextId = nextId + 1
        return {
            Id = nextId,
        }
    end
    Destroy = function(args)
        destroyed[#destroyed + 1] = args.Id
    end
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end

    local top = lib.overlays.registerStackedText({
        id = "top",
        componentName = "TopOverlay",
        region = "middleRightStack",
        order = 10,
        text = "Top",
    })
    lib.overlays.registerStackedText({
        id = "bottom",
        componentName = "BottomOverlay",
        region = "middleRightStack",
        order = 20,
        text = "Bottom",
    })

    local oldBottomId = HUDScreen.Components.BottomOverlay.Id
    lu.assertEquals(ScreenData.HUD.ComponentData.BottomOverlay.Y, 232)

    modified = {}
    top.unregister()

    lu.assertNil(HUDScreen.Components.TopOverlay)
    lu.assertEquals(ScreenData.HUD.ComponentData.BottomOverlay.Y, 200)
    lu.assertNotEquals(HUDScreen.Components.BottomOverlay.Id, oldBottomId)
    lu.assertEquals(modified[#modified].Text, "Bottom")
    lu.assertItemsEquals(destroyed, { 21, oldBottomId })
end

function TestOverlays:testHiddenStackedRowDoesNotCreateComponentBeforeLayout()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    local created = {}
    CreateComponentFromData = function(screenData, data)
        created[#created + 1] = {
            screenData = screenData,
            data = data,
        }
        return {
            Id = 909,
        }
    end
    ModifyTextBox = function() end

    local visible = false
    local handle = lib.overlays.registerStackedRow({
        id = "late.row",
        componentName = "LateRow",
        region = "middleRightStack",
        visible = function()
            return visible
        end,
        columns = {
            {
                key = "label",
                minWidth = 40,
                text = "IGT:",
            },
            {
                key = "time",
                minWidth = 80,
                text = "00:00.00",
            },
        },
    })

    lu.assertEquals(#created, 0)

    visible = true
    handle.refresh()

    lu.assertEquals(#created, 2)
    lu.assertEquals(ScreenData.HUD.ComponentData.AdamantOverlay_LateRow_label.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.AdamantOverlay_LateRow_time.Y, 200)
end

function TestOverlays:testStackedTextAddsGapBetweenOrderBands()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedText({
        id = "framework",
        componentName = "FrameworkOverlay",
        region = "middleRightStack",
        order = lib.overlays.order.framework,
        text = "Framework",
    })
    lib.overlays.registerStackedText({
        id = "module",
        componentName = "ModuleOverlay",
        region = "middleRightStack",
        order = lib.overlays.order.module,
        text = "Module",
    })
    lib.overlays.registerStackedText({
        id = "debug",
        componentName = "DebugOverlay",
        region = "middleRightStack",
        order = lib.overlays.order.debug,
        text = "Debug",
    })

    lu.assertEquals(ScreenData.HUD.ComponentData.FrameworkOverlay.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.ModuleOverlay.Y, 240)
    lu.assertEquals(ScreenData.HUD.ComponentData.DebugOverlay.Y, 280)
end

function TestOverlays:testStackedTextFiltersRegionOwnedTextArgs()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedText({
        id = "styled",
        componentName = "StyledOverlay",
        region = "middleRightStack",
        text = "Styled",
        textArgs = {
            Font = "CustomFont",
            Color = { 1, 0, 0, 1 },
            FontSize = 40,
            Justification = "Left",
            VerticalJustification = "Center",
            OffsetX = 99,
            OffsetY = 99,
        },
    })

    local textArgs = ScreenData.HUD.ComponentData.StyledOverlay.TextArgs
    lu.assertEquals(textArgs.Font, "CustomFont")
    lu.assertEquals(textArgs.Color, { 1, 0, 0, 1 })
    lu.assertEquals(textArgs.FontSize, 18)
    lu.assertEquals(textArgs.Justification, "Right")
    lu.assertEquals(textArgs.VerticalJustification, "Top")
    lu.assertNil(textArgs.OffsetX)
    lu.assertNil(textArgs.OffsetY)
end

function TestOverlays:testStackedRowUsesStableColumnSpacing()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedRow({
        id = "timer.row",
        componentName = "TimerRow",
        region = "middleRightStack",
        order = 10,
        columnGap = 6,
        columns = {
            {
                key = "label",
                minWidth = 42,
                justify = "Right",
                text = "IGT:",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                },
            },
            {
                key = "time",
                minWidth = 96,
                justify = "Right",
                text = "00:00.00",
                textArgs = {
                    Font = "MonospaceTypewriterBold",
                },
            },
        },
    })

    local label = ScreenData.HUD.ComponentData.AdamantOverlay_TimerRow_label
    local time = ScreenData.HUD.ComponentData.AdamantOverlay_TimerRow_time
    lu.assertEquals(label.RightOffset, 112)
    lu.assertEquals(time.RightOffset, 10)
    lu.assertEquals(label.Y, 200)
    lu.assertEquals(time.Y, 200)
    lu.assertEquals(label.TextArgs.Font, "P22UndergroundSCMedium")
    lu.assertEquals(time.TextArgs.Font, "MonospaceTypewriterBold")
    lu.assertEquals(label.TextArgs.Justification, "Right")
    lu.assertEquals(time.TextArgs.Justification, "Right")
end

function TestOverlays:testStackedRowRefreshUsesColumnCallbacks()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            LabelColumn = {
                Id = 301,
            },
            TimeColumn = {
                Id = 302,
            },
        },
    }
    local modified = {}
    local alphas = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end
    CreateComponentFromData = function(_, data)
        return {
            Id = data.Name == "LabelColumn" and 301 or 302,
        }
    end

    local timeText = "00:01.00"
    local visible = true
    local handle = lib.overlays.registerStackedRow({
        id = "callback.row",
        region = "middleRightStack",
        visible = function()
            return visible
        end,
        columns = {
            {
                key = "label",
                componentName = "LabelColumn",
                minWidth = 42,
                text = "IGT:",
            },
            {
                key = "time",
                componentName = "TimeColumn",
                minWidth = 96,
                text = function()
                    return timeText
                end,
            },
        },
    })

    lu.assertEquals(modified[#modified - 1].Text, "IGT:")
    lu.assertEquals(modified[#modified].Text, "00:01.00")

    modified = {}
    timeText = "00:02.00"
    handle.refresh()

    lu.assertEquals(modified[#modified].Text, "00:02.00")

    modified = {}
    alphas = {}
    visible = false
    handle.refresh()

    lu.assertEquals(#modified, 0)
    lu.assertEquals(alphas[#alphas - 1].Fraction, 0.0)
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)
end

function TestOverlays:testStackedRowRefreshTextSkipsRegionRelayout()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            LabelColumn = {
                Id = 401,
            },
            TimeColumn = {
                Id = 402,
            },
        },
    }
    local modified = {}
    local destroyed = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    Destroy = function(args)
        destroyed[#destroyed + 1] = args.Id
    end
    CreateComponentFromData = function(_, data)
        return {
            Id = data.Name == "LabelColumn" and 401 or 402,
        }
    end

    local timeText = "00:01.00"
    local handle = lib.overlays.registerStackedRow({
        id = "text.only",
        region = "middleRightStack",
        columns = {
            {
                key = "label",
                componentName = "LabelColumn",
                minWidth = 42,
                text = "IGT:",
            },
            {
                key = "time",
                componentName = "TimeColumn",
                minWidth = 96,
                text = function()
                    return timeText
                end,
            },
        },
    })

    destroyed = {}
    modified = {}
    timeText = "00:02.00"
    handle.refreshText()

    lu.assertEquals(#destroyed, 0)
    lu.assertEquals(#modified, 1)
    lu.assertEquals(modified[1].Text, "00:02.00")
    lu.assertEquals(ScreenData.HUD.ComponentData.LabelColumn.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.TimeColumn.Y, 200)
end

function TestOverlays:testStackedRowLeftJustifiedColumnAnchorsToReservedLeftEdge()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {},
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedRow({
        id = "timer.left",
        componentName = "TimerLeft",
        region = "middleRightStack",
        columnGap = 6,
        columns = {
            {
                key = "label",
                minWidth = 42,
                justify = "Right",
                text = "IGT:",
            },
            {
                key = "time",
                minWidth = 128,
                justify = "Left",
                text = "00:00.00",
            },
        },
    })

    local label = ScreenData.HUD.ComponentData.AdamantOverlay_TimerLeft_label
    local time = ScreenData.HUD.ComponentData.AdamantOverlay_TimerLeft_time
    lu.assertEquals(time.RightOffset, 138)
    lu.assertEquals(label.RightOffset, 144)
    lu.assertEquals(time.TextArgs.Justification, "Left")
    lu.assertEquals(label.TextArgs.Justification, "Right")
end

function TestOverlays:testStackedTextRefreshUsesTextAndVisibilityCallbacks()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            CallbackOverlay = {
                Id = 101,
            },
        },
    }
    local modified = {}
    local alphas = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end
    CreateComponentFromData = function()
        return {
            Id = 101,
        }
    end

    local text = "First"
    local visible = true
    local handle = lib.overlays.registerStackedText({
        id = "callback",
        componentName = "CallbackOverlay",
        region = "middleRightStack",
        text = function()
            return text
        end,
        visible = function()
            return visible
        end,
    })

    lu.assertEquals(modified[#modified].Text, "First")

    modified = {}
    text = "Second"
    lib.overlays.refreshStackedText("middleRightStack")

    lu.assertEquals(modified[#modified].Text, "Second")

    modified = {}
    alphas = {}
    visible = false
    handle.refresh()

    lu.assertEquals(#modified, 0)
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)
end

function TestOverlays:testHudTextCreatesMissingHudComponentOnDemand()
    ScreenData = {
        HUD = {
            ComponentData = {
                DefaultGroup = "HUD_Main",
            },
        },
    }
    HUDScreen = {
        Components = {},
    }
    local created = {}
    CreateComponentFromData = function(screenData, data)
        created[#created + 1] = {
            screenData = screenData,
            data = data,
        }
        return {
            Id = 202,
        }
    end
    local modified = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end

    lib.overlays.registerHudText({
        id = "late",
        componentName = "LateOverlay",
        layout = {
            RightOffset = 80,
            Y = 360,
        },
        text = "Late",
    })

    lu.assertEquals(#created, 1)
    lu.assertEquals(created[1].screenData, ScreenData.HUD.ComponentData)
    lu.assertEquals(HUDScreen.Components.LateOverlay.Id, 202)
    lu.assertEquals(modified[#modified].Text, "Late")
end

function TestOverlays:testHudTextUsesGlobalHudVisibilityGate()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            HiddenOverlay = {
                Id = 303,
            },
        },
    }
    local modified = {}
    local alphas = {}
    ModifyTextBox = function(args)
        modified[#modified + 1] = args
    end
    SetAlpha = function(args)
        alphas[#alphas + 1] = args
    end

    local text = "Initial"
    local handle = lib.overlays.registerHudText({
        id = "hidden-refresh",
        componentName = "HiddenOverlay",
        layout = {
            RightOffset = 80,
            Y = 360,
        },
        text = function()
            return text
        end,
    })

    lu.assertEquals(modified[#modified].Text, "Initial")

    ShowingCombatUI = nil
    text = "During transition"
    handle.refresh()

    lu.assertEquals(modified[#modified].Text, "During transition")
    lu.assertEquals(alphas[#alphas].Fraction, 0.0)

    ShowingCombatUI = true
    lib.overlays.refreshHudText(true)

    lu.assertEquals(modified[#modified].Text, "During transition")
    lu.assertEquals(alphas[#alphas].Fraction, 1.0)
end

function TestOverlays:testOwnerSuppressionHidesOwnedStackedRowsOnly()
    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }
    HUDScreen = {
        Components = {
            OwnedOverlay = {
                Id = 501,
            },
            OtherOverlay = {
                Id = 502,
            },
        },
    }
    ModifyTextBox = function() end

    lib.overlays.registerStackedText({
        id = "owned",
        componentName = "OwnedOverlay",
        owner = "test-owner",
        region = "middleRightStack",
        order = 10,
        text = "Owned",
    })
    lib.overlays.registerStackedText({
        id = "other",
        componentName = "OtherOverlay",
        region = "middleRightStack",
        order = 20,
        text = "Other",
    })

    lu.assertEquals(ScreenData.HUD.ComponentData.OwnedOverlay.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.OtherOverlay.Y, 232)

    lib.overlays.setOwnerSuppressed("test-owner", true)

    lu.assertTrue(AdamantModpackLib_Internal.overlays.suppressedOwners["test-owner"])
    lu.assertEquals(ScreenData.HUD.ComponentData.OtherOverlay.Y, 200)

    lib.overlays.setOwnerSuppressed("test-owner", false)

    lu.assertNil(AdamantModpackLib_Internal.overlays.suppressedOwners["test-owner"])
    lu.assertEquals(ScreenData.HUD.ComponentData.OwnedOverlay.Y, 200)
    lu.assertEquals(ScreenData.HUD.ComponentData.OtherOverlay.Y, 232)
end
