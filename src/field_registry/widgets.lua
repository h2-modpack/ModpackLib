local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry

local NormalizeInteger = registry.NormalizeInteger
local NormalizeChoiceValue = registry.NormalizeChoiceValue
local ChoiceDisplay = registry.ChoiceDisplay
local GetCursorPosXSafe = registry.GetCursorPosXSafe
local GetStyleMetricX = registry.GetStyleMetricX
local CalcTextWidth = registry.CalcTextWidth
local EstimateButtonWidth = registry.EstimateButtonWidth
local DrawWidgetSlots = registry.DrawWidgetSlots
local GetSlotGeometry = registry.GetSlotGeometry

local function BuildStepperSlots(imgui, node, boundValue, value, options)
    options = options or {}
    local current = NormalizeInteger(node, value)
    local step = node._step or 1
    local fastStep = node._fastStep
    local renderedValue = current

    local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
    local itemSpacingX = GetStyleMetricX(style, "ItemSpacing", 0)
    local label = node.label or ""
    local hasLabel = options.drawLabel ~= false and label ~= ""
    local slotPrefix = options.slotPrefix or ""
    local labelSlotName = options.labelSlotName or "label"
    local valueSlotStart = nil
    local valueSlotWidth = nil

    local function SlotName(name)
        if slotPrefix ~= "" then
            return slotPrefix .. name
        end
        return name
    end

    local function CommitValue(nextValue)
        local normalized = NormalizeInteger(node, nextValue)
        if normalized ~= renderedValue then
            renderedValue = normalized
            boundValue:set(normalized)
            return true
        end
        return false
    end

    local slots = {}

    if hasLabel then
        table.insert(slots, {
            name = labelSlotName,
            draw = function()
                imgui.Text(label)
                if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
                    imgui.SetTooltip(node.tooltip)
                end
                return false
            end,
        })
    end

    table.insert(slots, {
        name = SlotName("decrement"),
        sameLine = hasLabel,
        draw = function()
            if imgui.Button("-") and renderedValue > node.min then
                return CommitValue(renderedValue - step)
            end
            return false
        end,
    })

    table.insert(slots, {
        name = SlotName("value"),
        sameLine = true,
        draw = function(_, slot)
            valueSlotStart = GetCursorPosXSafe(imgui)
            valueSlotWidth = slot.width
            if node._lastStepperVal ~= renderedValue then
                node._lastStepperStr = tostring(renderedValue)
                node._lastStepperVal = renderedValue
            end
            local valueText = node._lastStepperStr
            if slot.width and slot.align ~= nil
                and type(imgui.SetCursorPosX) == "function" then
                local textWidth = CalcTextWidth(imgui, valueText)
                local alignOffset = slot.align == "center"
                    and math.max((slot.width - textWidth) / 2, 0)
                    or math.max(slot.width - textWidth, 0)
                imgui.SetCursorPosX(valueSlotStart + alignOffset)
            end
            imgui.Text(valueText)
            return false
        end,
    })

    table.insert(slots, {
        name = SlotName("increment"),
        sameLine = true,
        draw = function(_, slot)
            if slot.start == nil and valueSlotWidth and valueSlotStart ~= nil
                and type(imgui.SetCursorPosX) == "function" then
                imgui.SetCursorPosX(valueSlotStart + valueSlotWidth + itemSpacingX)
            end
            if imgui.Button("+") and renderedValue < node.max then
                return CommitValue(renderedValue + step)
            end
            return false
        end,
    })

    if fastStep then
        table.insert(slots, {
            name = SlotName("fastDecrement"),
            sameLine = true,
            draw = function()
                if imgui.Button("<<") and renderedValue > node.min then
                    return CommitValue(renderedValue - fastStep)
                end
                return false
            end,
        })
        table.insert(slots, {
            name = SlotName("fastIncrement"),
            sameLine = true,
            draw = function()
                if imgui.Button(">>") and renderedValue < node.max then
                    return CommitValue(renderedValue + fastStep)
                end
                return false
            end,
        })
    end

    return slots
end

WidgetTypes.checkbox = {
    binds = { value = { storageType = "bool" } },
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(node.default))
        end
    end,
    draw = function(imgui, node, bound)
        local value = bound.value:get()
        if value == nil then value = node.default == true end
        local label = tostring(node.label or (node.binds and node.binds.value) or "")
        local newVal, changed = imgui.Checkbox(label .. (node._imguiId or ""), value == true)
        if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
            imgui.SetTooltip(node.tooltip)
        end
        if changed then bound.value:set(newVal) end
    end,
}

