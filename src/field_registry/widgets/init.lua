local internal = AdamantModpackLib_Internal
local shared = internal.shared
local registry = shared.fieldRegistry

local SetCursorPosSafe = registry.SetCursorPosSafe
local GetStyleMetricX = registry.GetStyleMetricX
local CalcTextWidth = registry.CalcTextWidth
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt

local function EstimateToggleWidth(imgui, label)
    local frameHeight = type(imgui.GetFrameHeight) == "function" and imgui.GetFrameHeight() or nil
    if type(frameHeight) ~= "number" or frameHeight <= 0 then
        frameHeight = EstimateStructuredRowAdvanceY(imgui)
    end
    local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
    local itemInnerSpacingX = GetStyleMetricX(style, "ItemInnerSpacing", 4)
    return frameHeight + itemInnerSpacingX + CalcTextWidth(imgui, label)
end

local function DrawOrderedEntries(imgui, entries, startX, startY, fallbackHeight)
    local currentLine = nil
    local currentRowY = startY
    local currentRowAdvance = fallbackHeight
    local currentX = startX
    local maxRight = startX
    local maxBottom = startY
    local changed = false

    for _, entry in ipairs(entries or {}) do
        local isNewLine = currentLine ~= entry.line
        if isNewLine then
            if currentLine ~= nil then
                currentRowY = currentRowY + currentRowAdvance
            end
            currentLine = entry.line
            currentRowAdvance = fallbackHeight
            currentX = startX
        end

        local slotX
        if type(entry.start) == "number" then
            slotX = startX + entry.start
        else
            slotX = currentX
        end

        local estimatedWidth = type(entry.estimateWidth) == "function"
            and entry.estimateWidth(imgui, entry)
            or 0
        local drawX = slotX
        if type(entry.width) == "number" and type(estimatedWidth) == "number" then
            local offset = 0
            if entry.align == "center" then
                offset = math.max((entry.width - estimatedWidth) / 2, 0)
            elseif entry.align == "right" then
                offset = math.max(entry.width - estimatedWidth, 0)
            end
            drawX = slotX + offset
        end

        local measuredWidth = estimatedWidth
        local measuredHeight = fallbackHeight
        local entryChanged, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            slotX,
            currentRowY,
            fallbackHeight,
            function()
                if drawX ~= slotX then
                    if type(imgui.SetCursorPosX) == "function" then
                        imgui.SetCursorPosX(drawX)
                    else
                        SetCursorPosSafe(imgui, drawX, currentRowY)
                    end
                end
                local widgetChanged, contentWidth, contentHeight = entry.render(imgui, entry)
                if type(contentWidth) == "number" and contentWidth > 0 then
                    measuredWidth = contentWidth
                end
                if type(contentHeight) == "number" and contentHeight > 0 then
                    measuredHeight = contentHeight
                end
                return widgetChanged == true
            end)
        if entryChanged then
            changed = true
        end

        local slotConsumedHeight = measuredHeight > 0 and measuredHeight or consumedHeight
        if slotConsumedHeight > currentRowAdvance then
            currentRowAdvance = slotConsumedHeight
        end

        local slotConsumedWidth = type(entry.width) == "number" and entry.width or measuredWidth or 0
        local slotRight = slotX + math.max(slotConsumedWidth, 0)
        if slotRight > maxRight then
            maxRight = slotRight
        end
        local slotBottom = currentRowY + math.max(slotConsumedHeight or 0, 0)
        if slotBottom > maxBottom then
            maxBottom = slotBottom
        end

        currentX = math.max(currentX, slotRight)
    end

    return math.max(maxRight - startX, 0), math.max(maxBottom - startY, 0), changed
end

registry.EstimateToggleWidth = EstimateToggleWidth
registry.DrawOrderedEntries = DrawOrderedEntries

import 'field_registry/widgets/choice_helpers.lua'

import 'field_registry/widgets/base.lua'
import 'field_registry/widgets/inputs.lua'
import 'field_registry/widgets/dropdowns.lua'
import 'field_registry/widgets/radios.lua'
import 'field_registry/widgets/steppers.lua'
import 'field_registry/widgets/checkboxes.lua'
import 'field_registry/widgets/buttons.lua'
