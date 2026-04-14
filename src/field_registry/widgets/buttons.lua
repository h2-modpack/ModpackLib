local internal = AdamantModpackLib_Internal
local shared = internal.shared
local WidgetTypes = shared.WidgetTypes
local libWarn = shared.logging.warnIf
local registry = shared.fieldRegistry

local PrepareWidgetText = registry.PrepareWidgetText
local EstimateButtonWidth = registry.EstimateButtonWidth
local EstimateStructuredRowAdvanceY = registry.EstimateStructuredRowAdvanceY
local DrawStructuredAt = registry.DrawStructuredAt
local ShowPreparedTooltip = registry.ShowPreparedTooltip

WidgetTypes.button = {
    binds = {},
    validate = function(node, prefix)
        PrepareWidgetText(node)
        if node._label == "" then
            libWarn("%s: button requires non-empty label", prefix)
        end
        if node.onClick ~= nil and type(node.onClick) ~= "function" then
            libWarn("%s: button onClick must be function", prefix)
        end
    end,
    draw = function(imgui, node, _, x, y, _, _, uiState)
        local label = (node._label or "") .. (node._imguiId or "")
        local contentWidth = EstimateButtonWidth(imgui, node._label or "")
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if imgui.Button(label) then
                    ShowPreparedTooltip(imgui, node)
                    return true
                end
                ShowPreparedTooltip(imgui, node)
                return false
            end)
        if changed and type(node.onClick) == "function" then
            node.onClick(uiState, node, imgui)
        end
        return contentWidth, consumedHeight, changed
    end,
}

WidgetTypes.confirmButton = {
    binds = {},
    validate = function(node, prefix)
        PrepareWidgetText(node)
        if node._label == "" then
            libWarn("%s: confirmButton requires non-empty label", prefix)
        end
        if node.onConfirm ~= nil and type(node.onConfirm) ~= "function" then
            libWarn("%s: confirmButton onConfirm must be function", prefix)
        end
        if node.confirmLabel ~= nil and type(node.confirmLabel) ~= "string" then
            libWarn("%s: confirmButton confirmLabel must be string", prefix)
        end
        if node.cancelLabel ~= nil and type(node.cancelLabel) ~= "string" then
            libWarn("%s: confirmButton cancelLabel must be string", prefix)
        end
        node._confirmLabel = type(node.confirmLabel) == "string" and node.confirmLabel ~= "" and node.confirmLabel or "Confirm"
        node._cancelLabel = type(node.cancelLabel) == "string" and node.cancelLabel ~= "" and node.cancelLabel or "Cancel"
        node._confirmPopupId = (node._imguiId or "confirmButton") .. "##popup"
    end,
    draw = function(imgui, node, _, x, y, _, _, uiState)
        local state = node._confirmButtonState or {}
        state.uiState = uiState
        node._confirmButtonState = state

        local contentWidth = EstimateButtonWidth(imgui, node._label or "")
        local changed, _, _, consumedHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                if imgui.Button((node._label or "") .. (node._imguiId or "")) then
                    node._confirmButtonState = state
                    if type(imgui.OpenPopup) == "function" then
                        imgui.OpenPopup(node._confirmPopupId)
                    end
                end
                ShowPreparedTooltip(imgui, node)

                local popupChanged = false
                if type(imgui.BeginPopup) == "function" and imgui.BeginPopup(node._confirmPopupId) then
                    if imgui.Button(node._confirmLabel .. (node._imguiId or "")) then
                        node._confirmButtonState = state
                        if type(node.onConfirm) == "function" then
                            node.onConfirm(state.uiState, node, imgui)
                        end
                        if type(imgui.CloseCurrentPopup) == "function" then
                            imgui.CloseCurrentPopup()
                        end
                        popupChanged = true
                    end
                    if type(imgui.SameLine) == "function" then
                        imgui.SameLine()
                    end
                    if imgui.Button(node._cancelLabel .. "##cancel" .. (node._imguiId or "")) then
                        node._confirmButtonState = state
                        if type(imgui.CloseCurrentPopup) == "function" then
                            imgui.CloseCurrentPopup()
                        end
                    end
                    if type(imgui.EndPopup) == "function" then
                        imgui.EndPopup()
                    end
                end

                return popupChanged
            end)
        return contentWidth, consumedHeight, changed
    end,
}