WidgetTypes.dropdown = {
    binds = { value = { storageType = "string" } },
    slots = { "label", "control" },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
    end,
    draw = function(imgui, node, bound, width)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local currentIdx = 1
        for index, candidate in ipairs(node.values or {}) do
            if candidate == current then currentIdx = index; break end
        end

        local previewValue = (node.values and node.values[currentIdx]) or ""
        local label = node.label or (node.binds and node.binds.value) or ""
        local hasLabel = label ~= ""

        local slots = {}
        if hasLabel then
            table.insert(slots, {
                name = "label",
                draw = function()
                    imgui.Text(label)
                    if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
                        imgui.SetTooltip(node.tooltip)
                    end
                    return false
                end,
            })
        end

        table.insert(slots, {
            name = "control",
            sameLine = hasLabel,
            width = width,
            draw = function()
                if imgui.BeginCombo(node._imguiId, ChoiceDisplay(node, previewValue)) then
                    for index, candidate in ipairs(node.values or {}) do
                        if imgui.Selectable(ChoiceDisplay(node, candidate), index == currentIdx) then
                            if candidate ~= current then
                                bound.value:set(candidate)
                                return true
                            end
                        end
                    end
                    imgui.EndCombo()
                end
                return false
            end,
        })

        return DrawWidgetSlots(imgui, node, slots, GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.radio = {
    binds = { value = { storageType = "string" } },
    slots = { "label" },
    dynamicSlots = function(node, slotName)
        local optionIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^option:(%d+)$")) or nil
        if optionIndex == nil then
            return false, nil
        end
        local optionCount = type(node.values) == "table" and #node.values or 0
        if optionIndex < 1 or optionIndex > optionCount then
            return false, ("geometry slot '%s' is out of range for %d radio options"):format(
                tostring(slotName), optionCount)
        end
        return true, nil
    end,
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
    end,
    draw = function(imgui, node, bound)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local slots = {}
        local label = node.label or (node.binds and node.binds.value) or ""
        if label ~= "" then
            table.insert(slots, {
                name = "label",
                draw = function()
                    imgui.Text(label)
                    if imgui.IsItemHovered() and (node.tooltip or "") ~= "" then
                        imgui.SetTooltip(node.tooltip)
                    end
                    return false
                end,
            })
        end
        for index, candidate in ipairs(node.values or {}) do
            table.insert(slots, {
                name = "option:" .. tostring(index),
                sameLine = label == "" and index > 1,
                draw = function()
                    if imgui.RadioButton(ChoiceDisplay(node, candidate), current == candidate) then
                        if candidate ~= current then
                            bound.value:set(candidate)
                            return true
                        end
                    end
                    return false
                end,
            })
        end
        local changed = DrawWidgetSlots(imgui, node, slots, GetCursorPosXSafe(imgui))
        if label == "" then
            imgui.NewLine()
        end
        return changed
    end,
}

local function ValidateStepper(node, prefix)
    StorageTypes.int.validate(node, prefix)
    if node.step ~= nil and (type(node.step) ~= "number" or node.step <= 0) then
        libWarn("%s: stepper step must be a positive number", prefix)
    end
    if node.fastStep ~= nil and (type(node.fastStep) ~= "number" or node.fastStep <= 0) then
        libWarn("%s: stepper fastStep must be a positive number", prefix)
    end
    node._step = math.floor(tonumber(node.step) or 1)
    node._fastStep = node.fastStep and math.floor(node.fastStep) or nil
end

WidgetTypes.stepper = {
    binds = { value = { storageType = "int" } },
    slots = { "label", "decrement", "value", "increment", "fastDecrement", "fastIncrement" },
    validate = ValidateStepper,
    draw = function(imgui, node, bound)
        return DrawWidgetSlots(imgui, node, BuildStepperSlots(imgui, node, bound.value, bound.value:get()), GetCursorPosXSafe(imgui))
    end,
}

WidgetTypes.steppedRange = {
    binds = {
        min = { storageType = "int" },
        max = { storageType = "int" },
    },
    slots = {
        "label",
        "min.decrement", "min.value", "min.increment", "min.fastDecrement", "min.fastIncrement",
        "separator",
        "max.decrement", "max.value", "max.increment", "max.fastDecrement", "max.fastIncrement",
    },
    validate = function(node, prefix)
        local minStepper = {
            label = node.label,
            default = node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
        }
        local maxStepper = {
            default = node.defaultMax or node.default,
            min = node.min, max = node.max,
            step = node.step, fastStep = node.fastStep,
        }
        ValidateStepper(minStepper, prefix .. " min")
        ValidateStepper(maxStepper, prefix .. " max")
        node._minStepper = minStepper
        node._maxStepper = maxStepper
    end,
    draw = function(imgui, node, bound)
        local minStepper = node._minStepper
        local maxStepper = node._maxStepper
        if not minStepper or not maxStepper then
            libWarn("steppedRange '%s' not prepared", tostring(node.binds and node.binds.min or node.type))
            return false
        end

        local minValue = bound.min:get()
        local maxValue = bound.max:get()
        minStepper.max = maxValue
        maxStepper.min = minValue

        local rowStart = GetCursorPosXSafe(imgui)
        local slots = BuildStepperSlots(imgui, minStepper, bound.min, bound.min:get(), {
            drawLabel = true,
            slotPrefix = "min.",
            labelSlotName = "label",
        })

        table.insert(slots, {
            name = "separator",
            sameLine = true,
            draw = function(_, slot)
                maxStepper.min = bound.min:get()
                if slot.start == nil and type(imgui.SetCursorPosX) == "function" then
                    local beforeMax = GetSlotGeometry(node, "max.decrement")
                    if beforeMax and type(beforeMax.start) == "number" then
                        local TO_HALF_WIDTH = 7
                        local afterMin = GetCursorPosXSafe(imgui)
                        local separatorX = afterMin + math.max(((rowStart + beforeMax.start) - afterMin) / 2 - TO_HALF_WIDTH, 0)
                        imgui.SetCursorPosX(separatorX)
                    end
                end
                imgui.Text("to")
                return false
            end,
        })
        for _, slot in ipairs(BuildStepperSlots(imgui, maxStepper, bound.max, bound.max:get(), {
            drawLabel = false,
            slotPrefix = "max.",
        })) do
            table.insert(slots, slot)
        end
        return DrawWidgetSlots(imgui, node, slots, rowStart)
    end,
}

WidgetTypes.packedCheckboxList = {
    binds = { value = { storageType = "int" } },
    dynamicSlots = function(node, slotName)
        local itemIndex = type(slotName) == "string" and tonumber(string.match(slotName, "^item:(%d+)$")) or nil
        if itemIndex == nil then
            return false, nil
        end
        local slotCount = tonumber(node.slotCount)
        if slotCount == nil or slotCount < 1 then
            return false, "packedCheckboxList dynamic item slots require a positive slotCount"
        end
        slotCount = math.floor(slotCount)
        if itemIndex < 1 or itemIndex > slotCount then
            return false, ("geometry slot '%s' is out of range for packedCheckboxList slotCount %d"):format(
                tostring(slotName), slotCount)
        end
        return true, nil
    end,
    validate = function(node, prefix)
        if node.slotCount ~= nil then
            if type(node.slotCount) ~= "number" then
                libWarn("%s: packedCheckboxList slotCount must be a number", prefix)
            elseif node.slotCount < 1 or math.floor(node.slotCount) ~= node.slotCount then
                libWarn("%s: packedCheckboxList slotCount must be a positive integer", prefix)
            else
                node.slotCount = math.floor(node.slotCount)
            end
        end
    end,
    draw = function(imgui, node, bound)
        local children = bound.value and bound.value.children
        if not children or #children == 0 then
            libWarn("packedCheckboxList: no packed children for alias '%s'; bind to a packedInt root",
                tostring(node.binds and node.binds.value or "?"))
            return
        end

        if type(node.slotCount) == "number" and node.slotCount >= 1 then
            local slots = {}
            for index = 1, node.slotCount do
                local child = children[index]
                table.insert(slots, {
                    name = "item:" .. tostring(index),
                    line = index,
                    hidden = child == nil,
                    draw = function()
                        local val = child.get()
                        if val == nil then val = false end
                        local newVal, changed = imgui.Checkbox(child.label, val == true)
                        if changed then child.set(newVal) end
                        return changed
                    end,
                })
            end
            return DrawWidgetSlots(imgui, node, slots, GetCursorPosXSafe(imgui))
        end

        for index, child in ipairs(children) do
            local val = child.get()
            if val == nil then val = false end
            imgui.PushID(child.alias or tostring(index))
            local newVal, changed = imgui.Checkbox(child.label, val == true)
            if changed then child.set(newVal) end
            imgui.PopID()
        end
    end,
}
