local helpers = ...

---@class RadioOpts
---@field label string|nil
---@field values ChoiceValue[]|nil
---@field default ChoiceValue|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors ValueColorMap|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil

---@class MappedRadioOption
---@field label string|nil
---@field value any
---@field color Color|nil
---@field selected boolean|nil
---@field onSelect fun(option: MappedRadioOption, session: Session): boolean|nil

---@class MappedRadioOpts
---@field label string|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil
---@field getOptions fun(view: table<string, any>): MappedRadioOption[]|any[]

---@class PackedRadioOpts
---@field label string|nil
---@field displayValues ChoiceDisplayValues|nil
---@field valueColors table<string, Color>|nil
---@field noneLabel string|nil
---@field selectionMode PackedSelectionMode|nil
---@field optionsPerLine number|nil
---@field optionGap number|nil

---@class RadioOptionEntry
---@field label string
---@field color Color|nil
---@field selected boolean
---@field onSelect fun(): boolean

---@param imgui table
---@param radioId string
---@param labelText string
---@param optionEntries RadioOptionEntry[]
---@param optionsPerLine number|nil
---@param optionGap number|nil
---@return boolean
local function DrawRadioOptions(imgui, radioId, labelText, optionEntries, optionsPerLine, optionGap)
    local changed = false
    local normalizedPerLine = math.floor(tonumber(optionsPerLine) or 0)
    if normalizedPerLine < 1 then
        normalizedPerLine = #optionEntries
    end
    local normalizedGap = helpers.ResolveGap(imgui, optionGap)

    if labelText ~= "" then
        imgui.AlignTextToFramePadding()
        imgui.Text(labelText)
    end

    for index, option in ipairs(optionEntries) do
        local positionInLine = (index - 1) % normalizedPerLine
        if positionInLine ~= 0 then
            helpers.SameLineWithGap(imgui, normalizedGap)
        end

        local clicked = helpers.DrawWithValueColor(imgui, option.color, function()
            return imgui.RadioButton(option.label .. "##" .. tostring(radioId) .. "_" .. tostring(index), option.selected == true)
        end)
        if clicked and type(option.onSelect) == "function" and option.onSelect() == true then
            changed = true
        end
    end

    return changed
end

---@param imgui table
---@param session Session
---@param alias string
---@param opts RadioOpts|nil
---@return boolean
function public.widgets.radio(imgui, session, alias, opts)
    opts = opts or {}
    local current = helpers.NormalizeChoiceValue(opts, session.read(alias))
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local optionEntries = {}

    for _, value in ipairs(opts.values or {}) do
        optionEntries[#optionEntries + 1] = {
            label = helpers.ChoiceDisplay(opts, value),
            color = valueColors and valueColors[value] or nil,
            selected = current == value,
            onSelect = function()
                if current ~= value then
                    session.write(alias, value)
                    current = value
                    return true
                end
                return false
            end,
        }
    end

    return DrawRadioOptions(
        imgui,
        alias,
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end

---@param imgui table
---@param session Session
---@param alias string
---@param opts MappedRadioOpts|nil
---@return boolean
function public.widgets.mappedRadio(imgui, session, alias, opts)
    opts = opts or {}
    local current = session.read(alias)
    local optionEntries = {}

    for _, option in ipairs(type(opts.getOptions) == "function" and (opts.getOptions(session.view) or {}) or {}) do
        local label = type(option) == "table" and tostring(option.label or option.value or "") or tostring(option)
        local color = type(option) == "table" and option.color or nil
        local selected = type(option) == "table" and option.selected == true or current == option
        optionEntries[#optionEntries + 1] = {
            label = label,
            color = color,
            selected = selected,
            onSelect = function()
                if type(option) == "table" and type(option.onSelect) == "function" then
                    return option.onSelect(option, session) == true
                end
                local nextValue = type(option) == "table" and option.value or option
                if nextValue ~= current then
                    session.write(alias, nextValue)
                    current = nextValue
                    return true
                end
                return false
            end,
        }
    end

    return DrawRadioOptions(
        imgui,
        alias,
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end

---@param imgui table
---@param session Session
---@param alias string
---@param opts PackedRadioOpts|nil
---@return boolean
function public.widgets.packedRadio(imgui, session, alias, opts)
    opts = opts or {}
    local children = helpers.ResolvePackedChildren(session, alias)
    local valueColors = type(opts.valueColors) == "table" and opts.valueColors or nil
    local selection = helpers.ClassifyPackedChoice(opts, session, children)
    local optionEntries = {
        {
            label = tostring(opts.noneLabel or "None"),
            selected = selection.state == "none",
            onSelect = function()
                return helpers.ClearPackedChoiceSelection(session, children, selection) == true
            end,
        },
    }

    for _, child in ipairs(children) do
        optionEntries[#optionEntries + 1] = {
            label = helpers.GetPackedChoiceLabel(opts, child),
            color = valueColors and valueColors[child.alias] or nil,
            selected = selection.selectedChild and selection.selectedChild.alias == child.alias or false,
            onSelect = function()
                return helpers.ApplyPackedChoiceSelection(session, children, child.alias, selection) == true
            end,
        }
    end

    return DrawRadioOptions(
        imgui,
        alias,
        tostring(opts.label or ""),
        optionEntries,
        opts.optionsPerLine,
        opts.optionGap
    )
end
