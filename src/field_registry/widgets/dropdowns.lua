local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.logging.warnIf
local registry = shared.fieldRegistry

local NormalizeChoiceValue = registry.NormalizeChoiceValue
local PrepareWidgetText = registry.PrepareWidgetText
local ChoiceDisplay = registry.ChoiceDisplay
local GetStyleMetricX = registry.GetStyleMetricX
local CalcTextWidth = registry.CalcTextWidth
local EstimateButtonWidth = registry.EstimateButtonWidth
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt
local ShowPreparedTooltip = registry.ShowPreparedTooltip

local choiceHelpers = registry.choiceHelpers
local ValidateValueColorsTable = choiceHelpers.ValidateValueColorsTable
local DrawWithValueColor = choiceHelpers.DrawWithValueColor
local MakeSelectableId = choiceHelpers.MakeSelectableId
local GetPackedChoiceChildren = choiceHelpers.GetPackedChoiceChildren
local GetPackedChoiceLabel = choiceHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = choiceHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = choiceHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = choiceHelpers.ClearPackedChoiceSelection
local ValidatePackedChoiceWidget = choiceHelpers.ValidatePackedChoiceWidget

local function DrawLabeledDropdownControl(imgui, node, x, y, availWidth, estimatedControlWidth, drawControl)
    local labelText = node._label or ""
    local hasLabel = labelText ~= ""
    local labelWidth = hasLabel and CalcTextWidth(imgui, labelText) or 0
    local controlWidth = type(node.controlWidth) == "number" and node.controlWidth > 0
        and node.controlWidth
        or availWidth or estimatedControlWidth
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
            local widgetChanged = drawControl(controlWidth)
            if type(controlWidth) == "number" and controlWidth > 0 then
                imgui.PopItemWidth()
            end
            ShowPreparedTooltip(imgui, node)
            return widgetChanged == true
        end)
    if controlChanged then
        changed = true
    end
    if type(controlHeight) == "number" and controlHeight > maxHeight then
        maxHeight = controlHeight
    end

    local consumedWidth = math.max((controlSlotX - x) + controlWidth, hasLabel and labelWidth or 0)
    return consumedWidth, maxHeight, changed
end

WidgetTypes.dropdown = {
    binds = { value = { storageType = { "string", "int" } } },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: dropdown values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
        ValidateValueColorsTable(node, prefix, "dropdown")
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local currentIdx = 1
        for index, candidate in ipairs(node.values or {}) do
            if candidate == current then currentIdx = index; break end
        end

        local ctx = node._dropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = current
        ctx.currentIdx = currentIdx
        ctx.previewValue = (node.values and node.values[currentIdx]) or ""
        node._dropdownCtx = ctx
        local previewText = ChoiceDisplay(node, ctx.previewValue or "")
        local previewColor = node._valueColors and node._valueColors[ctx.previewValue] or nil
        local estimatedControlWidth = EstimateButtonWidth(imgui, previewText) + 16

        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, previewColor, function()
                    return imgui.BeginCombo(node._imguiId, previewText)
                end)
                if not opened then
                    return false
                end

                local changed = false
                local pendingValue = nil
                for index, candidate in ipairs(node.values or {}) do
                    local optionColor = node._valueColors and node._valueColors[candidate] or nil
                    local selected = DrawWithValueColor(imgui, optionColor, function()
                        return imgui.Selectable(
                            MakeSelectableId(ChoiceDisplay(node, candidate), index),
                            false)
                    end)
                    if selected and candidate ~= ctx.current then
                        pendingValue = candidate
                    end
                end
                imgui.EndCombo()
                if pendingValue ~= nil then
                    ctx.boundValue:set(pendingValue)
                    changed = true
                end
                return changed
            end)
    end,
}

