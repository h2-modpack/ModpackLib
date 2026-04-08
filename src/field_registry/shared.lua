local internal = AdamantModpackLib_Internal
local shared = internal.shared
local StorageTypes = shared.StorageTypes
local WidgetTypes = shared.WidgetTypes
local LayoutTypes = shared.LayoutTypes
local libWarn = shared.libWarn
local registry = shared.fieldRegistry or {}
shared.fieldRegistry = registry

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
    local normalized = value ~= nil and tostring(value) or tostring(node.default or "")
    if type(node.values) == "table" then
        for _, candidate in ipairs(node.values) do
            if candidate == normalized then
                return normalized
            end
        end
    end
    return node.default or ""
end

registry.NormalizeChoiceValue = NormalizeChoiceValue

local function ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

shared.ChoiceDisplay = ChoiceDisplay
registry.ChoiceDisplay = ChoiceDisplay

local function GetCursorPosXSafe(imgui)
    local getCursorPosX = imgui and imgui.GetCursorPosX
    if type(getCursorPosX) == "function" then
        return getCursorPosX() or 0
    end
    return 0
end

registry.GetCursorPosXSafe = GetCursorPosXSafe

local function BuildSlotSet(widgetType)
    if type(widgetType) ~= "table" or type(widgetType.slots) ~= "table" then
        return {}
    end
    local allowed = {}
    for _, key in ipairs(widgetType.slots) do
        allowed[key] = true
    end
    return allowed
end

local function ValidateDynamicSlot(widgetType, node, slotName)
    if type(widgetType) ~= "table" then
        return false, nil
    end
    local dynamicSlots = widgetType.dynamicSlots
    if type(dynamicSlots) == "function" then
        local ok, err = dynamicSlots(node, slotName)
        return ok == true, err
    end
    return false, nil
end

local function ParseWidgetGeometry(node, prefix, widgetType, geometry, opts)
    opts = opts or {}
    if geometry == nil then
        return {}
    end
    if type(geometry) ~= "table" then
        libWarn("%s: geometry must be a table", prefix)
        return {}
    end
    local allowed = BuildSlotSet(widgetType)
    local slotSpecs = geometry.slots
    local parsed = {}

    for key in pairs(geometry) do
        if key ~= "slots" then
            libWarn("%s: geometry key '%s' is not supported; geometry only supports 'slots'",
                prefix, tostring(key))
        end
    end

    if slotSpecs == nil then
        return parsed
    end
    if type(slotSpecs) ~= "table" then
        libWarn("%s: geometry.slots must be a list", prefix)
        return parsed
    end

    local seen = {}
    for index, slotSpec in ipairs(slotSpecs) do
        local slotPrefix = ("%s geometry.slots[%d]"):format(prefix, index)
        if type(slotSpec) ~= "table" then
            libWarn("%s must be a table", slotPrefix)
        else
            local slotName = slotSpec.name
            if type(slotName) ~= "string" or slotName == "" then
                libWarn("%s.name must be a non-empty string", slotPrefix)
            else
                local dynamicOk, dynamicErr = ValidateDynamicSlot(widgetType, node, slotName)
                if dynamicErr ~= nil then
                    libWarn("%s: %s", prefix, tostring(dynamicErr))
                elseif not allowed[slotName] and not dynamicOk then
                    libWarn("%s: geometry slot '%s' is not supported by widget type '%s'",
                        prefix, tostring(slotName), tostring(node.type))
                end
                if seen[slotName] then
                    libWarn("%s: geometry slot '%s' is declared more than once", prefix, tostring(slotName))
                end
                seen[slotName] = true

                for key, value in pairs(slotSpec) do
                    if key ~= "name" and key ~= "line" and key ~= "start" and key ~= "width" and key ~= "align"
                        and not (opts.allowHidden == true and key == "hidden") then
                        libWarn("%s: unknown slot geometry key '%s'", slotPrefix, tostring(key))
                    elseif key == "line" then
                        if type(value) ~= "number" then
                            libWarn("%s.line must be a number", slotPrefix)
                        elseif value < 1 or math.floor(value) ~= value then
                            libWarn("%s.line must be a positive integer", slotPrefix)
                        end
                    elseif key == "start" then
                        if type(value) ~= "number" then
                            libWarn("%s.start must be a number", slotPrefix)
                        elseif value < 0 then
                            libWarn("%s.start must be a non-negative number", slotPrefix)
                        end
                    elseif key == "width" then
                        if type(value) ~= "number" or value <= 0 then
                            libWarn("%s.width must be a positive number", slotPrefix)
                        end
                    elseif key == "align" then
                        if value ~= "center" and value ~= "right" then
                            libWarn("%s.align must be one of 'center' or 'right'", slotPrefix)
                        end
                    elseif key == "hidden" then
                        if type(value) ~= "boolean" then
                            libWarn("%s.hidden must be boolean", slotPrefix)
                        end
                    end
                end

                if slotSpec.align ~= nil and (type(slotSpec.width) ~= "number" or slotSpec.width <= 0) then
                    libWarn("%s.align requires width on the same slot", slotPrefix)
                end

                parsed[slotName] = {
                    line = type(slotSpec.line) == "number" and slotSpec.line >= 1 and math.floor(slotSpec.line) == slotSpec.line
                        and slotSpec.line or nil,
                    start = type(slotSpec.start) == "number" and slotSpec.start or nil,
                    width = type(slotSpec.width) == "number" and slotSpec.width > 0 and slotSpec.width or nil,
                    align = (slotSpec.align == "center" or slotSpec.align == "right") and slotSpec.align or nil,
                    hidden = opts.allowHidden == true and slotSpec.hidden == true or nil,
                }
            end
        end
    end
    return parsed
