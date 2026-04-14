local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.logging.warnIf
local registry = shared.fieldRegistry

local NormalizeColor = registry.NormalizeColor
local PrepareWidgetText = registry.PrepareWidgetText
local CalcTextWidth = registry.CalcTextWidth
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt
local ShowPreparedTooltip = registry.ShowPreparedTooltip

WidgetTypes.text = {
    binds = { value = { storageType = "string", optional = true } },
    validate = function(node, prefix)
        if node.text ~= nil and type(node.text) ~= "string" then
            libWarn("%s: text text must be string", prefix)
        end
        if node.label ~= nil and type(node.label) ~= "string" then
            libWarn("%s: text label must be string", prefix)
        end
        if node.color ~= nil then
            if type(node.color) ~= "table" then
                libWarn("%s: text color must be a table", prefix)
            else
                local count = 0
                for i = 1, 4 do
                    if node.color[i] ~= nil then
                        count = count + 1
                        if type(node.color[i]) ~= "number" then
                            libWarn("%s: text color[%d] must be a number", prefix, i)
                        end
                    end
                end
                if count ~= 3 and count ~= 4 then
                    libWarn("%s: text color must have 3 or 4 numeric entries", prefix)
                end
            end
        end
        if node.width ~= nil and (type(node.width) ~= "number" or node.width <= 0) then
            libWarn("%s: text width must be a positive number", prefix)
        end
        node._text = tostring(node.text or node.label or "")
        node._color = NormalizeColor(node.color)
        PrepareWidgetText(node)
    end,
    draw = function(imgui, node, bound, x, y)
        node._boundText = bound.value and bound.value:get() or nil
        local text = node._boundText ~= nil and tostring(node._boundText) or node._text or ""
        local contentWidth = CalcTextWidth(imgui, text)
        local reservedWidth = type(node.width) == "number" and node.width > 0 and node.width or nil
        local color = node._color
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if type(color) == "table" then
                    imgui.TextColored(color[1], color[2], color[3], color[4], text)
                else
                    imgui.Text(text)
                end
                ShowPreparedTooltip(imgui, node)
                return false
            end)
        return reservedWidth or contentWidth, consumedHeight, changed
    end,
}
