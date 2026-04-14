local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.logging.warnIf
local registry = shared.fieldRegistry

local PrepareWidgetText = registry.PrepareWidgetText
local GetStyleMetricX = registry.GetStyleMetricX
local CalcTextWidth = registry.CalcTextWidth
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt
local ShowPreparedTooltip = registry.ShowPreparedTooltip

WidgetTypes.inputText = {
    binds = { value = { storageType = "string" } },
    validate = function(node, prefix)
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: inputText maxLen must be a positive number", prefix)
        end
        if node.controlWidth ~= nil and (type(node.controlWidth) ~= "number" or node.controlWidth <= 0) then
            libWarn("%s: inputText controlWidth must be a positive number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 0)
        if node._maxLen < 1 then
            node._maxLen = nil
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local aliasNode = bound.value and bound.value.node or nil
        local ctx = node._inputTextCtx or {}
        ctx.boundValue = bound.value
        ctx.current = tostring(bound.value:get() or "")
        ctx.maxLen = node._maxLen or (aliasNode and aliasNode._maxLen) or 256
        node._inputTextCtx = ctx

        local labelText = node._label or ""
        local hasLabel = labelText ~= ""
        local labelWidth = hasLabel and CalcTextWidth(imgui, labelText) or 0
        local controlWidth = type(node.controlWidth) == "number" and node.controlWidth > 0
            and node.controlWidth
            or availWidth or 120
        local itemSpacingX = GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)

        local controlSlotX
        if hasLabel then
            controlSlotX = x + labelWidth + itemSpacingX
        else
            controlSlotX = x
        end

        local maxHeight = 0
        local changed = false

        if hasLabel then
            local _, _, _, labelHeight = DrawStructuredAt(
                imgui,
                x,
                y,
                EstimateStructuredRowAdvanceY(imgui),
                function()
                    imgui.Text(labelText)
                    ShowPreparedTooltip(imgui, node)
                    return false
                end)
            if type(labelHeight) == "number" and labelHeight > maxHeight then
                maxHeight = labelHeight
            end
        end

        local controlChanged, _, _, controlHeight = DrawStructuredAt(
            imgui,
            controlSlotX,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if type(controlWidth) == "number" and controlWidth > 0 then
                    imgui.PushItemWidth(controlWidth)
                end
                local newValue, widgetChanged = imgui.InputText(node._imguiId, ctx.current or "", ctx.maxLen)
                if type(controlWidth) == "number" and controlWidth > 0 then
                    imgui.PopItemWidth()
                end
                ShowPreparedTooltip(imgui, node)
                if widgetChanged then
                    ctx.boundValue:set(newValue)
                    return true
                end
                return false
            end)
        if controlChanged then
            changed = true
        end
        if type(controlHeight) == "number" and controlHeight > maxHeight then
            maxHeight = controlHeight
        end

        local consumedWidth = math.max((controlSlotX - x) + controlWidth, hasLabel and labelWidth or 0)
        return consumedWidth, maxHeight, changed
    end,
}