end

local function ValidateWidgetGeometry(node, prefix, widgetType)
    node._slotGeometry = ParseWidgetGeometry(node, prefix, widgetType, node.geometry)
end

registry.ValidateWidgetGeometry = ValidateWidgetGeometry

local function PrepareRuntimeWidgetGeometry(node, prefix, widgetType, geometry)
    return ParseWidgetGeometry(node, prefix, widgetType, geometry, { allowHidden = true })
end

registry.PrepareRuntimeWidgetGeometry = PrepareRuntimeWidgetGeometry

local function GetSlotGeometry(node, slotName)
    if type(node) ~= "table" then
        return nil
    end
    local runtimeGeometry = node._runtimeSlotGeometry
    local staticGeometry = node._slotGeometry
    local runtimeSlot = type(runtimeGeometry) == "table" and runtimeGeometry[slotName] or nil
    local staticSlot = type(staticGeometry) == "table" and staticGeometry[slotName] or nil
    if type(runtimeSlot) ~= "table" then
        if type(staticSlot) == "table" then
            return staticSlot
        end
        return nil
    end
    if type(staticSlot) ~= "table" then
        return runtimeSlot
    end
    local merged = {}
    for key, value in pairs(staticSlot) do
        merged[key] = value
    end
    for key, value in pairs(runtimeSlot) do
        if value ~= nil then
            merged[key] = value
        end
    end
    return merged
end

registry.GetSlotGeometry = GetSlotGeometry

local function GetStyleMetricX(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.x) == "number" then
        return metric.x
    end
    return fallback
end

registry.GetStyleMetricX = GetStyleMetricX

local function CalcTextWidth(imgui, text)
    if type(imgui.CalcTextSize) ~= "function" then
        return #(tostring(text or ""))
    end
    local width = imgui.CalcTextSize(tostring(text or ""))
    return type(width) == "number" and width or 0
end

registry.CalcTextWidth = CalcTextWidth

local function EstimateButtonWidth(imgui, label)
    local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
    local framePaddingX = GetStyleMetricX(style, "FramePadding", 0)
    return CalcTextWidth(imgui, label) + framePaddingX * 2
