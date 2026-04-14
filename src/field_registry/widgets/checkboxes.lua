local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.logging.warnIf
local registry = shared.fieldRegistry

local PrepareWidgetText = registry.PrepareWidgetText
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt
local ShowPreparedTooltip = registry.ShowPreparedTooltip
local EstimateToggleWidth = registry.EstimateToggleWidth
local DrawOrderedEntries = registry.DrawOrderedEntries

local choiceHelpers = registry.choiceHelpers
local ValidateValueColorsTable = choiceHelpers.ValidateValueColorsTable
local DrawWithValueColor = choiceHelpers.DrawWithValueColor

local DEFAULT_PACKED_SLOT_COUNT = 32

local function BuildOrderedCheckboxEntries(optionEntries)
    local entries = {}

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

    for index, option in ipairs(optionEntries or {}) do
        local slotName = option.slotName or ("item:" .. tostring(index))
        AddEntry(slotName, {
            line = option.line,
            start = option.start,
            width = option.width,
            align = option.align,
            estimateWidth = function(imgui)
                return EstimateToggleWidth(imgui, option.label)
            end,
            render = function(imgui)
                imgui.PushID((slotName or "item") .. "_" .. tostring(index))
                local nextValue, clicked = DrawWithValueColor(imgui, option.color, function()
                    return imgui.Checkbox(option.label, option.current == true)
                end)
                imgui.PopID()
                if clicked and type(option.onToggle) == "function" then
                    return option.onToggle(nextValue) == true,
                        EstimateToggleWidth(imgui, option.label),
                        EstimateStructuredRowAdvanceY(imgui)
                end
                return false, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    table.sort(entries, function(left, right)
        if left.line ~= right.line then
            return left.line < right.line
        end
        if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
            return left.start < right.start
        end
        return left.index < right.index
    end)

    return entries
end

WidgetTypes.checkbox = {
    binds = { value = { storageType = "bool" } },
    validate = function(node, prefix)
        if node.default ~= nil and type(node.default) ~= "boolean" then
            libWarn("%s: checkbox default must be boolean, got %s", prefix, type(node.default))
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y)
        node._checkboxBound = bound.value
        node._checkboxValue = bound.value:get()
        if node._checkboxValue == nil then node._checkboxValue = node.default == true end
        local contentWidth = EstimateToggleWidth(imgui, node._label or "")
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                local value = node._checkboxValue == true
                local newVal, widgetChanged = imgui.Checkbox((node._label or "") .. (node._imguiId or ""), value)
                ShowPreparedTooltip(imgui, node)
                if widgetChanged then
                    node._checkboxBound:set(newVal)
                    return true
                end
                return false
            end)
        return contentWidth, consumedHeight, changed
    end,
}

WidgetTypes.packedCheckboxList = {
    binds = {
        value = { storageType = "int", rootType = "packedInt" },
        filterText = { storageType = "string", optional = true },
        filterMode = { storageType = "string", optional = true },
    },
    validate = function(node, prefix)
        if node.slotCount == nil then
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        elseif type(node.slotCount) ~= "number" then
            libWarn("%s: packedCheckboxList slotCount must be a number", prefix)
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        elseif node.slotCount < 1 or math.floor(node.slotCount) ~= node.slotCount then
            libWarn("%s: packedCheckboxList slotCount must be a positive integer", prefix)
            node.slotCount = DEFAULT_PACKED_SLOT_COUNT
        else
            node.slotCount = math.floor(node.slotCount)
        end

        ValidateValueColorsTable(node, prefix, "packedCheckboxList")
    end,
    draw = function(imgui, node, bound, x, y)
        local children = bound.value and bound.value.children
        if not children or #children == 0 then
            libWarn("packedCheckboxList: no packed children for alias '%s'; bind to a packedInt root",
                tostring(node.binds and node.binds.value or "?"))
            return 0, 0, false
        end

        local filterBind = bound.filterText
        local filterText = filterBind and filterBind.get() or ""
        if type(filterText) ~= "string" then filterText = "" end
        local lowerFilter = filterText:lower()
        local hasFilter = lowerFilter ~= ""
        local filterModeBind = bound.filterMode
        local filterMode = filterModeBind and filterModeBind.get() or "all"
        if filterMode ~= "checked" and filterMode ~= "unchecked" then
            filterMode = "all"
        end
        local visibleIndex = 0
        local optionEntries = {}

        for _, child in ipairs(children) do
            if child ~= nil then
                local label = child.label or ""
                local val = child.get()
                if val == nil then val = false end
                local matchesText = not hasFilter or label:lower():find(lowerFilter, 1, true) ~= nil
                local matchesMode = filterMode == "all"
                    or (filterMode == "checked" and val == true)
                    or (filterMode == "unchecked" and val ~= true)
                local visible = matchesText and matchesMode
                if visible and visibleIndex < node.slotCount then
                    visibleIndex = visibleIndex + 1
                    optionEntries[#optionEntries + 1] = {
                        slotName = "item:" .. tostring(visibleIndex),
                        line = visibleIndex,
                        label = label,
                        current = val == true,
                        color = node._valueColors and node._valueColors[child.alias] or nil,
                        onToggle = function(nextValue)
                            child.set(nextValue)
                            return true
                        end,
                    }
                end
            end
        end

        return DrawOrderedEntries(
            imgui,
            BuildOrderedCheckboxEntries(optionEntries),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}
