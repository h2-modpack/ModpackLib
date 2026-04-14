local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetHelpers = shared.WidgetHelpers
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local LayoutTypes = shared.LayoutTypes
local registry = shared.fieldRegistry or {}
shared.fieldRegistry = registry
local mergedCustomTypesCache = setmetatable({}, { __mode = "k" })

local REQUIRED_STORAGE_METHODS = { "validate", "normalize", "toHash", "fromHash" }
local REQUIRED_LAYOUT_METHODS  = { "validate", "render" }

local function KeyStr(key)
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

shared.StorageKey = KeyStr

local function NormalizeInteger(node, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(node.default) or 0
    end
    num = math.floor(num)
    if node.min ~= nil and num < node.min then num = node.min end
    if node.max ~= nil and num > node.max then num = node.max end
    return num
end

shared.NormalizeInteger = NormalizeInteger
registry.NormalizeInteger = NormalizeInteger

local function NormalizeChoiceValue(node, value)
    local values = node.values
    if type(values) ~= "table" or #values == 0 then
        return value ~= nil and value or node.default
    end

    if value ~= nil then
        for _, candidate in ipairs(values) do
            if candidate == value then
                return candidate
            end
        end
    end

    if node.default ~= nil then
        for _, candidate in ipairs(values) do
            if candidate == node.default then
                return candidate
            end
        end
    end

    return values[1]
end

registry.NormalizeChoiceValue = NormalizeChoiceValue

local function NormalizeColor(value)
    if type(value) ~= "table" then
        return nil
    end
    local r = tonumber(value[1])
    local g = tonumber(value[2])
    local b = tonumber(value[3])
    local a = value[4] ~= nil and tonumber(value[4]) or 1
    if r == nil or g == nil or b == nil or a == nil then
        return nil
    end
    return { r, g, b, a }
end

shared.NormalizeColor = NormalizeColor
registry.NormalizeColor = NormalizeColor

local function PrepareWidgetText(node, fallbackLabel)
    if type(node) ~= "table" then
        return
    end
    node._label = tostring(node.label or fallbackLabel or "")
    node._tooltipText = node.tooltip ~= nil and tostring(node.tooltip) or ""
    node._hasTooltip = node._tooltipText ~= ""
end

shared.PrepareWidgetText = PrepareWidgetText
registry.PrepareWidgetText = PrepareWidgetText

local function ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

shared.ChoiceDisplay = ChoiceDisplay
registry.ChoiceDisplay = ChoiceDisplay

local function GetCursorPosXSafe(imgui)
    return imgui.GetCursorPosX() or 0
end

registry.GetCursorPosXSafe = GetCursorPosXSafe

local function GetCursorPosYSafe(imgui)
    local value = imgui.GetCursorPosY()
    if type(value) == "number" then
        return value
    end
    return 0
end

registry.GetCursorPosYSafe = GetCursorPosYSafe

local function SetCursorPosSafe(imgui, x, y)
    if type(imgui.SetCursorPos) == "function" then
        imgui.SetCursorPos(x, y)
    end
    if type(imgui.SetCursorPosX) == "function" and type(x) == "number" then
        imgui.SetCursorPosX(x)
    end
    if type(imgui.SetCursorPosY) == "function" and type(y) == "number" then
        imgui.SetCursorPosY(y)
    end
end

registry.SetCursorPosSafe = SetCursorPosSafe


local function GetStyleMetricX(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.x) == "number" then
        return metric.x
    end
    return fallback
end

registry.GetStyleMetricX = GetStyleMetricX

local function GetStyleMetricY(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.y) == "number" then
        return metric.y
    end
    return fallback
end

registry.GetStyleMetricY = GetStyleMetricY

local function CalcTextWidth(imgui, text)
    local width = imgui.CalcTextSize(tostring(text or ""))
    if type(width) == "number" then
        return width
    end
    if type(width) == "table" then
        if type(width.x) == "number" then
            return width.x
        end
        if type(width[1]) == "number" then
            return width[1]
        end
    end
    return 0
end

registry.CalcTextWidth = CalcTextWidth

local function EstimateStructuredRowAdvanceY(imgui)
    local value = imgui.GetFrameHeightWithSpacing()
    if type(value) == "number" and value > 0 then
        return value
    end
    value = imgui.GetTextLineHeightWithSpacing()
    if type(value) == "number" and value > 0 then
        return value
    end
    local style = imgui.GetStyle()
    local framePaddingY = type(style) == "table" and GetStyleMetricY(style, "FramePadding", 3) or 3
    local itemSpacingY = type(style) == "table" and GetStyleMetricY(style, "ItemSpacing", 4) or 4
    return 16 + framePaddingY * 2 + itemSpacingY
end

registry.EstimateStructuredRowAdvanceY = EstimateStructuredRowAdvanceY
if type(WidgetHelpers) == "table" then
    WidgetHelpers.estimateRowAdvanceY = EstimateStructuredRowAdvanceY
end

local function DrawStructuredAt(imgui, startX, startY, fallbackHeight, drawFn)
    SetCursorPosSafe(imgui, startX, startY)
    local changed = drawFn() == true
    local endX = GetCursorPosXSafe(imgui)
    local endY = GetCursorPosYSafe(imgui)
    local consumedHeight = endY - startY
    if type(consumedHeight) ~= "number" or consumedHeight <= 0 then
        consumedHeight = fallbackHeight
    end
    return changed, endX, endY, consumedHeight
end

registry.DrawStructuredAt = DrawStructuredAt
if type(WidgetHelpers) == "table" then
    WidgetHelpers.drawStructuredAt = DrawStructuredAt
end

local function ShowPreparedTooltip(imgui, node)
    if node and node._hasTooltip == true and imgui.IsItemHovered() then
        imgui.SetTooltip(node._tooltipText)
    end
end

registry.ShowPreparedTooltip = ShowPreparedTooltip

local function EstimateButtonWidth(imgui, label)
    local style = imgui.GetStyle()
    local framePaddingX = GetStyleMetricX(style, "FramePadding", 0)
    return CalcTextWidth(imgui, label) + framePaddingX * 2
end

registry.EstimateButtonWidth = EstimateButtonWidth

local function AssertRegistryContracts(registryTable, required, label)
    for typeName, item in pairs(registryTable) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        for _, method in ipairs(required) do
            if type(item[method]) ~= "function" then
                error(("%s type '%s' is missing required method '%s'"):format(
                    label, tostring(typeName), method), 0)
            end
        end
    end
end

local function AssertWidgetContracts(registryTable, label)
    for typeName, item in pairs(registryTable) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        if type(item.validate) ~= "function" then
            error(("%s type '%s' is missing required method 'validate'"):format(
                label, tostring(typeName)), 0)
        end
        if type(item.draw) ~= "function" then
            error(("%s type '%s' is missing required method 'draw'"):format(
                label, tostring(typeName)), 0)
        end
    end
end

local function ValidateCustomTypes(customTypes, label)
    if type(customTypes) ~= "table" then
        error((label or "module") .. ": definition.customTypes must be a table", 0)
    end
    local widgets = customTypes.widgets
    local layouts = customTypes.layouts
    if widgets ~= nil then
        if type(widgets) ~= "table" then
            error((label or "module") .. ": customTypes.widgets must be a table", 0)
        end
        for typeName, item in pairs(widgets) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertWidgetContracts({ [typeName] = item }, "Widget")
            if type(item) == "table" and type(item.binds) ~= "table" then
                error(("%s: customTypes.widgets '%s' must declare a binds table"):format(
                    label or "module", tostring(typeName)), 0)
            end
        end
    end
    if layouts ~= nil then
        if type(layouts) ~= "table" then
            error((label or "module") .. ": customTypes.layouts must be a table", 0)
        end
        for typeName, item in pairs(layouts) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertRegistryContracts({ [typeName] = item }, REQUIRED_LAYOUT_METHODS, "Layout")
        end
    end
end

registry.ValidateCustomTypes = ValidateCustomTypes

local function MergeCustomTypes(customTypes)
    if not customTypes then
        return WidgetTypes, LayoutTypes
    end
    local cached = mergedCustomTypesCache[customTypes]
    if cached then
        return cached.widgets, cached.layouts
    end
    local mergedWidgets = {}
    for k, v in pairs(WidgetTypes) do mergedWidgets[k] = v end
    if type(customTypes.widgets) == "table" then
        for k, v in pairs(customTypes.widgets) do mergedWidgets[k] = v end
    end
    local mergedLayouts = {}
    for k, v in pairs(LayoutTypes) do mergedLayouts[k] = v end
    if type(customTypes.layouts) == "table" then
        for k, v in pairs(customTypes.layouts) do mergedLayouts[k] = v end
    end
    mergedCustomTypesCache[customTypes] = {
        widgets = mergedWidgets,
        layouts = mergedLayouts,
    }
    return mergedWidgets, mergedLayouts
end

registry.MergeCustomTypes = MergeCustomTypes

function registry.validateRegistries()
    AssertRegistryContracts(StorageTypes, REQUIRED_STORAGE_METHODS, "Storage")
    AssertWidgetContracts(WidgetTypes, "Widget")
    AssertRegistryContracts(LayoutTypes, REQUIRED_LAYOUT_METHODS, "Layout")
    for typeName, widgetType in pairs(WidgetTypes) do
        if type(widgetType.binds) ~= "table" then
            error(("Widget type '%s' must declare a binds table"):format(tostring(typeName)), 0)
        end
    end
    return true
end