WidgetTypes.mappedDropdown = {
    binds = { value = {} },
    validate = function(node, prefix)
        if type(node.getPreview) ~= "function" then
            libWarn("%s: mappedDropdown getPreview must be function", prefix)
        end
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedDropdown getOptions must be function", prefix)
        end
        if node.getPreviewColor ~= nil and type(node.getPreviewColor) ~= "function" then
            libWarn("%s: mappedDropdown getPreviewColor must be function", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y, availWidth, _, uiState)
        local ctx = node._mappedDropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.preview = type(node.getPreview) == "function"
            and tostring(node.getPreview(node, bound, uiState) or "")
            or ""
        ctx.previewColor = type(node.getPreviewColor) == "function"
            and node.getPreviewColor(node, bound, uiState)
            or nil
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedDropdownCtx = ctx
        local estimatedControlWidth = EstimateButtonWidth(imgui, ctx.preview or "") + 16
        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                    return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                end)
                if not opened then
                    return false
                end

                local changed = false
                for _, option in ipairs(ctx.options or {}) do
                    local label
                    if type(option) == "table" then
                        label = tostring(option.label or option.value or "")
                    else
                        label = tostring(option or "")
                    end

                    local optionColor = type(option) == "table" and option.color or nil
                    local clicked = DrawWithValueColor(imgui, optionColor, function()
                        local uniqueId = type(option) == "table"
                            and (option.id or option.value or label)
                            or option
                        return imgui.Selectable(MakeSelectableId(label, uniqueId), false)
                    end)
                    if clicked then
                        if type(option) == "table" and type(option.onSelect) == "function" then
                            changed = option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true or changed
                        else
                            local nextValue = type(option) == "table" and option.value or option
                            if nextValue ~= ctx.current then
                                ctx.boundValue:set(nextValue)
                                changed = true
                            end
                        end
                    end
                end

                imgui.EndCombo()
                return changed
            end)
    end,
}

WidgetTypes.packedDropdown = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedDropdown")
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local children = GetPackedChoiceChildren(node, bound, "packedDropdown")
        if not children then
            return 0, 0, false
        end

        local selection = ClassifyPackedChoice(node, children)
        local ctx = node._packedDropdownCtx or {}
        ctx.children = children
        ctx.selection = selection
        ctx.noneLabel = node.noneLabel or "None"
        ctx.multipleLabel = node.multipleLabel or "Multiple"
        if selection.state == "single" and selection.selectedChild then
            ctx.preview = GetPackedChoiceLabel(node, selection.selectedChild)
            ctx.previewColor = node._valueColors and node._valueColors[selection.selectedChild.alias] or nil
        elseif selection.state == "multiple" then
            ctx.preview = ctx.multipleLabel
            ctx.previewColor = nil
        else
            ctx.preview = ctx.noneLabel
            ctx.previewColor = nil
        end
        node._packedDropdownCtx = ctx
        local estimatedControlWidth = EstimateButtonWidth(imgui, ctx.preview or "") + 16
        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                    return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                end)
                if not opened then
                    return false
                end

                local changed = false
                local pendingClear = false
                local pendingAlias = nil
                if imgui.Selectable(MakeSelectableId(ctx.noneLabel or "None", "none"), false) then
                    pendingClear = true
                end

                for _, child in ipairs(ctx.children or {}) do
                    local optionColor = node._valueColors and node._valueColors[child.alias] or nil
                    local clicked = DrawWithValueColor(imgui, optionColor, function()
                        return imgui.Selectable(
                            MakeSelectableId(GetPackedChoiceLabel(node, child), child.alias),
                            false)
                    end)
                    if clicked then
                        pendingClear = false
                        pendingAlias = child.alias
                    end
                end

                imgui.EndCombo()
                if pendingAlias ~= nil then
                    changed = ApplyPackedChoiceSelection(ctx.children, pendingAlias, ctx.selection) or changed
                elseif pendingClear then
                    changed = ClearPackedChoiceSelection(ctx.children, ctx.selection) or changed
                end
                return changed
            end)
    end,
}
