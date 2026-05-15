local internal = AdamantModpackLib_Internal

---@alias Color number[]
---@alias ChoiceValue any
---@alias ChoiceDisplayValues table<any, string>
---@alias ValueColorMap table<any, Color>
---@alias PackedSelectionMode "singleEnabled"|"singleDisabled"

local PACKED_CHOICE_NONE_VALUE = false

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

local function ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

local function NormalizeInteger(node, value)
    return internal.storage.NormalizeInteger(node, value)
end

local function ShowTooltip(imgui, tooltip)
    if type(tooltip) == "string" and tooltip ~= "" and imgui.IsItemHovered() then
        imgui.SetTooltip(tooltip)
    end
end

local function AdvanceInlineGap(imgui, gap)
    if tonumber(gap) and gap > 0 then
        imgui.SetCursorPosX(imgui.GetCursorPosX() + gap)
    end
end

local function ResolveGap(imgui, value, fallback)
    local gap = tonumber(value)
    if gap == nil or gap < 0 then
        if fallback ~= nil then
            return fallback
        end
        local style = imgui.GetStyle and imgui.GetStyle() or nil
        local spacing = style and style.ItemSpacing or nil
        if type(spacing) == "table" and spacing.x ~= nil then
            return spacing.x
        end
        return 0
    end
    return gap
end

local function SameLineWithGap(imgui, gap)
    imgui.SameLine()
    AdvanceInlineGap(imgui, gap)
end

local function DrawWithValueColor(imgui, color, drawFn)
    if type(color) ~= "table" then
        return drawFn()
    end

    local textEnum = imgui.ImGuiCol and imgui.ImGuiCol.Text or 0
    imgui.PushStyleColor(textEnum, color[1], color[2], color[3], color[4])
    local a, b, c, d = drawFn()
    imgui.PopStyleColor()
    return a, b, c, d
end

local function MakeSelectableId(label, uniqueId)
    return tostring(label or "") .. "##" .. tostring(uniqueId or "")
end

local function GetPackedChoiceMode(node)
    local mode = node.selectionMode
    if mode == nil or mode == "" then
        return "singleEnabled"
    end
    return mode
end

local function GetPackedChoiceLabel(node, child)
    if type(node.displayValues) == "table" and node.displayValues[child.alias] ~= nil then
        return tostring(node.displayValues[child.alias])
    end
    return tostring(child.label or child.alias or "")
end

local function IsPackedChoiceActive(mode, value)
    if mode == "singleDisabled" then
        return value == false
    end
    return value == true
end

local function GetPackedChoiceWriteValue(mode, isActive)
    if mode == "singleDisabled" then
        if isActive then
            return false
        end
        return true
    end
    return isActive == true
end

local function ClassifyPackedChoice(node, session, children)
    local mode = GetPackedChoiceMode(node)
    local activeCount = 0
    local totalCount = 0
    local lastActiveChild = nil

    for _, child in ipairs(children or {}) do
        totalCount = totalCount + 1
        local value = session.read(child.alias)
        if value == nil then
            value = PACKED_CHOICE_NONE_VALUE
        end
        if IsPackedChoiceActive(mode, value) then
            activeCount = activeCount + 1
            lastActiveChild = child
        end
    end

    local state = "multiple"
    if activeCount == 0 then
        state = "none"
    elseif activeCount == 1 then
        state = "single"
    elseif mode == "singleDisabled" and activeCount == totalCount then
        state = "none"
    end

    return {
        state = state,
        selectedChild = state == "single" and lastActiveChild or nil,
        mode = mode,
        noneValue = PACKED_CHOICE_NONE_VALUE,
    }
end

local function ApplyPackedChoiceSelection(session, children, selectedAlias, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local shouldBeActive = child.alias == selectedAlias
        local nextValue = GetPackedChoiceWriteValue(selection.mode, shouldBeActive)
        local currentValue = session.read(child.alias)
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= nextValue then
            session.write(child.alias, nextValue)
            changed = true
        end
    end
    return changed
end

local function ClearPackedChoiceSelection(session, children, selection)
    local changed = false
    for _, child in ipairs(children or {}) do
        local currentValue = session.read(child.alias)
        if currentValue == nil then
            currentValue = selection.noneValue
        end
        if currentValue ~= selection.noneValue then
            session.write(child.alias, selection.noneValue)
            changed = true
        end
    end
    return changed
end

local function ResolvePackedChildren(session, alias)
    if type(session) ~= "table" or type(session.getAliasSchema) ~= "function" then
        internal.violate(
            "widgets.invalid_packed_session",
            "packed widgets require a session with getAliasSchema(alias)"
        )
    end

    local node = session.getAliasSchema(alias)
    return internal.storage.getPackedAliases(node)
end

return {
    NormalizeColor = NormalizeColor,
    NormalizeChoiceValue = NormalizeChoiceValue,
    ChoiceDisplay = ChoiceDisplay,
    NormalizeInteger = NormalizeInteger,
    ShowTooltip = ShowTooltip,
    AdvanceInlineGap = AdvanceInlineGap,
    ResolveGap = ResolveGap,
    SameLineWithGap = SameLineWithGap,
    DrawWithValueColor = DrawWithValueColor,
    MakeSelectableId = MakeSelectableId,
    GetPackedChoiceLabel = GetPackedChoiceLabel,
    ClassifyPackedChoice = ClassifyPackedChoice,
    ApplyPackedChoiceSelection = ApplyPackedChoiceSelection,
    ClearPackedChoiceSelection = ClearPackedChoiceSelection,
    ResolvePackedChildren = ResolvePackedChildren,
}
