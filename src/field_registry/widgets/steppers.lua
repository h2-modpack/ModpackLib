local internal = AdamantModpackLib_Internal
local StorageTypes = public.registry.storage
local WidgetTypes = public.registry.widgets
local libWarn = internal.logging.warnIf
local ui = internal.ui
local widgets = internal.widgets

local NormalizeInteger = ui.NormalizeInteger
local PrepareWidgetText = widgets.PrepareWidgetText
local CalcTextWidth = ui.CalcTextWidth
local EstimateButtonWidth = ui.EstimateButtonWidth
local EstimateStructuredRowAdvanceY = ui.EstimateStructuredRowAdvanceY
local DrawOrderedEntries = ui.DrawOrderedEntries
local ShowPreparedTooltip = ui.ShowPreparedTooltip
local GetStyleMetricX = ui.GetStyleMetricX

local choiceHelpers = widgets.choiceHelpers
local ValidateValueColorsTable = choiceHelpers.ValidateValueColorsTable

local function CompareEntries(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end
    if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
        return left.start < right.start
    end
    return left.index < right.index
end

local function PrepareStepperDrawContext(node, boundValue, limits)
    local ctx = node._stepperCtx or {}
    ctx.boundValue = boundValue
    ctx.renderedValue = NormalizeInteger(node, boundValue:get())
    ctx.min = limits and limits.min or node.min
    ctx.max = limits and limits.max or node.max
    ctx.valueSlotStart = nil
    ctx.valueSlotWidth = nil
    node._stepperCtx = ctx
end

local function BuildOrderedStepperEntries(node, options)
    options = options or {}
    local label = node._label or ""
    local hasLabel = options.drawLabel ~= false and label ~= ""
    local slotPrefix = options.slotPrefix or ""
    local labelSlotName = options.labelSlotName or "label"
    local geometryOwner = options.geometryOwner or node
    local entries = {}

    local function SlotName(name)
        return slotPrefix ~= "" and (slotPrefix .. name) or name
    end

    local function ControlGap(imgui)
        if type(geometryOwner.controlGap) == "number" and geometryOwner.controlGap >= 0 then
            return geometryOwner.controlGap
        end
        return GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)
    end

    local function AddEntry(name, config)
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = config.line or 1,
            start = config.start,
            width = config.width,
            align = config.align,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    local function GetStepperLimits()
        local ctx = node._stepperCtx
        local minValue = ctx and ctx.min ~= nil and ctx.min or node.min
        local maxValue = ctx and ctx.max ~= nil and ctx.max or node.max
        return minValue, maxValue
    end

    local function CommitValue(nextValue)
        local ctx = node._stepperCtx
        if not ctx or not ctx.boundValue then
            return false
        end
        local minValue, maxValue = GetStepperLimits()
        local normalized = NormalizeInteger(node, nextValue)
        if minValue ~= nil and normalized < minValue then
            normalized = minValue
        end
        if maxValue ~= nil and normalized > maxValue then
            normalized = maxValue
        end
        if normalized ~= ctx.renderedValue then
            ctx.renderedValue = normalized
            ctx.boundValue:set(normalized)
            return true
        end
        return false
    end

    local function GetValueText()
        local ctx = node._stepperCtx
        local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
        local displayValue = node.displayValues and node.displayValues[renderedValue]
        if not ctx then
            return tostring(displayValue ~= nil and displayValue or renderedValue), renderedValue
        end
        if ctx._lastStepperVal ~= renderedValue or ctx._lastStepperStr == nil then
            ctx._lastStepperStr = tostring(displayValue ~= nil and displayValue or renderedValue)
            ctx._lastStepperVal = renderedValue
        end
        return ctx._lastStepperStr, renderedValue
    end

    if hasLabel then
        AddEntry(labelSlotName, {
            estimateWidth = function(imgui)
                return CalcTextWidth(imgui, label)
            end,
            render = function(imgui)
                imgui.AlignTextToFramePadding()
                imgui.Text(label)
                ShowPreparedTooltip(imgui, node)
                return false, CalcTextWidth(imgui, label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
        AddEntry(SlotName("controlGap"), {
            estimateWidth = function(imgui)
                return ControlGap(imgui)
            end,
            render = function(imgui)
                return false, ControlGap(imgui), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    AddEntry(SlotName("decrement"), {
        estimateWidth = function(imgui)
            return EstimateButtonWidth(imgui, "-")
        end,
        render = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            local minValue = GetStepperLimits()
            local changed = imgui.Button("-") and renderedValue > minValue and CommitValue(renderedValue - (node._step or 1)) or false
            return changed, EstimateButtonWidth(imgui, "-"), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    AddEntry(SlotName("value"), {
        width = geometryOwner.valueWidth,
        align = geometryOwner.valueAlign,
        estimateWidth = function(imgui)
            local valueText = GetValueText()
            return CalcTextWidth(imgui, valueText)
        end,
        render = function(imgui, entry)
            local valueText, renderedValue = GetValueText()
            local textWidth = CalcTextWidth(imgui, valueText)
            local color = node._valueColors and node._valueColors[renderedValue] or nil
            local ctx = node._stepperCtx
            if ctx then ctx.valueSlotWidth = entry.width end
            imgui.AlignTextToFramePadding()
            if type(color) == "table" then
                imgui.TextColored(color[1], color[2], color[3], color[4], valueText)
            else
                imgui.Text(valueText)
            end
            return false, textWidth, EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    AddEntry(SlotName("increment"), {
        estimateWidth = function(imgui)
            return EstimateButtonWidth(imgui, "+")
        end,
        render = function(imgui)
            local ctx = node._stepperCtx
            local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
            local _, maxValue = GetStepperLimits()
            local changed = imgui.Button("+") and renderedValue < maxValue and CommitValue(renderedValue + (node._step or 1)) or false
            return changed, EstimateButtonWidth(imgui, "+"), EstimateStructuredRowAdvanceY(imgui)
        end,
    })

    if node._fastStep then
        AddEntry(SlotName("fastDecrement"), {
            estimateWidth = function(imgui)
                return EstimateButtonWidth(imgui, "<<")
            end,
            render = function(imgui)
                local ctx = node._stepperCtx
                local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
                local minValue = GetStepperLimits()
                local changed = imgui.Button("<<")
                    and renderedValue > minValue
                    and CommitValue(renderedValue - node._fastStep)
                    or false
                return changed, EstimateButtonWidth(imgui, "<<"), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
        AddEntry(SlotName("fastIncrement"), {
            estimateWidth = function(imgui)
                return EstimateButtonWidth(imgui, ">>")
            end,
            render = function(imgui)
                local ctx = node._stepperCtx
                local renderedValue = ctx and ctx.renderedValue or NormalizeInteger(node, node.default)
                local _, maxValue = GetStepperLimits()
                local changed = imgui.Button(">>")
                    and renderedValue < maxValue
                    and CommitValue(renderedValue + node._fastStep)
                    or false
                return changed, EstimateButtonWidth(imgui, ">>"), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    table.sort(entries, CompareEntries)

    return entries
end

local function PrepareOrderedRangeEntries(node, minStepper, maxStepper)
    local entries = BuildOrderedStepperEntries(minStepper, {
        drawLabel = true,
        slotPrefix = "min.",
        labelSlotName = "label",
        geometryOwner = node,
    })
    entries[#entries + 1] = {
        index = #entries + 1,
        name = "separator",
        line = 1,
        estimateWidth = function(_imgui)
            return CalcTextWidth(_imgui, "  to")
        end,
        render = function(_imgui)
            _imgui.AlignTextToFramePadding()
            _imgui.Text("  to")
            return false, CalcTextWidth(_imgui, "  to"), EstimateStructuredRowAdvanceY(_imgui)
        end,
    }
    local maxEntries = BuildOrderedStepperEntries(maxStepper, {
        drawLabel = false,
        slotPrefix = "max.",
        geometryOwner = node,
    })
    for _, entry in ipairs(maxEntries) do
        entry.index = #entries + 1
        entries[#entries + 1] = entry
    end
    for index, entry in ipairs(entries) do
        entry.index = index
    end
    table.sort(entries, CompareEntries)
    return entries
end

local function ValidateStepper(node, prefix)
    StorageTypes.int.validate(node, prefix)
    if node.step ~= nil and (type(node.step) ~= "number" or node.step <= 0) then
        libWarn("%s: stepper step must be a positive number", prefix)
    end
    if node.fastStep ~= nil and (type(node.fastStep) ~= "number" or node.fastStep <= 0) then
        libWarn("%s: stepper fastStep must be a positive number", prefix)
    end
    if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
        libWarn("%s: stepper displayValues must be a table", prefix)
    end
    if node.valueWidth ~= nil and (type(node.valueWidth) ~= "number" or node.valueWidth <= 0) then
        libWarn("%s: stepper valueWidth must be a positive number", prefix)
    end
    if node.controlGap ~= nil and (type(node.controlGap) ~= "number" or node.controlGap < 0) then
        libWarn("%s: stepper controlGap must be a non-negative number", prefix)
    end
    if node.valueAlign ~= nil and node.valueAlign ~= "left" and node.valueAlign ~= "center" and node.valueAlign ~= "right" then
        libWarn("%s: stepper valueAlign must be 'left', 'center', or 'right'", prefix)
    end
    ValidateValueColorsTable(node, prefix, "stepper")
    node._step = math.floor(tonumber(node.step) or 1)
    node._fastStep = node.fastStep and math.floor(node.fastStep) or nil
    PrepareWidgetText(node, node.binds and node.binds.value)
    node._orderedEntries = BuildOrderedStepperEntries(node)
end

WidgetTypes.stepper = {
    binds = { value = { storageType = "int" } },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        default = { type = "integer", optional = true },
        min = { type = "integer", optional = true },
        max = { type = "integer", optional = true },
        step = { type = "number", optional = true },
        fastStep = { type = "number", optional = true },
        displayValues = { type = "table", optional = true },
        valueColors = { type = "table", optional = true },
        valueWidth = { type = "number", optional = true },
        valueAlign = { type = "string", optional = true },
        controlGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = ValidateStepper,
    draw = function(imgui, node, bound, x, y)
        PrepareStepperDrawContext(node, bound.value)
        return DrawOrderedEntries(
            imgui,
            node._orderedEntries or BuildOrderedStepperEntries(node),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.steppedRange = {
    binds = {
        min = { storageType = "int" },
        max = { storageType = "int" },
    },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        default = { type = "integer", optional = true },
        defaultMax = { type = "integer", optional = true },
        min = { type = "integer", optional = true },
        max = { type = "integer", optional = true },
        step = { type = "number", optional = true },
        fastStep = { type = "number", optional = true },
        valueWidth = { type = "number", optional = true },
        valueAlign = { type = "string", optional = true },
        controlGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        if node.valueWidth ~= nil and (type(node.valueWidth) ~= "number" or node.valueWidth <= 0) then
            libWarn("%s: steppedRange valueWidth must be a positive number", prefix)
        end
        if node.controlGap ~= nil and (type(node.controlGap) ~= "number" or node.controlGap < 0) then
            libWarn("%s: steppedRange controlGap must be a non-negative number", prefix)
        end
        if node.valueAlign ~= nil and node.valueAlign ~= "left" and node.valueAlign ~= "center" and node.valueAlign ~= "right" then
            libWarn("%s: steppedRange valueAlign must be 'left', 'center', or 'right'", prefix)
        end
        local minStepper = {
            label = node.label,
            default = node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
            controlGap = node.controlGap,
        }
        local maxStepper = {
            default = node.defaultMax or node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
            controlGap = node.controlGap,
        }
        ValidateStepper(minStepper, prefix .. " min")
        ValidateStepper(maxStepper, prefix .. " max")
        node._minStepper = minStepper
        node._maxStepper = maxStepper
        node._orderedEntries = PrepareOrderedRangeEntries(node, minStepper, maxStepper)
    end,
    draw = function(imgui, node, bound, x, y)
        local minStepper = node._minStepper
        local maxStepper = node._maxStepper
        if not minStepper or not maxStepper then
            libWarn("steppedRange '%s' not prepared", tostring(node.binds and node.binds.min or node.type))
            return 0, 0, false
        end

        local minValue = bound.min:get()
        local maxValue = bound.max:get()

        PrepareStepperDrawContext(minStepper, bound.min, { min = minStepper.min, max = maxValue })
        PrepareStepperDrawContext(maxStepper, bound.max, { min = minValue, max = maxStepper.max })
        return DrawOrderedEntries(
            imgui,
            node._orderedEntries or PrepareOrderedRangeEntries(node, minStepper, maxStepper),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}