end

registry.EstimateButtonWidth = EstimateButtonWidth

local function DrawWidgetSlots(imgui, node, slots, rowStart)
    if type(slots) ~= "table" then
        return false
    end

    local changed = false
    rowStart = rowStart or GetCursorPosXSafe(imgui)
    local renderSlots = {}

    for index, slot in ipairs(slots) do
        if type(slot) == "table" and type(slot.draw) == "function" then
            local geometry = type(slot.name) == "string" and GetSlotGeometry(node, slot.name) or nil
            local hidden = slot.hidden == true or (type(geometry) == "table" and geometry.hidden == true)
            if not hidden then
            table.insert(renderSlots, {
                slot = slot,
                index = index,
                line = (geometry and geometry.line) or slot.line or 1,
                start = (geometry and geometry.start) or slot.start,
                width = (geometry and geometry.width) or slot.width,
                align = (geometry and geometry.align) or slot.align,
            })
            end
        end
    end

    table.sort(renderSlots, function(a, b)
        if a.line ~= b.line then
            return a.line < b.line
        end
        if type(a.start) == "number" and type(b.start) == "number" and a.start ~= b.start then
            return a.start < b.start
        end
        return a.index < b.index
    end)

    local currentLine = nil
    local firstOnLine = true

    for _, entry in ipairs(renderSlots) do
        local slot = entry.slot
        local merged = {
            name = slot.name,
            hidden = slot.hidden == true,
            start = entry.start,
            width = entry.width,
            align = entry.align,
            sameLine = slot.sameLine,
            line = entry.line,
        }

        if currentLine ~= entry.line then
            if currentLine ~= nil then
                imgui.NewLine()
            end
            currentLine = entry.line
            firstOnLine = true
        elseif not firstOnLine and slot.sameLine ~= false then
            imgui.SameLine()
        end

        if type(entry.start) == "number" and type(imgui.SetCursorPosX) == "function" then
            imgui.SetCursorPosX(rowStart + entry.start)
        end
        if type(entry.width) == "number" and entry.width > 0 then
            imgui.PushItemWidth(entry.width)
        end
        imgui.PushID((slot.name or "slot") .. "_" .. tostring(entry.index))
        if slot.draw(imgui, merged, rowStart) then
            changed = true
        end
        imgui.PopID()
        if type(entry.width) == "number" and entry.width > 0 then
            imgui.PopItemWidth()
        end
        firstOnLine = false
    end
    return changed
end

registry.DrawWidgetSlots = DrawWidgetSlots

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

local function AssertWidgetSlotsContract(widgetType, typeName, label)
    if widgetType.slots == nil then
        return
    end
    if type(widgetType.slots) ~= "table" then
        error(("%s type '%s' slots must be a list of non-empty strings"):format(
            label, tostring(typeName)), 0)
    end
    for index, key in ipairs(widgetType.slots) do
        if type(key) ~= "string" or key == "" then
            error(("%s type '%s' slots[%d] must be a non-empty string"):format(
                label, tostring(typeName), index), 0)
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
            AssertWidgetSlotsContract(item, typeName, "Widget")
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
    return mergedWidgets, mergedLayouts
end

registry.MergeCustomTypes = MergeCustomTypes

function public.validateRegistries()
    AssertRegistryContracts(StorageTypes, REQUIRED_STORAGE_METHODS, "Storage")
    AssertWidgetContracts(WidgetTypes, "Widget")
    AssertRegistryContracts(LayoutTypes, REQUIRED_LAYOUT_METHODS, "Layout")
    for typeName, widgetType in pairs(WidgetTypes) do
        if type(widgetType.binds) ~= "table" then
            error(("Widget type '%s' must declare a binds table"):format(tostring(typeName)), 0)
        end
        AssertWidgetSlotsContract(widgetType, typeName, "Widget")
    end
    return true
end
