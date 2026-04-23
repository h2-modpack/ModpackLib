local lu = require('luaunit')

TestWidgets = {}

local function makeSession(value)
    return {
        read = function()
            return value
        end,
        write = function(_, nextValue)
            value = nextValue
        end,
    }
end

local function makeDropdownImgui()
    local state = {
        beginComboPreview = nil,
        customPreviewCalls = 0,
    }

    local imgui = {
        GetCursorPosX = function() return 0 end,
        SetCursorPosX = function() end,
        AlignTextToFramePadding = function() end,
        Text = function() end,
        IsItemHovered = function() return false end,
        SetTooltip = function() end,
        SameLine = function() end,
        PushItemWidth = function() end,
        PopItemWidth = function() end,
        BeginCombo = function(_, preview)
            state.beginComboPreview = preview
            return false
        end,
        GetWindowDrawList = function()
            state.customPreviewCalls = state.customPreviewCalls + 1
            return {}
        end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemInnerSpacing = { x = 4, y = 4 },
            }
        end,
        GetItemRectMin = function() return 0, 0 end,
        GetItemRectMax = function() return 200, 24 end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8, 16 end,
        GetFrameHeight = function() return 20 end,
        GetColorU32 = function() return 1 end,
        PushClipRect = function() end,
        ImDrawListAddText = function() end,
        PopClipRect = function() end,
    }

    return imgui, state
end

function TestWidgets:testPlainDropdownUsesNativePreview()
    local imgui, state = makeDropdownImgui()

    lib.widgets.dropdown(imgui, makeSession(2), "Mode", {
        label = "Mode",
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        labelWidth = 80,
        controlWidth = 120,
    })

    lu.assertEquals(state.beginComboPreview, "Two")
    lu.assertEquals(state.customPreviewCalls, 0)
end

function TestWidgets:testColoredDropdownUsesCustomPreview()
    local imgui, state = makeDropdownImgui()

    lib.widgets.dropdown(imgui, makeSession(2), "Mode", {
        label = "Mode",
        values = { 1, 2 },
        displayValues = {
            [1] = "One",
            [2] = "Two",
        },
        valueColors = {
            [2] = { 1, 0, 0, 1 },
        },
        labelWidth = 80,
        controlWidth = 120,
    })

    lu.assertEquals(state.beginComboPreview, "")
    lu.assertEquals(state.customPreviewCalls, 1)
end
